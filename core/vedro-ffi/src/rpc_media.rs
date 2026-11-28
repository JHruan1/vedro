use std::sync::Arc;
use std::time::Duration;

use serde_json::{json, Value};
use vedro_playback::{AudioOutputMode, PlaybackConfig, ToneMappingAlgorithm};
use vedro_protocol::{
    ClientTransportOptions, EmbyClient, ItemsQuery, MediaSourceInfo, MediaStream,
    PlaybackProgressPayload,
};
use vedro_stream::{inspect_media_header, InspectedMedia};

use crate::security::{container_mime_type, same_origin_as_client, str_param, validate_http_url};
use crate::types::{
    ActivePlaybackSession, CombinedPlayerStats, ExternalSubtitle, PreparedPlayback,
};
use crate::VedroRuntime;

impl VedroRuntime {
    pub(crate) async fn handle_media_rpc(
        &self,
        method: &str,
        params: &Value,
    ) -> Result<Value, crate::RpcErr> {
        match method {
            "get_home" => {
                let epoch = self.session_epoch.load(std::sync::atomic::Ordering::SeqCst);
                let client = self.require_client()?;
                let snap_sid = self.active_server_id.lock().clone();
                let include_suggestions = params
                    .get("include_suggestions")
                    .and_then(Value::as_bool)
                    .unwrap_or(true);
                let include_favorites = params
                    .get("include_favorites")
                    .and_then(Value::as_bool)
                    .unwrap_or(true);

                // Kick off `views` + `latest` pipeline concurrently with `resume`, `next_up`, `popular`,
                // `suggestions`, and `favorites` so `latest` NEVER waits for slower secondary rails!
                let views_and_latest_fut = async {
                    let views = client.views().await.map_err(|e| e.to_string())?;
                    let mut join_set = tokio::task::JoinSet::new();
                    for (idx, lib) in views.items.iter().take(8).cloned().enumerate() {
                        let c = client.clone();
                        join_set.spawn(async move {
                            let items = c.latest(Some(&lib.id), 16).await.unwrap_or_default();
                            (idx, lib, items)
                        });
                    }
                    let mut fetched_latest = Vec::new();
                    while let Some(res) = join_set.join_next().await {
                        if let Ok(tuple) = res {
                            fetched_latest.push(tuple);
                        }
                    }
                    fetched_latest.sort_by_key(|(idx, _, _)| *idx);
                    let latest_by_library: Vec<Value> = fetched_latest
                        .into_iter()
                        .filter(|(_, _, items)| !items.is_empty())
                        .map(|(_, lib, items)| {
                            json!({
                                "library": lib,
                                "items": items,
                            })
                        })
                        .collect();
                    Ok::<_, String>((views.items, latest_by_library))
                };

                let suggestions_fut = async {
                    if include_suggestions {
                        client.suggestions(16).await.unwrap_or_default().items
                    } else {
                        Vec::new()
                    }
                };
                let favorites_fut = async {
                    if include_favorites {
                        client.home_favorites(16).await.unwrap_or_default().items
                    } else {
                        Vec::new()
                    }
                };

                let (vl_r, resume_r, next_up_r, popular_r, suggestions, favorites) = tokio::join!(
                    views_and_latest_fut,
                    client.resume(20, None),
                    client.next_up(20, None),
                    client.popular(10),
                    suggestions_fut,
                    favorites_fut,
                );
                let (views_items, latest_by_library) = vl_r?;
                let resume = resume_r.unwrap_or_default();
                let next_up = next_up_r.unwrap_or_default();
                let popular = popular_r.unwrap_or_default();

                let out = json!({
                    "capabilities": client.capabilities(),
                    "views": views_items,
                    "popular": popular,
                    "resume": resume.items,
                    "next_up": next_up.items,
                    "suggestions": suggestions,
                    "favorites": favorites,
                    "latest_by_library": latest_by_library,
                });

                // Persist Home SWR snapshot asynchronously ONLY if session_epoch hasn't moved
                // (prevents writing Server A's Home payload into Server B's SWR cache!).
                if self.session_epoch.load(std::sync::atomic::Ordering::SeqCst) == epoch {
                    let cache_sid =
                        snap_sid
                            .filter(|s| !s.trim().is_empty())
                            .unwrap_or_else(|| {
                                let cid = client.capabilities().server_id;
                                if cid.is_empty() {
                                    client.base_url().to_string()
                                } else {
                                    cid
                                }
                            });
                    let store_bg = Arc::clone(&self.store);
                    let out_bg = out.clone();
                    let key_bg = format!("home_cache_v1:{cache_sid}");
                    tokio::task::spawn_blocking(move || {
                        let _ = store_bg.set_setting(&key_bg, &out_bg);
                    });
                }

                Ok(out)
            }

            "get_next_up_for_series" => {
                let client = self.require_client()?;
                let series_id = str_param(params, "series_id")?;
                let res = client
                    .next_up(5, Some(&series_id))
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "get_track_preference" => {
                let scope_id = params
                    .get("scope_id")
                    .or_else(|| params.get("series_or_item_id"))
                    .and_then(Value::as_str)
                    .filter(|s| !s.trim().is_empty())
                    .map(ToString::to_string)
                    .ok_or_else(|| "missing required string parameter `scope_id`".to_string())?;
                let server_id = params
                    .get("server_id")
                    .and_then(Value::as_str)
                    .filter(|s| !s.trim().is_empty())
                    .map(ToString::to_string)
                    .or_else(|| self.active_server_id.lock().clone())
                    .unwrap_or_else(|| "local".to_string());
                let pref = self
                    .store
                    .get_track_preference(&server_id, &scope_id)
                    .map_err(|e| e.to_string())?;
                Ok(json!({ "preference": pref }))
            }

            "set_track_preference" => {
                let scope_id = params
                    .get("scope_id")
                    .or_else(|| params.get("series_or_item_id"))
                    .and_then(Value::as_str)
                    .filter(|s| !s.trim().is_empty())
                    .map(ToString::to_string)
                    .ok_or_else(|| "missing required string parameter `scope_id`".to_string())?;
                let server_id = params
                    .get("server_id")
                    .and_then(Value::as_str)
                    .filter(|s| !s.trim().is_empty())
                    .map(ToString::to_string)
                    .or_else(|| self.active_server_id.lock().clone())
                    .unwrap_or_else(|| "local".to_string());
                let existing = self
                    .store
                    .get_track_preference(&server_id, &scope_id)
                    .ok()
                    .flatten();
                let pref = vedro_storage::TrackPreference {
                    server_id,
                    scope_id,
                    audio_lang: params
                        .get("audio_lang")
                        .and_then(Value::as_str)
                        .map(ToString::to_string)
                        .or_else(|| existing.as_ref().and_then(|e| e.audio_lang.clone())),
                    subtitle_lang: params
                        .get("subtitle_lang")
                        .and_then(Value::as_str)
                        .map(ToString::to_string)
                        .or_else(|| existing.as_ref().and_then(|e| e.subtitle_lang.clone())),
                    subtitle_disabled: params
                        .get("subtitle_disabled")
                        .and_then(Value::as_bool)
                        .unwrap_or_else(|| {
                            existing
                                .as_ref()
                                .map(|e| e.subtitle_disabled)
                                .unwrap_or(false)
                        }),
                    playback_speed: params
                        .get("playback_speed")
                        .and_then(Value::as_f64)
                        .filter(|v| v.is_finite())
                        .map(|v| v.clamp(0.25, 4.0))
                        .unwrap_or_else(|| {
                            existing.as_ref().map(|e| e.playback_speed).unwrap_or(1.0)
                        }),
                    skip_intro_secs: params
                        .get("skip_intro_secs")
                        .and_then(Value::as_i64)
                        .unwrap_or_else(|| {
                            existing.as_ref().map(|e| e.skip_intro_secs).unwrap_or(0)
                        }),
                };
                self.store
                    .set_track_preference(&pref)
                    .map_err(|e| e.to_string())?;
                Ok(json!({ "saved": true, "preference": pref }))
            }

            "get_items" => {
                let client = self.require_client()?;
                let query: ItemsQuery = serde_json::from_value(params.clone()).unwrap_or_default();
                let res = client.items(&query).await.map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "get_item" => {
                let client = self.require_client()?;
                let id = str_param(params, "item_id")?;
                let (item_r, similar_r, segments_r) = tokio::join!(
                    client.item(&id),
                    client.similar(&id, 12),
                    client.media_segments(&id),
                );
                let mut item = item_r.map_err(|e| e.to_string())?;
                self.enrich_item_with_learned_tracks(&mut item);
                let similar = similar_r.unwrap_or_default();
                let segments = segments_r.unwrap_or_default();
                Ok(json!({
                    "item": item,
                    "similar": similar.items,
                    "segments": segments.items,
                }))
            }

            "get_seasons" => {
                let client = self.require_client()?;
                let series_id = str_param(params, "series_id")?;
                let res = client
                    .seasons(&series_id)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "get_episodes" => {
                let client = self.require_client()?;
                let series_id = str_param(params, "series_id")?;
                let season_id = params.get("season_id").and_then(Value::as_str);
                let start_index = params.get("start_index").and_then(Value::as_u64);
                let limit = params.get("limit").and_then(Value::as_u64);
                let mut res = client
                    .episodes(&series_id, season_id, start_index, limit)
                    .await
                    .map_err(|e| e.to_string())?;
                self.enrich_items_batch_with_learned_tracks(&mut res.items);
                Ok(serde_json::to_value(res).map_err(|e| e.to_string())?)
            }

            "get_filters" => {
                let client = self.require_client()?;
                let parent_id = params.get("parent_id").and_then(Value::as_str);
                let res = client
                    .filters2(parent_id)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "search_hints" => {
                let client = self.require_client()?;
                let term = str_param(params, "term")?;
                let types = params.get("include_item_types").and_then(Value::as_str);
                let limit = params.get("limit").and_then(Value::as_u64).unwrap_or(30) as u32;
                let res = client
                    .search_hints(&term, types, limit)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "aggregated_search" => {
                let term = str_param(params, "term")?;
                let limit = params.get("limit").and_then(Value::as_u64).unwrap_or(24) as u32;
                let saved = self.store.list_servers().unwrap_or_default();
                let identity = self.identity.lock().clone();
                let mut set = tokio::task::JoinSet::new();

                for srv in saved {
                    let (Some(token), Some(uid)) = (srv.access_token.clone(), srv.user_id.clone())
                    else {
                        continue;
                    };
                    let active_route = srv.active_route().cloned();
                    let route_url = active_route
                        .as_ref()
                        .map(|r| r.url.clone())
                        .unwrap_or_else(|| srv.url.clone());
                    let proxy_url = active_route.as_ref().and_then(|r| r.proxy_url.clone());
                    let accept_invalid = active_route
                        .as_ref()
                        .map(|r| r.accept_invalid_certs)
                        .unwrap_or(false);

                    let hdrs = identity.build_headers(Some(&token));
                    self.proxy.register_server_image_upstream(
                        srv.id.clone(),
                        route_url.clone(),
                        hdrs,
                    );

                    let id_clone = identity.clone();
                    let term_clone = term.clone();
                    set.spawn(async move {
                        let res = tokio::time::timeout(Duration::from_secs(6), async {
                            let client = EmbyClient::with_options(
                                &route_url,
                                id_clone,
                                ClientTransportOptions {
                                    proxy_url,
                                    accept_invalid_certs: accept_invalid,
                                },
                            )
                            .map_err(|e| e.to_string())?;
                            client.set_credentials(token, uid);
                            client
                                .search_hints(&term_clone, None, limit)
                                .await
                                .map_err(|e| e.to_string())
                        })
                        .await;
                        (srv, res)
                    });
                }

                let mut items_out = Vec::new();
                let mut servers_out = Vec::new();
                while let Some(joined) = set.join_next().await {
                    let Ok((srv, res)) = joined else { continue };
                    match res {
                        Ok(Ok(hints)) => {
                            let count = hints.search_hints.len();
                            servers_out.push(json!({
                                "server_id": srv.id,
                                "server_name": srv.name,
                                "count": count,
                                "ok": true,
                            }));
                            for h in hints.search_hints {
                                let item_id = if !h.item_id.is_empty() {
                                    h.item_id
                                } else {
                                    h.id
                                };
                                items_out.push(json!({
                                    "server_id": srv.id,
                                    "server_name": srv.name,
                                    "id": item_id,
                                    "name": h.name,
                                    "type": h.item_type,
                                    "production_year": h.production_year,
                                    "primary_image_tag": h.primary_image_tag,
                                    "series": h.series,
                                    "run_time_ticks": h.run_time_ticks,
                                }));
                            }
                        }
                        _ => {
                            servers_out.push(json!({
                                "server_id": srv.id,
                                "server_name": srv.name,
                                "count": 0,
                                "ok": false,
                            }));
                        }
                    }
                }

                // Fallback to currently connected client if no saved servers were queried
                if servers_out.is_empty() {
                    if let Ok(client) = self.require_client() {
                        if let Ok(hints) = client.search_hints(&term, None, limit).await {
                            let caps = client.capabilities();
                            let sid = if caps.server_id.is_empty() {
                                "active".to_string()
                            } else {
                                caps.server_id.clone()
                            };
                            let sname = if caps.server_name.is_empty() {
                                "当前服务器".to_string()
                            } else {
                                caps.server_name.clone()
                            };
                            servers_out.push(json!({
                                "server_id": sid,
                                "server_name": sname,
                                "count": hints.search_hints.len(),
                                "ok": true,
                            }));
                            for h in hints.search_hints {
                                let item_id = if !h.item_id.is_empty() {
                                    h.item_id
                                } else {
                                    h.id
                                };
                                items_out.push(json!({
                                    "server_id": sid,
                                    "server_name": sname,
                                    "id": item_id,
                                    "name": h.name,
                                    "type": h.item_type,
                                    "production_year": h.production_year,
                                    "primary_image_tag": h.primary_image_tag,
                                    "series": h.series,
                                    "run_time_ticks": h.run_time_ticks,
                                }));
                            }
                        }
                    }
                }

                Ok(json!({
                    "servers": servers_out,
                    "items": items_out,
                    "proxy_addr": self.proxy.listen_addr().to_string(),
                }))
            }

            "get_person_credits" => {
                let client = self.require_client()?;
                let person_id = str_param(params, "person_id")?;
                let res = client
                    .person_credits(&person_id)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "set_favorite" => {
                let client = self.require_client()?;
                let item_id = str_param(params, "item_id")?;
                let favorite = params
                    .get("favorite")
                    .and_then(Value::as_bool)
                    .unwrap_or(true);
                let res = client
                    .set_favorite(&item_id, favorite)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "set_played" => {
                let client = self.require_client()?;
                let item_id = str_param(params, "item_id")?;
                let played = params
                    .get("played")
                    .and_then(Value::as_bool)
                    .unwrap_or(true);
                let res = client
                    .set_played(&item_id, played)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "hide_from_resume" => {
                let client = self.require_client()?;
                let item_id = str_param(params, "item_id")?;
                let hide = params.get("hide").and_then(Value::as_bool).unwrap_or(true);
                let res = client
                    .hide_from_resume(&item_id, hide)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "list_playlists" => {
                let client = self.require_client()?;
                let res = client.playlists().await.map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "get_playlist_items" => {
                let client = self.require_client()?;
                let playlist_id = str_param(params, "playlist_id")?;
                let res = client
                    .playlist_items(&playlist_id)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "create_playlist" => {
                let client = self.require_client()?;
                let name = str_param(params, "name")?;
                let item_ids: Vec<String> = params
                    .get("item_ids")
                    .and_then(Value::as_array)
                    .map(|a| {
                        a.iter()
                            .filter_map(|v| v.as_str().map(ToString::to_string))
                            .collect()
                    })
                    .unwrap_or_default();
                let res = client
                    .create_playlist(&name, &item_ids)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "add_to_playlist" => {
                let client = self.require_client()?;
                let playlist_id = str_param(params, "playlist_id")?;
                let item_ids: Vec<String> = params
                    .get("item_ids")
                    .and_then(Value::as_array)
                    .map(|a| {
                        a.iter()
                            .filter_map(|v| v.as_str().map(ToString::to_string))
                            .collect()
                    })
                    .unwrap_or_default();
                client
                    .add_to_playlist(&playlist_id, &item_ids)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(json!({"added": true}))
            }

            "remove_from_playlist" => {
                let client = self.require_client()?;
                let playlist_id = str_param(params, "playlist_id")?;
                let entry_ids: Vec<String> = params
                    .get("entry_ids")
                    .and_then(Value::as_array)
                    .map(|a| {
                        a.iter()
                            .filter_map(|v| v.as_str().map(ToString::to_string))
                            .collect()
                    })
                    .unwrap_or_default();
                client
                    .remove_from_playlist(&playlist_id, &entry_ids)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(json!({"removed": true}))
            }

            "probe_media_source" => {
                let client = self.require_client()?;
                let item_id = str_param(params, "item_id")?;
                let media_source_id = params
                    .get("media_source_id")
                    .and_then(Value::as_str)
                    .filter(|s| !s.trim().is_empty());

                let cache_key = format!(
                    "source_probe_v1:{}:{}",
                    item_id,
                    media_source_id.unwrap_or("default")
                );
                if let Ok(Some(cached)) = self.store.get_setting::<Value>(&cache_key) {
                    if cached
                        .get("media_source")
                        .and_then(|m| m.get("MediaStreams"))
                        .and_then(Value::as_array)
                        .map(|arr| {
                            arr.iter().any(|s| {
                                s.get("Type")
                                    .and_then(Value::as_str)
                                    .map(|t| {
                                        t.eq_ignore_ascii_case("Audio")
                                            || t.eq_ignore_ascii_case("Video")
                                    })
                                    .unwrap_or(false)
                            })
                        })
                        .unwrap_or(false)
                    {
                        return Ok(cached);
                    }
                }

                // 1. Ask server PlaybackInfo with EnableMediaProbe=true for this exact MediaSourceId
                let pb = client
                    .playback_info_with_probe(&item_id, media_source_id, None, None, true)
                    .await
                    .map_err(|e| e.to_string())?;
                let mut chosen = if let Some(target_id) = media_source_id {
                    pb.media_sources
                        .iter()
                        .find(|s| s.id == target_id)
                        .cloned()
                        .or_else(|| pb.media_sources.first().cloned())
                } else {
                    pb.media_sources.first().cloned()
                }
                .ok_or_else(|| "no media source returned".to_string())?;

                let has_embedded_av = chosen.media_streams.iter().any(|s| {
                    s.stream_type.eq_ignore_ascii_case("Audio")
                        || s.stream_type.eq_ignore_ascii_case("Video")
                });

                // 2. Fallback: if server still returned zero embedded AV streams (e.g. unprobed file or
                //    version with sidecar subtitles), read first 512 KiB via HTTP Range & parse container tracks!
                if !has_embedded_av {
                    if let Some(dsu) = chosen.direct_stream_url.clone() {
                        if let Ok(upstream_url) = client.resolve_media_url(&dsu) {
                            let uses_ticket =
                                vedro_protocol::auth::url_has_stream_ticket(upstream_url.as_str());
                            let headers = if !uses_ticket
                                && same_origin_as_client(&client, upstream_url.as_str())
                            {
                                client.auth_headers()
                            } else {
                                let mut h = reqwest::header::HeaderMap::new();
                                if let Ok(ua) = reqwest::header::HeaderValue::from_str(
                                    &client.identity().user_agent(),
                                ) {
                                    h.insert(reqwest::header::USER_AGENT, ua);
                                }
                                h
                            };
                            let (temp_id, _) = self.proxy.register_stream(
                                upstream_url.to_string(),
                                headers,
                                chosen.size,
                                chosen.container.as_deref().map(container_mime_type),
                            );
                            let header_bytes = self.proxy.read_range(&temp_id, 0, 512 * 1024).await;
                            self.proxy.unregister_stream(&temp_id);

                            if let Some(bytes) = header_bytes {
                                let tracks = vedro_stream::inspect_media_tracks(&bytes);
                                if !tracks.is_empty() {
                                    let base_idx = chosen
                                        .media_streams
                                        .iter()
                                        .map(|s| s.index.saturating_add(1))
                                        .max()
                                        .unwrap_or(0)
                                        .max(0);
                                    for (offset, t) in tracks.into_iter().enumerate() {
                                        chosen.media_streams.push(vedro_protocol::MediaStream {
                                            index: base_idx.saturating_add(offset as i32),
                                            stream_type: t.stream_type,
                                            codec: Some(t.codec),
                                            language: t.language,
                                            title: t.title,
                                            display_title: Some(t.display_title),
                                            is_default: t.is_default,
                                            is_forced: t.is_forced,
                                            is_external: false,
                                            is_text_subtitle_stream: t.is_text_subtitle,
                                            width: t.width,
                                            height: t.height,
                                            channels: t.channels,
                                            video_range: t.video_range,
                                            ..Default::default()
                                        });
                                    }
                                }
                            }
                        }
                    }
                }

                let out = json!({
                    "media_source": chosen,
                    "probed": true,
                });
                if chosen.media_streams.iter().any(|s| {
                    s.stream_type.eq_ignore_ascii_case("Audio")
                        || s.stream_type.eq_ignore_ascii_case("Video")
                }) {
                    let _ = self.store.set_setting(&cache_key, &out);
                }
                Ok(out)
            }

            "save_learned_tracks" => {
                let item_id = str_param(params, "item_id")?;
                let media_source_id = params
                    .get("media_source_id")
                    .and_then(Value::as_str)
                    .filter(|s| !s.trim().is_empty())
                    .unwrap_or("default");
                let streams: Vec<MediaStream> = serde_json::from_value(
                    params.get("streams").cloned().unwrap_or_else(|| json!([])),
                )
                .map_err(|e| format!("invalid learned streams: {e}"))?;
                if !streams.is_empty() {
                    let learned_key = format!("learned_streams_v1:{item_id}:{media_source_id}");
                    let _ = self.store.set_setting(&learned_key, &streams);
                }
                Ok(json!({"saved": true}))
            }

            "prepare_playback" => {
                let pb_epoch = self
                    .playback_epoch
                    .fetch_add(1, std::sync::atomic::Ordering::SeqCst)
                    + 1;
                let client = self.require_client()?;
                let item_id = str_param(params, "item_id")?;
                let media_source_id = params.get("media_source_id").and_then(Value::as_str);
                let audio_idx = params
                    .get("audio_stream_index")
                    .and_then(Value::as_i64)
                    .map(|v| v as i32);
                let sub_idx = params
                    .get("subtitle_stream_index")
                    .and_then(Value::as_i64)
                    .map(|v| v as i32);
                let inspect_header = params
                    .get("inspect_header")
                    .and_then(Value::as_bool)
                    .unwrap_or(true);

                let pb = client
                    .playback_info(&item_id, media_source_id, audio_idx, sub_idx)
                    .await
                    .map_err(|e| e.to_string())?;

                let chosen = media_source_id
                    .and_then(|req_id| pb.media_sources.iter().find(|s| s.id == req_id))
                    .or_else(|| pb.media_sources.first())
                    .cloned()
                    .ok_or_else(|| "no media source returned".to_string())?;

                let is_transcode_hls = chosen.direct_stream_url.is_none()
                    && chosen.transcoding_url.is_some()
                    && !chosen.supports_direct_play
                    && !chosen.supports_direct_stream;

                let upstream_url = if let Some(dsu) = &chosen.direct_stream_url {
                    client.resolve_media_url(dsu).map_err(|e| e.to_string())?
                } else if is_transcode_hls {
                    client
                        .resolve_media_url(chosen.transcoding_url.as_deref().unwrap_or_default())
                        .map_err(|e| e.to_string())?
                } else {
                    client
                        .build_fallback_video_url(
                            &item_id,
                            &chosen.id,
                            chosen.container.as_deref(),
                            &pb.play_session_id,
                        )
                        .map_err(|e| e.to_string())?
                };
                let uses_ticket =
                    vedro_protocol::auth::url_has_stream_ticket(upstream_url.as_str());

                // Security: ONLY attach Emby auth headers when upstream matches the connected
                // server origin AND does not already carry a StreamTicket!
                let headers =
                    if !uses_ticket && same_origin_as_client(&client, upstream_url.as_str()) {
                        client.auth_headers()
                    } else {
                        let mut h = reqwest::header::HeaderMap::new();
                        if let Ok(ua) =
                            reqwest::header::HeaderValue::from_str(&client.identity().user_agent())
                        {
                            h.insert(reqwest::header::USER_AGENT, ua);
                        }
                        h
                    };

                let (stream_id, proxy_url) = if is_transcode_hls {
                    // HLS m3u8 transcode playlists must be read directly by libmpv (not byte-chunked)
                    (String::new(), upstream_url.to_string())
                } else {
                    self.proxy.register_stream(
                        upstream_url.to_string(),
                        headers,
                        chosen.size,
                        chosen.container.as_deref().map(container_mime_type),
                    )
                };

                // Fast-path startup (inspect_header: false): NEVER block first frame on downloading
                // Chunk 0 over WAN/cloud-drive! StreamProxy::register_stream already pre-warms Chunk 0
                // & tail chunk in parallel; infer HDR/Atmos in 0ms from PlaybackInfo metadata and learn
                // embedded tracks asynchronously in the background once Chunk 0 arrives.
                let badges = chosen.infer_badges();
                let inspected = if inspect_header && !stream_id.is_empty() {
                    self.proxy
                        .read_range(&stream_id, 0, 256 * 1024)
                        .await
                        .map(|bytes| {
                            let has_av = chosen.media_streams.iter().any(|s| {
                                s.stream_type.eq_ignore_ascii_case("Audio")
                                    || s.stream_type.eq_ignore_ascii_case("Video")
                            });
                            if !has_av {
                                let tracks = vedro_stream::inspect_media_tracks(&bytes);
                                if !tracks.is_empty() {
                                    let learned: Vec<MediaStream> = tracks
                                        .into_iter()
                                        .enumerate()
                                        .map(|(idx, t)| MediaStream {
                                            index: idx as i32,
                                            stream_type: t.stream_type,
                                            codec: Some(t.codec),
                                            language: t.language,
                                            title: t.title,
                                            display_title: Some(t.display_title),
                                            is_default: t.is_default,
                                            is_forced: t.is_forced,
                                            is_external: false,
                                            is_text_subtitle_stream: t.is_text_subtitle,
                                            width: t.width,
                                            height: t.height,
                                            channels: t.channels,
                                            video_range: t.video_range,
                                            ..Default::default()
                                        })
                                        .collect();
                                    let src_id = if chosen.id.is_empty() {
                                        "default"
                                    } else {
                                        chosen.id.as_str()
                                    };
                                    let learned_key =
                                        format!("learned_streams_v1:{item_id}:{src_id}");
                                    let _ = self.store.set_setting(&learned_key, &learned);
                                }
                            }
                            inspect_media_header(&bytes)
                        })
                } else {
                    if !stream_id.is_empty() {
                        let has_av = chosen.media_streams.iter().any(|s| {
                            s.stream_type.eq_ignore_ascii_case("Audio")
                                || s.stream_type.eq_ignore_ascii_case("Video")
                        });
                        if !has_av {
                            let proxy_bg = Arc::clone(&self.proxy);
                            let store_bg = self.store.clone();
                            let sid_bg = stream_id.clone();
                            let item_bg = item_id.clone();
                            let src_bg = if chosen.id.is_empty() {
                                "default".to_string()
                            } else {
                                chosen.id.clone()
                            };
                            tokio::spawn(async move {
                                if let Some(bytes) =
                                    proxy_bg.read_range(&sid_bg, 0, 256 * 1024).await
                                {
                                    let tracks = vedro_stream::inspect_media_tracks(&bytes);
                                    if !tracks.is_empty() {
                                        let learned: Vec<MediaStream> = tracks
                                            .into_iter()
                                            .enumerate()
                                            .map(|(idx, t)| MediaStream {
                                                index: idx as i32,
                                                stream_type: t.stream_type,
                                                codec: Some(t.codec),
                                                language: t.language,
                                                title: t.title,
                                                display_title: Some(t.display_title),
                                                is_default: t.is_default,
                                                is_forced: t.is_forced,
                                                is_external: false,
                                                is_text_subtitle_stream: t.is_text_subtitle,
                                                width: t.width,
                                                height: t.height,
                                                channels: t.channels,
                                                video_range: t.video_range,
                                                ..Default::default()
                                            })
                                            .collect();
                                        let learned_key =
                                            format!("learned_streams_v1:{item_bg}:{src_bg}");
                                        let _ = store_bg.set_setting(&learned_key, &learned);
                                    }
                                }
                            });
                        }
                    }
                    None
                };

                let cfg = self.playback_config.lock().clone();
                let hdr_fmt = inspected
                    .as_ref()
                    .and_then(|i| i.hdr_format.clone())
                    .unwrap_or_else(|| {
                        let hdr_lc = badges
                            .hdr_format
                            .as_deref()
                            .unwrap_or("")
                            .to_ascii_lowercase();
                        if badges.dolby_vision_profile.is_some()
                            || hdr_lc.contains("dolby")
                            || hdr_lc.contains("dovi")
                            || hdr_lc == "dv"
                        {
                            let prof = badges.dolby_vision_profile.unwrap_or(8);
                            vedro_stream::HdrFormat::DolbyVision(
                                vedro_stream::inspector::DolbyVisionInfo {
                                    dv_version_major: 1,
                                    dv_version_minor: 0,
                                    dv_profile: prof,
                                    dv_level: 6,
                                    rpu_present: true,
                                    el_present: prof == 7,
                                    bl_present: prof != 5,
                                    bl_signal_compatibility_id: if prof == 5 { 0 } else { 1 },
                                },
                            )
                        } else if hdr_lc.contains("hdr10+") || hdr_lc.contains("hdr10plus") {
                            vedro_stream::HdrFormat::Hdr10Plus
                        } else if hdr_lc.contains("hlg") {
                            vedro_stream::HdrFormat::Hlg
                        } else if hdr_lc.contains("hdr") {
                            vedro_stream::HdrFormat::Hdr10
                        } else {
                            let is_hlg = chosen.media_streams.iter().any(|s| {
                                s.video_range
                                    .as_deref()
                                    .map(|r| r.to_ascii_lowercase().contains("hlg"))
                                    .unwrap_or(false)
                            });
                            if is_hlg {
                                vedro_stream::HdrFormat::Hlg
                            } else {
                                vedro_stream::HdrFormat::Sdr
                            }
                        }
                    });
                let spatial = inspected
                    .as_ref()
                    .and_then(|i| i.spatial_audio.clone())
                    .or_else(|| {
                        if badges.is_dolby_atmos {
                            let is_truehd = chosen.media_streams.iter().any(|s| {
                                s.codec
                                    .as_deref()
                                    .map(|c| c.eq_ignore_ascii_case("truehd"))
                                    .unwrap_or(false)
                            });
                            Some(if is_truehd {
                                vedro_stream::SpatialAudioFormat::DolbyAtmosTrueHd
                            } else {
                                vedro_stream::SpatialAudioFormat::DolbyAtmosEac3Joc
                            })
                        } else if badges.is_dts_x {
                            Some(vedro_stream::SpatialAudioFormat::DtsX)
                        } else {
                            None
                        }
                    });

                let hdr_decision = vedro_playback::resolve_hdr_pipeline(
                    cfg.platform,
                    &cfg.display,
                    &hdr_fmt,
                    cfg.prefer_native_dolby_vision,
                    cfg.tone_mapping,
                );
                let audio_decision = vedro_playback::resolve_audio_routing(
                    cfg.platform,
                    cfg.audio_mode,
                    spatial.as_ref(),
                    cfg.night_mode,
                    cfg.dialogue_boost,
                );
                let mpv_options = cfg.build_mpv_options(&hdr_fmt, spatial.as_ref());

                let external_subtitles: Vec<ExternalSubtitle> = chosen
                    .media_streams
                    .iter()
                    .filter(|s| {
                        s.stream_type.eq_ignore_ascii_case("Subtitle") && s.delivery_url.is_some()
                    })
                    .filter_map(|s| {
                        let resolved = client.resolve_media_url(s.delivery_url.as_deref()?).ok()?;
                        Some(ExternalSubtitle {
                            index: s.index,
                            language: s.language.clone(),
                            title: s
                                .display_title
                                .clone()
                                .or_else(|| s.title.clone())
                                .or_else(|| s.language.clone())
                                .unwrap_or_else(|| format!("Subtitle #{}", s.index)),
                            codec: s.codec.clone().unwrap_or_else(|| "srt".to_string()),
                            is_default: s.is_default,
                            is_forced: s.is_forced,
                            is_external: true,
                            url: resolved.to_string(),
                        })
                    })
                    .collect();

                let text_subtitles: Vec<ExternalSubtitle> = chosen
                    .media_streams
                    .iter()
                    .filter(|s| {
                        if !s.stream_type.eq_ignore_ascii_case("Subtitle") {
                            return false;
                        }
                        let codec_lc = s.codec.as_deref().unwrap_or("").to_ascii_lowercase();
                        let is_bitmap = matches!(
                            codec_lc.as_str(),
                            "pgs"
                                | "pgssub"
                                | "hdmv_pgs_subtitle"
                                | "dvdsub"
                                | "dvd_subtitle"
                                | "vobsub"
                                | "dvbsub"
                                | "dvb_subtitle"
                                | "xsub"
                        );
                        !is_bitmap
                    })
                    .filter_map(|s| {
                        let raw_url = if let Some(du) = s.delivery_url.as_deref() {
                            client.resolve_media_url(du).ok()?.to_string()
                        } else {
                            let rel = format!(
                                "/Videos/{}/{}/Subtitles/{}/Stream.vtt",
                                item_id, chosen.id, s.index
                            );
                            client.resolve_media_url(&rel).ok()?.to_string()
                        };
                        Some(ExternalSubtitle {
                            index: s.index,
                            language: s.language.clone(),
                            title: s
                                .display_title
                                .clone()
                                .or_else(|| s.title.clone())
                                .or_else(|| s.language.clone())
                                .unwrap_or_else(|| format!("Subtitle #{}", s.index)),
                            codec: s.codec.clone().unwrap_or_else(|| "vtt".to_string()),
                            is_default: s.is_default,
                            is_forced: s.is_forced,
                            is_external: s.delivery_url.is_some() || s.is_external,
                            url: raw_url,
                        })
                    })
                    .collect();

                // Atomically commit active_session ONLY if playback_epoch still matches;
                // otherwise unregister this superseded stream immediately so zero streams leak!
                {
                    let mut guard = self.active_session.lock();
                    if self
                        .playback_epoch
                        .load(std::sync::atomic::Ordering::SeqCst)
                        != pb_epoch
                    {
                        if !stream_id.is_empty() {
                            self.proxy.unregister_stream(&stream_id);
                        }
                        return Err(crate::RpcErr::from(
                            "播放准备已被新的切换/停止操作取代".to_string(),
                        ));
                    }
                    let prev = guard.replace(ActivePlaybackSession {
                        item_id: item_id.clone(),
                        media_source_id: chosen.id.clone(),
                        play_session_id: pb.play_session_id.clone(),
                        stream_id: stream_id.clone(),
                        run_time_ticks: chosen.run_time_ticks,
                        audio_stream_index: audio_idx.or(chosen.default_audio_stream_index),
                        subtitle_stream_index: sub_idx.or(chosen.default_subtitle_stream_index),
                    });
                    if let Some(p) = prev {
                        if !p.stream_id.is_empty() && p.stream_id != stream_id {
                            self.proxy.unregister_stream(&p.stream_id);
                        }
                    }
                }

                let prepared = PreparedPlayback {
                    item_id,
                    media_source_id: chosen.id.clone(),
                    play_session_id: pb.play_session_id,
                    stream_id,
                    proxy_url,
                    upstream_url: upstream_url.to_string(),
                    uses_stream_ticket: uses_ticket,
                    media_source: chosen,
                    badges,
                    inspected,
                    hdr_decision,
                    audio_decision,
                    mpv_options,
                    external_subtitles,
                    text_subtitles,
                    all_sources: pb.media_sources,
                };
                Ok(serde_json::to_value(prepared).unwrap())
            }

            "refresh_stream_ticket" => {
                let client = self.require_client()?;
                let active = self
                    .active_session
                    .lock()
                    .as_ref()
                    .map(|s| {
                        (
                            s.item_id.clone(),
                            s.media_source_id.clone(),
                            s.stream_id.clone(),
                        )
                    })
                    .ok_or_else(|| "no active playback session".to_string())?;
                let pb = client
                    .playback_info(&active.0, Some(&active.1), None, None)
                    .await
                    .map_err(|e| e.to_string())?;
                let src = pb
                    .media_sources
                    .iter()
                    .find(|s| s.id == active.1)
                    .or_else(|| pb.media_sources.first())
                    .ok_or_else(|| "no media source on refresh".to_string())?;
                let new_url = src
                    .direct_stream_url
                    .as_deref()
                    .ok_or_else(|| "no DirectStreamUrl on refresh".to_string())?;
                let resolved = client
                    .resolve_media_url(new_url)
                    .map_err(|e| e.to_string())?;
                let new_hdrs = if same_origin_as_client(&client, resolved.as_str())
                    && !vedro_protocol::auth::url_has_stream_ticket(resolved.as_str())
                {
                    client.auth_headers()
                } else {
                    reqwest::header::HeaderMap::new()
                };
                let swapped =
                    self.proxy
                        .update_upstream_url(&active.2, resolved.to_string(), Some(new_hdrs));
                if swapped && !pb.play_session_id.is_empty() {
                    if let Some(ref mut sess) = *self.active_session.lock() {
                        if sess.stream_id == active.2 {
                            sess.play_session_id = pb.play_session_id.clone();
                        }
                    }
                }
                Ok(json!({
                    "swapped": swapped,
                    "play_session_id": pb.play_session_id,
                }))
            }

            "player_start" => {
                let url = str_param(params, "url")?;
                let start_secs = params.get("start_secs").and_then(Value::as_f64);
                let headless = params.get("headless").and_then(Value::as_bool);
                let wid = params.get("wid").and_then(Value::as_i64);
                let inspected: Option<InspectedMedia> = params
                    .get("inspected")
                    .and_then(|v| serde_json::from_value(v.clone()).ok());

                let eng = self.ensure_engine(headless)?;
                if let Some(w) = wid {
                    let _ = eng.attach_window_id(w);
                }
                let (hdr_dec, audio_dec) = eng
                    .load_media(&url, start_secs, inspected.as_ref())
                    .map_err(|e| e.to_string())?;
                let _ = eng.set_paused(false);
                Ok(json!({
                    "started": true,
                    "hdr_decision": hdr_dec,
                    "audio_decision": audio_dec,
                }))
            }

            "player_pause" => {
                let paused = params
                    .get("paused")
                    .and_then(Value::as_bool)
                    .unwrap_or(true);
                let eng = self.ensure_engine(None)?;
                eng.set_paused(paused).map_err(|e| e.to_string())?;
                Ok(json!({"paused": paused}))
            }

            "player_toggle_pause" => {
                let eng = self.ensure_engine(None)?;
                eng.toggle_pause().map_err(|e| e.to_string())?;
                Ok(json!({"ok": true}))
            }

            "player_seek" => {
                let seconds = params
                    .get("seconds")
                    .and_then(Value::as_f64)
                    .ok_or("missing seconds")?;
                let relative = params
                    .get("relative")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                let eng = self.ensure_engine(None)?;
                if relative {
                    eng.seek_relative(seconds).map_err(|e| e.to_string())?;
                } else {
                    eng.seek_absolute(seconds).map_err(|e| e.to_string())?;
                }
                Ok(json!({"seeked": seconds}))
            }

            "player_set_speed" => {
                let speed = params
                    .get("speed")
                    .and_then(Value::as_f64)
                    .ok_or("missing speed")?;
                let eng = self.ensure_engine(None)?;
                eng.set_speed(speed).map_err(|e| e.to_string())?;
                Ok(json!({"speed": speed}))
            }

            "player_set_volume" => {
                let volume = params
                    .get("volume")
                    .and_then(Value::as_f64)
                    .ok_or("missing volume")?;
                let eng = self.ensure_engine(None)?;
                eng.set_volume(volume).map_err(|e| e.to_string())?;
                Ok(json!({"volume": volume}))
            }

            "player_set_audio_track" => {
                let track_id = params
                    .get("track_id")
                    .and_then(Value::as_i64)
                    .ok_or("missing track_id")?;
                let eng = self.ensure_engine(None)?;
                eng.set_audio_track(track_id).map_err(|e| e.to_string())?;
                Ok(json!({"track_id": track_id}))
            }

            "player_set_subtitle_track" => {
                let track_id = params
                    .get("track_id")
                    .and_then(Value::as_i64)
                    .ok_or("missing track_id")?;
                let eng = self.ensure_engine(None)?;
                eng.set_subtitle_track(track_id)
                    .map_err(|e| e.to_string())?;
                Ok(json!({"track_id": track_id}))
            }

            "player_add_subtitle" => {
                let url = str_param(params, "url")?;
                let title = params.get("title").and_then(Value::as_str);
                let lang = params.get("language").and_then(Value::as_str);
                let eng = self.ensure_engine(None)?;
                eng.add_external_subtitle(&url, title, lang)
                    .map_err(|e| e.to_string())?;
                Ok(json!({"added": true}))
            }

            "player_set_tone_mapping" => {
                let algo: ToneMappingAlgorithm =
                    serde_json::from_value(params.get("algorithm").cloned().unwrap_or(Value::Null))
                        .map_err(|e| format!("invalid algorithm: {e}"))?;
                self.playback_config.lock().tone_mapping = algo;
                if let Some(eng) = self.engine.lock().as_ref() {
                    let _ = eng.set_tone_mapping(algo);
                }
                Ok(json!({"tone_mapping": algo}))
            }

            "player_set_audio_mode" => {
                let mode: AudioOutputMode =
                    serde_json::from_value(params.get("mode").cloned().unwrap_or(Value::Null))
                        .map_err(|e| format!("invalid audio mode: {e}"))?;
                let night = params
                    .get("night_mode")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                let dialogue = params
                    .get("dialogue_boost")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                {
                    let mut cfg = self.playback_config.lock();
                    cfg.audio_mode = mode;
                    cfg.night_mode = night;
                    cfg.dialogue_boost = dialogue;
                }
                if let Some(eng) = self.engine.lock().as_ref() {
                    let dec = eng
                        .set_audio_mode(mode, night, dialogue)
                        .map_err(|e| e.to_string())?;
                    return Ok(serde_json::to_value(dec).unwrap());
                }
                Ok(json!({"audio_mode": mode}))
            }

            "player_stop" => {
                let target_stream_id = params
                    .get("stream_id")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty());
                if target_stream_id.is_none() {
                    self.playback_epoch
                        .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                    if let Some(eng) = self.engine.lock().as_ref() {
                        let _ = eng.stop();
                    }
                }
                let mut guard = self.active_session.lock();
                let should_take = match (guard.as_ref(), target_stream_id) {
                    (Some(active), Some(req_sid)) => active.stream_id == req_sid,
                    (Some(_), None) => true,
                    (None, _) => false,
                };
                if should_take {
                    if let Some(active) = guard.take() {
                        if !active.stream_id.is_empty() {
                            self.proxy.unregister_stream(&active.stream_id);
                        }
                    }
                } else if let Some(req_sid) = target_stream_id {
                    // Explicitly unregister only the caller's stream ID without touching a newer video's active_session!
                    self.proxy.unregister_stream(req_sid);
                }
                Ok(json!({"stopped": true}))
            }

            "player_stats" => {
                let playback = self
                    .engine
                    .lock()
                    .as_ref()
                    .map(|e| e.stats_snapshot())
                    .unwrap_or_default();
                let proxy = self.proxy.stats();
                Ok(serde_json::to_value(CombinedPlayerStats { playback, proxy }).unwrap())
            }

            "get_image_cache_stats" => {
                let proxy = Arc::clone(&self.proxy);
                let stats = tokio::task::spawn_blocking(move || proxy.image_cache_stats())
                    .await
                    .map_err(|e| format!("读取图片缓存统计失败: {e}"))?;
                Ok(serde_json::to_value(stats).unwrap())
            }

            "clear_image_cache" => {
                let proxy = Arc::clone(&self.proxy);
                let (removed_files, freed_bytes, after) = tokio::task::spawn_blocking(move || {
                    let (r, f) = proxy.clear_image_cache();
                    let a = proxy.image_cache_stats();
                    (r, f, a)
                })
                .await
                .map_err(|e| format!("清理图片缓存失败: {e}"))?;
                Ok(json!({
                    "removed_files": removed_files,
                    "freed_bytes": freed_bytes,
                    "stats": after,
                }))
            }

            "report_playback_start" | "report_playback_progress" | "report_playback_stopped" => {
                let client = self.require_client()?;
                let position_ticks = params
                    .get("position_ticks")
                    .and_then(Value::as_i64)
                    .unwrap_or(0);
                let is_paused = params
                    .get("is_paused")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);

                let payload = if let Some(item_id) = params.get("item_id").and_then(Value::as_str) {
                    PlaybackProgressPayload {
                        item_id: item_id.to_string(),
                        media_source_id: params
                            .get("media_source_id")
                            .and_then(Value::as_str)
                            .map(ToString::to_string),
                        play_session_id: params
                            .get("play_session_id")
                            .and_then(Value::as_str)
                            .unwrap_or("")
                            .to_string(),
                        position_ticks,
                        run_time_ticks: params.get("run_time_ticks").and_then(Value::as_i64),
                        is_paused,
                        play_method: "DirectPlay".to_string(),
                        audio_stream_index: params
                            .get("audio_stream_index")
                            .and_then(Value::as_i64)
                            .map(|v| v as i32),
                        subtitle_stream_index: params
                            .get("subtitle_stream_index")
                            .and_then(Value::as_i64)
                            .map(|v| v as i32),
                        can_seek: Some(true),
                    }
                } else {
                    let active = self.active_session.lock();
                    let s = active
                        .as_ref()
                        .ok_or_else(|| "no active playback session".to_string())?;
                    PlaybackProgressPayload {
                        item_id: s.item_id.clone(),
                        media_source_id: Some(s.media_source_id.clone()),
                        play_session_id: s.play_session_id.clone(),
                        position_ticks,
                        run_time_ticks: params
                            .get("run_time_ticks")
                            .and_then(Value::as_i64)
                            .or(s.run_time_ticks),
                        is_paused,
                        play_method: "DirectPlay".to_string(),
                        audio_stream_index: s.audio_stream_index,
                        subtitle_stream_index: s.subtitle_stream_index,
                        can_seek: Some(true),
                    }
                };

                match method {
                    "report_playback_start" => client
                        .report_playback_start(&payload)
                        .await
                        .map_err(|e| e.to_string())?,
                    "report_playback_progress" => client
                        .report_playback_progress(&payload)
                        .await
                        .map_err(|e| e.to_string())?,
                    _ => client
                        .report_playback_stopped(&payload)
                        .await
                        .map_err(|e| e.to_string())?,
                }
                Ok(json!({"reported": true}))
            }

            "report_playback_ping" => {
                let client = self.require_client()?;
                let psid = params
                    .get("play_session_id")
                    .and_then(Value::as_str)
                    .map(ToString::to_string)
                    .or_else(|| {
                        self.active_session
                            .lock()
                            .as_ref()
                            .map(|s| s.play_session_id.clone())
                    })
                    .unwrap_or_default();
                client
                    .report_playback_ping(&psid)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(json!({"pinged": true}))
            }

            "delete_playlist" => {
                let client = self.require_client()?;
                let playlist_id = str_param(params, "playlist_id")?;
                client
                    .delete_item(&playlist_id)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(json!({ "deleted": playlist_id }))
            }

            "external_play_url" => {
                let client = self.require_client()?;
                let item_id = str_param(params, "item_id")?;
                let media_source_id = params.get("media_source_id").and_then(Value::as_str);
                let player_id = params.get("player_id").and_then(Value::as_str);
                let pb = client
                    .external_play_info(&item_id, media_source_id, player_id)
                    .await
                    .map_err(|e| e.to_string())?;
                let chosen = media_source_id
                    .and_then(|sid| pb.media_sources.iter().find(|s| s.id == sid))
                    .or_else(|| pb.media_sources.first())
                    .ok_or_else(|| "no playable media source".to_string())?;
                let prefer_proxy = params
                    .get("use_local_proxy")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                let url = if let Some(ds) = chosen.direct_stream_url.as_deref() {
                    let resolved = client.resolve_media_url(ds).map_err(|e| e.to_string())?;
                    validate_http_url(resolved.as_str())?;
                    resolved
                } else {
                    let mut fallback = client
                        .build_fallback_video_url(
                            &item_id,
                            &chosen.id,
                            chosen.container.as_deref(),
                            &pb.play_session_id,
                        )
                        .map_err(|e| e.to_string())?;
                    if prefer_proxy {
                        let (_sid, proxy_url) = self.proxy.register_stream(
                            fallback.to_string(),
                            client.auth_headers(),
                            chosen.size,
                            chosen.container.as_deref().map(container_mime_type),
                        );
                        url::Url::parse(&proxy_url).map_err(|e| e.to_string())?
                    } else {
                        if let Some(tok) = client.access_token() {
                            fallback.query_pairs_mut().append_pair("api_key", &tok);
                        }
                        fallback
                    }
                };
                Ok(json!({
                    "url": url.to_string(),
                    "media_source_id": chosen.id,
                }))
            }

            "get_settings" => {
                let cfg = self.playback_config.lock().clone();
                Ok(serde_json::to_value(cfg).unwrap())
            }

            "save_settings" => {
                let cfg: PlaybackConfig = serde_json::from_value(params.clone())
                    .map_err(|e| format!("invalid settings: {e}"))?;
                self.store
                    .set_setting("playback_config", &cfg)
                    .map_err(|e| e.to_string())?;
                *self.playback_config.lock() = cfg.clone();
                Ok(serde_json::to_value(cfg).unwrap())
            }

            "get_kv" => {
                let key = str_param(params, "key")?;
                let val: Option<Value> = self.store.get_setting(&key).map_err(|e| e.to_string())?;
                Ok(json!({ "value": val }))
            }

            "set_kv" => {
                let key = str_param(params, "key")?;
                let value = params.get("value").cloned().unwrap_or(Value::Null);
                self.store
                    .set_setting(&key, &value)
                    .map_err(|e| e.to_string())?;
                // Keep AI translation cache & learned probe cache bounded in SQLite
                if key.starts_with("ai_sub_cache_v1:") || key.starts_with("ai_sub_cache_v2:") {
                    let _ = self.store.prune_settings_prefix("ai_sub_cache_", 60);
                } else if key.starts_with("learned_streams_v1:") {
                    let _ = self
                        .store
                        .prune_settings_prefix("learned_streams_v1:", 2000);
                }
                Ok(json!({ "saved": true }))
            }

            "image_url" => {
                let client = self.require_client()?;
                let item_id = str_param(params, "item_id")?;
                let image_type = params
                    .get("image_type")
                    .and_then(Value::as_str)
                    .unwrap_or("Primary");
                let tag = params.get("tag").and_then(Value::as_str);
                let max_width = params
                    .get("max_width")
                    .and_then(Value::as_u64)
                    .map(|v| v as u32);
                let max_height = params
                    .get("max_height")
                    .and_then(Value::as_u64)
                    .map(|v| v as u32);
                let quality = params
                    .get("quality")
                    .and_then(Value::as_u64)
                    .map(|v| v as u8);
                let url = client
                    .image_url(&item_id, image_type, tag, max_width, max_height, quality)
                    .map_err(|e| e.to_string())?;
                Ok(json!({"url": url.to_string()}))
            }
            _ => Err(crate::RpcErr::Unhandled),
        }
    }
}

pub(crate) fn apply_learned_streams(ms: &mut MediaSourceInfo, learned: Vec<MediaStream>) {
    if learned.is_empty() {
        return;
    }
    let mut merged: Vec<MediaStream> = ms
        .media_streams
        .iter()
        .filter(|s| s.is_external)
        .cloned()
        .collect();
    let offset = merged
        .iter()
        .map(|s| s.index.saturating_add(1))
        .max()
        .unwrap_or(0)
        .max(0);
    for (idx, mut st) in learned.into_iter().enumerate() {
        if offset > 0 && st.index < offset {
            st.index = offset.saturating_add(idx as i32);
        }
        merged.push(st);
    }
    ms.media_streams = merged;
}
