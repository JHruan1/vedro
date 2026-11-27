use std::time::Duration;

use serde_json::{json, Value};

use crate::security::{
    bilibili_limiter, is_bilibili_index_url, read_reqwest_body_capped, same_origin_as_client,
    str_param, validate_http_url, MAX_AI_JSON_BYTES, MAX_SUBTITLE_BYTES,
};
use crate::VedroRuntime;

impl VedroRuntime {
    pub(crate) async fn handle_ai_rpc(
        &self,
        method: &str,
        params: &Value,
    ) -> Result<Value, crate::RpcErr> {
        match method {
            "ai_translate" => {
                let base_url = str_param(params, "base_url")?;
                let _ = validate_http_url(&base_url)?;
                let api_key = params.get("api_key").and_then(Value::as_str).unwrap_or("");
                let is_bilibili_index = is_bilibili_index_url(&base_url)
                    || params
                        .get("model")
                        .and_then(Value::as_str)
                        .map(|m| m.to_ascii_lowercase().starts_with("index-translate"))
                        .unwrap_or(false);
                let model = params
                    .get("model")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .unwrap_or(if is_bilibili_index {
                        "Index-Translate-35B-A3B"
                    } else {
                        "gpt-4o-mini"
                    });
                let text = str_param(params, "text")?;
                let target_lang = params
                    .get("target_lang")
                    .and_then(Value::as_str)
                    .unwrap_or("简体中文");
                // Bilibili Index-Translate checks client IP: always default to user's direct IP (`no_proxy`)
                // so it never exits via datacenter proxies and NEVER touches the media server!
                let direct_ip = params
                    .get("direct_ip")
                    .and_then(Value::as_bool)
                    .unwrap_or(is_bilibili_index);

                let endpoint = format!("{}/chat/completions", base_url.trim_end_matches('/'));
                let http = if direct_ip {
                    &self.http_direct
                } else {
                    &self.http_default
                };

                let payload = if is_bilibili_index {
                    json!({
                        "model": model,
                        "temperature": 0.1,
                        "messages": [
                            {
                                "role": "user",
                                "content": format!(
                                    "请将以下文本翻译为{target_lang}，直接输出翻译结果，不要进行任何解释。\n\n{text}"
                                )
                            }
                        ]
                    })
                } else {
                    let system_prompt = params
                        .get("system_prompt")
                        .and_then(Value::as_str)
                        .map(ToString::to_string)
                        .unwrap_or_else(|| {
                            format!(
                                "You are a concise cinema translator. Translate the user text naturally into {target_lang}. Output only the translation with no extra commentary."
                            )
                        });
                    json!({
                        "model": model,
                        "temperature": 0.2,
                        "messages": [
                            { "role": "system", "content": system_prompt },
                            { "role": "user", "content": text }
                        ]
                    })
                };

                let _bili_permit = if is_bilibili_index {
                    Some(bilibili_limiter().acquire_slot().await?)
                } else {
                    None
                };
                let mut req = http
                    .post(&endpoint)
                    .header(
                        reqwest::header::USER_AGENT,
                        if is_bilibili_index {
                            "Index-Translate-Client/1.0"
                        } else {
                            concat!("Vedro-Translate/", env!("CARGO_PKG_VERSION"))
                        },
                    )
                    .json(&payload);
                if !api_key.trim().is_empty() {
                    req = req.bearer_auth(api_key.trim());
                }
                let resp = match req.send().await {
                    Ok(r) => r,
                    Err(e) => {
                        if is_bilibili_index {
                            bilibili_limiter().record_failure(true);
                        }
                        return Err(crate::RpcErr::from(
                            vedro_protocol::error::format_transport_error(&e),
                        ));
                    }
                };
                let status = resp.status();
                let raw_bytes = match read_reqwest_body_capped(resp, MAX_AI_JSON_BYTES).await {
                    Ok(b) => b,
                    Err(e) => {
                        if is_bilibili_index {
                            bilibili_limiter().record_failure(true);
                        }
                        return Err(crate::RpcErr::from(e));
                    }
                };
                if !status.is_success() {
                    if is_bilibili_index {
                        bilibili_limiter().record_failure(
                            status == reqwest::StatusCode::TOO_MANY_REQUESTS
                                || status.is_server_error(),
                        );
                    }
                    let msg = serde_json::from_slice::<Value>(&raw_bytes)
                        .ok()
                        .and_then(|v| {
                            v.pointer("/error/message")
                                .and_then(Value::as_str)
                                .map(ToString::to_string)
                        })
                        .unwrap_or_else(|| "AI request failed".to_string());
                    return Err(crate::RpcErr::from(format!(
                        "HTTP {}: {msg}",
                        status.as_u16()
                    )));
                }
                let body: Value = serde_json::from_slice(&raw_bytes)
                    .map_err(|e| format!("invalid AI response ({status}): {e}"))?;
                if is_bilibili_index {
                    bilibili_limiter().record_success();
                }
                let translated = body
                    .pointer("/choices/0/message/content")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .trim()
                    .to_string();
                Ok(json!({
                    "translated": translated,
                    "direct_ip": direct_ip,
                    "provider": if is_bilibili_index { "bilibili_index" } else { "openai_compat" }
                }))
            }

            "load_subtitle_cues" => {
                let local_path = params
                    .get("local_path")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty());
                let url_param = params
                    .get("url")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty());
                let format_hint = params.get("format").and_then(Value::as_str).unwrap_or("");

                let (raw_text, ext_hint) = if let Some(path) = local_path {
                    let meta = tokio::fs::metadata(path)
                        .await
                        .map_err(|e| format!("无法读取本地字幕文件: {e}"))?;
                    if usize::try_from(meta.len()).unwrap_or(usize::MAX) > MAX_SUBTITLE_BYTES {
                        return Err(crate::RpcErr::from("字幕文件超过 16 MB 限制".to_string()));
                    }
                    let bytes = tokio::fs::read(path)
                        .await
                        .map_err(|e| format!("无法读取本地字幕文件: {e}"))?;
                    (
                        vedro_stream::decode_subtitle_bytes(&bytes),
                        if format_hint.is_empty() {
                            path
                        } else {
                            format_hint
                        },
                    )
                } else if let Some(raw_url) = url_param {
                    let (resolved_url, headers) = if let Some(client) = self.client.lock().clone() {
                        let resolved =
                            if raw_url.starts_with("http://") || raw_url.starts_with("https://") {
                                raw_url.to_string()
                            } else {
                                client
                                    .resolve_media_url(raw_url)
                                    .map(|u| u.to_string())
                                    .unwrap_or_else(|_| raw_url.to_string())
                            };
                        // Security: ONLY attach Emby auth headers when target origin matches the
                        // connected server AND does not already carry a StreamTicket!
                        let hdrs = if same_origin_as_client(&client, &resolved)
                            && !vedro_protocol::auth::url_has_stream_ticket(&resolved)
                        {
                            client.auth_headers()
                        } else {
                            reqwest::header::HeaderMap::new()
                        };
                        (resolved, hdrs)
                    } else {
                        (raw_url.to_string(), reqwest::header::HeaderMap::new())
                    };
                    let _ = validate_http_url(&resolved_url)?;

                    let resp = self
                        .http_default
                        .get(&resolved_url)
                        .headers(headers)
                        .send()
                        .await
                        .map_err(|e| {
                            format!(
                                "拉取字幕失败: {}",
                                vedro_protocol::error::format_transport_error(&e)
                            )
                        })?;
                    if !resp.status().is_success() {
                        return Err(crate::RpcErr::from(format!(
                            "拉取字幕失败: HTTP {}",
                            resp.status().as_u16()
                        )));
                    }
                    let bytes = read_reqwest_body_capped(resp, MAX_SUBTITLE_BYTES).await?;
                    (
                        vedro_stream::decode_subtitle_bytes(&bytes),
                        if format_hint.is_empty() {
                            raw_url
                        } else {
                            format_hint
                        },
                    )
                } else {
                    return Err(crate::RpcErr::from("缺少字幕地址或本地路径".to_string()));
                };

                let fmt = vedro_stream::detect_format(ext_hint, &raw_text);
                let cues = vedro_stream::parse_subtitles(&raw_text, fmt);
                let cue_json: Vec<Value> = cues
                    .into_iter()
                    .enumerate()
                    .map(|(idx, c)| {
                        json!({
                            "idx": idx,
                            "start_ms": c.start_ms,
                            "end_ms": c.end_ms,
                            "text": c.text,
                        })
                    })
                    .collect();
                Ok(json!({
                    "format": fmt,
                    "total": cue_json.len(),
                    "cues": cue_json,
                }))
            }

            "ai_translate_subtitle_batch" => {
                let base_url = str_param(params, "base_url")?;
                let _ = validate_http_url(&base_url)?;
                let api_key = params.get("api_key").and_then(Value::as_str).unwrap_or("");
                let is_bilibili_index = is_bilibili_index_url(&base_url)
                    || params
                        .get("model")
                        .and_then(Value::as_str)
                        .map(|m| m.to_ascii_lowercase().starts_with("index-translate"))
                        .unwrap_or(false);
                let model = params
                    .get("model")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .unwrap_or(if is_bilibili_index {
                        "Index-Translate-35B-A3B"
                    } else {
                        "gpt-4o-mini"
                    });
                let target_lang = params
                    .get("target_lang")
                    .and_then(Value::as_str)
                    .unwrap_or("简体中文");
                let direct_ip = params
                    .get("direct_ip")
                    .and_then(Value::as_bool)
                    .unwrap_or(is_bilibili_index);
                let media_title = params.get("media_title").and_then(Value::as_str);
                let context: Vec<String> = params
                    .get("context")
                    .and_then(Value::as_array)
                    .map(|arr| {
                        arr.iter()
                            .filter_map(Value::as_str)
                            .map(ToString::to_string)
                            .collect()
                    })
                    .unwrap_or_default();
                let raw_lines = params
                    .get("lines")
                    .and_then(Value::as_array)
                    .ok_or_else(|| "missing lines array".to_string())?;
                let mut lines: Vec<(usize, String)> = Vec::with_capacity(raw_lines.len());
                let mut expected_indices: Vec<usize> = Vec::with_capacity(raw_lines.len());
                for item in raw_lines {
                    let idx = item
                        .get("idx")
                        .and_then(Value::as_u64)
                        .ok_or_else(|| "line missing idx".to_string())?
                        as usize;
                    let text = item
                        .get("text")
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .trim()
                        .to_string();
                    if !text.is_empty() {
                        lines.push((idx, text));
                        expected_indices.push(idx);
                    }
                }
                if lines.is_empty() {
                    return Ok(json!({ "translations": {}, "model": model }));
                }

                let (sys_prompt, user_prompt) = vedro_stream::build_subtitle_batch_prompt(
                    &lines,
                    &context,
                    target_lang,
                    media_title,
                    is_bilibili_index,
                );

                let endpoint = format!("{}/chat/completions", base_url.trim_end_matches('/'));
                let http = if direct_ip {
                    &self.http_direct
                } else {
                    &self.http_default
                };

                let payload = if let Some(sys) = sys_prompt {
                    json!({
                        "model": model,
                        "temperature": 0.15,
                        "messages": [
                            { "role": "system", "content": sys },
                            { "role": "user", "content": user_prompt }
                        ]
                    })
                } else {
                    json!({
                        "model": model,
                        "temperature": 0.1,
                        "messages": [
                            { "role": "user", "content": user_prompt }
                        ]
                    })
                };

                let _bili_permit = if is_bilibili_index {
                    Some(bilibili_limiter().acquire_slot().await?)
                } else {
                    None
                };
                let mut req = http
                    .post(&endpoint)
                    .header(
                        reqwest::header::USER_AGENT,
                        if is_bilibili_index {
                            "Index-Translate-Client/1.0"
                        } else {
                            concat!("Vedro-Translate/", env!("CARGO_PKG_VERSION"))
                        },
                    )
                    .json(&payload);
                if !api_key.trim().is_empty() {
                    req = req.bearer_auth(api_key.trim());
                }
                let resp = match req.send().await {
                    Ok(r) => r,
                    Err(e) => {
                        if is_bilibili_index {
                            bilibili_limiter().record_failure(true);
                        }
                        return Err(crate::RpcErr::from(
                            vedro_protocol::error::format_transport_error(&e),
                        ));
                    }
                };
                let status = resp.status();
                let raw_bytes = match read_reqwest_body_capped(resp, MAX_AI_JSON_BYTES).await {
                    Ok(b) => b,
                    Err(e) => {
                        if is_bilibili_index {
                            bilibili_limiter().record_failure(true);
                        }
                        return Err(crate::RpcErr::from(e));
                    }
                };
                if !status.is_success() {
                    if is_bilibili_index {
                        bilibili_limiter().record_failure(
                            status == reqwest::StatusCode::TOO_MANY_REQUESTS
                                || status.is_server_error(),
                        );
                    }
                    let msg = serde_json::from_slice::<Value>(&raw_bytes)
                        .ok()
                        .and_then(|v| {
                            v.pointer("/error/message")
                                .and_then(Value::as_str)
                                .map(ToString::to_string)
                        })
                        .unwrap_or_else(|| "AI request failed".to_string());
                    return Err(crate::RpcErr::from(format!(
                        "HTTP {}: {msg}",
                        status.as_u16()
                    )));
                }
                let body: Value = serde_json::from_slice(&raw_bytes)
                    .map_err(|e| format!("invalid AI response ({status}): {e}"))?;
                if is_bilibili_index {
                    bilibili_limiter().record_success();
                }
                let content = body
                    .pointer("/choices/0/message/content")
                    .and_then(Value::as_str)
                    .unwrap_or("");
                let parsed =
                    vedro_stream::parse_subtitle_batch_response(content, &expected_indices);
                let translations: serde_json::Map<String, Value> = parsed
                    .into_iter()
                    .map(|(k, v)| (k.to_string(), Value::String(v)))
                    .collect();
                Ok(json!({
                    "translations": Value::Object(translations),
                    "model": model,
                    "direct_ip": direct_ip,
                }))
            }

            "ai_transcribe_audio_slice" => {
                let asr_base_url = str_param(params, "asr_base_url")?;
                let _ = validate_http_url(&asr_base_url)?;
                let asr_api_key = params
                    .get("asr_api_key")
                    .and_then(Value::as_str)
                    .unwrap_or("");
                let asr_model = params
                    .get("asr_model")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .unwrap_or("whisper-large-v3-turbo");
                let asr_language = params
                    .get("asr_language")
                    .and_then(Value::as_str)
                    .map(ToString::to_string);
                let prompt = params
                    .get("prompt")
                    .and_then(Value::as_str)
                    .map(ToString::to_string);
                let direct_ip = params
                    .get("direct_ip")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                let start_secs = params
                    .get("start_secs")
                    .and_then(Value::as_f64)
                    .unwrap_or(0.0)
                    .max(0.0);
                let duration_secs = params
                    .get("duration_secs")
                    .and_then(Value::as_f64)
                    .unwrap_or(25.0)
                    .clamp(5.0, 45.0);

                let local_path = params
                    .get("local_path")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty());
                let source_url = params
                    .get("source_url")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty());

                let audio_source = if let Some(p) = local_path {
                    vedro_stream::AudioSliceSource::LocalFile(std::path::PathBuf::from(p))
                } else if let Some(u) = source_url {
                    let _ = validate_http_url(u)?;
                    let hdrs = if u.starts_with("http://127.0.0.1:") {
                        reqwest::header::HeaderMap::new()
                    } else {
                        self.client
                            .lock()
                            .as_ref()
                            .filter(|c| {
                                same_origin_as_client(c, u)
                                    && !vedro_protocol::auth::url_has_stream_ticket(u)
                            })
                            .map(|c| c.auth_headers())
                            .unwrap_or_default()
                    };
                    vedro_stream::AudioSliceSource::HttpUrl {
                        url: u.to_string(),
                        headers: hdrs,
                    }
                } else {
                    return Err(crate::RpcErr::from(
                        "缺少音频源（source_url 或 local_path）".to_string(),
                    ));
                };

                let media_http = self.http_direct.clone();
                let handle = tokio::runtime::Handle::current();
                let wav_bytes = tokio::task::spawn_blocking(move || {
                    vedro_stream::extract_audio_slice_wav(
                        &audio_source,
                        start_secs,
                        duration_secs,
                        handle,
                        media_http,
                    )
                })
                .await
                .map_err(|e| format!("音频提取任务异常: {e}"))??;

                let boundary = format!("VedroAsr{}", uuid::Uuid::new_v4().simple());
                let multipart = vedro_stream::build_multipart_wav_body(
                    &wav_bytes,
                    asr_model,
                    asr_language.as_deref(),
                    prompt.as_deref(),
                    &boundary,
                );

                let endpoint = format!(
                    "{}/audio/transcriptions",
                    asr_base_url.trim_end_matches('/')
                );
                let asr_http = if direct_ip {
                    &self.http_direct
                } else {
                    &self.http_default
                };
                let mut req = asr_http
                    .post(&endpoint)
                    .header(
                        reqwest::header::CONTENT_TYPE,
                        format!("multipart/form-data; boundary={boundary}"),
                    )
                    .header(
                        reqwest::header::USER_AGENT,
                        concat!("Vedro-ASR/", env!("CARGO_PKG_VERSION")),
                    )
                    .body(multipart);
                if !asr_api_key.trim().is_empty() {
                    req = req.bearer_auth(asr_api_key.trim());
                }

                let resp = req.send().await.map_err(|e| {
                    format!(
                        "语音识别请求失败: {}",
                        vedro_protocol::error::format_transport_error(&e)
                    )
                })?;
                let status = resp.status();
                let raw_bytes = read_reqwest_body_capped(resp, MAX_AI_JSON_BYTES).await?;
                let body: Value = serde_json::from_slice(&raw_bytes)
                    .map_err(|e| format!("语音识别返回解析失败 ({status}): {e}"))?;
                if !status.is_success() {
                    let msg = body
                        .pointer("/error/message")
                        .or_else(|| body.get("message"))
                        .and_then(Value::as_str)
                        .unwrap_or("ASR request failed");
                    return Err(crate::RpcErr::from(format!(
                        "ASR HTTP {}: {msg}",
                        status.as_u16()
                    )));
                }

                let slice_start_ms = (start_secs * 1000.0).round() as i64;
                let slice_dur_ms = (duration_secs * 1000.0).round() as i64;
                let (cues, detected_lang) =
                    vedro_stream::parse_asr_response(&body, slice_start_ms, slice_dur_ms);
                let cue_json: Vec<Value> = cues
                    .into_iter()
                    .map(|c| {
                        json!({
                            "start_ms": c.start_ms,
                            "end_ms": c.end_ms,
                            "text": c.text,
                        })
                    })
                    .collect();
                Ok(json!({
                    "cues": cue_json,
                    "detected_language": detected_lang,
                    "wav_bytes": wav_bytes.len(),
                    "model": asr_model,
                }))
            }

            "extract_audio_slice_file" => {
                let start_secs = params
                    .get("start_secs")
                    .and_then(Value::as_f64)
                    .unwrap_or(0.0)
                    .max(0.0);
                let duration_secs = params
                    .get("duration_secs")
                    .and_then(Value::as_f64)
                    .unwrap_or(20.0)
                    .clamp(4.0, 45.0);
                let local_path = params
                    .get("local_path")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty());
                let source_url = params
                    .get("source_url")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty());

                let audio_source = if let Some(p) = local_path {
                    vedro_stream::AudioSliceSource::LocalFile(std::path::PathBuf::from(p))
                } else if let Some(u) = source_url {
                    let _ = validate_http_url(u)?;
                    let hdrs = if u.starts_with("http://127.0.0.1:") {
                        reqwest::header::HeaderMap::new()
                    } else {
                        self.client
                            .lock()
                            .as_ref()
                            .filter(|c| {
                                same_origin_as_client(c, u)
                                    && !vedro_protocol::auth::url_has_stream_ticket(u)
                            })
                            .map(|c| c.auth_headers())
                            .unwrap_or_default()
                    };
                    vedro_stream::AudioSliceSource::HttpUrl {
                        url: u.to_string(),
                        headers: hdrs,
                    }
                } else {
                    return Err(crate::RpcErr::from(
                        "缺少音频源（source_url 或 local_path）".to_string(),
                    ));
                };

                let media_http = self.http_direct.clone();
                let handle = tokio::runtime::Handle::current();
                let wav_bytes = tokio::task::spawn_blocking(move || {
                    vedro_stream::extract_audio_slice_wav(
                        &audio_source,
                        start_secs,
                        duration_secs,
                        handle,
                        media_http,
                    )
                })
                .await
                .map_err(|e| format!("音频提取任务异常: {e}"))??;

                let _ = tokio::fs::create_dir_all(&self.asr_temp_dir).await;
                // Periodically sweep orphaned temp WAV files older than 5 minutes
                let sweep_dir = self.asr_temp_dir.clone();
                tokio::spawn(async move {
                    if let Ok(mut rd) = tokio::fs::read_dir(&sweep_dir).await {
                        let now = std::time::SystemTime::now();
                        while let Ok(Some(ent)) = rd.next_entry().await {
                            if let Ok(meta) = ent.metadata().await {
                                if let Ok(mod_t) = meta.modified() {
                                    if now.duration_since(mod_t).unwrap_or_default()
                                        > Duration::from_secs(300)
                                    {
                                        let _ = tokio::fs::remove_file(ent.path()).await;
                                    }
                                }
                            }
                        }
                    }
                });

                let wav_path = self
                    .asr_temp_dir
                    .join(format!("vedro_asr_{}.wav", uuid::Uuid::new_v4().simple()));
                tokio::fs::write(&wav_path, &wav_bytes)
                    .await
                    .map_err(|e| format!("写入临时音频切片失败: {e}"))?;
                #[cfg(unix)]
                {
                    use std::os::unix::fs::PermissionsExt;
                    let _ =
                        std::fs::set_permissions(&wav_path, std::fs::Permissions::from_mode(0o600));
                }

                Ok(json!({
                    "wav_path": wav_path.to_string_lossy().to_string(),
                    "wav_bytes": wav_bytes.len(),
                    "sample_rate": 16000,
                }))
            }

            "ai_list_models" => {
                let base_url = str_param(params, "base_url")?;
                let _ = validate_http_url(&base_url)?;
                let api_key = params.get("api_key").and_then(Value::as_str).unwrap_or("");
                let is_bilibili_index = is_bilibili_index_url(&base_url);
                let direct_ip = params
                    .get("direct_ip")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);

                let endpoint = format!("{}/models", base_url.trim_end_matches('/'));
                let http = if direct_ip {
                    &self.http_direct
                } else {
                    &self.http_default
                };
                let _bili_permit = if is_bilibili_index {
                    Some(bilibili_limiter().acquire_slot().await?)
                } else {
                    None
                };
                let mut req = http.get(&endpoint).header(
                    reqwest::header::USER_AGENT,
                    if is_bilibili_index {
                        "Index-Translate-Client/1.0"
                    } else {
                        concat!("Vedro-Translate/", env!("CARGO_PKG_VERSION"))
                    },
                );
                if !api_key.trim().is_empty() {
                    req = req.bearer_auth(api_key.trim());
                }

                let mut models: Vec<String> = Vec::new();
                let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();
                match req.send().await {
                    Ok(resp) if resp.status().is_success() => {
                        if is_bilibili_index {
                            bilibili_limiter().record_success();
                        }
                        if let Ok(raw_bytes) =
                            read_reqwest_body_capped(resp, MAX_AI_JSON_BYTES).await
                        {
                            if let Ok(body) = serde_json::from_slice::<Value>(&raw_bytes) {
                                let arr_opt = body
                                    .get("data")
                                    .and_then(Value::as_array)
                                    .or_else(|| body.get("models").and_then(Value::as_array))
                                    .or_else(|| body.as_array());
                                if let Some(arr) = arr_opt {
                                    for item in arr {
                                        if models.len() >= 500 {
                                            break;
                                        }
                                        let id = item
                                            .get("id")
                                            .and_then(Value::as_str)
                                            .or_else(|| item.get("name").and_then(Value::as_str))
                                            .or_else(|| item.as_str())
                                            .map(str::trim)
                                            .filter(|s| !s.is_empty());
                                        if let Some(m) = id {
                                            let clean =
                                                m.strip_prefix("models/").unwrap_or(m).to_string();
                                            if seen.insert(clean.clone()) {
                                                models.push(clean);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Ok(resp) => {
                        let status = resp.status();
                        if is_bilibili_index {
                            bilibili_limiter().record_failure(
                                status == reqwest::StatusCode::TOO_MANY_REQUESTS
                                    || status.is_server_error(),
                            );
                        } else {
                            let raw_err = read_reqwest_body_capped(resp, 64 * 1024)
                                .await
                                .unwrap_or_default();
                            let text = String::from_utf8_lossy(&raw_err);
                            let msg = serde_json::from_str::<Value>(&text)
                                .ok()
                                .and_then(|v| {
                                    v.pointer("/error/message")
                                        .and_then(Value::as_str)
                                        .map(ToString::to_string)
                                })
                                .unwrap_or_else(|| format!("HTTP {}", status.as_u16()));
                            return Err(crate::RpcErr::from(format!("获取模型失败: {msg}")));
                        }
                    }
                    Err(e) => {
                        if is_bilibili_index {
                            bilibili_limiter().record_failure(true);
                        } else {
                            return Err(crate::RpcErr::from(format!(
                                "获取模型失败: {}",
                                vedro_protocol::error::format_transport_error(&e)
                            )));
                        }
                    }
                }
                if models.is_empty() && is_bilibili_index {
                    models.push("Index-Translate-35B-A3B".to_string());
                }
                models.sort();
                Ok(json!({
                    "models": models,
                    "direct_ip": direct_ip,
                }))
            }
            _ => Err(crate::RpcErr::Unhandled),
        }
    }
}
