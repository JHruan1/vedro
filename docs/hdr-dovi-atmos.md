# Hardware Decoding, Dolby Vision & Dolby Atmos Guide

## 1. Platform Hardware Decoding Matrix

| Platform | Video Hardware Decoder (`hwdec`) | GPU Rendering Engine | HDR / Dolby Vision Output | Dolby Atmos / DTS:X Audio |
| --- | --- | --- | --- | --- |
| **Android** | `mediacodec` (zero-copy Surface) | `libmpv` + `libplacebo` (`gpu-next`, Vulkan) / Native `MediaCodec` DoVi Surface | Display `HDR_TYPE_DOLBY_VISION` / `HDR10` / `HLG` + `libplacebo` RPU | `AudioTrack` IEC61937 (`ENCODING_DOLBY_TRUEHD`, `ENCODING_E_AC3_JOC`, `ENCODING_DTS_HD`) + Android Spatializer |
| **iOS** | `videotoolbox` (HEVC 10-bit, AV1 on A17 Pro+, H.264) | `libmpv` + `libplacebo` (MoltenVK/Metal) / Native `AVSampleBufferDisplayLayer` EDR | Apple EDR PQ/HLG + Native DoVi P5/P8.1/P8.4 | `AVAudioSession` multichannel Apple Spatial Audio (E-AC-3 JOC Atmos) + PCM |
| **macOS** | `videotoolbox` (Apple Silicon ProRes/HEVC/AV1) | `libmpv` + `libplacebo` (`macvk` / Metal EDR) | Liquid Retina XDR 1600 nits EDR (`target-colorspace-hint=yes`) | CoreAudio Exclusive (`ac3,eac3,dts`) + Apple Spatial Audio |
| **Windows** | `d3d11va` / `nvdec` (zero-copy NVIDIA/AMD/Intel) | `libmpv` + `libplacebo` (`gpu-api=d3d11`, `d3d11-output-csp=pq`) | DXGI 1.6 PQ HDR10 / DoVi RPU dynamic tone-mapping | **WASAPI Exclusive** (`audio-spdif=ac3,eac3,dts,dts-hd,truehd`) — TrueHD Atmos & DTS:X bit-perfect over HDMI eARC |

## 2. How Prism Handles Every Dolby Vision Profile

- **Profile 5 (IPT-PQ-C2, streaming services — no HDR10 base layer)**:
  - Naive players produce purple/green inverted video.
  - Prism's Rust `inspector.rs` detects `dv_profile = 5` (`bl_signal_compatibility_id = 0`) immediately from the `dvcC`/`dvvC` record and activates `libplacebo`'s IPT-PQ-C2 RPU reshaper (or Apple/Android native DoVi hardware display layer), rendering accurate colors on **both HDR and SDR displays**.
- **Profile 7 (UHD Blu-ray Dual-Layer MEL/FEL)**:
  - Plays directly via `libmpv` + `libplacebo` (`vo=gpu-next`) with full dynamic RPU tone-mapping; flags `requires_p7_to_p81_rpu_conversion` when routing to Apple/Android native hardware layers.
- **Profile 8.1 (HDR10-compatible RPU) & Profile 8.4 (HLG-compatible RPU)**:
  - Natively supported by both Apple EDR/Android MediaCodec and `libplacebo` `gpu-next`.

## 3. Dolby Atmos Modes

1. **Auto**: Engages HDMI eARC bitstream passthrough on Windows/Android AVR setups, Apple Spatial Audio on iOS/macOS, and 32-bit float PCM elsewhere.
2. **Passthrough Bitstream**: Forces WASAPI Exclusive / AudioTrack IEC61937 for lossless **TrueHD Atmos**, **E-AC-3 JOC Atmos**, and **DTS-HD MA / DTS:X**.
3. **Spatial Audio**: Native OS multichannel Atmos decoding (AirPods Pro/Max head-tracking Spatial Audio, Android Spatializer).
4. **Headphone Binaural / Night Mode**: 32-bit float decode + BS2B binaural crossfeed + optional DRC Night Mode & vocal dialogue boost.
