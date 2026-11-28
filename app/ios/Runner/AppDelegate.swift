import AVFoundation
import CFNetwork
import Flutter
import MediaPlayer
import Network
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
  private var channel: FlutterMethodChannel?
  private var pendingPickResult: FlutterResult?
  private var originalBrightness: CGFloat?
  private var playerBrightnessOverride: CGFloat?
  private var audioObservers: [NSObjectProtocol] = []
  private var lifecycleObservers: [NSObjectProtocol] = []
  private var remoteCommandsInstalled = false
  private var pathMonitor: NWPathMonitor?
  private var isUnmeteredNetwork = true

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    let instance = VedroHardwarePlugin()
    instance.channel = channel
    retainedInstance = instance
    instance.startNetworkMonitor()
    instance.installLifecycleObservers()
    channel.setMethodCallHandler { [weak instance] call, result in
      instance?.handle(call, result: result)
    }
  }

  deinit {
    pathMonitor?.cancel()
    removeAudioObservers()
    removeRemoteCommands()
    for obs in lifecycleObservers {
      NotificationCenter.default.removeObserver(obs)
    }
  }

  private func startNetworkMonitor() {
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { [weak self] path in
      let wifiOrWired = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) || !path.isExpensive
      self?.isUnmeteredNetwork = (path.status == .satisfied) && wifiOrWired
    }
    monitor.start(queue: DispatchQueue.global(qos: .utility))
    pathMonitor = monitor
  }

  private func installLifecycleObservers() {
    let nc = NotificationCenter.default
    lifecycleObservers.append(
      nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
        if let orig = self?.originalBrightness {
          UIScreen.main.brightness = orig
        }
      }
    )
    lifecycleObservers.append(
      nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
        if let overrideVal = self?.playerBrightnessOverride {
          UIScreen.main.brightness = overrideVal
        }
      }
    )
    lifecycleObservers.append(
      nc.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
        if let orig = self?.originalBrightness {
          UIScreen.main.brightness = orig
          self?.originalBrightness = nil
          self?.playerBrightnessOverride = nil
        }
      }
    )
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
    cc.changePlaybackPositionCommand.isEnabled = true
    cc.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let posEv = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
      self?.channel?.invokeMethod("mediaAction", arguments: [
        "action": "seek",
        "position_ms": Int(posEv.positionTime * 1000.0)
      ])
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
    cc.changePlaybackPositionCommand.removeTarget(nil)
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }

  private func updateNowPlaying(
    title: String,
    subtitle: String,
    durationMs: Int,
    positionMs: Int,
    isPlaying: Bool,
    speed: Double,
    hasNext: Bool,
    hasPrevious: Bool,
    active: Bool
  ) {
    DispatchQueue.main.async {
      if !active || (title.isEmpty && !isPlaying) {
        self.removeRemoteCommands()
        return
      }
      self.installRemoteCommands()
      let cc = MPRemoteCommandCenter.shared()
      cc.nextTrackCommand.isEnabled = hasNext
      cc.previousTrackCommand.isEnabled = hasPrevious
      var info: [String: Any] = [
        MPMediaItemPropertyTitle: title,
        MPMediaItemPropertyArtist: subtitle,
        MPMediaItemPropertyPlaybackDuration: Double(max(0, durationMs)) / 1000.0,
        MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(max(0, positionMs)) / 1000.0,
        MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? speed : 0.0,
      ]
      info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = speed
      MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
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
    case "updateNowPlaying":
      let args = call.arguments as? [String: Any]
      let title = (args?["title"] as? String) ?? ""
      let subtitle = (args?["subtitle"] as? String) ?? ""
      let durationMs = (args?["duration_ms"] as? NSNumber)?.intValue
        ?? Int(((args?["duration_secs"] as? NSNumber)?.doubleValue ?? 0.0) * 1000.0)
      let positionMs = (args?["position_ms"] as? NSNumber)?.intValue
        ?? Int(((args?["position_secs"] as? NSNumber)?.doubleValue ?? 0.0) * 1000.0)
      let isPlaying = (args?["is_playing"] as? Bool) ?? (args?["playing"] as? Bool) ?? false
      let speed = (args?["speed"] as? NSNumber)?.doubleValue ?? 1.0
      let hasNext = (args?["has_next"] as? Bool) ?? false
      let hasPrevious = (args?["has_previous"] as? Bool) ?? false
      let active = (args?["active"] as? Bool) ?? true
      updateNowPlaying(
        title: title,
        subtitle: subtitle,
        durationMs: durationMs,
        positionMs: positionMs,
        isPlaying: isPlaying,
        speed: speed,
        hasNext: hasNext,
        hasPrevious: hasPrevious,
        active: active
      )
      result(nil)
    case "saveScreenshotToGallery":
      let args = call.arguments as? [String: Any]
      guard let typed = args?["bytes"] as? FlutterStandardTypedData,
            let image = UIImage(data: typed.data) else {
        result(nil)
        return
      }
      DispatchQueue.main.async {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        result("Photos")
      }
    case "setScreenBrightness":
      let args = call.arguments as? [String: Any]
      let v = CGFloat((args?["value"] as? NSNumber)?.doubleValue ?? 0.5)
      let clamped = max(0.01, min(1.0, v))
      DispatchQueue.main.async {
        if self.originalBrightness == nil {
          self.originalBrightness = UIScreen.main.brightness
        }
        self.playerBrightnessOverride = clamped
        UIScreen.main.brightness = clamped
      }
      result(nil)
    case "resetScreenBrightness":
      DispatchQueue.main.async {
        self.playerBrightnessOverride = nil
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
      result(isUnmeteredNetwork)
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
        // Always include generic .item / .data so .mkv / .srt / .ass / .ttf are never greyed out in iOS Files
        if !types.contains(.item) { types.append(.item) }
        if !types.contains(.data) { types.append(.data) }
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
      // Disabled to prevent direct media stream URLs from leaking to external apps/downloaders.
      result(false)
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
    if let enabled = dict["HTTPSEnable"] as? Int, enabled == 1,
       let host = dict["HTTPSProxy"] as? String, !host.isEmpty {
      let port = (dict["HTTPSPort"] as? Int) ?? 443
      return "http://\(host):\(port)"
    }
    if let enabled = dict["SOCKSEnable"] as? Int, enabled == 1,
       let host = dict["SOCKSProxy"] as? String, !host.isEmpty {
      let port = (dict["SOCKSPort"] as? Int) ?? 1080
      return "socks5h://\(host):\(port)"
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
