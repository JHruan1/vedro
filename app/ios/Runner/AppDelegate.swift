import AVFoundation
import Flutter
import UIKit

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

/// Native iOS hardware bridge for Vedro:
/// - Detects EDR headroom, Dolby Vision / HDR10 / HLG display support, and ProMotion 120Hz
/// - Configures AVAudioSession for multichannel Apple Spatial Audio & Dolby Atmos E-AC-3 JOC
/// - Manages idle timer during playback
final class VedroHardwarePlugin: NSObject {
  static let channelName = "com.vedro.player/hardware"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    let instance = VedroHardwarePlugin()
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
    case "enterPiP", "createVideoSurface":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
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
    ]
  }
}
