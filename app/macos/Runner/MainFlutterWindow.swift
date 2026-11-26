import AVFoundation
import CFNetwork
import Cocoa
import FlutterMacOS
import IOKit.pwr_mgt
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
    }
  }

  deinit {
    for obs in observers {
      NotificationCenter.default.removeObserver(obs)
    }
  }

  static func register(with messenger: FlutterBinaryMessenger, window: NSWindow?) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    let instance = VedroHardwarePlugin(window: window, channel: channel)
    channel.setMethodCallHandler(instance.handle)
  }

  func emitDroppedFiles(_ paths: [String]) {
    DispatchQueue.main.async {
      self.channel?.invokeMethod("filesDropped", arguments: ["paths": paths])
    }
  }

  private func resolveWindow() -> NSWindow? {
    return window ?? NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "queryCapabilities":
      result(queryCapabilities())
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
    case "enterPiP", "createVideoSurface":
      result(nil)
    case "openUrl":
      let args = call.arguments as? [String: Any]
      let raw = (args?["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard let url = URL(string: raw) else {
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
    if let screen = NSScreen.main {
      headroom = screen.maximumPotentialExtendedDynamicRangeColorComponentValue
      if #available(macOS 12.0, *) {
        refreshHz = Double(screen.maximumFramesPerSecond)
      }
    }
    let supportsHdr = headroom > 1.2 || AVPlayer.eligibleForHDRPlayback
    let maxNits = headroom > 1.2 ? Int(min(1600.0, Double(headroom) * 400.0)) : (supportsHdr ? 1000 : 400)
    let supportsDovi = supportsHdr && headroom > 1.2

    return [
      "supports_hdr10": supportsHdr,
      "supports_hlg": supportsHdr,
      "supports_native_dolby_vision": supportsDovi,
      "supports_atmos_bitstream": true,
      "supports_spatial_audio": true,
      "max_luminance_nits": maxNits,
      "refresh_rate_hz": refreshHz,
      "system_proxy_url": detectSystemProxyUrl(),
    ]
  }
}
