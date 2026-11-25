# Vedro Technical Architecture

## 1. Why Rust Core + Native Playback + Flutter/Impeller?

Media players spend 95% of their critical-path latency in:
1. **Network I/O & HTTP Range demuxing** (4K UHD Blu-ray Remuxes peak at 100–140 Mbps).
2. **Binary container parsing & subtitle decoding** (MKV EBML, MP4 ISOBMFF, ASS/SSA, PGS).
3. **Hardware video decoding & HDR/Dolby Vision GPU compositing** (120Hz frame pacing with zero dropped frames).
4. **Audio bitstreaming / multichannel spatialization** (TrueHD Atmos, E-AC-3 JOC, DTS:X).

Writing the entire core (`vedro-protocol`, `vedro-stream`, `vedro-playback`, `vedro-storage`, `vedro-ffi`) in **Rust** eliminates GC pauses, minimizes RSS memory footprint, enforces thread-safe concurrency across Tokio async tasks, and produces a single ~7.4 MB LTO-optimized native library compiled identically for Android, iOS, macOS, and Windows.

## 2. Data & Media Flow

```text
embygo / Emby / Jellyfin Server
        │  HTTP/2 + TLS (rustls) + StreamTicket / X-Emby-Token
        ▼
┌────────────────────────────────────────────────────────┐
│  Rust Core (libvedro_ffi)                              │
│  ├─ vedro-protocol: REST, WebSocket, UDP 7359          │
│  ├─ vedro-stream:   Loopback HTTP Range Proxy          │
│  │     • Strict <= 2 upstream conns/session (no 429!)  │
│  │     • 1 MiB LRU Chunk Cache + Read-Ahead Prefetch   │
│  │     • MKV/MP4 Head+Tail Pre-warm for Instant Seek   │
│  │     • Zero-Interruption StreamTicket URL Hot-Swap   │
│  │     • Binary dvcC/dvvC/TrueHD/E-AC-3 JOC Inspector  │
│  ├─ vedro-playback: libmpv + libplacebo Controller     │
│  │     • DoVi P5/P7/P8.1/P8.4 & HDR10+/HLG Policy      │
│  │     • Atmos Bitstream / Spatial / HRTF Router       │
│  └─ vedro-storage:  SQLite WAL (Servers/Prefs/Cache)   │
└───────────────────────────┬────────────────────────────┘
                            │ dart:ffi (C-ABI, zero HTTP overhead)
                            ▼
┌────────────────────────────────────────────────────────┐
│  Flutter Impeller UI + Native Platform Plugins         │
│  ├─ Android: Kotlin MediaCodec DoVi + AudioTrack Atmos │
│  ├─ iOS:     Swift EDR Metal/DoVi + AVAudioSession     │
│  ├─ macOS:   Swift Liquid Retina XDR + CoreAudio       │
│  └─ Windows: C++ DXGI 1.6 HDR + WASAPI Exclusive Atmos │
└────────────────────────────────────────────────────────┘
```
