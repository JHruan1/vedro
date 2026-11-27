use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};

use parking_lot::Mutex;
use serde::Serialize;
use serde_json::{json, Value};

use crate::security::{read_reqwest_body_capped, str_param, validate_http_url, MAX_UPDATE_BYTES};
use crate::VedroRuntime;

#[derive(Debug, Clone, Default, Serialize)]
pub(crate) struct UpdateDownloadState {
    pub(crate) status: String, // "idle" | "downloading" | "verifying" | "ready" | "error" | "cancelled"
    pub(crate) version: String,
    pub(crate) file_name: String,
    pub(crate) file_path: Option<String>,
    pub(crate) downloaded_bytes: u64,
    pub(crate) total_bytes: Option<u64>,
    pub(crate) speed_bps: u64,
    pub(crate) sha256: Option<String>,
    pub(crate) sha256_verified: bool,
    pub(crate) error: Option<String>,
}

pub(crate) fn is_trusted_update_host(u: &url::Url) -> bool {
    if !u.scheme().eq_ignore_ascii_case("https") {
        return false;
    }
    let Some(host) = u.host_str() else {
        return false;
    };
    let h = host.to_ascii_lowercase();
    h == "github.com"
        || h == "api.github.com"
        || h == "objects.githubusercontent.com"
        || h == "release-assets.githubusercontent.com"
        || h == "github-releases.githubusercontent.com"
        || h.ends_with(".githubusercontent.com")
}

pub(crate) fn sanitize_update_filename(raw: &str) -> String {
    let base = std::path::Path::new(raw)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("vedro-update.bin");
    let cleaned: String = base
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_') {
                c
            } else {
                '_'
            }
        })
        .collect();
    if cleaned.is_empty() || cleaned.starts_with('.') {
        "vedro-update.bin".to_string()
    } else {
        cleaned
    }
}

pub(crate) fn parse_sha256sums_map(raw: &str) -> std::collections::HashMap<String, String> {
    let mut map = std::collections::HashMap::new();
    for line in raw.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let mut parts = trimmed.split_whitespace();
        let Some(hash) = parts.next() else { continue };
        let Some(name_raw) = parts.next() else {
            continue;
        };
        let hash_l = hash.to_ascii_lowercase();
        if hash_l.len() == 64 && hash_l.bytes().all(|b| b.is_ascii_hexdigit()) {
            let clean_name = name_raw.trim_start_matches('*');
            let file_only = std::path::Path::new(clean_name)
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or(clean_name);
            map.insert(file_only.to_string(), hash_l);
        }
    }
    map
}

pub(crate) fn is_safe_release_tag(tag: &str) -> bool {
    !tag.is_empty()
        && tag.len() <= 64
        && !tag.contains("..")
        && tag
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_' | '+'))
}

pub(crate) fn extract_tag_from_release_url(url: &url::Url) -> Option<String> {
    let path = url.path();
    let (_, after) = path.split_once("/releases/tag/")?;
    let seg = after.split('/').next()?.trim();
    if is_safe_release_tag(seg) {
        Some(seg.to_string())
    } else {
        None
    }
}

pub(crate) async fn fetch_sha256sums_map(
    http: &reqwest::Client,
    sums_url: &str,
    verify_hosts: bool,
) -> std::collections::HashMap<String, String> {
    let Ok(sums_parsed) = validate_http_url(sums_url) else {
        return std::collections::HashMap::new();
    };
    if verify_hosts && !is_trusted_update_host(&sums_parsed) {
        return std::collections::HashMap::new();
    }
    let Ok(s_resp) = http
        .get(sums_parsed)
        .header(
            reqwest::header::USER_AGENT,
            concat!("Vedro/", env!("CARGO_PKG_VERSION")),
        )
        .send()
        .await
    else {
        return std::collections::HashMap::new();
    };
    if !s_resp.status().is_success() {
        return std::collections::HashMap::new();
    }
    let Ok(s_bytes) = read_reqwest_body_capped(s_resp, 256 * 1024).await else {
        return std::collections::HashMap::new();
    };
    parse_sha256sums_map(&String::from_utf8_lossy(&s_bytes))
}

pub(crate) async fn fetch_github_latest_release(
    http: &reqwest::Client,
    api_url: &str,
    web_latest_url: &str,
    release_download_base: &str,
    verify_hosts: bool,
) -> Result<Value, String> {
    let parsed_api = validate_http_url(api_url)?;
    if verify_hosts && !is_trusted_update_host(&parsed_api) {
        return Err("仅允许从受信任的 GitHub 官方发布源检查更新".to_string());
    }

    // 1. Primary: GitHub REST API (returns full release notes, published_at, asset sizes)
    let primary_err: String = match http
        .get(parsed_api)
        .header(reqwest::header::ACCEPT, "application/vnd.github+json")
        .header(
            reqwest::header::USER_AGENT,
            concat!("Vedro/", env!("CARGO_PKG_VERSION")),
        )
        .send()
        .await
    {
        Ok(resp) if resp.status().is_success() => {
            if let Ok(raw_bytes) = read_reqwest_body_capped(resp, 2 * 1024 * 1024).await {
                if let Ok(release) = serde_json::from_slice::<Value>(&raw_bytes) {
                    let tag_name = release
                        .get("tag_name")
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .trim()
                        .to_string();
                    if is_safe_release_tag(&tag_name) {
                        let html_url = release
                            .get("html_url")
                            .and_then(Value::as_str)
                            .unwrap_or("https://github.com/JHruan1/vedro/releases/latest")
                            .to_string();
                        let body = release
                            .get("body")
                            .and_then(Value::as_str)
                            .unwrap_or("")
                            .to_string();
                        let published_at = release
                            .get("published_at")
                            .and_then(Value::as_str)
                            .unwrap_or("")
                            .to_string();
                        let raw_assets = release
                            .get("assets")
                            .and_then(Value::as_array)
                            .cloned()
                            .unwrap_or_default();
                        let sums_url = raw_assets
                            .iter()
                            .find_map(|a| {
                                let name = a.get("name").and_then(Value::as_str)?;
                                if name.eq_ignore_ascii_case("SHA256SUMS.txt") {
                                    a.get("browser_download_url")
                                        .and_then(Value::as_str)
                                        .map(ToString::to_string)
                                } else {
                                    None
                                }
                            })
                            .unwrap_or_else(|| {
                                format!(
                                    "{}/{}/SHA256SUMS.txt",
                                    release_download_base.trim_end_matches('/'),
                                    tag_name
                                )
                            });
                        let sha_map = fetch_sha256sums_map(http, &sums_url, verify_hosts).await;
                        let assets: Vec<Value> = raw_assets
                            .into_iter()
                            .filter_map(|a| {
                                let name = a.get("name").and_then(Value::as_str)?.to_string();
                                let url = a
                                    .get("browser_download_url")
                                    .and_then(Value::as_str)?
                                    .to_string();
                                let size = a.get("size").and_then(Value::as_u64).unwrap_or(0);
                                let sha256 = sha_map.get(&name).cloned();
                                Some(json!({
                                    "name": name,
                                    "url": url,
                                    "size": size,
                                    "sha256": sha256,
                                }))
                            })
                            .collect();
                        return Ok(json!({
                            "current_version": env!("CARGO_PKG_VERSION"),
                            "tag_name": tag_name,
                            "version": tag_name.trim_start_matches(['v', 'V']),
                            "html_url": html_url,
                            "body": body,
                            "published_at": published_at,
                            "assets": assets,
                            "source": "github_api",
                        }));
                    }
                }
            }
            "解析 GitHub API 响应失败".to_string()
        }
        Ok(resp) => format!("HTTP {}", resp.status().as_u16()),
        Err(e) => vedro_protocol::error::format_transport_error(&e),
    };

    // 2. Fallback: Rate-limit-free GitHub Web `/releases/latest` + CDN `SHA256SUMS.txt`.
    // Immune to GitHub REST API's 60 req/hr per-IP limit on shared VPN/proxy/NAT IPs!
    let parsed_web = validate_http_url(web_latest_url)?;
    if verify_hosts && !is_trusted_update_host(&parsed_web) {
        return Err(format!("检查更新失败: {primary_err}"));
    }
    let web_resp = http
        .get(parsed_web)
        .header(reqwest::header::ACCEPT, "application/json")
        .header(
            reqwest::header::USER_AGENT,
            concat!("Vedro/", env!("CARGO_PKG_VERSION")),
        )
        .send()
        .await
        .map_err(|e| {
            format!(
                "检查更新失败: {primary_err}（备用源: {}）",
                vedro_protocol::error::format_transport_error(&e)
            )
        })?;
    if !web_resp.status().is_success() {
        return Err(format!(
            "检查更新失败: {primary_err}（备用源 HTTP {}）",
            web_resp.status().as_u16()
        ));
    }
    let final_url = web_resp.url().clone();
    let web_bytes = read_reqwest_body_capped(web_resp, 1024 * 1024).await?;
    let mut tag_name = serde_json::from_slice::<Value>(&web_bytes)
        .ok()
        .and_then(|v| {
            v.get("tag_name")
                .and_then(Value::as_str)
                .map(|s| s.trim().to_string())
        })
        .filter(|t| is_safe_release_tag(t))
        .or_else(|| extract_tag_from_release_url(&final_url))
        .unwrap_or_default();
    if tag_name.is_empty() {
        return Err(format!(
            "检查更新失败: 无法解析最新版本号（主源: {primary_err}）"
        ));
    }
    let dl_base = release_download_base.trim_end_matches('/');
    let sums_url = format!("{dl_base}/{tag_name}/SHA256SUMS.txt");
    let sha_map = fetch_sha256sums_map(http, &sums_url, verify_hosts).await;
    let mut entries: Vec<(String, String)> = sha_map.into_iter().collect();
    entries.sort_by(|a, b| a.0.cmp(&b.0));
    let assets: Vec<Value> = entries
        .into_iter()
        .map(|(name, sha256)| {
            json!({
                "name": name,
                "url": format!("{dl_base}/{tag_name}/{name}"),
                "size": 0,
                "sha256": sha256,
            })
        })
        .collect();
    let html_url = if verify_hosts {
        format!("https://github.com/JHruan1/vedro/releases/tag/{tag_name}")
    } else {
        final_url.to_string()
    };
    if !tag_name.starts_with('v') && !tag_name.starts_with('V') {
        tag_name = format!("v{tag_name}");
    }
    Ok(json!({
        "current_version": env!("CARGO_PKG_VERSION"),
        "tag_name": tag_name,
        "version": tag_name.trim_start_matches(['v', 'V']),
        "html_url": html_url,
        "body": "已通过 GitHub 官方发布通道校验最新版本，支持应用内高速下载与 SHA-256 完整性校验。",
        "published_at": "",
        "assets": assets,
        "source": "github_web_fallback",
    }))
}

pub(crate) fn bytes_to_lower_hex(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for &b in bytes {
        out.push(HEX[(b >> 4) as usize] as char);
        out.push(HEX[(b & 0x0f) as usize] as char);
    }
    out
}

pub(crate) fn compute_file_sha256(path: &std::path::Path) -> Result<String, String> {
    use std::io::Read;
    let mut f = std::fs::File::open(path).map_err(|e| e.to_string())?;
    let mut ctx = ring::digest::Context::new(&ring::digest::SHA256);
    let mut buf = [0u8; 64 * 1024];
    loop {
        let n = f.read(&mut buf).map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        ctx.update(&buf[..n]);
    }
    Ok(bytes_to_lower_hex(ctx.finish().as_ref()))
}

#[allow(clippy::too_many_arguments)]
pub(crate) async fn download_and_verify_update_file(
    http: reqwest::Client,
    initial_url: String,
    part_path: PathBuf,
    final_path: PathBuf,
    expected_sha256: Option<String>,
    enforce_trusted_hosts: bool,
    state_arc: Arc<Mutex<UpdateDownloadState>>,
    cancel_arc: Arc<std::sync::atomic::AtomicBool>,
) -> Result<UpdateDownloadState, String> {
    use futures_util::StreamExt;
    use tokio::io::AsyncWriteExt;

    let mut current_url = initial_url;
    let mut resp_opt: Option<reqwest::Response> = None;
    for _ in 0..8 {
        if cancel_arc.load(std::sync::atomic::Ordering::SeqCst) {
            return Err("下载已取消".to_string());
        }
        let parsed = validate_http_url(&current_url)?;
        if enforce_trusted_hosts && !is_trusted_update_host(&parsed) {
            return Err("重定向目标不在受信任的 GitHub 官方域名白名单内".to_string());
        }
        let resp = http
            .get(parsed.clone())
            .header(
                reqwest::header::USER_AGENT,
                concat!("Vedro/", env!("CARGO_PKG_VERSION")),
            )
            .send()
            .await
            .map_err(|e| {
                format!(
                    "下载更新失败: {}",
                    vedro_protocol::error::format_transport_error(&e)
                )
            })?;
        if resp.status().is_redirection() {
            let Some(loc) = resp
                .headers()
                .get(reqwest::header::LOCATION)
                .and_then(|v| v.to_str().ok())
            else {
                return Err("下载重定向缺少 Location 头".to_string());
            };
            let next = parsed
                .join(loc)
                .map_err(|e| format!("无效的重定向地址: {e}"))?;
            current_url = next.to_string();
            continue;
        }
        resp_opt = Some(resp);
        break;
    }

    let resp = resp_opt.ok_or_else(|| "下载重定向次数过多".to_string())?;
    if !resp.status().is_success() {
        return Err(format!("下载更新失败: HTTP {}", resp.status().as_u16()));
    }
    if let Some(cl) = resp.content_length() {
        if cl > MAX_UPDATE_BYTES {
            return Err("更新安装包体积超出安全限制".to_string());
        }
        state_arc.lock().total_bytes = Some(cl);
    }

    let mut file = tokio::fs::File::create(&part_path)
        .await
        .map_err(|e| format!("创建临时安装包失败: {e}"))?;
    let mut ctx = ring::digest::Context::new(&ring::digest::SHA256);
    let mut downloaded: u64 = 0;
    let started = Instant::now();
    let mut last_tick = Instant::now();
    let mut bytes_since_tick: u64 = 0;

    let mut stream = resp.bytes_stream();
    while let Some(chunk_res) = stream.next().await {
        if cancel_arc.load(std::sync::atomic::Ordering::SeqCst) {
            drop(file);
            let _ = tokio::fs::remove_file(&part_path).await;
            return Err("下载已取消".to_string());
        }
        let chunk = chunk_res.map_err(|e| {
            format!(
                "下载中断: {}",
                vedro_protocol::error::format_transport_error(&e)
            )
        })?;
        downloaded = downloaded.saturating_add(chunk.len() as u64);
        if downloaded > MAX_UPDATE_BYTES {
            drop(file);
            let _ = tokio::fs::remove_file(&part_path).await;
            return Err("更新安装包体积超出安全限制".to_string());
        }
        file.write_all(&chunk)
            .await
            .map_err(|e| format!("写入更新包失败: {e}"))?;
        ctx.update(&chunk);
        bytes_since_tick = bytes_since_tick.saturating_add(chunk.len() as u64);

        let dt = last_tick.elapsed();
        if dt >= Duration::from_millis(250) {
            let bps = ((bytes_since_tick as f64) / dt.as_secs_f64().max(0.05)) as u64;
            let mut st = state_arc.lock();
            st.downloaded_bytes = downloaded;
            st.speed_bps = bps;
            last_tick = Instant::now();
            bytes_since_tick = 0;
        }
    }
    file.flush()
        .await
        .map_err(|e| format!("刷写更新包失败: {e}"))?;
    drop(file);

    if cancel_arc.load(std::sync::atomic::Ordering::SeqCst) {
        let _ = tokio::fs::remove_file(&part_path).await;
        return Err("下载已取消".to_string());
    }

    {
        let mut st = state_arc.lock();
        st.status = "verifying".to_string();
        st.downloaded_bytes = downloaded;
        let avg_bps = ((downloaded as f64) / started.elapsed().as_secs_f64().max(0.1)) as u64;
        st.speed_bps = avg_bps;
    }

    let actual_sha256 = bytes_to_lower_hex(ctx.finish().as_ref());
    let mut verified = false;
    if let Some(ref exp) = expected_sha256 {
        if actual_sha256 != *exp {
            let _ = tokio::fs::remove_file(&part_path).await;
            return Err(format!(
                "安装包 SHA-256 校验失败（预期 {}…，实际 {}…），已自动删除防篡改文件",
                &exp[..12.min(exp.len())],
                &actual_sha256[..12.min(actual_sha256.len())]
            ));
        }
        verified = true;
    }

    if final_path.exists() {
        let _ = tokio::fs::remove_file(&final_path).await;
    }
    tokio::fs::rename(&part_path, &final_path)
        .await
        .map_err(|e| format!("保存更新包失败: {e}"))?;

    let ready = {
        let mut st = state_arc.lock();
        st.status = "ready".to_string();
        st.file_path = Some(final_path.to_string_lossy().into_owned());
        st.downloaded_bytes = downloaded;
        if st.total_bytes.is_none() {
            st.total_bytes = Some(downloaded);
        }
        st.speed_bps = 0;
        st.sha256 = Some(actual_sha256);
        st.sha256_verified = verified;
        st.error = None;
        st.clone()
    };
    Ok(ready)
}

impl VedroRuntime {
    pub(crate) fn build_update_http_client(
        &self,
        follow_redirects: bool,
    ) -> Result<reqwest::Client, String> {
        let proxy_opt = self.client.lock().as_ref().and_then(|client| {
            client
                .transport_options()
                .proxy_url
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(ToString::to_string)
        });
        let attempt = |disable_native_certs: bool| {
            let mut b = reqwest::Client::builder()
                .connect_timeout(Duration::from_secs(15))
                .timeout(Duration::from_secs(if follow_redirects { 20 } else { 600 }))
                .tcp_nodelay(true);
            if !follow_redirects {
                b = b.redirect(reqwest::redirect::Policy::none());
            }
            if disable_native_certs {
                b = b.tls_built_in_native_certs(false);
            }
            if let Some(ref p) = proxy_opt {
                if let Ok(proxy) = reqwest::Proxy::all(p) {
                    b = b.proxy(proxy);
                }
            }
            b.build()
        };
        attempt(false)
            .or_else(|_| attempt(true))
            .map_err(|e| e.to_string())
    }

    pub(crate) async fn handle_updater_rpc(
        &self,
        method: &str,
        params: &Value,
    ) -> Result<Value, crate::RpcErr> {
        match method {
            "check_app_update" => {
                let api_url = params
                    .get("api_url")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .unwrap_or("https://api.github.com/repos/JHruan1/vedro/releases/latest");
                let http = self.build_update_http_client(true)?;
                Ok(fetch_github_latest_release(
                    &http,
                    api_url,
                    "https://github.com/JHruan1/vedro/releases/latest",
                    "https://github.com/JHruan1/vedro/releases/download",
                    true,
                )
                .await?)
            }

            "start_update_download" => {
                let url_str = str_param(params, "url")?;
                let parsed = validate_http_url(&url_str)?;
                if !is_trusted_update_host(&parsed) {
                    return Err(crate::RpcErr::from(
                        "仅允许从受信任的 GitHub 官方地址下载安装包".to_string(),
                    ));
                }
                let raw_name = params
                    .get("file_name")
                    .and_then(Value::as_str)
                    .filter(|s| !s.trim().is_empty())
                    .unwrap_or_else(|| {
                        parsed
                            .path_segments()
                            .and_then(|mut s| s.next_back())
                            .unwrap_or("vedro-update.bin")
                    });
                let safe_name = sanitize_update_filename(raw_name);
                let version = params
                    .get("version")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .trim()
                    .to_string();
                let expected_sha256 = params
                    .get("expected_sha256")
                    .and_then(Value::as_str)
                    .map(|s| s.trim().to_ascii_lowercase())
                    .filter(|s| s.len() == 64 && s.bytes().all(|b| b.is_ascii_hexdigit()));

                let epoch = self
                    .update_epoch
                    .fetch_add(1, std::sync::atomic::Ordering::SeqCst)
                    + 1;
                self.update_cancel
                    .store(false, std::sync::atomic::Ordering::SeqCst);

                let _ = std::fs::create_dir_all(&self.updates_dir);
                let final_path = self.updates_dir.join(&safe_name);
                let part_path = self.updates_dir.join(format!("{safe_name}.part"));

                // Reuse already verified cached file on disk if exact SHA-256 matches!
                if let Some(ref exp) = expected_sha256 {
                    if final_path.is_file() {
                        if let Ok(existing_hash) = compute_file_sha256(&final_path) {
                            if existing_hash == *exp {
                                let fsize =
                                    std::fs::metadata(&final_path).map(|m| m.len()).unwrap_or(0);
                                let ready_state = UpdateDownloadState {
                                    status: "ready".to_string(),
                                    version: version.clone(),
                                    file_name: safe_name.clone(),
                                    file_path: Some(final_path.to_string_lossy().into_owned()),
                                    downloaded_bytes: fsize,
                                    total_bytes: Some(fsize),
                                    speed_bps: 0,
                                    sha256: Some(existing_hash),
                                    sha256_verified: true,
                                    error: None,
                                };
                                *self.update_download.lock() = ready_state.clone();
                                return Ok(serde_json::to_value(ready_state).unwrap());
                            }
                        }
                    }
                }

                let init_state = UpdateDownloadState {
                    status: "downloading".to_string(),
                    version: version.clone(),
                    file_name: safe_name.clone(),
                    file_path: None,
                    downloaded_bytes: 0,
                    total_bytes: None,
                    speed_bps: 0,
                    sha256: None,
                    sha256_verified: false,
                    error: None,
                };
                *self.update_download.lock() = init_state.clone();

                let http = self.build_update_http_client(false)?;
                let state_arc = Arc::clone(&self.update_download);
                let cancel_arc = Arc::clone(&self.update_cancel);
                let rt_handle = tokio::runtime::Handle::current();

                // Clean up older update installers in updates_dir (keep only current download)
                let sweep_dir = self.updates_dir.clone();
                let keep_name = safe_name.clone();
                let keep_part = format!("{safe_name}.part");
                rt_handle.spawn(async move {
                    if let Ok(mut rd) = tokio::fs::read_dir(&sweep_dir).await {
                        while let Ok(Some(ent)) = rd.next_entry().await {
                            let n = ent.file_name().to_string_lossy().to_string();
                            if n != keep_name && n != keep_part {
                                let _ = tokio::fs::remove_file(ent.path()).await;
                            }
                        }
                    }
                    let res = download_and_verify_update_file(
                        http,
                        url_str,
                        part_path.clone(),
                        final_path.clone(),
                        expected_sha256,
                        true,
                        Arc::clone(&state_arc),
                        Arc::clone(&cancel_arc),
                    )
                    .await;
                    if let Err(err) = res {
                        let _ = tokio::fs::remove_file(&part_path).await;
                        let mut st = state_arc.lock();
                        if st.status != "cancelled" {
                            st.status = "error".to_string();
                            st.speed_bps = 0;
                            st.error = Some(err);
                        }
                    }
                });

                let _ = epoch;
                Ok(serde_json::to_value(init_state).unwrap())
            }

            "get_update_download_status" => {
                let st = self.update_download.lock().clone();
                Ok(serde_json::to_value(st).unwrap())
            }

            "cancel_update_download" => {
                self.update_cancel
                    .store(true, std::sync::atomic::Ordering::SeqCst);
                let mut st = self.update_download.lock();
                if st.status == "downloading" || st.status == "verifying" {
                    st.status = "cancelled".to_string();
                    st.speed_bps = 0;
                    st.error = None;
                }
                Ok(serde_json::to_value(st.clone()).unwrap())
            }
            _ => Err(crate::RpcErr::Unhandled),
        }
    }
}
