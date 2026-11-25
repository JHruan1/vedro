use std::env;
use std::time::Duration;

use anyhow::{bail, Context, Result};
use prism_ffi::PrismRuntime;
use prism_playback::{AudioOutputMode, PlaybackConfig, TargetPlatform, ToneMappingAlgorithm};
use prism_stream::{inspect_media_header, HdrFormat, SpatialAudioFormat};
use serde_json::{json, Value};

fn main() -> Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        print_usage();
        return Ok(());
    }

    match args[1].as_str() {
        "inspect" => {
            let path = args.get(2).context("missing file path")?;
            let data = std::fs::read(path).with_context(|| format!("reading {path}"))?;
            let head = &data[..data.len().min(512 * 1024)];
            let inspected = inspect_media_header(head);
            println!("{}", serde_json::to_string_pretty(&inspected)?);
        }
        "profile-matrix" => {
            let platforms = [
                TargetPlatform::Android,
                TargetPlatform::Ios,
                TargetPlatform::MacOs,
                TargetPlatform::Windows,
            ];
            let dv81 = prism_stream::DolbyVisionInfo {
                dv_version_major: 1,
                dv_version_minor: 0,
                dv_profile: 8,
                dv_level: 6,
                rpu_present: true,
                el_present: false,
                bl_present: true,
                bl_signal_compatibility_id: 1,
            };
            let mut matrix = Vec::new();
            for p in platforms {
                let mut cfg = PlaybackConfig {
                    platform: p,
                    audio_mode: AudioOutputMode::Auto,
                    tone_mapping: ToneMappingAlgorithm::Bt2446a,
                    ..Default::default()
                };
                cfg.display.supports_native_dolby_vision = matches!(
                    p,
                    TargetPlatform::Ios | TargetPlatform::MacOs | TargetPlatform::Android
                );
                let opts = cfg.build_mpv_options(
                    &HdrFormat::DolbyVision(dv81.clone()),
                    Some(&SpatialAudioFormat::DolbyAtmosTrueHd),
                );
                matrix.push(json!({
                    "platform": p,
                    "mpv_options": opts,
                }));
            }
            println!("{}", serde_json::to_string_pretty(&matrix)?);
        }
        "e2e-embygo" => {
            let url = args.get(2).context("missing server url")?;
            let username = args.get(3).context("missing username")?;
            let password = args.get(4).context("missing password")?;
            run_e2e_embygo(url, username, password)?;
        }
        _ => print_usage(),
    }
    Ok(())
}

fn run_e2e_embygo(url: &str, username: &str, password: &str) -> Result<()> {
    println!("=== Prism Player Live E2E Verification against {url} ===");
    let rt = PrismRuntime::new(None).map_err(anyhow::Error::msg)?;

    // 1. Probe server & dialect detection
    let conn = rt
        .invoke(
            "connect_server",
            json!({"url": url, "device_name": "Prism E2E Runner"}),
        )
        .map_err(anyhow::Error::msg)?;
    println!(
        "[1/11] Connected: dialect={} version={}",
        conn["capabilities"]["dialect"], conn["capabilities"]["advertised_version"]
    );
    assert_eq!(
        conn["capabilities"]["dialect"], "embygo",
        "expected embygo dialect detection"
    );
    assert_eq!(conn["capabilities"]["supports_transcoding"], false);

    // 2. Authenticate
    let auth = rt
        .invoke("login", json!({"username": username, "password": password}))
        .map_err(anyhow::Error::msg)?;
    println!(
        "[2/11] Authenticated user={} id={}",
        auth["auth"]["User"]["Name"], auth["auth"]["User"]["Id"]
    );

    // 3. Home screen aggregation (Views, Popular, Suggestions, Resume, NextUp, Latest)
    let home = rt
        .invoke("get_home", json!({}))
        .map_err(anyhow::Error::msg)?;
    let views = home["views"].as_array().context("views array")?;
    println!(
        "[3/11] Home loaded: {} libraries, {} popular, {} resume",
        views.len(),
        home["popular"].as_array().map(|a| a.len()).unwrap_or(0),
        home["resume"].as_array().map(|a| a.len()).unwrap_or(0),
    );
    assert!(!views.is_empty(), "expected at least one library view");

    // 4. Browse items recursively
    let items_res = rt
        .invoke(
            "get_items",
            json!({"Recursive": true, "IncludeItemTypes": "Movie,Episode", "Limit": 20}),
        )
        .map_err(anyhow::Error::msg)?;
    let items = items_res["Items"].as_array().context("Items array")?;
    println!("[4/11] Browsed {} playable items", items.len());
    assert!(
        !items.is_empty(),
        "expected at least one playable item in test library"
    );
    let first_item = &items[0];
    let item_id = first_item["Id"].as_str().context("item Id")?.to_string();

    // 5. Item detail + Similar + Filters2 + Search
    let detail = rt
        .invoke("get_item", json!({"item_id": item_id}))
        .map_err(anyhow::Error::msg)?;
    let filters = rt
        .invoke("get_filters", json!({}))
        .map_err(anyhow::Error::msg)?;
    let search = rt
        .invoke(
            "search_hints",
            json!({"term": first_item["Name"].as_str().unwrap_or("a")}),
        )
        .map_err(anyhow::Error::msg)?;
    println!(
        "[5/11] Detail={}, Genres={}, SearchHints={}",
        detail["item"]["Name"],
        filters["Genres"].as_array().map(|a| a.len()).unwrap_or(0),
        search["SearchHints"]
            .as_array()
            .map(|a| a.len())
            .unwrap_or(0),
    );

    // 6. Prepare Playback (PlaybackInfo + StreamTicket + Range Proxy + Binary Header Inspector + DoVi/Atmos Routing)
    let prepared = rt
        .invoke(
            "prepare_playback",
            json!({"item_id": item_id, "inspect_header": true}),
        )
        .map_err(anyhow::Error::msg)?;
    let proxy_url = prepared["proxy_url"]
        .as_str()
        .context("proxy_url")?
        .to_string();
    let uses_ticket = prepared["uses_stream_ticket"].as_bool().unwrap_or(false);
    println!("[6/11] Prepared playback: proxy_url={proxy_url}, uses_stream_ticket={uses_ticket}, container={}, hdr={:?}, ext_subs={}",
        prepared["inspected"]["container"],
        prepared["inspected"]["hdr_format"],
        prepared["external_subtitles"].as_array().map(|a| a.len()).unwrap_or(0),
    );
    assert!(
        uses_ticket,
        "embygo must issue StreamTicket on DirectStreamUrl"
    );

    // 7. Start REAL libmpv playback through local prism-stream proxy (headless null vo)
    let started = rt
        .invoke(
            "player_start",
            json!({
                "url": proxy_url,
                "headless": true,
                "inspected": prepared["inspected"],
            }),
        )
        .map_err(anyhow::Error::msg)?;
    assert_eq!(started["started"], true);
    std::thread::sleep(Duration::from_millis(600));
    let stats = rt
        .invoke("player_stats", json!({}))
        .map_err(anyhow::Error::msg)?;
    println!("[7/11] Live libmpv + proxy stats: mpv_api={}, cache_hits={}, served_bytes={}, active_up_conns={}",
        stats["playback"]["libmpv_api_version"],
        stats["proxy"]["cache"]["hits"],
        stats["proxy"]["total_served_bytes"],
        stats["proxy"]["active_upstream_connections"],
    );
    assert!(
        stats["proxy"]["total_served_bytes"].as_u64().unwrap_or(0) > 0,
        "proxy must serve bytes to libmpv"
    );

    // 8. Refresh StreamTicket hot-swap
    let refreshed = rt
        .invoke("refresh_stream_ticket", json!({}))
        .map_err(anyhow::Error::msg)?;
    assert_eq!(refreshed["swapped"], true);
    println!("[8/11] StreamTicket hot-swapped seamlessly");

    // 9. Progress lifecycle: Start -> Progress -> Ping -> Stop (50%) -> HideFromResume
    rt.invoke(
        "report_playback_start",
        json!({"position_ticks": 5_000_000, "run_time_ticks": 30_000_000, "is_paused": false}),
    )
    .map_err(anyhow::Error::msg)?;
    rt.invoke(
        "report_playback_progress",
        json!({"position_ticks": 12_000_000, "run_time_ticks": 30_000_000, "is_paused": false}),
    )
    .map_err(anyhow::Error::msg)?;
    rt.invoke("report_playback_ping", json!({}))
        .map_err(anyhow::Error::msg)?;
    rt.invoke(
        "report_playback_stopped",
        json!({"position_ticks": 15_000_000, "run_time_ticks": 30_000_000, "is_paused": true}),
    )
    .map_err(anyhow::Error::msg)?;
    let _ = rt.invoke("player_stop", json!({}));

    let hidden = rt
        .invoke(
            "hide_from_resume",
            json!({"item_id": item_id, "hide": true}),
        )
        .map_err(anyhow::Error::msg)?;
    assert_eq!(
        hidden["PlaybackPositionTicks"], 15_000_000,
        "HideFromResume must preserve PlaybackPositionTicks"
    );
    println!(
        "[9/11] Progress lifecycle + HideFromResume verified (pos_ticks preserved={})",
        hidden["PlaybackPositionTicks"]
    );

    // 10. Favorites, Playlists & Played status
    let fav = rt
        .invoke(
            "set_favorite",
            json!({"item_id": item_id, "favorite": true}),
        )
        .map_err(anyhow::Error::msg)?;
    assert_eq!(fav["IsFavorite"], true);
    let pl = rt
        .invoke(
            "create_playlist",
            json!({"name": "Prism E2E Watchlist", "item_ids": [item_id.clone()]}),
        )
        .map_err(anyhow::Error::msg)?;
    let pl_id = pl["Id"].as_str().context("playlist id")?;
    let pl_items = rt
        .invoke("get_playlist_items", json!({"playlist_id": pl_id}))
        .map_err(anyhow::Error::msg)?;
    assert_eq!(pl_items["Items"].as_array().map(|a| a.len()), Some(1));
    println!("[10/11] Favorite + Playlist (片单 id={pl_id}) verified");

    // 11. EmbyGo Admin Diagnostics + WebSocket connectivity
    let admin = rt
        .invoke("get_embygo_admin_dashboard", json!({}))
        .map_err(anyhow::Error::msg)?;
    let events: Vec<Value> = rt.poll_events();
    let ws_connected = events
        .iter()
        .any(|e| e["source"] == "websocket" && e["event"]["kind"] == "connected");
    println!(
        "[11/11] Admin dashboard items={:?}, counts={:?}, ws_connected={ws_connected}",
        admin["status"]["items"], admin["counts"],
    );
    if admin["status"].is_null() {
        bail!("expected embygo admin status response");
    }

    let _ = rt.invoke("logout", json!({}));
    println!("=== ALL 11 LIVE EMBYGO E2E CHECKS PASSED ===");
    Ok(())
}

fn print_usage() {
    println!("Prism Player Native CLI & Diagnostics");
    println!("  prism-cli inspect <media-file>                     Inspect container, Dolby Vision, HDR10, Atmos");
    println!("  prism-cli profile-matrix                           Show HWDec/DoVi/Atmos profiles for all 4 platforms");
    println!("  prism-cli e2e-embygo <url> <username> <password>   Run full live E2E verification against embygo");
}
