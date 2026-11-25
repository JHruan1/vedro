import 'package:flutter/services.dart';

/// Platform channel bridging Flutter UI with native OS hardware capabilities:
/// - Android: MediaCodec Dolby Vision probe, AudioTrack IEC61937 TrueHD/E-AC-3 JOC Atmos, SurfaceView, PiP
/// - iOS: Metal EDR + AVSampleBufferDisplayLayer Dolby Vision, AVAudioSession Spatial Audio, PiP
/// - macOS: Metal EDR + VideoToolbox, CoreAudio Exclusive / Spatial Audio
/// - Windows: DXGI HDR10/Dolby Vision detection, WASAPI Exclusive TrueHD/E-AC-3 Atmos
class NativePlaybackChannel {
  static const MethodChannel _channel = MethodChannel('com.vedro.player/hardware');

  static Future<Map<String, dynamic>> queryDisplayAndAudioCapabilities() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('queryCapabilities');
      if (res != null) return res;
    } on MissingPluginException {
      // Fallback on headless test runner or desktop hosts without plugin registered
    } catch (_) {}
    return const {
      'supports_hdr10': true,
      'supports_hlg': true,
      'supports_native_dolby_vision': false,
      'supports_atmos_bitstream': false,
      'supports_spatial_audio': false,
      'max_luminance_nits': 1000,
      'refresh_rate_hz': 60.0,
    };
  }

  static Future<int?> attachNativeVideoSurface() async {
    try {
      return await _channel.invokeMethod<int>('createVideoSurface');
    } catch (_) {
      return null;
    }
  }

  static Future<void> enterPictureInPicture() async {
    try {
      await _channel.invokeMethod<void>('enterPiP');
    } catch (_) {}
  }

  static Future<void> setKeepScreenOn(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setKeepScreenOn', {'enabled': enabled});
    } catch (_) {}
  }
}
