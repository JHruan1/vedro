# Vedro Architecture & Engineering Governance

Vedro is a cross-platform cinema media player built on a **shared Rust core (`core/`)** exposed over a stable 8-symbol C-ABI (`libvedro_ffi`) and consumed by a **Flutter UI client (`app/`)** targeting macOS, Windows, Linux, Android/Android TV, and iOS.

Every architectural invariant documented here is **machine-enforced** by [`scripts/check-architecture.py`](scripts/check-architecture.py), which runs automatically inside [`scripts/verify-all.sh`](scripts/verify-all.sh) and GitHub Actions CI.

---

## 1. Rust Core Workspace DAG (`core/`)

Strict acyclic crate dependency graph (leaf crates stay leaf):

```text
vedro-protocol  (leaf: Emby/Jellyfin/EmbyGo HTTP/WS protocol & DTOs)
vedro-storage   (leaf: SQLite persistence for servers, routes, settings & KV)
vedro-stream    (leaf: local loopback HTTP proxy, image/chunk cache, header inspector, subtitle & ASR helpers)
      ▲
vedro-playback  (depends ONLY on vedro-stream: libmpv config, Dolby Vision & Atmos routing)
      ▲
vedro-ffi       (orchestration facade: depends on protocol, storage, stream, playback; exposes 8 C-ABI symbols)
      ▲
vedro-cli       (headless CLI & profile-matrix verification binary)
```

### `core/vedro-ffi/src/` Deep-Module Ownership Map

| Module | Responsibility |
|---|---|
| `lib.rs` | `VedroRuntime` lifecycle, Tokio runtime & `Drop` ordering, domain RPC router (`invoke_async`) |
| `c_abi.rs` | Process-wide `Arc<VedroRuntime>` registry & the **8 exported `pub extern "C" fn vedro_*` C-ABI symbols** |
| `types.rs` | Shared FFI DTOs (`PreparedPlayback`, `ExternalSubtitle`, `CombinedPlayerStats`, `ActivePlaybackSession`) |
| `security.rs` | Hard response size caps, URL/origin/path validators, `BilibiliRateLimiter`, `str_param`, MIME mapping |
| `rpc_server.rs` | Server discovery, multi-route probing/switching, login, Quick Connect, session restore, `version` |
| `rpc_media.rs` | Home/library/search/playlists, `prepare_playback`, `refresh_stream_ticket`, playback reporting, KV/settings, image cache |
| `rpc_admin.rs` | EmbyGo admin dashboard, devices, speed test, user/quota/library management, download preparation |
| `rpc_ai.rs` | OpenAI/Bilibili subtitle translation, subtitle cue loading, audio slice extraction & cloud ASR |
| `danmaku.rs` | DandanPlay & Bilibili danmaku auto-match, candidate search, cookie cache & XML/deflate decoding |
| `updater.rs` | Rate-limit-free GitHub release checker, `SHA256SUMS.txt` parser & `ring` SHA-256 verified downloader |
| `tests.rs` | C-ABI lifecycle, real SQLite persistence & end-to-end mock Emby + SHA-256 update tests |

---

## 2. Flutter Layer Architecture (`app/lib/`)

Strict unidirectional layer DAG (**zero circular imports**, **zero upward dependencies**):

```text
core/  ──▶  (leaf: ffi/, models/, platform/, services/, theme/, utils/)
  ▲
state/ ──▶  (depends ONLY on core/: reactive VedroAppState & domain parts)
  ▲
widgets/ ─▶ (depends ONLY on core/ & state/: reusable UI components & panes)
  ▲
screens/ ─▶ (depends on core/, state/, widgets/: route-level views & domain parts)
  ▲
main.dart ─▶ (bootstrap entrypoint & global shortcuts/router)
```

### Canonical Single Sources of Truth (SSOT)

| Concept | Canonical Module | Notes |
|---|---|---|
| Time / Size / Quota / Speed formatters | `app/lib/core/utils/formatters.dart` | Re-exported by `models.dart`; never define `_fmtSpeed` / `_fmtNetSpeed` elsewhere |
| Human-readable error formatting | `app/lib/core/utils/error_formatter.dart` | `VedroErrorFormatter.format(raw)` |
| Artwork global cache-bust signal | `app/lib/core/utils/artwork_signal.dart` | `VedroArtworkSignal.refreshEpoch` / `notifyRefresh()` |
| OS / Form-factor / Perf profile | `app/lib/core/platform/platform_perf.dart` | Use `PlatformPerfProfile.isDesktop` / `isMobile` / `isMobileOs` / `isApple` / `isTv` |
| Danmaku comment model & parsers | `app/lib/core/services/danmaku_parser.dart` | Pure domain parser; `widgets/danmaku_engine.dart` is UI rendering only |
| Local offline ASR (sherpa-onnx) | `app/lib/core/services/local_asr_engine.dart` | Pure service in `core/services/`, never in `widgets/` |
| Core data models | `app/lib/core/models/models.dart` (barrel) | Split into `json_helpers`, `server_models`, `media_models`, `quota_models`, `local_history_model`, `preferences` |

### Domain Subsystems (Optimized for Parallel Agent Development)

- **State (`app/lib/state/`)**: `app_state.dart` (core lifecycle & prefs) + `app_state_servers.dart`, `app_state_media.dart`, `app_state_downloads.dart`, `app_state_ai_admin.dart`, `app_state_artwork.dart`.
- **Player (`app/lib/screens/player_screen.dart` + `player/`)**: `player_engine.dart` (MPV/filters/beauty/AI/danmaku), `player_controls.dart` (transport/gestures/keys), `player_hud.dart` (main canvas & chrome), `player_sheets.dart`, `player_subtitle_sheet.dart`, `player_widgets.dart`.
- **Detail (`app/lib/screens/detail_screen.dart` + `detail/`)**: `detail_body.dart`, `detail_episodes_section.dart`, `detail_components.dart`, `detail_episode_widgets.dart`, `detail_tracks_panel.dart`, `detail_batch_download_dialog.dart`.
- **Settings (`app/lib/screens/settings_screen.dart` + `settings/`)**: `settings_server_download_sections.dart`, `settings_appearance_sections.dart`, `settings_playback_sections.dart`, `settings_ai_privacy_sections.dart`, `settings_primitives.dart`.
- **Home, Shell & Admin**: `screens/home/` (`home_welcome_hub.dart`, `home_hero_banner.dart`), `screens/shell/` (`shell_nav_chrome.dart`), `widgets/admin_console/` (`admin_ui_components.dart`, `admin_quota_dialog.dart`).

---

## 3. State Ownership & Hot-Path Isolation

- **Durable truth** (servers, routes, tokens, playback settings, KV caches, local history, download queue) lives in **SQLite** via `vedro-storage` and is mutated exclusively through Rust RPCs (`core.invoke(...)`).
- **Session & UI truth** lives in `VedroAppState` (`ChangeNotifier`), scoped by `_sessionEpoch` to discard stale async responses after server switches or logout.
- **High-frequency playback ticks** (position, buffered progress, network throughput, gesture HUD, sleep countdown, status bar clock/battery, downloads progress ticks) use isolated `ValueNotifier`s so 60–120fps HUD updates never rebuild screen trees.

---

## 4. Machine-Enforced Invariants (`scripts/check-architecture.py`)

Run `bash scripts/verify-all.sh` before every commit/PR. It fails fast if any of the following regress:

1. **Zero Dart import cycles** across `app/lib/`.
2. **Strict Dart & Rust layer DAGs** (zero upward edges).
3. **100% Dart ↔ Rust RPC parity** (every `core.invoke('<name>')` in `app/lib/` must have a Rust match arm in `core/vedro-ffi/src/`).
4. **All 8 C-ABI symbols exported** (`vedro_init`, `vedro_destroy`, `vedro_invoke`, `vedro_poll_events`, `vedro_proxy_speed_bps`, `vedro_free_string`, `vedro_version`, `vedro_last_init_error`).
5. **Security & product invariants**:
   - `BilibiliRateLimiter` intact in `vedro-ffi`.
   - Zero `REQUEST_INSTALL_PACKAGES` permission in Android manifest.
   - Zero whole-screen `ColorFilter.matrix` beauty veil in player screens (2-Pass shader pipeline only).
   - Max volume boost cap `.clamp(100.0, 150.0)` preserved.
   - Single canonical transfer-speed formatter (`fmtTransferSpeed`) and `PlatformPerfProfile` OS checks.
6. **File-size complexity ratchets + 2,200-line global ceiling** across all `.rs` and `.dart` source files.

---

## 5. Playbook: Where to Make Changes (Locality of Change)

- **Add a Rust RPC**: Implement the arm in the owning `core/vedro-ffi/src/rpc_<domain>.rs` (or `danmaku.rs` / `updater.rs`), add the Dart caller in the matching `app/lib/state/app_state_<domain>.dart`, and run `bash scripts/verify-all.sh`.
- **Add a Model**: Add to the appropriate file in `app/lib/core/models/` (automatically re-exported by `models.dart`).
- **Add a Settings section**: Add the builder to the matching `app/lib/screens/settings/settings_*_sections.dart` and wire the `_SettingsSection` enum in `settings_screen.dart`.
- **Add a Player sheet / filter**: Add engine logic in `screens/player/player_engine.dart` and UI in `screens/player/player_sheets.dart` (or `player_subtitle_sheet.dart`).
