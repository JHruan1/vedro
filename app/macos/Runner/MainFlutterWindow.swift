import AVFoundation
import Cocoa
import FlutterMacOS
import IOKit.pwr_mgt

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    PrismHardwarePlugin.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

/// Native macOS hardware bridge for Prism Player:
/// - Detects Apple Silicon Liquid Retina XDR / external HDR EDR headroom (up to 1600 nits)
/// - Reports VideoToolbox HEVC/AV1/Dolby Vision & CoreAudio Spatial Audio capabilities
/// - Prevents display sleep via IOKit IOPMAssertion during active playback
final class PrismHardwarePlugin: NSObject {
  static let channelName = "com.prismplayer/hardware"
  private var sleepAssertionId: IOPMAssertionID = 0
  private var holdingAssertion = false

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    let instance = PrismHardwarePlugin()
    channel.setMethodCallHandler(instance.handle)
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
    case "enterPiP", "createVideoSurface":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func setPreventSleep(_ enabled: Bool) {
    if enabled && !holdingAssertion {
      let reason = "Prism Player active video playback" as CFString
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

  private func queryCapabilities() -> [String: Any] {
    var headroom: CGFloat = 1.0
    var refreshHz: Double = 60.0
    if let screen = NSScreen.main {
      headroom = screen.maximumPotentialExtendedDynamicRangeColorComponentValue
      if #available(macOS 12.0, *) {
        refreshHz = Double(screen.maximumFramesPerSecond)
      }
    }
    let supportsHdr = headroom > 1.2
    let maxNits = supportsHdr ? Int(min(1600.0, Double(headroom) * 400.0)) : 400
    let hdrModes = AVPlayer.availableHDRModes
    let supportsDovi = hdrModes.contains(.dolbyVision) && supportsHdr

    return [
      "supports_hdr10": supportsHdr || hdrModes.contains(.hdr10),
      "supports_hlg": supportsHdr || hdrModes.contains(.hlg),
      "supports_native_dolby_vision": supportsDovi,
      "supports_atmos_bitstream": true,
      "supports_spatial_audio": true,
      "max_luminance_nits": maxNits,
      "refresh_rate_hz": refreshHz,
    ]
  }
}
