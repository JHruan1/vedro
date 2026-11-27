import AVFoundation
import CFNetwork
import Cocoa
import FlutterMacOS
import IOKit.pwr_mgt
import MediaPlayer
import UniformTypeIdentifiers

class MainFlutterWindow: NSWindow, NSDraggingDestination {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let desiredSize = NSSize(width: 1280, height: 820)
    var windowFrame = self.frame
    if windowFrame.width < 1000 || windowFrame.height < 680 {
      windowFrame.size = desiredSize
    }
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 860, height: 580)
    self.center()

    // Full-bleed Apple TV+ / IINA / SenPlayer native dark window chrome + native macOS Fullscreen
    self.styleMask.insert(.fullSizeContentView)
    self.collectionBehavior.insert(.fullScreenPrimary)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.isMovableByWindowBackground = true
    self.appearance = NSAppearance(named: .darkAqua)
    self.backgroundColor = NSColor(calibratedRed: 0.043, green: 0.043, blue: 0.051, alpha: 1.0)

    // Accept drag-and-drop video files, folders, and subtitle files anywhere on the window
    self.registerForDraggedTypes([.fileURL])

    RegisterGeneratedPlugins(registry: flutterViewController)
    VedroHardwarePlugin.register(with: flutterViewController.engine.binaryMessenger, window: self)

    super.awakeFromNib()
  }

  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    let pb = sender.draggingPasteboard
    if pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
      return .copy
    }
    return []
  }

  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let pb = sender.draggingPasteboard
    guard let urls = pb.readObjects(
      forClasses: [NSURL.self],
      options: [.urlReadingFileURLsOnly: true]
    ) as? [URL], !urls.isEmpty else {
      return false
    }
    let paths = urls.map { $0.path }.filter { !$0.isEmpty }
    if paths.isEmpty { return false }
    VedroHardwarePlugin.shared?.emitDroppedFiles(paths)
    return true
  }
}

/// Native macOS hardware & window bridge for Vedro:
/// - Native macOS Fullscreen (`toggleFullscreen`, `setFullscreen`, `isFullscreen`)
/// - Titlebar Double-Click Zoom (`toggleZoom`), Always-on-Top (`setAlwaysOnTop`)
/// - Native macOS File / Folder Picker (`pickFiles` via `NSOpenPanel`)
/// - Drag-and-Drop / Open-With file events (`filesDropped`)
/// - EDR / HDR / Dolby Vision probing, system proxy auto-detection, IOKit sleep prevention
final class VedroHardwarePlugin: NSObject {
  static let channelName = "com.vedro.player/hardware"
  static weak var shared: VedroHardwarePlugin?

  private weak var window: NSWindow?
  private var channel: FlutterMethodChannel?
  private var sleepAssertionId: IOPMAssertionID = 0
  private var holdingAssertion = false
  private var observers: [NSObjectProtocol] = []

  init(window: NSWindow?, channel: FlutterMethodChannel) {
    self.window = window
    self.channel = channel
    super.init()
    VedroHardwarePlugin.shared = self
    if let win = window {
      let nc = NotificationCenter.default
      observers.append(nc.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: win, queue: .main) { [weak self] _ in
        self?.channel?.invokeMethod("fullscreenChanged", arguments: ["fullscreen": true])
      })
      observers.append(nc.addObserver(forName: NSWindow.didExitFullScreenNotification, object: win, queue: .main) { [weak self] _ in
        self?.channel?.invokeMethod("fullscreenChanged", arguments: ["fullscreen": false])
      })
      observers.append(nc.addObserver(forName: NSWindow.willCloseNotification, object: win, queue: .main) { [weak self] _ in
        self?.setPreventSleep(false)
        VedroHardwarePlugin.retainedInstance = nil
      })
    }
  }

  private static var retainedInstance: VedroHardwarePlugin?
  private static var pendingColdLaunchFiles: [String] = []
  private var remoteCommandsInstalled = false

  deinit {
    setPreventSleep(false)
    removeRemoteCommands()
    for obs in observers {
      NotificationCenter.default.removeObserver(obs)
    }
  }

  static func enqueueOrEmitDroppedFiles(_ paths: [String]) {
    if let shared = shared {
      shared.emitDroppedFiles(paths)
    } else {
      pendingColdLaunchFiles.append(contentsOf: paths)
    }
  }

  static func register(with messenger: FlutterBinaryMessenger, window: NSWindow?) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    let instance = VedroHardwarePlugin(window: window, channel: channel)
    retainedInstance = instance
    channel.setMethodCallHandler { [weak instance] call, result in
      instance?.handle(call, result: result)
    }
  }

  func emitDroppedFiles(_ paths: [String]) {
    DispatchQueue.main.async {
      self.channel?.invokeMethod("filesDropped", arguments: ["paths": paths])
    }
  }

  private func flushPendingColdLaunchFiles() {
    if !Self.pendingColdLaunchFiles.isEmpty {
      let batch = Self.pendingColdLaunchFiles
      Self.pendingColdLaunchFiles.removeAll()
      emitDroppedFiles(batch)
    }
  }

  private func installRemoteCommands() {
    if remoteCommandsInstalled { return }
    remoteCommandsInstalled = true
    let cc = MPRemoteCommandCenter.shared()
    cc.playCommand.isEnabled = true
    cc.playCommand.addTarget { [weak self] _ in
      self?.channel?.invokeMethod("mediaAction", arguments: ["action": "play"])
      return .success
    }
    cc.pauseCommand.isEnabled = true
    cc.pauseCommand.addTarget { [weak self] _ in
      self?.channel?.invokeMethod("mediaAction", arguments: ["action": "pause"])
      return .success
    }
    cc.togglePlayPauseCommand.isEnabled = true
    cc.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.channel?.invokeMethod("mediaAction", arguments: ["action": "toggle_play"])
      return .success
    }
    cc.nextTrackCommand.isEnabled = true
    cc.nextTrackCommand.addTarget { [weak self] _ in
      self?.channel?.invokeMethod("mediaAction", arguments: ["action": "next"])
      return .success
    }
    cc.previousTrackCommand.isEnabled = true
    cc.previousTrackCommand.addTarget { [weak self] _ in
      self?.channel?.invokeMethod("mediaAction", arguments: ["action": "previous"])
      return .success
    }
  }

  private func removeRemoteCommands() {
    if !remoteCommandsInstalled { return }
    remoteCommandsInstalled = false
    let cc = MPRemoteCommandCenter.shared()
    cc.playCommand.removeTarget(nil)
    cc.pauseCommand.removeTarget(nil)
    cc.togglePlayPauseCommand.removeTarget(nil)
    cc.nextTrackCommand.removeTarget(nil)
    cc.previousTrackCommand.removeTarget(nil)
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }

  private func resolveWindow() -> NSWindow? {
    return window ?? NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "queryCapabilities":
      flushPendingColdLaunchFiles()
      result(queryCapabilities())
    case "updateNowPlaying":
      let args = call.arguments as? [String: Any]
      let title = (args?["title"] as? String) ?? ""
      let subtitle = (args?["subtitle"] as? String) ?? ""
      let durationMs = (args?["duration_ms"] as? NSNumber)?.intValue ?? 0
      let positionMs = (args?["position_ms"] as? NSNumber)?.intValue ?? 0
      let isPlaying = (args?["is_playing"] as? Bool) ?? false
      let speed = (args?["speed"] as? NSNumber)?.doubleValue ?? 1.0
      DispatchQueue.main.async {
        if title.isEmpty && !isPlaying {
          MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
          MPNowPlayingInfoCenter.default().playbackState = .stopped
        } else {
          self.installRemoteCommands()
          MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: subtitle,
            MPMediaItemPropertyPlaybackDuration: Double(max(0, durationMs)) / 1000.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(max(0, positionMs)) / 1000.0,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? speed : 0.0,
          ]
          MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        }
      }
      result(nil)
    case "saveScreenshotToGallery":
      let args = call.arguments as? [String: Any]
      guard let typed = args?["bytes"] as? FlutterStandardTypedData else {
        result(nil)
        return
      }
      let rawName = (args?["file_name"] as? String) ?? "vedro_\(Int(Date().timeIntervalSince1970)).png"
      let safeName = rawName.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
      let picturesDir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
      let vedroDir = picturesDir?.appendingPathComponent("Vedro", isDirectory: true)
      if let dir = vedroDir {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(safeName)
        if (try? typed.data.write(to: dest)) != nil {
          result(dest.path)
          return
        }
      }
      result(nil)
    case "setKeepScreenOn":
      let args = call.arguments as? [String: Any]
      let enabled = (args?["enabled"] as? Bool) ?? false
      setPreventSleep(enabled)
      result(nil)
    case "isFullscreen":
      DispatchQueue.main.async {
        let fs = self.resolveWindow()?.styleMask.contains(.fullScreen) ?? false
        result(fs)
      }
    case "toggleFullscreen":
      DispatchQueue.main.async {
        guard let win = self.resolveWindow() else {
          result(false)
          return
        }
        let currentlyFs = win.styleMask.contains(.fullScreen)
        win.toggleFullScreen(nil)
        result(!currentlyFs)
      }
    case "setFullscreen":
      let args = call.arguments as? [String: Any]
      let target = (args?["enabled"] as? Bool) ?? false
      DispatchQueue.main.async {
        guard let win = self.resolveWindow() else {
          result(false)
          return
        }
        let currentlyFs = win.styleMask.contains(.fullScreen)
        if currentlyFs != target {
          win.toggleFullScreen(nil)
        }
        result(target)
      }
    case "toggleZoom":
      DispatchQueue.main.async {
        self.resolveWindow()?.performZoom(nil)
        result(nil)
      }
    case "setAlwaysOnTop":
      let args = call.arguments as? [String: Any]
      let enabled = (args?["enabled"] as? Bool) ?? false
      DispatchQueue.main.async {
        self.resolveWindow()?.level = enabled ? .floating : .normal
        result(enabled)
      }
    case "setWindowChrome":
      let args = call.arguments as? [String: Any]
      let isLight = (args?["is_light"] as? Bool) ?? false
      let canvasArgb = (args?["canvas_argb"] as? Int) ?? 0xFF0B0B0D
      let r = CGFloat((canvasArgb >> 16) & 0xFF) / 255.0
      let g = CGFloat((canvasArgb >> 8) & 0xFF) / 255.0
      let b = CGFloat(canvasArgb & 0xFF) / 255.0
      DispatchQueue.main.async {
        if let win = self.resolveWindow() {
          win.appearance = NSAppearance(named: isLight ? .aqua : .darkAqua)
          win.backgroundColor = NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
        }
        result(nil)
      }
    case "pickFiles":
      let args = call.arguments as? [String: Any]
      let extensions = (args?["extensions"] as? [String]) ?? []
      let allowDirectory = (args?["allow_directory"] as? Bool) ?? false
      let allowMultiple = (args?["allow_multiple"] as? Bool) ?? false
      let title = (args?["title"] as? String) ?? "选择文件"
      DispatchQueue.main.async {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = !allowDirectory || !extensions.isEmpty
        panel.canChooseDirectories = allowDirectory
        panel.allowsMultipleSelection = allowMultiple
        if !extensions.isEmpty {
          if #available(macOS 11.0, *) {
            let types = extensions.compactMap { UTType(filenameExtension: $0) }
            if !types.isEmpty {
              panel.allowedContentTypes = types
            }
          } else {
            panel.allowedFileTypes = extensions
          }
        }
        if let win = self.resolveWindow() {
          panel.beginSheetModal(for: win) { response in
            if response == .OK {
              result(panel.urls.map { $0.path })
            } else {
              result([String]())
            }
          }
        } else {
          let response = panel.runModal()
          result(response == .OK ? panel.urls.map { $0.path } : [String]())
        }
      }
    case "enterPiP":
      result(false)
    case "createVideoSurface":
      result(nil)
    case "openUrl":
      let args = call.arguments as? [String: Any]
      let raw = (args?["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard let url = URL(string: raw),
            let scheme = url.scheme?.lowercased(),
            (scheme == "http" || scheme == "https"),
            let host = url.host, !host.isEmpty else {
        result(false)
        return
      }
      DispatchQueue.main.async {
        result(NSWorkspace.shared.open(url))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func setPreventSleep(_ enabled: Bool) {
    if enabled && !holdingAssertion {
      let reason = "Vedro active video playback" as CFString
      if IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
        IOPMAssertionLevel(kIOPMAssertionLevelOn),
        reason,
        &sleepAssertionId
      ) == kIOReturnSuccess {
        holdingAssertion = true
      }
    } else if !enabled && holdingAssertion {
      IOPMAssertionRelease(sleepAssertionId)
      holdingAssertion = false
    }
  }

  private func detectSystemProxyUrl() -> String {
    guard let dict = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
      return ""
    }
    if let enabled = dict[kCFNetworkProxiesHTTPEnable as String] as? Int, enabled == 1,
       let host = dict[kCFNetworkProxiesHTTPProxy as String] as? String, !host.isEmpty {
      let port = (dict[kCFNetworkProxiesHTTPPort as String] as? Int) ?? 80
      return "http://\(host):\(port)"
    }
    if let enabled = dict[kCFNetworkProxiesHTTPSEnable as String] as? Int, enabled == 1,
       let host = dict[kCFNetworkProxiesHTTPSProxy as String] as? String, !host.isEmpty {
      let port = (dict[kCFNetworkProxiesHTTPSPort as String] as? Int) ?? 443
      return "http://\(host):\(port)"
    }
    if let enabled = dict[kCFNetworkProxiesSOCKSEnable as String] as? Int, enabled == 1,
       let host = dict[kCFNetworkProxiesSOCKSProxy as String] as? String, !host.isEmpty {
      let port = (dict[kCFNetworkProxiesSOCKSPort as String] as? Int) ?? 1080
      return "socks5h://\(host):\(port)"
    }
    return ""
  }

  private func queryCapabilities() -> [String: Any] {
    var headroom: CGFloat = 1.0
    var refreshHz: Double = 60.0
    if let screen = resolveWindow()?.screen ?? NSScreen.main {
      headroom = screen.maximumPotentialExtendedDynamicRangeColorComponentValue
      if #available(macOS 12.0, *) {
        refreshHz = Double(screen.maximumFramesPerSecond)
      }
    }
    let supportsHdr = headroom > 1.2 || AVPlayer.eligibleForHDRPlayback
    let maxNits = headroom > 1.2 ? Int(min(1600.0, Double(headroom) * 400.0)) : (supportsHdr ? 1000 : 400)
    let supportsDovi = supportsHdr && headroom > 1.2

    return [
      "is_tv": false,
      "has_touchscreen": false,
      "supports_pip": false,
      "supports_hdr10": supportsHdr,
      "supports_hlg": supportsHdr,
      "supports_native_dolby_vision": supportsDovi,
      "supports_atmos_bitstream": false,
      "supports_spatial_audio": true,
      "max_luminance_nits": maxNits,
      "refresh_rate_hz": refreshHz,
      "system_proxy_url": detectSystemProxyUrl(),
    ]
  }
}
