# embygo / Emby / Jellyfin Compatibility Matrix

Vedro was engineered by auditing `embygo` directly alongside standard Emby 4.8/4.9 and Jellyfin 10.9/10.10 contracts.

| Capability / Endpoint | embygo | Emby | Jellyfin | Vedro Implementation |
| --- | :---: | :---: | :---: | --- |
| `GET /System/Info/Public` & dialect probe | ✅ | ✅ | ✅ | Auto-detects `EmbyGo`, `Emby`, `Jellyfin` |
| `POST /Users/AuthenticateByName` (`Pw` JSON) | ✅ | ✅ | ✅ | Header-only auth (`X-Emby-Authorization`, `X-Emby-Token`) |
| `security.allow_query_credentials: false` | ✅ | ✅ | ✅ | Fully compliant — never leaks tokens in query strings |
| `POST /Items/{id}/PlaybackInfo` DirectPlay | ✅ | ✅ | ✅ | Omits restrictive `DeviceProfile` on `embygo`; universal DirectPlay on Emby/Jellyfin |
| `StreamTicket` short-lived media/subtitle URLs | ✅ | — | — | Preserves signed ticket untouched; hot-swaps upstream URL in `vedro-stream` before expiry |
| `max_connections_per_session` (default 4) | ✅ | — | — | `vedro-stream` Semaphore caps upstream connections to `<= 2` + HTTP 429 `Retry-After` backoff |
| `GET /Users/{id}/Items/Popular` | ✅ | — | — | Powers Home Hero Spotlight & Trending rail (graceful fallback on 404) |
| `GET /Users/{id}/Suggestions` | ✅ | ✅ | ✅ | Powers "猜你喜欢" rail |
| `POST/DELETE /Users/{id}/Items/{id}/HideFromResume` | ✅ | ✅ | — | Removes from Continue Watching while preserving position & `PlayCount` |
| Numeric decimal Facet/Person IDs (SenPlayer compat) | ✅ | ✅ | ✅ | Custom `deserialize_string_or_int` accepts both `int64` and `string` IDs |
| Multi-version Provider-ID merges (`MediaSources`) | ✅ | ✅ | ✅ | Version selector in Detail & live in-Player |
| Unprobed files (no server-side `ffprobe`) | ✅ | — | — | Local Rust `inspector.rs` parses MKV/MP4 `dvcC`/`TrueHD`/`E-AC-3 JOC` from chunk 0 in <50ms |
| `POST /Sessions/Playing`, `/Progress`, `/Stopped`, `/Ping` | ✅ | ✅ | ✅ | Always sends `PlayMethod=DirectPlay`; 10s heartbeat stays well inside 5-min freshness window |
| WebSocket `/embywebsocket` & `/socket` | ✅ | ✅ | ✅ | Text framing default, KeepAlive, auto-reconnect, Remote Control + `UserDataChanged` live sync |
| External Sidecar Subtitles (`.srt`/`.ass`/`.ssa`/`.vtt`) | ✅ | ✅ | ✅ | Native `libass` rendering + Rust SRT/VTT/ASS timing shifter |
| Playlists (`POST/GET /Playlists`) | ✅ | ✅ | ✅ | Full create/list/add/remove support |
| `GET /MediaSegments/{id}` (Future Skip Intro/Outro) | 🔜 | ✅ | ✅ | Already wired; activates automatically once server populates segments |
| Admin `/emby-compat/status`, `/Items/Counts`, `/Library/Refresh` | ✅ | Partial | Partial | Automatically surfaced in Settings for `embygo` administrators |
