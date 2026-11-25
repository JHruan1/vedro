# Vedro

Cross-platform media player for **embygo**, **Emby**, and **Jellyfin** — built with a **Rust** core (`libmpv` / `libplacebo`) and **Flutter**.

Supports **Android**, **iOS**, **macOS**, and **Windows**.

## Highlights

- **Rust core (`core/`)**: Async HTTP/2 client, local HTTP Range prefetch proxy (bounded to ≤2 upstream connections per session for `embygo`), `StreamTicket` auto-renewal, binary MKV/MP4 HDR/DoVi/Atmos header inspector, SQLite WAL storage, C-ABI FFI (`libvedro_ffi`).
- **Video & HDR**: Platform hardware decoding (`MediaCodec`, `VideoToolbox`, `D3D11VA` / `NVDEC`), `libmpv` + `libplacebo` (`gpu-next`), Dolby Vision (Profile 5 / 7 / 8.1 / 8.4), HDR10 / HDR10+ / HLG.
- **Audio**: Dolby Atmos (TrueHD / E-AC-3 JOC) & DTS:X via WASAPI Exclusive, Android AudioTrack IEC61937, Apple Spatial Audio / CoreAudio, plus headphone downmix & DRC.
- **embygo / Emby / Jellyfin**: DirectPlay-first (zero transcode on `embygo`), `Popular`, `Suggestions`, `HideFromResume`, multi-version picker, external sidecar subtitles, playlists, WebSocket remote control & `UserDataChanged` sync, LAN UDP 7359 discovery.

## Download

Get prebuilt installers from [Releases](https://github.com/JHruan1/vedro/releases):

- **Android**: `vedro-android-arm64-v8a.apk` (recommended) / `armeabi-v7a` / `x86_64` / `universal`
- **Windows x64**: `vedro-windows-x64.zip`
- **macOS (Universal)**: `vedro-macos-universal.dmg`
- **iOS (arm64)**: `vedro-ios-unsigned.ipa`

## Build from Source

```bash
# Verify Rust core + Flutter + FFI
bash scripts/verify-all.sh

# Platform packages
bash scripts/build-android.sh
bash scripts/build-macos.sh
bash scripts/build-ios.sh
pwsh scripts/build-windows.ps1
```

## Docs

- [Architecture](docs/architecture.md)
- [embygo / Emby / Jellyfin Compatibility](docs/embygo-compatibility.md)
- [Hardware Decoding, Dolby Vision & Dolby Atmos](docs/hdr-dovi-atmos.md)
