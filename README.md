# Vedro

**Vedro** 是一款面向 **embygo / Emby / Jellyfin** 生态打造的次世代跨平台全能硬件解码播放器，专为追求极致性能、**零转码直连播放 (DirectPlay)**、**杜比视界 (Dolby Vision)** 与 **杜比全景声 (Dolby Atmos)** 的影音发烧友设计。

支持全平台：**Android** · **iOS** · **macOS** · **Windows**（以及 Linux 桌面/CI 测试环境）。

---

## 核心技术选型

| 层级 | 技术栈 | 核心优势 |
| --- | --- | --- |
| **核心引擎 (`core/`)** | **Rust** (Tokio + Rustls HTTP/2 + Hyper + SQLite WAL + C-ABI FFI) | 零 GC 停顿、微秒级内存安全并发、7.4MB 精简原生动态库、统一复用于 Android / iOS / macOS / Windows |
| **视频解码 & HDR / 杜比视界** | **libmpv + libplacebo (`vo=gpu-next`)** + 平台原生硬件管线 (`VideoToolbox` / `AVSampleBufferDisplayLayer` / `MediaCodec` / `D3D11VA` / `NVDEC`) | 零拷贝硬件解码、原生支持 Dolby Vision Profile 5 (无绿紫偏色) / Profile 7 / Profile 8.1 & 8.4 动态元数据与 HDR10+ / HLG 色调映射 |
| **音频 & 杜比全景声** | **WASAPI Exclusive** / **Android AudioTrack IEC61937** / **Apple CoreAudio & Spatial Audio** / 32-bit Float HRTF | 支持 TrueHD Atmos、E-AC-3 JOC Atmos、DTS-HD MA / DTS:X 源码直通与空间音频，并内置夜间模式 DRC 与对白增强 |
| **高速流媒体代理 (`vedro-stream`)** | Rust 本地回环 HTTP Range 预取代理 + 环形 LRU 分块缓存 | 严格限制单会话并发上游连接数（≤2，完美适配 `embygo` 默认 4 连接上限，绝不触发 429）、自动预热 MKV 头尾 Cues 索引、支持 `StreamTicket` 无缝热更新、内置纯 Rust 二进制容器探针（无需服务端 ffprobe 即可识别 DoVi/Atmos） |
| **跨平台 UI (`app/`)** | **Flutter (Impeller GPU 引擎)** + `dart:ffi` 直连 Rust + 四端原生硬件桥接插件 | 120Hz GPU 渲染、自适应桌面侧边栏与移动端底部导航、完整手势与键盘快捷键、实时硬件统计浮窗 (`I`) |

---

## 完美适配 `embygo`（及兼容 Emby / Jellyfin）

详见 [docs/embygo-compatibility.md](docs/embygo-compatibility.md)：

- **自动识别后端方言**：通过 `System/Info/Public` 与 `/emby-compat/status` 自动识别 `embygo`、`Emby` 与 `Jellyfin`，动态开启专属特性。
- **彻底的零转码 DirectPlay**：针对 `embygo` 永不请求 `PlayMethod=Transcode`，在 `PlaybackInfo` 中遵循 `embygo` 最佳实践省略受限 `DeviceProfile` 以获取全部原始版本，并完整支持多版本合并选择（本地/云盘优先级、体积、估算码率）。
- **`StreamTicket` 安全规范与无感续期**：严禁在携带短效 `StreamTicket` 的媒体/字幕 URL 上附加长效 `api_key` 或 Bearer Token；支持 `embygo` 开启 `allow_query_credentials: false`；长暂停/长片播放前后台自动调用 `PlaybackInfo` 刷新票据并由 Rust 代理无缝热切换上游 URL。
- **`embygo` 专属能力全覆盖**：
  - 全站热播首页横幅 (`GET /Users/{id}/Items/Popular`)
  - 猜你喜欢推荐 (`GET /Users/{id}/Suggestions`)
  - 从「继续观看」移除且保留播放进度 (`POST/DELETE /Users/{id}/Items/{itemId}/HideFromResume`)
  - 播放保活心跳 (`POST /Sessions/Playing/Ping`) 与 5 分钟在线状态同步
  - 兼容数字型与字符串型分类/人物 ID（完美适配 `embygo` 面向 SenPlayer 优化的十进制 Facet ID）
  - 文本帧 WebSocket (`/embywebsocket` & `/socket`) 远程控制 (`Play`, `Playstate`, `GeneralCommand`, `DisplayMessage`) 与多端观看进度实时同步 (`UserDataChanged`)
  - UDP 7359 局域网服务器自动发现
  - 管理员专属 `embygo` 运行诊断面板（`/emby-compat/status`、`/Items/Counts`、在线会话、触发扫描 `/Library/Refresh`）
  - 面向未来扩展：已预留 `/MediaSegments/{id}`（跳过片头/片尾）与前向兼容 DTO 反序列化

---

## 仓库结构

```text
├── core/
│   ├── vedro-protocol/     # Emby / Jellyfin / embygo REST + WebSocket + UDP 7359 协议引擎
│   ├── vedro-stream/       # 本地 Range 预取代理、LRU 分块缓存、MKV/MP4 杜比视界/全景声探针、字幕解析器
│   ├── vedro-playback/     # libmpv + libplacebo 硬件解码控制、DoVi P5/7/8 策略、Atmos 音频路由
│   ├── vedro-storage/      # SQLite WAL 本地多服/配置/缓存持久化
│   ├── vedro-ffi/          # C-ABI 原生共享/静态库（供 Flutter dart:ffi / Swift / Kotlin / C++ 调用）
│   └── vedro-cli/          # 原生命令行探针、多平台配置矩阵与 embygo 端到端集成测试工具
├── app/
│   ├── lib/                # Flutter 跨平台 UI + dart:ffi Rust 桥接
│   ├── android/            # Android Kotlin 原生硬件插件 (MediaCodec DoVi, AudioTrack IEC61937 Atmos, PiP)
│   ├── ios/                # iOS Swift 原生硬件插件 (EDR Metal/DoVi, AVAudioSession Spatial Audio)
│   ├── macos/              # macOS Swift 原生硬件插件 (Liquid Retina XDR EDR, VideoToolbox, CoreAudio)
│   └── windows/            # Windows C++ 原生硬件插件 (DXGI 1.6 HDR/DoVi, WASAPI Exclusive TrueHD Atmos)
├── scripts/                # Android / iOS / macOS / Windows 一键构建与本地全量验证脚本
├── .github/workflows/      # GitHub Actions 四端自动化编译发布流水线
└── docs/                   # 架构设计、embygo 兼容性与杜比视界/全景声技术文档
```

---

## 快速构建与验证

### 本地一键全量验证（Rust 单元测试 + Clippy + Live embygo E2E + Flutter 分析与 FFI 实测）

```bash
bash scripts/verify-all.sh
```

### 各平台正式版构建

- **Android (arm64-v8a / armeabi-v7a / x86_64)**：`bash scripts/build-android.sh`
- **iOS (XCFramework + IPA)**：`bash scripts/build-ios.sh`（需 macOS + Xcode）
- **macOS (Universal Apple Silicon + Intel)**：`bash scripts/build-macos.sh`
- **Windows (x64 + DXGI HDR + WASAPI Atmos)**：`pwsh scripts/build-windows.ps1`
- 或直接推送到 GitHub 触发 `.github/workflows/ci-release.yml` 自动产出四端安装包。
