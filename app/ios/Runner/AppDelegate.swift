import AVFoundation
import CFNetwork
import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    VedroHardwarePlugin.register(with: engineBridge.applicationRegistrar.messenger())
  }
}

/// Native iOS hardware, audio-session, brightness, battery & file picker bridge for Vedro:
/// - Lazy AVAudioSession activation (does not interrupt user's background music on app launch)
/// - Observes AVAudioSession interruption & route-change (pauses automatically on headphone unplug/call)
/// - Real UIScreen brightness & UIDevice battery level/charging state
/// - Validated HTTP/HTTPS external links & safe URLQueryItem encoding for Infuse/VLC
final class VedroHardwarePlugin: NSObject, UIDocumentPickerDelegate {
  static let channelName = "com.vedro.player/hardware"
  private static var retainedInstance: VedroHardwarePlugin?
  private weak var channel: FlutterMethodChannel?
  private var pendingPickResult: FlutterResult?
  private var originalBrightness: CGFloat?
  private var audioObservers: [NSObjectProtocol] = []

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    let instance = VedroHardwarePlugin()
    instance.channel = channel
    retainedInstance = instance
    channel.setMethodCallHandler { [weak instance] call, result in
      instance?.handle(call, result: result)
    }
  }

  deinit {
    removeAudioObservers()
  }

  private func isAllowedHttpUrl(_ raw: String) -> URL? {
    guard let url = URL(string: raw),
          let scheme = url.scheme?.lowercased(),
          (scheme == "http" || scheme == "https"),
          let host = url.host, !host.isEmpty else {
      return nil
    }
    return url
  }

  private func setAudioPlaybackActive(_ active: Bool) {
    let session = AVAudioSession.sharedInstance()
    if active {
      do {
        try session.setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)
        if #available(iOS 15.0, *) {
          try? session.setSupportsMultichannelContent(true)
        }
        try session.setActive(true)
      } catch {
        NSLog("VedroHardwarePlugin: AVAudioSession activate warning: \(error)")
      }
      installAudioObservers()
    } else {
      removeAudioObservers()
      try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
  }

  private func installAudioObservers() {
    if !audioObservers.isEmpty { return }
    let nc = NotificationCenter.default
    audioObservers.append(
      nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
        guard let info = note.userInfo,
              let typeVal = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeVal),
              type == .began else { return }
        self?.channel?.invokeMethod("audioInterrupted", arguments: ["reason": "interruption"])
      }
    )
    audioObservers.append(
      nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
        guard let info = note.userInfo,
              let reasonVal = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonVal),
              reason == .oldDeviceUnavailable else { return }
        self?.channel?.invokeMethod("audioInterrupted", arguments: ["reason": "becoming_noisy"])
      }
    )
  }

  private func removeAudioObservers() {
    let nc = NotificationCenter.default
    for obs in audioObservers {
      nc.removeObserver(obs)
    }
    audioObservers.removeAll()
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard let root = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController
      ?? scenes.first?.windows.first?.rootViewController else {
      return nil
    }
    var top = root
    while let presented = top.presentedViewController {
      top = presented
    }
    return top
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "queryCapabilities":
      result(queryCapabilities())
    case "setAudioPlaybackActive":
      let args = call.arguments as? [String: Any]
      let active = (args?["active"] as? Bool) ?? false
      setAudioPlaybackActive(active)
      result(nil)
    case "getScreenBrightness":
      DispatchQueue.main.async {
        result(Double(UIScreen.main.brightness))
      }
    case "setScreenBrightness":
      let args = call.arguments as? [String: Any]
      let v = CGFloat((args?["value"] as? NSNumber)?.doubleValue ?? 0.5)
      DispatchQueue.main.async {
        if self.originalBrightness == nil {
          self.originalBrightness = UIScreen.main.brightness
        }
        UIScreen.main.brightness = max(0.01, min(1.0, v))
      }
      result(nil)
    case "resetScreenBrightness":
      DispatchQueue.main.async {
        if let orig = self.originalBrightness {
          UIScreen.main.brightness = orig
          self.originalBrightness = nil
        }
      }
      result(nil)
    case "getBatteryInfo":
      DispatchQueue.main.async {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let raw = UIDevice.current.batteryLevel
        let pct = raw >= 0 ? Int((raw * 100.0).rounded()) : -1
        let st = UIDevice.current.batteryState
        let charging = (st == .charging || st == .full)
        result(["level": pct, "charging": charging])
      }
    case "isWifiConnected":
      result(true)
    case "setKeepScreenOn":
      let args = call.arguments as? [String: Any]
      let enabled = (args?["enabled"] as? Bool) ?? false
      DispatchQueue.main.async {
        UIApplication.shared.isIdleTimerDisabled = enabled
      }
      result(nil)
    case "setWindowChrome":
      let args = call.arguments as? [String: Any]
      let canvasArgb = (args?["canvas_argb"] as? Int) ?? 0xFF0B0B0D
      let r = CGFloat((canvasArgb >> 16) & 0xFF) / 255.0
      let g = CGFloat((canvasArgb >> 8) & 0xFF) / 255.0
      let b = CGFloat(canvasArgb & 0xFF) / 255.0
      DispatchQueue.main.async {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for win in scenes.flatMap({ $0.windows }) {
          win.backgroundColor = UIColor(red: r, green: g, blue: b, alpha: 1.0)
        }
      }
      result(nil)
    case "pickFiles":
      let args = call.arguments as? [String: Any]
      let extensions = (args?["extensions"] as? [String]) ?? []
      let allowMultiple = (args?["allow_multiple"] as? Bool) ?? false
      DispatchQueue.main.async {
        self.pendingPickResult?([String]())
        self.pendingPickResult = nil
        guard let presenter = self.topViewController() else {
          result([String]())
          return
        }
        var types: [UTType] = extensions.compactMap { UTType(filenameExtension: $0) }
        if types.isEmpty {
          types = [.item, .movie, .data]
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = allowMultiple
        picker.delegate = self
        self.pendingPickResult = result
        presenter.present(picker, animated: true)
      }
    case "openUrl":
      let args = call.arguments as? [String: Any]
      let raw = (args?["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard let url = isAllowedHttpUrl(raw) else {
        result(false)
        return
      }
      DispatchQueue.main.async {
        UIApplication.shared.open(url, options: [:]) { ok in
          result(ok)
        }
      }
    case "launchExternalPlayer":
      let args = call.arguments as? [String: Any]
      let streamUrl = (args?["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let player = ((args?["player"] as? String) ?? "").lowercased()
      guard let validStreamUrl = isAllowedHttpUrl(streamUrl) else {
        result(false)
        return
      }
      var targetUrl: URL?
      switch player {
      case "infuse":
        var comps = URLComponents(string: "infuse://x-callback-url/play")
        comps?.queryItems = [URLQueryItem(name: "url", value: validStreamUrl.absoluteString)]
        targetUrl = comps?.url
      case "vlc":
        var comps = URLComponents(string: "vlc-x-callback://x-callback-url/stream")
        comps?.queryItems = [URLQueryItem(name: "url", value: validStreamUrl.absoluteString)]
        targetUrl = comps?.url
      case "outplayer":
        targetUrl = URL(string: "outplayer://\(validStreamUrl.absoluteString)")
      case "nplayer":
        let replaced = validStreamUrl.absoluteString
          .replacingOccurrences(of: "https://", with: "nplayer-https://")
          .replacingOccurrences(of: "http://", with: "nplayer-http://")
        targetUrl = URL(string: replaced)
      default:
        targetUrl = validStreamUrl
      }
      let finalTarget = targetUrl ?? validStreamUrl
      DispatchQueue.main.async {
        UIApplication.shared.open(finalTarget, options: [:]) { ok in
          if !ok, finalTarget.absoluteString != validStreamUrl.absoluteString {
            UIApplication.shared.open(validStreamUrl, options: [:]) { ok2 in
              result(ok2)
            }
          } else {
            result(ok)
          }
        }
      }
    case "enterPiP":
      result(false)
    case "createVideoSurface":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    let paths = urls.map { $0.path }.filter { !$0.isEmpty }
    pendingPickResult?(paths)
    pendingPickResult = nil
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingPickResult?([String]())
    pendingPickResult = nil
  }

  private func detectSystemProxyUrl() -> String {
    guard let dict = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
      return ""
    }
    if let enabled = dict["HTTPEnable"] as? Int, enabled == 1,
       let host = dict["HTTPProxy"] as? String, !host.isEmpty {
      let port = (dict["HTTPPort"] as? Int) ?? 80
      return "http://\(host):\(port)"
    }
    return ""
  }

  private func queryCapabilities() -> [String: Any] {
    let screen = UIScreen.main
    let refreshHz = Double(screen.maximumFramesPerSecond)
    var supportsHdr10 = false
    var supportsHlg = false
    var supportsDovi = false
    var maxNits = 600

    if #available(iOS 16.0, *) {
      let headroom = screen.potentialEDRHeadroom
      if headroom > 1.2 {
        supportsHdr10 = true
        supportsHlg = true
        maxNits = Int(min(2000.0, headroom * 400.0))
      }
    }

    let hdrModes = AVPlayer.availableHDRModes
    if hdrModes.contains(.dolbyVision) { supportsDovi = true }
    if hdrModes.contains(.hdr10) { supportsHdr10 = true }
    if hdrModes.contains(.hlg) { supportsHlg = true }

    var spatialAvailable = false
    if #available(iOS 15.0, *) {
      spatialAvailable = AVAudioSession.sharedInstance().currentRoute.outputs.contains {
        $0.isSpatialAudioEnabled
      }
    }

    return [
      "is_tv": false,
      "has_touchscreen": true,
      "supports_pip": false,
      "supports_hdr10": supportsHdr10,
      "supports_hlg": supportsHlg,
      "supports_native_dolby_vision": supportsDovi,
      "supports_atmos_bitstream": false,
      "supports_spatial_audio": spatialAvailable,
      "max_luminance_nits": maxNits,
      "refresh_rate_hz": refreshHz,
      "system_proxy_url": detectSystemProxyUrl(),
    ]
  }
}
