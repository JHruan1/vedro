use std::time::Duration;

use serde_json::{json, Value};
use vedro_protocol::{discover_lan_servers, ClientTransportOptions, EmbyClient};
use vedro_storage::{ServerProfile, ServerRoute};

use crate::security::str_param;
use crate::VedroRuntime;

impl VedroRuntime {
    pub(crate) async fn handle_server_rpc(
        &self,
        method: &str,
        params: &Value,
    ) -> Result<Value, crate::RpcErr> {
        match method {
            "version" => Ok(json!({
                "version": env!("CARGO_PKG_VERSION"),
                "proxy_addr": self.proxy.listen_addr().to_string(),
            })),

            "bootstrap_state" => {
                let list = self.store.list_servers().unwrap_or_default();
                let id_snap = self.identity.lock().clone();
                for srv in &list {
                    let route_url = srv
                        .active_route()
                        .map(|r| r.url.clone())
                        .filter(|u| !u.is_empty())
                        .unwrap_or_else(|| srv.url.clone());
                    let hdrs = id_snap.build_headers(srv.access_token.as_deref());
                    self.proxy
                        .register_server_image_upstream(srv.id.clone(), route_url, hdrs);
                }
                let remembered_id = self
                    .store
                    .get_setting::<String>("last_active_server_id")
                    .ok()
                    .flatten()
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty());
                let target_srv = remembered_id
                    .as_deref()
                    .and_then(|rid| {
                        list.iter().find(|s| {
                            s.id == rid && s.access_token.is_some() && s.user_id.is_some()
                        })
                    })
                    .or_else(|| {
                        list.iter()
                            .filter(|s| s.access_token.is_some() && s.user_id.is_some())
                            .max_by_key(|s| s.last_connected_at)
                    });
                let mut cached_home: Option<Value> = None;
                let raw_remembered = self
                    .store
                    .get_setting::<String>("last_active_server_id")
                    .ok()
                    .flatten();
                let logged_out_marker = raw_remembered
                    .as_deref()
                    .map(|s| s.trim().is_empty())
                    .unwrap_or(false);
                if !logged_out_marker {
                    if let Some(srv) = target_srv {
                        let route = srv.active_route();
                        let route_url = route
                            .map(|r| r.url.clone())
                            .filter(|u| !u.is_empty())
                            .unwrap_or_else(|| srv.url.clone());
                        let route_proxy = route
                            .and_then(|r| r.proxy_url.as_deref())
                            .map(str::trim)
                            .filter(|s| !s.is_empty());
                        let accept_invalid = route.map(|r| r.accept_invalid_certs).unwrap_or(false);
                        let _ = self.proxy.configure_transport(route_proxy, accept_invalid);
                        let hdrs = id_snap.build_headers(srv.access_token.as_deref());
                        self.proxy.set_image_upstream(route_url, hdrs);
                        let _ = self.attach_saved_server_optimistically();
                        cached_home = self
                            .store
                            .get_setting::<Value>(&format!("home_cache_v1:{}", srv.id))
                            .ok()
                            .flatten();
                    }
                }
                let cfg = self.playback_config.lock().clone();
                let home_layout = self
                    .store
                    .get_setting::<Value>("home_layout")
                    .ok()
                    .flatten();
                let vedro_prefs = self
                    .store
                    .get_setting::<Value>("vedro_prefs")
                    .ok()
                    .flatten();
                let downloads_queue = self
                    .store
                    .get_setting::<Value>("downloads_queue")
                    .ok()
                    .flatten();

                Ok(json!({
                    "version": env!("CARGO_PKG_VERSION"),
                    "proxy_addr": self.proxy.listen_addr().to_string(),
                    "servers": list,
                    "settings": cfg,
                    "home_layout": home_layout,
                    "vedro_prefs": vedro_prefs,
                    "downloads_queue": downloads_queue,
                    "last_active_server_id": remembered_id,
                    "cached_home": cached_home,
                }))
            }

            "discover_servers" => {
                let timeout_ms = params
                    .get("timeout_ms")
                    .and_then(Value::as_u64)
                    .unwrap_or(1500)
                    .clamp(200, 5000);
                let found = discover_lan_servers(Duration::from_millis(timeout_ms))
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(found).unwrap())
            }

            "list_servers" => {
                let list = self.store.list_servers().map_err(|e| e.to_string())?;
                let id_snap = self.identity.lock().clone();
                for srv in &list {
                    let route_url = srv
                        .active_route()
                        .map(|r| r.url.clone())
                        .filter(|u| !u.is_empty())
                        .unwrap_or_else(|| srv.url.clone());
                    let hdrs = id_snap.build_headers(srv.access_token.as_deref());
                    self.proxy
                        .register_server_image_upstream(srv.id.clone(), route_url, hdrs);
                }
                Ok(serde_json::to_value(list).unwrap())
            }

            "delete_server" => {
                let id = str_param(params, "id")?;
                self.store.delete_server(&id).map_err(|e| e.to_string())?;
                self.proxy.unregister_server_image_upstream(&id);
                if let Ok(Some(last_id)) = self.store.get_setting::<String>("last_active_server_id")
                {
                    if last_id == id {
                        let _ = self.store.set_setting("last_active_server_id", &"");
                    }
                }
                Ok(json!({"deleted": id}))
            }

            "save_server_routes" => {
                let server_id = str_param(params, "server_id")?;
                let mut profile = self
                    .store
                    .get_server(&server_id)
                    .map_err(|e| e.to_string())?
                    .ok_or_else(|| format!("server not found: {server_id}"))?;
                let routes: Vec<ServerRoute> = serde_json::from_value(
                    params.get("routes").cloned().unwrap_or_else(|| json!([])),
                )
                .map_err(|e| format!("invalid routes payload: {e}"))?;
                if routes.is_empty() {
                    return Err(crate::RpcErr::from(
                        "server must have at least one route".to_string(),
                    ));
                }
                profile.routes = routes;
                if let Some(active_id) = params.get("active_route_id").and_then(Value::as_str) {
                    if let Some(r) = profile.routes.iter().find(|r| r.id == active_id) {
                        profile.active_route_id = Some(r.id.clone());
                        profile.url = r.url.clone();
                    }
                } else if !profile
                    .routes
                    .iter()
                    .any(|r| Some(r.id.as_str()) == profile.active_route_id.as_deref())
                {
                    let first = profile.routes[0].clone();
                    profile.active_route_id = Some(first.id);
                    profile.url = first.url;
                }
                self.store
                    .upsert_server(&profile)
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(profile).unwrap())
            }

            "test_server_routes" => {
                let routes: Vec<ServerRoute> =
                    if let Some(sid) = params.get("server_id").and_then(Value::as_str) {
                        let profile = self
                            .store
                            .get_server(sid)
                            .map_err(|e| e.to_string())?
                            .ok_or_else(|| format!("server not found: {sid}"))?;
                        profile.routes
                    } else {
                        serde_json::from_value(
                            params.get("routes").cloned().unwrap_or_else(|| json!([])),
                        )
                        .map_err(|e| format!("invalid routes: {e}"))?
                    };

                let identity = self.identity.lock().clone();
                let mut set = tokio::task::JoinSet::new();
                for (idx, route) in routes.into_iter().enumerate() {
                    let id_clone = identity.clone();
                    set.spawn(async move {
                        let started = std::time::Instant::now();
                        let res = tokio::time::timeout(Duration::from_secs(5), async {
                            let client = EmbyClient::with_options(
                                &route.url,
                                id_clone,
                                ClientTransportOptions {
                                    proxy_url: route.proxy_url.clone(),
                                    accept_invalid_certs: route.accept_invalid_certs,
                                },
                            )
                            .map_err(|e| e.to_string())?;
                            client.probe_server().await.map_err(|e| e.to_string())
                        })
                        .await;
                        let elapsed_ms = started.elapsed().as_millis() as u64;
                        match res {
                            Ok(Ok(_)) => (
                                idx,
                                json!({
                                    "id": route.id,
                                    "name": route.name,
                                    "url": route.url,
                                    "ok": true,
                                    "latency_ms": elapsed_ms,
                                }),
                            ),
                            Ok(Err(err)) => (
                                idx,
                                json!({
                                    "id": route.id,
                                    "name": route.name,
                                    "url": route.url,
                                    "ok": false,
                                    "latency_ms": null,
                                    "error": err,
                                }),
                            ),
                            Err(_) => (
                                idx,
                                json!({
                                    "id": route.id,
                                    "name": route.name,
                                    "url": route.url,
                                    "ok": false,
                                    "latency_ms": null,
                                    "error": "连接超时",
                                }),
                            ),
                        }
                    });
                }
                let mut results = Vec::new();
                while let Some(joined) = set.join_next().await {
                    if let Ok(item) = joined {
                        results.push(item);
                    }
                }
                results.sort_by_key(|(idx, _)| *idx);
                let out: Vec<Value> = results.into_iter().map(|(_, v)| v).collect();
                Ok(Value::Array(out))
            }

            "probe_servers_status" => {
                let target_id = params
                    .get("server_id")
                    .and_then(Value::as_str)
                    .map(ToString::to_string);
                let servers = if let Some(sid) = target_id {
                    self.store
                        .get_server(&sid)
                        .map_err(|e| e.to_string())?
                        .into_iter()
                        .collect::<Vec<_>>()
                } else {
                    self.store.list_servers().map_err(|e| e.to_string())?
                };

                let identity = self.identity.lock().clone();
                let mut set = tokio::task::JoinSet::new();
                for srv in servers {
                    let id_clone = identity.clone();
                    set.spawn(async move {
                        let active_route = srv
                            .active_route_id
                            .as_deref()
                            .and_then(|rid| srv.routes.iter().find(|r| r.id == rid))
                            .or_else(|| srv.routes.first());
                        let url = active_route
                            .map(|r| r.url.clone())
                            .filter(|u| !u.is_empty())
                            .unwrap_or_else(|| srv.url.clone());
                        let proxy_url = active_route.and_then(|r| r.proxy_url.clone());
                        let accept_invalid_certs = active_route
                            .map(|r| r.accept_invalid_certs)
                            .unwrap_or(false);

                        let started = std::time::Instant::now();
                        let res = tokio::time::timeout(Duration::from_secs(4), async {
                            let client = EmbyClient::with_options(
                                &url,
                                id_clone,
                                ClientTransportOptions {
                                    proxy_url,
                                    accept_invalid_certs,
                                },
                            )
                            .map_err(|e| e.to_string())?;
                            let (info, _caps) =
                                client.probe_server().await.map_err(|e| e.to_string())?;
                            let elapsed_ms = started.elapsed().as_millis() as u64;

                            let counts = if let (Some(tok), Some(uid)) =
                                (srv.access_token.clone(), srv.user_id.clone())
                            {
                                client.set_credentials(tok, uid);
                                client.item_counts().await.ok()
                            } else {
                                None
                            };
                            Ok::<_, String>((elapsed_ms, info.version, counts))
                        })
                        .await;

                        let payload = match res {
                            Ok(Ok((latency_ms, version, counts))) => json!({
                                "server_id": srv.id,
                                "online": true,
                                "latency_ms": latency_ms,
                                "version": version,
                                "movie_count": counts.as_ref().map(|c| c.movie_count),
                                "series_count": counts.as_ref().map(|c| c.series_count),
                                "episode_count": counts.as_ref().map(|c| c.episode_count),
                            }),
                            Ok(Err(err)) => json!({
                                "server_id": srv.id,
                                "online": false,
                                "latency_ms": null,
                                "error": err,
                            }),
                            Err(_) => json!({
                                "server_id": srv.id,
                                "online": false,
                                "latency_ms": null,
                                "error": "连接超时",
                            }),
                        };
                        (srv.id, payload)
                    });
                }

                let mut map = serde_json::Map::new();
                while let Some(joined) = set.join_next().await {
                    if let Ok((sid, val)) = joined {
                        map.insert(sid, val);
                    }
                }
                Ok(Value::Object(map))
            }

            "switch_server_route" => {
                let server_id = str_param(params, "server_id")?;
                let route_id = str_param(params, "route_id")?;
                let mut profile = self
                    .store
                    .get_server(&server_id)
                    .map_err(|e| e.to_string())?
                    .ok_or_else(|| format!("server not found: {server_id}"))?;
                let route = profile
                    .routes
                    .iter()
                    .find(|r| r.id == route_id)
                    .cloned()
                    .ok_or_else(|| format!("route not found: {route_id}"))?;
                let token = profile
                    .access_token
                    .clone()
                    .ok_or_else(|| "server has no saved token".to_string())?;
                let user_id = profile
                    .user_id
                    .clone()
                    .ok_or_else(|| "server has no saved user_id".to_string())?;

                let eff_route_proxy = route
                    .proxy_url
                    .as_deref()
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(ToString::to_string);
                let _ = self
                    .proxy
                    .configure_transport(eff_route_proxy.as_deref(), route.accept_invalid_certs);
                let identity = self.identity.lock().clone();
                let epoch = self
                    .session_epoch
                    .fetch_add(1, std::sync::atomic::Ordering::SeqCst)
                    + 1;
                let client = EmbyClient::with_options(
                    &route.url,
                    identity,
                    ClientTransportOptions {
                        proxy_url: eff_route_proxy,
                        accept_invalid_certs: route.accept_invalid_certs,
                    },
                )
                .map_err(|e| e.to_string())?;
                let (info, caps) = client.probe_server().await.map_err(|e| e.to_string())?;
                client.set_credentials(token, user_id);
                let user = client.current_user().await.map_err(|e| e.to_string())?;

                if self.session_epoch.load(std::sync::atomic::Ordering::SeqCst) != epoch {
                    return Err(crate::RpcErr::from(
                        "切换线路已被新的会话操作取代".to_string(),
                    ));
                }

                profile.url = route.url.clone();
                profile.active_route_id = Some(route.id.clone());
                profile.last_connected_at = chrono::Utc::now().timestamp();
                let _ = self.store.upsert_server(&profile);
                let _ = self.store.set_setting("last_active_server_id", &server_id);

                let hdrs = client.auth_headers();
                let eff_url = client.effective_base_url();
                self.proxy.set_image_upstream(eff_url.clone(), hdrs.clone());
                self.proxy
                    .register_server_image_upstream(profile.id.clone(), eff_url, hdrs);
                self.explicitly_logged_out
                    .store(false, std::sync::atomic::Ordering::SeqCst);
                *self.active_server_id.lock() = Some(profile.id.clone());
                *self.client.lock() = Some(client.clone());
                self.start_websocket(client, epoch);
                Ok(json!({
                    "info": info,
                    "capabilities": caps,
                    "user": user,
                    "profile": profile,
                    "proxy_addr": self.proxy.listen_addr().to_string(),
                }))
            }

            "connect_server" => {
                let epoch = self
                    .session_epoch
                    .fetch_add(1, std::sync::atomic::Ordering::SeqCst)
                    + 1;
                let url = str_param(params, "url")?;
                if let Some(dev_name) = params.get("device_name").and_then(Value::as_str) {
                    self.identity.lock().device_name = dev_name.to_string();
                }
                let raw_proxy = params
                    .get("proxy_url")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty());
                let proxy_url = raw_proxy.map(ToString::to_string);
                let accept_invalid_certs = params
                    .get("accept_invalid_certs")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                let _ = self
                    .proxy
                    .configure_transport(proxy_url.as_deref(), accept_invalid_certs);

                let identity = self.identity.lock().clone();
                let client = EmbyClient::with_options(
                    &url,
                    identity,
                    ClientTransportOptions {
                        proxy_url,
                        accept_invalid_certs,
                    },
                )
                .map_err(|e| e.to_string())?;
                let (info, caps) = client.probe_server().await.map_err(|e| e.to_string())?;
                if self.session_epoch.load(std::sync::atomic::Ordering::SeqCst) != epoch {
                    return Err(crate::RpcErr::from(
                        "连接操作已被新的会话操作取代".to_string(),
                    ));
                }
                self.proxy
                    .set_image_upstream(client.effective_base_url(), client.auth_headers());
                self.explicitly_logged_out
                    .store(false, std::sync::atomic::Ordering::SeqCst);
                *self.active_server_id.lock() =
                    (!caps.server_id.is_empty()).then(|| caps.server_id.clone());
                *self.client.lock() = Some(client);
                Ok(json!({
                    "info": info,
                    "capabilities": caps,
                    "proxy_addr": self.proxy.listen_addr().to_string(),
                }))
            }

            "login" => {
                let client = self.require_client()?;
                let username = str_param(params, "username")?;
                let password = params.get("password").and_then(Value::as_str).unwrap_or("");
                let auth = client
                    .authenticate_by_name(&username, password)
                    .await
                    .map_err(|e| e.to_string())?;
                let caps = client.capabilities();
                let server_id = if !caps.server_id.is_empty() {
                    caps.server_id.clone()
                } else {
                    auth.server_id
                        .clone()
                        .unwrap_or_else(|| client.base_url().to_string())
                };
                let is_admin = auth
                    .user
                    .policy
                    .as_ref()
                    .map(|p| p.is_administrator)
                    .unwrap_or(false);
                let existing = self.store.get_server(&server_id).ok().flatten();
                let current_url = client.base_url().to_string();
                let mut routes = existing
                    .as_ref()
                    .map(|e| e.routes.clone())
                    .unwrap_or_default();
                let active_route_id = if let Some(found) = routes
                    .iter()
                    .find(|r| r.url.trim_end_matches('/') == current_url.trim_end_matches('/'))
                {
                    Some(found.id.clone())
                } else {
                    let rid = if routes.is_empty() {
                        "default".to_string()
                    } else {
                        uuid::Uuid::new_v4().simple().to_string()
                    };
                    let rname = if routes.is_empty() {
                        "默认线路".to_string()
                    } else {
                        format!("线路 {}", routes.len() + 1)
                    };
                    let transport = client.transport_options();
                    routes.push(ServerRoute {
                        id: rid.clone(),
                        name: rname,
                        url: current_url.clone(),
                        proxy_url: transport.proxy_url.clone(),
                        accept_invalid_certs: transport.accept_invalid_certs,
                    });
                    Some(rid)
                };

                let _ = self.store.upsert_server(&ServerProfile {
                    id: server_id.clone(),
                    name: if caps.server_name.is_empty() {
                        current_url.clone()
                    } else {
                        caps.server_name.clone()
                    },
                    url: current_url.clone(),
                    dialect: caps.dialect.as_str().to_string(),
                    user_id: Some(auth.user.id.clone()),
                    username: Some(auth.user.name.clone()),
                    access_token: Some(auth.access_token.clone()),
                    is_admin,
                    last_connected_at: chrono::Utc::now().timestamp(),
                    routes,
                    active_route_id,
                });
                let hdrs = client.auth_headers();
                let eff_url = client.effective_base_url();
                self.proxy.set_image_upstream(eff_url.clone(), hdrs.clone());
                self.proxy
                    .register_server_image_upstream(server_id.clone(), eff_url, hdrs);
                self.explicitly_logged_out
                    .store(false, std::sync::atomic::Ordering::SeqCst);
                let _ = self.store.set_setting("last_active_server_id", &server_id);
                *self.active_server_id.lock() = Some(server_id);
                let cur_epoch = self.session_epoch.load(std::sync::atomic::Ordering::SeqCst);
                self.start_websocket(client.clone(), cur_epoch);
                Ok(json!({
                    "auth": auth,
                    "capabilities": caps,
                    "proxy_addr": self.proxy.listen_addr().to_string(),
                }))
            }

            "quick_connect_initiate" => {
                let client = self.require_client()?;
                Ok(client
                    .quick_connect_initiate()
                    .await
                    .map_err(|e| e.to_string())?)
            }

            "quick_connect_check" => {
                let client = self.require_client()?;
                let secret = str_param(params, "secret")?;
                let state = client
                    .quick_connect_state(&secret)
                    .await
                    .map_err(|e| e.to_string())?;
                let authed = state
                    .get("Authenticated")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                if !authed {
                    return Ok(json!({
                        "authenticated": false,
                        "state": state,
                    }));
                }
                let auth = client
                    .authenticate_with_quick_connect(&secret)
                    .await
                    .map_err(|e| e.to_string())?;
                let caps = client.capabilities();
                let server_id = if !caps.server_id.is_empty() {
                    caps.server_id.clone()
                } else {
                    auth.server_id
                        .clone()
                        .unwrap_or_else(|| client.base_url().to_string())
                };
                let is_admin = auth
                    .user
                    .policy
                    .as_ref()
                    .map(|p| p.is_administrator)
                    .unwrap_or(false);
                let current_url = client.base_url().to_string();
                let existing = self.store.get_server(&server_id).ok().flatten();
                let mut routes = existing
                    .as_ref()
                    .map(|e| e.routes.clone())
                    .unwrap_or_default();
                let active_route_id = if let Some(found) = routes
                    .iter()
                    .find(|r| r.url.trim_end_matches('/') == current_url.trim_end_matches('/'))
                {
                    Some(found.id.clone())
                } else {
                    let rid = if routes.is_empty() {
                        "default".to_string()
                    } else {
                        uuid::Uuid::new_v4().simple().to_string()
                    };
                    let transport = client.transport_options();
                    routes.push(ServerRoute {
                        id: rid.clone(),
                        name: if routes.is_empty() {
                            "默认线路".to_string()
                        } else {
                            format!("线路 {}", routes.len() + 1)
                        },
                        url: current_url.clone(),
                        proxy_url: transport.proxy_url.clone(),
                        accept_invalid_certs: transport.accept_invalid_certs,
                    });
                    Some(rid)
                };
                let _ = self.store.upsert_server(&ServerProfile {
                    id: server_id.clone(),
                    name: if caps.server_name.is_empty() {
                        current_url.clone()
                    } else {
                        caps.server_name.clone()
                    },
                    url: current_url.clone(),
                    dialect: caps.dialect.as_str().to_string(),
                    user_id: Some(auth.user.id.clone()),
                    username: Some(auth.user.name.clone()),
                    access_token: Some(auth.access_token.clone()),
                    is_admin,
                    last_connected_at: chrono::Utc::now().timestamp(),
                    routes,
                    active_route_id,
                });
                let hdrs = client.auth_headers();
                let eff_url = client.effective_base_url();
                self.proxy.set_image_upstream(eff_url.clone(), hdrs.clone());
                self.proxy
                    .register_server_image_upstream(server_id.clone(), eff_url, hdrs);
                self.explicitly_logged_out
                    .store(false, std::sync::atomic::Ordering::SeqCst);
                let _ = self.store.set_setting("last_active_server_id", &server_id);
                *self.active_server_id.lock() = Some(server_id);
                let cur_epoch = self.session_epoch.load(std::sync::atomic::Ordering::SeqCst);
                self.start_websocket(client.clone(), cur_epoch);
                Ok(json!({
                    "authenticated": true,
                    "auth": auth,
                    "capabilities": caps,
                    "proxy_addr": self.proxy.listen_addr().to_string(),
                }))
            }

            "restore_session" => {
                let epoch = self
                    .session_epoch
                    .fetch_add(1, std::sync::atomic::Ordering::SeqCst)
                    + 1;
                let url = str_param(params, "url")?;
                let explicit_server_id = params
                    .get("server_id")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(ToString::to_string);
                let token = str_param(params, "access_token")?;
                let user_id = str_param(params, "user_id")?;
                let raw_proxy = params
                    .get("proxy_url")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty());
                let proxy_url = raw_proxy.map(ToString::to_string);
                let accept_invalid_certs = params
                    .get("accept_invalid_certs")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                let _ = self
                    .proxy
                    .configure_transport(proxy_url.as_deref(), accept_invalid_certs);

                let identity = self.identity.lock().clone();
                let client = EmbyClient::with_options(
                    &url,
                    identity,
                    ClientTransportOptions {
                        proxy_url,
                        accept_invalid_certs,
                    },
                )
                .map_err(|e| e.to_string())?;
                if let Some(ref sid) = explicit_server_id {
                    if let Ok(Some(saved)) = self.store.get_server(sid) {
                        client.seed_dialect_hint(
                            &saved.dialect,
                            Some(&saved.id),
                            Some(&saved.name),
                        );
                    }
                }
                client.set_credentials(token.clone(), user_id.clone());

                // Optimistically attach client & image upstream IMMEDIATELY before waiting on network
                // round-trips so concurrent Home/Detail/Image requests never hit "no server connected"!
                self.explicitly_logged_out
                    .store(false, std::sync::atomic::Ordering::SeqCst);
                let pre_hdrs = client.auth_headers();
                let pre_eff_url = client.effective_base_url();
                self.proxy
                    .set_image_upstream(pre_eff_url.clone(), pre_hdrs.clone());
                if let Some(ref sid) = explicit_server_id {
                    self.proxy
                        .register_server_image_upstream(sid.clone(), pre_eff_url, pre_hdrs);
                }
                *self.active_server_id.lock() = explicit_server_id.clone();
                *self.client.lock() = Some(client.clone());

                // Probe server capabilities AND validate current user in ONE RTT, retrying `current_user`
                // once if `probe_server` just discovered a reverse-proxy `/emby` subpath prefix!
                let (probe_res, user_res) =
                    tokio::join!(client.probe_server(), client.current_user());
                let (info, caps) = probe_res.map_err(|e| e.to_string())?;
                let user = match user_res {
                    Ok(u) => u,
                    Err(_) if !caps.api_prefix.is_empty() => {
                        client.current_user().await.map_err(|e| e.to_string())?
                    }
                    Err(e) => return Err(crate::RpcErr::from(e.to_string())),
                };

                if self.session_epoch.load(std::sync::atomic::Ordering::SeqCst) != epoch {
                    return Err(crate::RpcErr::from(
                        "会话恢复已被新的切换/退出操作取代".to_string(),
                    ));
                }

                // Update last_connected_at & last_active_server_id so next launch remembers this exact server
                let resolved_sid = explicit_server_id
                    .or_else(|| (!caps.server_id.is_empty()).then(|| caps.server_id.clone()));
                if let Some(ref sid) = resolved_sid {
                    let _ = self.store.set_setting("last_active_server_id", sid);
                    if let Ok(Some(mut saved)) = self.store.get_server(sid) {
                        saved.last_connected_at = chrono::Utc::now().timestamp();
                        saved.access_token = Some(token);
                        saved.user_id = Some(user_id);
                        saved.is_admin = user
                            .policy
                            .as_ref()
                            .map(|p| p.is_administrator)
                            .unwrap_or(saved.is_admin);
                        let _ = self.store.upsert_server(&saved);
                    }
                }

                let hdrs = client.auth_headers();
                let eff_url = client.effective_base_url();
                self.proxy.set_image_upstream(eff_url.clone(), hdrs.clone());
                if let Some(ref sid) = resolved_sid {
                    self.proxy
                        .register_server_image_upstream(sid.clone(), eff_url, hdrs);
                }
                *self.active_server_id.lock() = resolved_sid;
                *self.client.lock() = Some(client.clone());
                self.start_websocket(client, epoch);
                Ok(json!({
                    "info": info,
                    "capabilities": caps,
                    "user": user,
                    "proxy_addr": self.proxy.listen_addr().to_string(),
                }))
            }

            "logout" => {
                self.session_epoch
                    .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                self.explicitly_logged_out
                    .store(true, std::sync::atomic::Ordering::SeqCst);
                *self.active_server_id.lock() = None;
                let _ = self.active_session.lock().take();
                self.proxy.clear_all_streams_and_upstreams();
                let ws_opt = self.ws.lock().take();
                if let Some(mut ws) = ws_opt {
                    ws.stop().await;
                }
                let client_opt = self.client.lock().take();
                if let Some(client) = client_opt {
                    let _ = client.logout().await;
                }
                let _ = self.store.set_setting("last_active_server_id", &"");
                Ok(json!({"logged_out": true}))
            }
            _ => Err(crate::RpcErr::Unhandled),
        }
    }
}
