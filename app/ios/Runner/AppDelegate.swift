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

/// Native iOS hardware & file picker bridge for Vedro:
/// - Detects EDR headroom, Dolby Vision / HDR10 / HLG display support, ProMotion 120Hz & system proxy
/// - Configures AVAudioSession for multichannel Apple Spatial Audio & Dolby Atmos E-AC-3 JOC
/// - Native UIDocumentPickerViewController (`pickFiles`) for local videos, subtitles, danmaku XML & fonts
final class VedroHardwarePlugin: NSObject, UIDocumentPickerDelegate {
  static let channelName = "com.vedro.player/hardware"
  private static var retainedInstance: VedroHardwarePlugin?
  private var pendingPickResult: FlutterResult?

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    let instance = VedroHardwarePlugin()
    retainedInstance = instance
    instance.configureSpatialAudioSession()
    channel.setMethodCallHandler(instance.handle)
  }

  private func configureSpatialAudioSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)
      if #available(iOS 15.0, *) {
        try? session.setSupportsMultichannelContent(true)
      }
      try session.setActive(true)
    } catch {
      NSLog("VedroHardwarePlugin: AVAudioSession setup warning: \(error)")
    }
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
    case "setKeepScreenOn":
      let args = call.arguments as? [String: Any]
      let enabled = (args?["enabled"] as? Bool) ?? false
      DispatchQueue.main.async {
        UIApplication.shared.isIdleTimerDisabled = enabled
      }
      result(nil)
    case "pickFiles":
      let args = call.arguments as? [String: Any]
      let extensions = (args?["extensions"] as? [String]) ?? []
      let allowMultiple = (args?["allow_multiple"] as? Bool) ?? false
      DispatchQueue.main.async {
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
    case "enterPiP", "createVideoSurface":
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
