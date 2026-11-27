use std::time::Duration;

use serde_json::{json, Value};

use crate::security::{read_reqwest_body_capped, same_origin_as_client, str_param};
use crate::VedroRuntime;

impl VedroRuntime {
    pub(crate) async fn handle_admin_rpc(
        &self,
        method: &str,
        params: &Value,
    ) -> Result<Value, crate::RpcErr> {
        match method {
            "get_embygo_admin_dashboard" => {
                let client = self.require_client()?;
                let (status, counts, sessions, devices, libraries, users, tasks, activity) = tokio::join!(
                    client.embygo_status(),
                    client.item_counts(),
                    client.sessions(false),
                    client.embygo_devices(None),
                    client.virtual_folders(),
                    client.query_users(),
                    client.scheduled_tasks(),
                    client.activity_log(30),
                );
                let all_sessions = sessions.unwrap_or_default();
                let playing_sessions: Vec<_> = all_sessions
                    .iter()
                    .filter(|s| s.now_playing_item.is_some())
                    .cloned()
                    .collect();
                Ok(json!({
                    "status": status.ok(),
                    "counts": counts.ok(),
                    "playing_sessions": playing_sessions,
                    "sessions": all_sessions,
                    "devices": devices.ok(),
                    "libraries": libraries.ok(),
                    "users": users.ok(),
                    "tasks": tasks.ok(),
                    "activity": activity.ok(),
                }))
            }

            "get_user_devices" => {
                let client = self.require_client()?;
                let explicit_uid = params
                    .get("user_id")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty());
                let raw = client
                    .embygo_devices(explicit_uid)
                    .await
                    .map_err(|e| e.to_string())?;
                let items = if let Some(arr) = raw.get("Items").and_then(Value::as_array) {
                    arr.clone()
                } else if let Some(arr) = raw.as_array() {
                    arr.clone()
                } else {
                    Vec::new()
                };
                let cur_dev = self.identity.lock().device_id.clone();
                Ok(json!({
                    "items": items,
                    "current_device_id": cur_dev,
                }))
            }

            "delete_user_device" => {
                let client = self.require_client()?;
                let device_id = str_param(params, "device_id")?;
                let explicit_uid = params
                    .get("user_id")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(ToString::to_string)
                    .or_else(|| client.user_id());
                client
                    .embygo_delete_device(explicit_uid.as_deref(), &device_id)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(json!({
                    "deleted": device_id,
                    "user_id": explicit_uid,
                }))
            }

            "cancel_embygo_speedtest" => {
                self.speedtest_epoch
                    .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                self.speedtest_cancel
                    .store(true, std::sync::atomic::Ordering::SeqCst);
                Ok(json!({"cancelled": true}))
            }

            "run_embygo_speedtest" => {
                use futures_util::StreamExt;
                use std::sync::atomic::Ordering;

                let st_epoch = self.speedtest_epoch.fetch_add(1, Ordering::SeqCst) + 1;
                let client = self.require_client()?;
                self.speedtest_cancel.store(false, Ordering::SeqCst);
                let start = client
                    .embygo_start_speedtest()
                    .await
                    .map_err(|e| e.to_string())?;

                let raw_ping = start
                    .get("PingUrl")
                    .and_then(Value::as_str)
                    .ok_or_else(|| "服务器未返回 PingUrl".to_string())?;
                let raw_dl = start
                    .get("DownloadUrl")
                    .and_then(Value::as_str)
                    .ok_or_else(|| "服务器未返回 DownloadUrl".to_string())?;
                let ping_url = client
                    .resolve_media_url(raw_ping)
                    .map_err(|e| format!("无效测速地址: {e}"))?;
                let dl_url = client
                    .resolve_media_url(raw_dl)
                    .map_err(|e| format!("无效测速下载流地址: {e}"))?;
                if !same_origin_as_client(&client, ping_url.as_str())
                    || !same_origin_as_client(&client, dl_url.as_str())
                {
                    return Err(crate::RpcErr::from(
                        "安全拦截：测速目标与当前服务器不同源".to_string(),
                    ));
                }

                let route = start
                    .get("Route")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_string();
                let duration_secs = start
                    .get("DurationSeconds")
                    .and_then(Value::as_u64)
                    .unwrap_or(8)
                    .clamp(1, 25);
                let account_limit_bps = start
                    .get("AccountBitrateLimit")
                    .and_then(Value::as_i64)
                    .unwrap_or(0);
                let remaining_hour = start
                    .get("RemainingThisHour")
                    .and_then(Value::as_i64)
                    .unwrap_or(-1);
                let remaining_today = start
                    .get("RemainingToday")
                    .and_then(Value::as_i64)
                    .unwrap_or(-1);

                // Build a clean ticket-only HTTP client honoring active route TLS/proxy settings
                let accept_invalid = client.transport_options().accept_invalid_certs;
                let eff_proxy = client
                    .transport_options()
                    .proxy_url
                    .as_deref()
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(ToString::to_string);
                let mut builder = reqwest::Client::builder()
                    .danger_accept_invalid_certs(accept_invalid)
                    .connect_timeout(Duration::from_secs(5));
                if let Some(ref p) = eff_proxy {
                    if let Ok(px) = reqwest::Proxy::all(p) {
                        builder = builder.proxy(px);
                    }
                } else {
                    builder = builder.no_proxy();
                }
                let http = builder.build().map_err(|e| e.to_string())?;

                // 1. Five sequential pings (1st warms up TCP/TLS; median of 2..=5)
                let mut ping_samples_ms: Vec<f64> = Vec::new();
                let mut client_ip: Option<String> = None;
                for _ in 0..5 {
                    if self.speedtest_cancel.load(Ordering::SeqCst)
                        || self.speedtest_epoch.load(Ordering::SeqCst) != st_epoch
                    {
                        return Err("测速已取消".into());
                    }
                    let t0 = std::time::Instant::now();
                    if let Ok(Ok(resp)) = tokio::time::timeout(
                        Duration::from_secs(5),
                        http.get(ping_url.clone()).send(),
                    )
                    .await
                    {
                        let elapsed = t0.elapsed().as_secs_f64() * 1000.0;
                        if resp.status().is_success() {
                            ping_samples_ms.push(elapsed);
                            if let Ok(Ok(raw_bytes)) = tokio::time::timeout(
                                Duration::from_secs(4),
                                read_reqwest_body_capped(resp, 64 * 1024),
                            )
                            .await
                            {
                                if let Ok(body) = serde_json::from_slice::<Value>(&raw_bytes) {
                                    if let Some(ip) = body
                                        .get("Ip")
                                        .and_then(Value::as_str)
                                        .filter(|s| !s.is_empty())
                                    {
                                        client_ip = Some(ip.to_string());
                                    }
                                }
                            }
                        }
                    }
                }
                let latency_ms: Option<f64> = {
                    let slice = if ping_samples_ms.len() > 1 {
                        &ping_samples_ms[1..]
                    } else {
                        &ping_samples_ms[..]
                    };
                    if slice.is_empty() {
                        None
                    } else {
                        let mut sorted = slice.to_vec();
                        sorted
                            .sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
                        let mid = sorted.len() / 2;
                        Some(if sorted.len() % 2 == 1 {
                            sorted[mid]
                        } else {
                            (sorted[mid - 1] + sorted[mid]) / 2.0
                        })
                    }
                };

                {
                    let mut q = self.events.lock();
                    if q.len() >= 256 {
                        q.pop_front();
                    }
                    q.push_back(json!({
                        "source": "speedtest",
                        "phase": "ping",
                        "latency_ms": latency_ms,
                        "client_ip": client_ip,
                    }));
                }

                // 2. Timed download throughput measurement (excluding 1s warm-up if >= 2s)
                let mut samples: Vec<(u128, u64)> = Vec::new();
                let mut total_bytes: u64 = 0;
                let mut first_byte_at: Option<std::time::Instant> = None;
                let mut last_emit_ms: u128 = 0;
                let dl_deadline = tokio::time::Instant::now() + Duration::from_secs(duration_secs);

                let compute_mbps = |pts: &[(u128, u64)]| -> Option<f64> {
                    if pts.len() < 2 {
                        return None;
                    }
                    let first = pts[0];
                    let last = *pts.last().unwrap();
                    let mut warm = first;
                    if last.0.saturating_sub(first.0) >= 2000 {
                        if let Some(hit) = pts.iter().find(|s| s.0.saturating_sub(first.0) >= 1000)
                        {
                            warm = *hit;
                        }
                    }
                    let secs = (last.0.saturating_sub(warm.0)) as f64 / 1000.0;
                    if secs <= 0.0 {
                        return None;
                    }
                    let mbps = ((last.1.saturating_sub(warm.1)) as f64 * 8.0) / secs / 1e6;
                    (mbps.is_finite() && mbps >= 0.0).then_some(mbps)
                };

                let resp = tokio::time::timeout_at(dl_deadline, http.get(dl_url).send())
                    .await
                    .map_err(|_| "测速下载流连接超时".to_string())?
                    .map_err(|e| {
                        format!(
                            "测速连接失败: {}",
                            vedro_protocol::error::format_transport_error(&e)
                        )
                    })?;
                if !resp.status().is_success() {
                    return Err(crate::RpcErr::from(format!(
                        "测速响应异常: HTTP {}",
                        resp.status().as_u16()
                    )));
                }
                let mut stream = resp.bytes_stream();
                let transfer_epoch = std::time::Instant::now();
                let mut last_sample_ms: u128 = 0;
                loop {
                    if self.speedtest_cancel.load(Ordering::SeqCst)
                        || self.speedtest_epoch.load(Ordering::SeqCst) != st_epoch
                    {
                        return Err("测速已取消".into());
                    }
                    match tokio::time::timeout_at(dl_deadline, stream.next()).await {
                        Ok(Some(Ok(chunk))) => {
                            if !chunk.is_empty() {
                                let now = std::time::Instant::now();
                                let t_ms = transfer_epoch.elapsed().as_millis();
                                if first_byte_at.is_none() {
                                    first_byte_at = Some(now);
                                }
                                total_bytes = total_bytes.saturating_add(chunk.len() as u64);
                                if samples.is_empty()
                                    || (samples.len() < 2000
                                        && t_ms.saturating_sub(last_sample_ms) >= 25)
                                {
                                    last_sample_ms = t_ms;
                                    samples.push((t_ms, total_bytes));
                                } else if let Some(last) = samples.last_mut() {
                                    *last = (t_ms, total_bytes);
                                }
                                if t_ms.saturating_sub(last_emit_ms) >= 250 {
                                    last_emit_ms = t_ms;
                                    let live = compute_mbps(&samples).or_else(|| {
                                        let fb = first_byte_at?;
                                        let dt = now.duration_since(fb).as_secs_f64();
                                        (dt > 0.02).then_some((total_bytes as f64 * 8.0) / dt / 1e6)
                                    });
                                    if let Some(mbps) = live {
                                        let mut q = self.events.lock();
                                        if q.len() >= 256 {
                                            q.pop_front();
                                        }
                                        q.push_back(json!({
                                            "source": "speedtest",
                                            "phase": "download",
                                            "live_mbps": mbps,
                                        }));
                                    }
                                }
                            }
                        }
                        Ok(Some(Err(e))) => {
                            if samples.len() < 2 {
                                return Err(crate::RpcErr::from(format!("测速读取中断: {e}")));
                            }
                            break;
                        }
                        Ok(None) | Err(_) => break,
                    }
                }

                let measured_mbps = compute_mbps(&samples).or_else(|| {
                    let fb = first_byte_at?;
                    let dt = fb.elapsed().as_secs_f64();
                    (total_bytes > 0 && dt > 0.01).then_some((total_bytes as f64 * 8.0) / dt / 1e6)
                });
                let effective_mbps = measured_mbps.map(|m| {
                    if account_limit_bps > 0 {
                        m.min(account_limit_bps as f64 / 1e6)
                    } else {
                        m
                    }
                });

                Ok(json!({
                    "route": route,
                    "latency_ms": latency_ms,
                    "client_ip": client_ip,
                    "measured_mbps": measured_mbps,
                    "account_limit_bps": account_limit_bps,
                    "effective_mbps": effective_mbps,
                    "remaining_this_hour": remaining_hour,
                    "remaining_today": remaining_today,
                }))
            }

            "trigger_library_refresh" => {
                let client = self.require_client()?;
                client
                    .trigger_library_refresh()
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(json!({"refresh_started": true}))
            }

            "admin_end_session" => {
                let client = self.require_client()?;
                let session_id = str_param(params, "session_id")?;
                client
                    .end_session(&session_id)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(json!({"ended": session_id}))
            }

            "admin_create_user" => {
                let client = self.require_client()?;
                let name = str_param(params, "name")?;
                let password = params.get("password").and_then(Value::as_str).unwrap_or("");
                let user = client
                    .create_user(&name, password)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(user)
            }

            "admin_set_user_policy" => {
                let client = self.require_client()?;
                let user_id = str_param(params, "user_id")?;
                let policy = params.get("policy").cloned().unwrap_or_else(|| json!({}));
                client
                    .set_user_policy(&user_id, policy)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(json!({"updated": user_id}))
            }

            "admin_delete_user" => {
                let client = self.require_client()?;
                let user_id = str_param(params, "user_id")?;
                client
                    .delete_user(&user_id)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(json!({"deleted": user_id}))
            }

            "admin_run_task" => {
                let client = self.require_client()?;
                let key = str_param(params, "key")?;
                client
                    .run_scheduled_task(&key)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(json!({"started": key}))
            }

            "get_me_quota" => {
                let client = self.require_client()?;
                let quota = client.me_quota().await.map_err(|e| e.to_string())?;
                Ok(quota.unwrap_or(Value::Null))
            }

            "prepare_download" => {
                let client = self.require_client()?;
                let item_id = str_param(params, "item_id")?;
                let media_source_id = params.get("media_source_id").and_then(Value::as_str);
                let caps = client.capabilities();

                // On embygo, mint a long-lived StreamTicket via `external_play_info` (just like embygo Web)
                // so large downloads never expire mid-transfer and cross-origin 302 redirects never need tokens.
                let pb = if caps.is_embygo() {
                    client
                        .external_play_info(&item_id, media_source_id, Some("vedro-download"))
                        .await
                        .map_err(|e| e.to_string())?
                } else {
                    client
                        .playback_info(&item_id, media_source_id, None, None)
                        .await
                        .map_err(|e| e.to_string())?
                };

                let chosen = media_source_id
                    .and_then(|sid| pb.media_sources.iter().find(|s| s.id == sid))
                    .or_else(|| pb.media_sources.first())
                    .cloned()
                    .ok_or_else(|| "未找到可下载的媒体源".to_string())?;

                // Extract StreamTicket from DirectStreamUrl if issued by embygo
                let stream_ticket = chosen.direct_stream_url.as_deref().and_then(|dsu| {
                    client.resolve_media_url(dsu).ok().and_then(|u| {
                        u.query_pairs()
                            .find(|(k, _)| k == "StreamTicket")
                            .map(|(_, v)| v.into_owned())
                            .filter(|v| !v.is_empty())
                    })
                });

                let download_url = client
                    .build_download_url(&item_id, Some(&chosen.id), stream_ticket.as_deref())
                    .map_err(|e| e.to_string())?;

                let uses_ticket = stream_ticket.is_some();
                let mut header_map = serde_json::Map::new();
                header_map.insert(
                    "User-Agent".to_string(),
                    Value::String(client.identity().user_agent()),
                );
                if !uses_ticket {
                    for (k, v) in client.auth_headers().iter() {
                        if let Ok(val) = v.to_str() {
                            header_map
                                .insert(k.as_str().to_string(), Value::String(val.to_string()));
                        }
                    }
                }

                let basename = chosen
                    .path
                    .as_deref()
                    .and_then(|p| p.rsplit(['/', '\\']).next())
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(ToString::to_string);

                let transport = client.transport_options();
                Ok(json!({
                    "url": download_url.to_string(),
                    "headers": header_map,
                    "uses_stream_ticket": uses_ticket,
                    "media_source_id": chosen.id,
                    "container": chosen.container,
                    "size": chosen.size,
                    "filename": basename,
                    "proxy_url": transport.proxy_url,
                    "accept_invalid_certs": transport.accept_invalid_certs,
                }))
            }

            "admin_user_detail" => {
                let client = self.require_client()?;
                let user_id = str_param(params, "user_id")?;
                Ok(client
                    .admin_user_detail(&user_id)
                    .await
                    .map_err(|e| e.to_string())?)
            }

            "admin_adjust_download_pack" => {
                let client = self.require_client()?;
                let user_id = str_param(params, "user_id")?;
                let bytes = params
                    .get("bytes")
                    .and_then(Value::as_i64)
                    .ok_or_else(|| "missing required integer parameter `bytes`".to_string())?;
                let note = params.get("note").and_then(Value::as_str);
                Ok(client
                    .admin_adjust_download_pack(&user_id, bytes, note)
                    .await
                    .map_err(|e| e.to_string())?)
            }

            "admin_set_monthly_download_quota" => {
                let client = self.require_client()?;
                let user_id = str_param(params, "user_id")?;
                let monthly_bytes = params.get("monthly_bytes").and_then(Value::as_i64);
                Ok(client
                    .admin_set_monthly_download_quota(&user_id, monthly_bytes)
                    .await
                    .map_err(|e| e.to_string())?)
            }

            "admin_download_quota_events" => {
                let client = self.require_client()?;
                let user_id = str_param(params, "user_id")?;
                let limit = params.get("limit").and_then(Value::as_u64).unwrap_or(20) as u32;
                Ok(client
                    .admin_download_quota_events(&user_id, limit)
                    .await
                    .map_err(|e| e.to_string())?)
            }

            "admin_set_library_covers" => {
                let client = self.require_client()?;
                let id = str_param(params, "id")?;
                let enabled = params
                    .get("enabled")
                    .and_then(Value::as_bool)
                    .unwrap_or(true);
                client
                    .set_library_generate_covers(&id, enabled)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(json!({"updated": id, "enabled": enabled}))
            }
            _ => Err(crate::RpcErr::Unhandled),
        }
    }
}
