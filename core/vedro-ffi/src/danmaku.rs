use std::sync::OnceLock;
use std::time::{Duration, Instant};

use parking_lot::Mutex;
use serde_json::{json, Value};

use crate::security::{
    is_safe_path_token, read_json_capped, read_reqwest_body_capped, str_param, validate_http_url,
    MAX_DANMAKU_BYTES,
};
use crate::VedroRuntime;

impl VedroRuntime {
    pub(crate) fn build_danmaku_http_client(&self) -> Result<reqwest::Client, String> {
        // Security: NEVER inherit a LAN media server's `accept_invalid_certs` for public internet danmaku fetches!
        let proxy_opt = self.client.lock().as_ref().and_then(|client| {
            client
                .transport_options()
                .proxy_url
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(ToString::to_string)
        });
        let mut builder = reqwest::Client::builder()
            .timeout(Duration::from_secs(12))
            .user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36");
        if let Some(p) = proxy_opt {
            if let Ok(proxy) = reqwest::Proxy::all(&p) {
                builder = builder.proxy(proxy);
            }
        }
        builder.build().map_err(|e| e.to_string())
    }

    pub(crate) async fn handle_danmaku_rpc(
        &self,
        method: &str,
        params: &Value,
    ) -> Result<Value, crate::RpcErr> {
        match method {
            "danmaku_fetch" => {
                let custom_base = params
                    .get("api_base")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty());
                if let Some(cb) = custom_base {
                    let _ = validate_http_url(cb)?;
                }
                let raw_title = str_param(params, "title")?;
                let alt_title = params
                    .get("alt_title")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty());
                let episode = params.get("episode").and_then(Value::as_u64);
                let season = params.get("season").and_then(Value::as_u64);
                let http = self.build_danmaku_http_client()?;

                // 1. Direct XML/comment URL if provided explicitly
                if let Some(base) = custom_base {
                    if base.ends_with(".xml")
                        || base.contains("/comment/")
                        || base.contains("list.so")
                    {
                        let raw = fetch_danmaku_xml_text(&http, base).await?;
                        return Ok(json!({
                            "source": "direct_xml",
                            "episode_title": raw_title,
                            "raw": raw,
                        }));
                    }
                }

                let queries = build_danmaku_queries(&raw_title, alt_title, season);

                // 2. Try user-configured DandanPlay endpoint (if set) + community DandanPlay proxy
                let mut dandan_bases: Vec<&str> = Vec::new();
                if let Some(b) = custom_base {
                    if !b.contains("api.dandanplay.net") {
                        dandan_bases.push(b);
                    }
                }
                dandan_bases.push("https://dandan-proxy.wiidede.space");
                if let Some(b) = custom_base {
                    if b.contains("api.dandanplay.net") {
                        dandan_bases.push(b);
                    }
                }

                for base in &dandan_bases {
                    for q in &queries {
                        if let Ok(Some(matched)) = dandan_auto_match(&http, base, q, episode).await
                        {
                            return Ok(matched);
                        }
                    }
                }

                // 3. Fallback to official Bilibili PGC (番剧 + 影视) & Bilibili Video XML danmaku
                for q in &queries {
                    if let Ok(Some(matched)) = bilibili_auto_match(&http, q, episode).await {
                        return Ok(matched);
                    }
                }

                Err(crate::RpcErr::from(
                    "未匹配到对应弹幕库，可尝试精简片名关键词或手动选择剧集",
                ))
            }

            "danmaku_search" => {
                let keyword = str_param(params, "keyword")?;
                let custom_base = params
                    .get("api_base")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty() && !s.contains("api.dandanplay.net"));
                if let Some(cb) = custom_base {
                    let _ = validate_http_url(cb)?;
                }
                let http = self.build_danmaku_http_client()?;
                let cleaned = clean_danmaku_title(&keyword);
                let search_kw = if cleaned.is_empty() {
                    keyword.trim().to_string()
                } else {
                    cleaned
                };

                let dandan_base = custom_base.unwrap_or("https://dandan-proxy.wiidede.space");
                let (dd_res, bili_res) = tokio::join!(
                    dandan_search_candidates(&http, dandan_base, &search_kw),
                    bilibili_search_candidates(&http, &search_kw),
                );
                let mut candidates = Vec::new();
                if let Ok(mut dd) = dd_res {
                    candidates.append(&mut dd);
                }
                if let Ok(mut bl) = bili_res {
                    candidates.append(&mut bl);
                }
                Ok(json!({ "candidates": candidates }))
            }

            "danmaku_load_target" => {
                let provider = str_param(params, "provider")?;
                let target_id = str_param(params, "target_id")?;
                let title = params
                    .get("title")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_string();
                let custom_base = params
                    .get("api_base")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty() && !s.contains("api.dandanplay.net"));
                if let Some(cb) = custom_base {
                    let _ = validate_http_url(cb)?;
                }
                if !is_safe_path_token(&target_id) {
                    return Err(crate::RpcErr::from("无效的弹幕目标 ID".to_string()));
                }
                let http = self.build_danmaku_http_client()?;

                match provider.as_str() {
                    "bilibili_cid" => {
                        let url = format!("https://comment.bilibili.com/{target_id}.xml");
                        let raw = fetch_danmaku_xml_text(&http, &url).await?;
                        Ok(json!({
                            "source": "bilibili",
                            "episode_title": title,
                            "raw": raw,
                        }))
                    }
                    "bilibili_bvid" => {
                        let view_url = format!(
                            "https://api.bilibili.com/x/web-interface/view?bvid={target_id}"
                        );
                        let raw_resp = http
                            .get(&view_url)
                            .header("Referer", "https://www.bilibili.com/")
                            .send()
                            .await
                            .map_err(|e| vedro_protocol::error::format_transport_error(&e))?;
                        if !raw_resp.status().is_success() {
                            return Err(crate::RpcErr::from(format!(
                                "B 站接口返回 HTTP {}",
                                raw_resp.status().as_u16()
                            )));
                        }
                        let raw_bytes = read_reqwest_body_capped(raw_resp, 2 * 1024 * 1024).await?;
                        let resp: Value = serde_json::from_slice(&raw_bytes)
                            .map_err(|e| format!("B 站弹幕响应解析失败: {e}"))?;
                        let cid = resp
                            .pointer("/data/cid")
                            .and_then(Value::as_u64)
                            .ok_or_else(|| "无法解析 B 站视频 CID".to_string())?;
                        let xml_url = format!("https://comment.bilibili.com/{cid}.xml");
                        let raw = fetch_danmaku_xml_text(&http, &xml_url).await?;
                        Ok(json!({
                            "source": "bilibili",
                            "episode_title": title,
                            "raw": raw,
                        }))
                    }
                    _ => {
                        let base = custom_base
                            .unwrap_or("https://dandan-proxy.wiidede.space")
                            .trim_end_matches('/');
                        let c_url = format!("{base}/api/v2/comment/{target_id}?withRelated=true");
                        let raw_resp = http
                            .get(&c_url)
                            .send()
                            .await
                            .map_err(|e| vedro_protocol::error::format_transport_error(&e))?;
                        if !raw_resp.status().is_success() {
                            return Err(crate::RpcErr::from(format!(
                                "弹弹play 返回 HTTP {}",
                                raw_resp.status().as_u16()
                            )));
                        }
                        let raw_bytes =
                            read_reqwest_body_capped(raw_resp, MAX_DANMAKU_BYTES).await?;
                        let c_json: Value = serde_json::from_slice(&raw_bytes)
                            .map_err(|e| format!("弹弹play 响应解析失败: {e}"))?;
                        Ok(json!({
                            "source": "dandan",
                            "episode_id": target_id,
                            "episode_title": title,
                            "comments": c_json.get("comments").cloned().unwrap_or_else(|| json!([])),
                        }))
                    }
                }
            }
            _ => Err(crate::RpcErr::Unhandled),
        }
    }
}

fn clean_danmaku_title(raw: &str) -> String {
    let mut s = raw.trim().to_string();
    // Strip common video extensions (to_ascii_lowercase preserves exact UTF-8 byte offsets!)
    for ext in [
        ".mkv", ".mp4", ".avi", ".ts", ".m2ts", ".mov", ".webm", ".strm",
    ] {
        if s.len() > ext.len()
            && s.is_char_boundary(s.len() - ext.len())
            && s[s.len() - ext.len()..].eq_ignore_ascii_case(ext)
        {
            s.truncate(s.len() - ext.len());
        }
    }
    // Strip leading bracket tags like `[4K]` / `【动漫】`
    while let Some(rest) = s.strip_prefix('[') {
        if let Some(idx) = rest.find(']') {
            s = rest[idx + 1..].trim().to_string();
        } else {
            break;
        }
    }
    while let Some(rest) = s.strip_prefix('【') {
        if let Some(idx) = rest.find('】') {
            s = rest[idx + '】'.len_utf8()..].trim().to_string();
        } else {
            break;
        }
    }
    // Replace dots/underscores in torrent-style names when no spaces exist
    if !s.contains(' ') && (s.matches('.').count() >= 2 || s.matches('_').count() >= 2) {
        s = s.replace(['.', '_'], " ");
    }
    // Truncate at common release / technical tokens (`to_ascii_lowercase` guarantees 1:1 byte indices!)
    let lower = s.to_ascii_lowercase();
    let cut_tokens = [
        " 2160p", " 1080p", " 720p", " 4k", " bluray", " blu-ray", " remux", " web-dl", " webrip",
        " hdtv", " hevc", " x265", " x264", " h265", " h264", " dovi", " hdr", " s01", " s02",
        " s03", " s04",
    ];
    let mut cut_at = s.len();
    for tok in cut_tokens {
        if let Some(pos) = lower.find(tok) {
            if pos >= 2 && pos < cut_at && s.is_char_boundary(pos) {
                cut_at = pos;
            }
        }
    }
    s.truncate(cut_at);
    // Strip trailing `(2024)` year suffix
    let trimmed = s.trim();
    if trimmed.ends_with(')') {
        if let Some(open) = trimmed.rfind('(') {
            let inside = trimmed[open + 1..trimmed.len() - 1].trim();
            if inside.len() == 4 && inside.chars().all(|c| c.is_ascii_digit()) && open >= 2 {
                return trimmed[..open].trim().to_string();
            }
        }
    }
    trimmed.to_string()
}

fn build_danmaku_queries(title: &str, alt_title: Option<&str>, season: Option<u64>) -> Vec<String> {
    let mut out = Vec::new();
    let base = clean_danmaku_title(title);
    if !base.is_empty() {
        if let Some(sn) = season.filter(|&n| n > 1) {
            out.push(format!("{base} 第{sn}季"));
        }
        out.push(base.clone());
        // If title contains middle dot or colon subtitle, also try main prefix
        for sep in ['：', ':', '·', '-'] {
            if let Some((head, _)) = base.split_once(sep) {
                let h = head.trim();
                if h.chars().count() >= 2 && !out.iter().any(|x| x == h) {
                    out.push(h.to_string());
                }
            }
        }
    }
    if let Some(alt) = alt_title {
        let cleaned_alt = clean_danmaku_title(alt);
        if !cleaned_alt.is_empty() && !out.iter().any(|x| x.eq_ignore_ascii_case(&cleaned_alt)) {
            out.push(cleaned_alt);
        }
    }
    if out.is_empty() && !title.trim().is_empty() {
        out.push(title.trim().to_string());
    }
    out
}

fn strip_html_tags(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    let mut in_tag = false;
    for ch in raw.chars() {
        match ch {
            '<' => in_tag = true,
            '>' => in_tag = false,
            _ if !in_tag => out.push(ch),
            _ => {}
        }
    }
    out
}

fn extract_episode_number_from_text(text: &str) -> Option<u64> {
    let trimmed = text.trim();
    if let Ok(n) = trimmed.parse::<u64>() {
        return Some(n);
    }
    // Look for `第12话` / `第12集` / `EP12` / `E12` / leading digits
    let chars: Vec<char> = trimmed.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        if chars[i].is_ascii_digit() {
            let start = i;
            while i < chars.len() && chars[i].is_ascii_digit() {
                i += 1;
            }
            let num_str: String = chars[start..i].iter().collect();
            if let Ok(n) = num_str.parse::<u64>() {
                // Skip 4-digit years like 2024 unless preceded by 第/E
                let prev = if start > 0 {
                    Some(chars[start - 1])
                } else {
                    None
                };
                if n < 1900 || matches!(prev, Some('第' | 'E' | 'e' | 'P' | 'p')) {
                    return Some(n);
                }
            }
        } else {
            i += 1;
        }
    }
    None
}

async fn fetch_danmaku_xml_text(http: &reqwest::Client, url: &str) -> Result<String, String> {
    let _ = validate_http_url(url)?;
    let resp = http
        .get(url)
        .header("Accept-Encoding", "identity")
        .send()
        .await
        .map_err(|e| vedro_protocol::error::format_transport_error(&e))?;
    if !resp.status().is_success() {
        return Err(format!("HTTP {}", resp.status().as_u16()));
    }
    let bytes = read_reqwest_body_capped(resp, MAX_DANMAKU_BYTES).await?;
    let trimmed = bytes
        .iter()
        .position(|b| !b.is_ascii_whitespace())
        .map(|pos| &bytes[pos..])
        .unwrap_or(&bytes[..]);
    // Only skip decompression when payload clearly begins with XML markup (never scan the whole
    // body for `<d `, which randomly appears inside ~2-6% of raw-deflate compressed Bilibili streams!).
    if trimmed.starts_with(b"<?xml")
        || trimmed.starts_with(b"<i")
        || trimmed.starts_with(b"<d ")
        || trimmed.starts_with(b"\xef\xbb\xbf<?xml")
        || trimmed.starts_with(b"\xef\xbb\xbf<i")
    {
        return Ok(String::from_utf8_lossy(&bytes).into_owned());
    }
    // Offload deflate/zlib decompression to blocking pool with strict 16 MiB zip-bomb cap!
    tokio::task::spawn_blocking(move || {
        use std::io::Read;
        let cap = (MAX_DANMAKU_BYTES + 1) as u64;
        let mut inflated = Vec::new();
        if flate2::read::DeflateDecoder::new(&bytes[..])
            .take(cap)
            .read_to_end(&mut inflated)
            .is_ok()
            && !inflated.is_empty()
            && inflated.len() <= MAX_DANMAKU_BYTES
        {
            return Ok(String::from_utf8_lossy(&inflated).into_owned());
        }
        let mut zlib_out = Vec::new();
        if flate2::read::ZlibDecoder::new(&bytes[..])
            .take(cap)
            .read_to_end(&mut zlib_out)
            .is_ok()
            && !zlib_out.is_empty()
            && zlib_out.len() <= MAX_DANMAKU_BYTES
        {
            return Ok(String::from_utf8_lossy(&zlib_out).into_owned());
        }
        Ok(String::from_utf8_lossy(&bytes).into_owned())
    })
    .await
    .map_err(|e| format!("弹幕解压任务异常: {e}"))?
}

async fn dandan_auto_match(
    http: &reqwest::Client,
    api_base: &str,
    query: &str,
    target_ep: Option<u64>,
) -> Result<Option<Value>, String> {
    let base = api_base.trim_end_matches('/');
    let mut search_url = reqwest::Url::parse(&format!("{base}/api/v2/search/episodes"))
        .map_err(|e| e.to_string())?;
    search_url.query_pairs_mut().append_pair("anime", query);

    let resp = http
        .get(search_url)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Ok(None);
    }
    let s_json: Value = read_json_capped(resp, 4 * 1024 * 1024).await?;
    let animes = match s_json.get("animes").and_then(Value::as_array) {
        Some(arr) if !arr.is_empty() => arr,
        _ => return Ok(None),
    };

    let q_lower = query.to_lowercase();
    let best_anime = animes
        .iter()
        .max_by_key(|a| {
            let t = a
                .get("animeTitle")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_lowercase();
            let eps_len = a
                .get("episodes")
                .and_then(Value::as_array)
                .map(|e| e.len())
                .unwrap_or(0);
            let mut score: i64 = 0;
            if t == q_lower {
                score += 1000;
            } else if t.starts_with(&q_lower) {
                score += 650;
            } else if t.contains(&q_lower) || q_lower.contains(&t) {
                score += 350;
            }
            if let Some(ep) = target_ep {
                if eps_len >= ep as usize {
                    score += 180;
                }
            }
            score
        })
        .unwrap();

    let anime_title = best_anime
        .get("animeTitle")
        .and_then(Value::as_str)
        .unwrap_or(query);
    let episodes = match best_anime.get("episodes").and_then(Value::as_array) {
        Some(arr) if !arr.is_empty() => arr,
        _ => return Ok(None),
    };

    let chosen_ep = if let Some(ep_num) = target_ep {
        episodes
            .iter()
            .find(|e| {
                e.get("episodeTitle")
                    .and_then(Value::as_str)
                    .and_then(extract_episode_number_from_text)
                    == Some(ep_num)
            })
            .or_else(|| episodes.get((ep_num.saturating_sub(1)) as usize))
            .unwrap_or(&episodes[0])
    } else {
        &episodes[0]
    };

    let ep_id = match chosen_ep.get("episodeId").and_then(Value::as_i64) {
        Some(id) => id,
        None => return Ok(None),
    };
    let ep_sub = chosen_ep
        .get("episodeTitle")
        .and_then(Value::as_str)
        .unwrap_or("");
    let full_title = if ep_sub.is_empty() {
        anime_title.to_string()
    } else {
        format!("{anime_title} · {ep_sub}")
    };

    let c_url = format!("{base}/api/v2/comment/{ep_id}?withRelated=true");
    let c_resp = http.get(&c_url).send().await.map_err(|e| e.to_string())?;
    if !c_resp.status().is_success() {
        return Ok(None);
    }
    let c_json: Value = read_json_capped(c_resp, MAX_DANMAKU_BYTES).await?;
    let comments = c_json
        .get("comments")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    if comments.is_empty() {
        return Ok(None);
    }
    Ok(Some(json!({
        "source": "dandan",
        "episode_id": ep_id,
        "episode_title": full_title,
        "comments": comments,
    })))
}

static BILI_COOKIE_CACHE: OnceLock<Mutex<Option<(Instant, String)>>> = OnceLock::new();

async fn bilibili_cookie_header(http: &reqwest::Client) -> String {
    let cache = BILI_COOKIE_CACHE.get_or_init(|| Mutex::new(None));
    if let Some((ts, ref cookie)) = *cache.lock() {
        if ts.elapsed() < Duration::from_secs(3600) {
            return cookie.clone();
        }
    }
    if let Ok(resp) = http
        .get("https://api.bilibili.com/x/frontend/finger/spi")
        .header("Referer", "https://www.bilibili.com/")
        .send()
        .await
    {
        if let Ok(v) = read_json_capped(resp, 256 * 1024).await {
            let b3 = v.pointer("/data/b_3").and_then(Value::as_str).unwrap_or("");
            let b4 = v.pointer("/data/b_4").and_then(Value::as_str).unwrap_or("");
            if !b3.is_empty() {
                let cookie = format!("buvid3={b3}; buvid4={b4}");
                *cache.lock() = Some((Instant::now(), cookie.clone()));
                return cookie;
            }
        }
    }
    "buvid3=vedro-client".to_string()
}

async fn bilibili_auto_match(
    http: &reqwest::Client,
    query: &str,
    target_ep: Option<u64>,
) -> Result<Option<Value>, String> {
    let cookie = bilibili_cookie_header(http).await;

    // 1. Official Bilibili PGC Bangumi & Film/TV (`media_bangumi`, `media_ft`)
    for search_type in ["media_bangumi", "media_ft"] {
        let mut s_url = reqwest::Url::parse("https://api.bilibili.com/x/web-interface/search/type")
            .map_err(|e| e.to_string())?;
        {
            let mut qp = s_url.query_pairs_mut();
            qp.append_pair("search_type", search_type);
            qp.append_pair("keyword", query);
        }
        let resp = match http
            .get(s_url)
            .header("Referer", "https://www.bilibili.com/")
            .header("Cookie", &cookie)
            .send()
            .await
        {
            Ok(r) if r.status().is_success() => r,
            _ => continue,
        };
        let data: Value = match read_json_capped(resp, 4 * 1024 * 1024).await {
            Ok(v) => v,
            Err(_) => continue,
        };
        let results = match data.pointer("/data/result").and_then(Value::as_array) {
            Some(arr) if !arr.is_empty() => arr,
            _ => continue,
        };
        let first = &results[0];
        let season_title =
            strip_html_tags(first.get("title").and_then(Value::as_str).unwrap_or(query));
        let season_id = match first.get("season_id").and_then(Value::as_u64) {
            Some(id) => id,
            None => continue,
        };

        let pgc_url = format!("https://api.bilibili.com/pgc/view/web/season?season_id={season_id}");
        let s_resp = match http
            .get(&pgc_url)
            .header("Referer", "https://www.bilibili.com/")
            .header("Cookie", &cookie)
            .send()
            .await
        {
            Ok(r) if r.status().is_success() => r,
            _ => continue,
        };
        let s_json: Value = match read_json_capped(s_resp, 4 * 1024 * 1024).await {
            Ok(v) => v,
            Err(_) => continue,
        };
        let eps = match s_json.pointer("/result/episodes").and_then(Value::as_array) {
            Some(arr) if !arr.is_empty() => arr,
            _ => continue,
        };

        let chosen = if let Some(ep_num) = target_ep {
            eps.iter()
                .find(|e| {
                    e.get("title")
                        .and_then(Value::as_str)
                        .and_then(|t| t.trim().parse::<u64>().ok())
                        == Some(ep_num)
                })
                .or_else(|| eps.get((ep_num.saturating_sub(1)) as usize))
                .unwrap_or(&eps[0])
        } else {
            &eps[0]
        };

        if let Some(cid) = chosen.get("cid").and_then(Value::as_u64) {
            let ep_label = chosen
                .get("long_title")
                .and_then(Value::as_str)
                .filter(|s| !s.is_empty())
                .or_else(|| chosen.get("title").and_then(Value::as_str))
                .unwrap_or("");
            let xml_url = format!("https://comment.bilibili.com/{cid}.xml");
            if let Ok(raw) = fetch_danmaku_xml_text(http, &xml_url).await {
                if raw.contains("<d ") {
                    let matched_title = if ep_label.is_empty() {
                        season_title
                    } else if ep_label.chars().all(|c| c.is_ascii_digit()) {
                        format!("{season_title} · 第{ep_label}话")
                    } else {
                        format!("{season_title} · {ep_label}")
                    };
                    return Ok(Some(json!({
                        "source": "bilibili",
                        "episode_title": matched_title,
                        "raw": raw,
                    })));
                }
            }
        }
    }

    // 2. Fallback to Bilibili user-uploaded video when not in PGC
    if target_ep.is_none() || target_ep == Some(1) {
        let mut v_url = reqwest::Url::parse("https://api.bilibili.com/x/web-interface/search/type")
            .map_err(|e| e.to_string())?;
        {
            let mut qp = v_url.query_pairs_mut();
            qp.append_pair("search_type", "video");
            qp.append_pair("keyword", query);
        }
        if let Ok(resp) = http
            .get(v_url)
            .header("Referer", "https://www.bilibili.com/")
            .header("Cookie", &cookie)
            .send()
            .await
        {
            if let Ok(data) = read_json_capped(resp, 4 * 1024 * 1024).await {
                if let Some(results) = data.pointer("/data/result").and_then(Value::as_array) {
                    let q_lower = query.to_lowercase();
                    if let Some(hit) = results.iter().find(|r| {
                        let t =
                            strip_html_tags(r.get("title").and_then(Value::as_str).unwrap_or(""))
                                .to_lowercase();
                        t.contains(&q_lower)
                    }) {
                        if let Some(bvid) = hit
                            .get("bvid")
                            .and_then(Value::as_str)
                            .filter(|b| is_safe_path_token(b))
                        {
                            let hit_title = strip_html_tags(
                                hit.get("title").and_then(Value::as_str).unwrap_or(query),
                            );
                            let view_url = format!(
                                "https://api.bilibili.com/x/web-interface/view?bvid={bvid}"
                            );
                            if let Ok(vr) = http
                                .get(&view_url)
                                .header("Referer", "https://www.bilibili.com/")
                                .header("Cookie", &cookie)
                                .send()
                                .await
                            {
                                if let Ok(vj) = read_json_capped(vr, 2 * 1024 * 1024).await {
                                    if let Some(cid) =
                                        vj.pointer("/data/cid").and_then(Value::as_u64)
                                    {
                                        let xml_url =
                                            format!("https://comment.bilibili.com/{cid}.xml");
                                        if let Ok(raw) =
                                            fetch_danmaku_xml_text(http, &xml_url).await
                                        {
                                            if raw.contains("<d ") {
                                                return Ok(Some(json!({
                                                    "source": "bilibili",
                                                    "episode_title": hit_title,
                                                    "raw": raw,
                                                })));
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Ok(None)
}

async fn dandan_search_candidates(
    http: &reqwest::Client,
    api_base: &str,
    keyword: &str,
) -> Result<Vec<Value>, String> {
    let base = api_base.trim_end_matches('/');
    let mut url = reqwest::Url::parse(&format!("{base}/api/v2/search/episodes"))
        .map_err(|e| e.to_string())?;
    url.query_pairs_mut().append_pair("anime", keyword);
    let resp = http.get(url).send().await.map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Ok(Vec::new());
    }
    let body: Value = read_json_capped(resp, 4 * 1024 * 1024).await?;
    let mut out = Vec::new();
    if let Some(animes) = body.get("animes").and_then(Value::as_array) {
        for a in animes.iter().take(8) {
            let title = a.get("animeTitle").and_then(Value::as_str).unwrap_or("");
            let kind = a
                .get("typeDescription")
                .and_then(Value::as_str)
                .unwrap_or("弹弹Play");
            let eps: Vec<Value> = a
                .get("episodes")
                .and_then(Value::as_array)
                .map(|arr| {
                    arr.iter()
                        .take(200)
                        .filter_map(|e| {
                            let id = e.get("episodeId")?.as_i64()?.to_string();
                            let ep_title =
                                e.get("episodeTitle").and_then(Value::as_str).unwrap_or("");
                            Some(json!({
                                "provider": "dandan",
                                "target_id": id,
                                "label": ep_title,
                            }))
                        })
                        .collect()
                })
                .unwrap_or_default();
            if !title.is_empty() && !eps.is_empty() {
                out.push(json!({
                    "source_badge": format!("弹弹 · {kind}"),
                    "title": title,
                    "episodes": eps,
                }));
            }
        }
    }
    Ok(out)
}

async fn bilibili_search_candidates(
    http: &reqwest::Client,
    keyword: &str,
) -> Result<Vec<Value>, String> {
    let cookie = bilibili_cookie_header(http).await;
    let mut out = Vec::new();

    for (stype, badge) in [("media_bangumi", "B站番剧"), ("media_ft", "B站影视")] {
        let mut s_url = reqwest::Url::parse("https://api.bilibili.com/x/web-interface/search/type")
            .map_err(|e| e.to_string())?;
        {
            let mut qp = s_url.query_pairs_mut();
            qp.append_pair("search_type", stype);
            qp.append_pair("keyword", keyword);
        }
        let resp = match http
            .get(s_url)
            .header("Referer", "https://www.bilibili.com/")
            .header("Cookie", &cookie)
            .send()
            .await
        {
            Ok(r) if r.status().is_success() => r,
            _ => continue,
        };
        let data: Value = match read_json_capped(resp, 4 * 1024 * 1024).await {
            Ok(v) => v,
            Err(_) => continue,
        };
        if let Some(results) = data.pointer("/data/result").and_then(Value::as_array) {
            for item in results.iter().take(4) {
                let title =
                    strip_html_tags(item.get("title").and_then(Value::as_str).unwrap_or(""));
                let season_id = match item.get("season_id").and_then(Value::as_u64) {
                    Some(id) => id,
                    None => continue,
                };
                let pgc_url =
                    format!("https://api.bilibili.com/pgc/view/web/season?season_id={season_id}");
                if let Ok(sr) = http
                    .get(&pgc_url)
                    .header("Referer", "https://www.bilibili.com/")
                    .header("Cookie", &cookie)
                    .send()
                    .await
                {
                    if let Ok(sj) = read_json_capped(sr, 4 * 1024 * 1024).await {
                        if let Some(eps_raw) =
                            sj.pointer("/result/episodes").and_then(Value::as_array)
                        {
                            let eps: Vec<Value> = eps_raw
                                .iter()
                                .take(300)
                                .filter_map(|e| {
                                    let cid = e.get("cid")?.as_u64()?.to_string();
                                    let t = e.get("title").and_then(Value::as_str).unwrap_or("");
                                    let lt =
                                        e.get("long_title").and_then(Value::as_str).unwrap_or("");
                                    let lbl = if lt.is_empty() {
                                        format!("第 {t} 话")
                                    } else {
                                        format!("{t}. {lt}")
                                    };
                                    Some(json!({
                                        "provider": "bilibili_cid",
                                        "target_id": cid,
                                        "label": lbl,
                                    }))
                                })
                                .collect();
                            if !title.is_empty() && !eps.is_empty() {
                                out.push(json!({
                                    "source_badge": badge,
                                    "title": title,
                                    "episodes": eps,
                                }));
                            }
                        }
                    }
                }
            }
        }
    }
    Ok(out)
}
