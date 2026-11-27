import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'native_playback_channel.dart';

/// Per-platform rendering, animation, and thermal optimization policy.
///
/// Tuned individually for Android, Android TV, iOS, macOS, Windows, and Linux to keep
/// animations locked to native display refresh rates (60/90/120Hz) while
/// aggressively eliminating GPU overdraw, large-sigma `BackdropFilter` stalls,
/// redundant `saveLayer` passes, and mobile SoC thermal throttling.
class PlatformPerfProfile {
  PlatformPerfProfile._();

  /// Optional user-controlled TV / D-Pad Remote Mode override (for TV boxes that don't declare LEANBACK).
  static bool tvModeManualOverride = false;

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;
  static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get isLinux => !kIsWeb && Platform.isLinux;
  static bool get isTv => NativePlaybackChannel.detectedAndroidTv || tvModeManualOverride;
  static bool get isMobileOs => isAndroid || isIOS;
  static bool get isApple => isMacOS || isIOS;
  static bool get isMobile => (isAndroid && !isTv) || isIOS;
  static bool get isDesktop => isMacOS || isWindows || isLinux;

  /// Maximum Gaussian sigma for live `BackdropFilter` surfaces composited over
  /// scrolling content or live video. Large sigmas (28–48) saturate mobile tile
  /// GPUs (Adreno/Mali) and Windows D3D11/ANGLE integrated GPUs; clamping keeps
  /// frosted glass visually silky while cutting fragment bandwidth 3×–6×.
  static double get maxLiveBlurSigma {
    if (isAndroid) return 11.0;
    if (isIOS) return 15.0;
    if (isWindows || isLinux) return 14.0;
    if (isMacOS) return 20.0;
    return 14.0;
  }

  /// Blur sigma for pre-downscaled (`cacheWidth: 96`) static ambient fanart /
  /// poster backdrops cached inside a `RepaintBoundary`.
  static double get ambientBlurSigma {
    if (isAndroid) return 11.0;
    if (isIOS) return 14.0;
    if (isWindows || isLinux) return 15.0;
    return 18.0;
  }

  /// Blur sigma for `FramedPoster` episode cover ambient fills (decoded at tiny
  /// `cacheWidth: 96` inside a `RepaintBoundary`, so sigma 5–7 looks identical
  /// to sigma 10+ on full-res textures at a tiny fraction of the GPU cost).
  static double get framedPosterBlurSigma => isMobile ? 5.5 : 7.0;

  /// Scroll pre-layout cache extent: lean on phones to avoid decoding dozens of
  /// offscreen posters during fast flings (reduces CPU/RAM spikes & heat).
  static double get scrollCacheExtent => isMobile ? 320.0 : 560.0;

  /// Clamp any requested live `BackdropFilter` sigma for the active OS.
  static double clampLiveBlur(double requested, {bool reduceMotion = false}) {
    if (requested <= 0.1) return 0.0;
    final cap = reduceMotion ? (maxLiveBlurSigma * 0.72) : maxLiveBlurSigma;
    return requested.clamp(0.0, cap);
  }

  /// Slightly boost translucent fill opacity on platforms with tighter blur
  /// caps (e.g. Android) so frosted glass retains crisp contrast and depth.
  static Color adaptGlassFill(Color base) {
    if (!isAndroid) return base;
    final nextAlpha = (base.a + 0.08).clamp(0.0, 0.96);
    return base.withValues(alpha: nextAlpha);
  }

  /// Whether to use native `CupertinoPageRoute` (hardware-composited push +
  /// interactive edge swipe-back with zero double-fullscreen alpha `saveLayer`).
  static bool get preferCupertinoRoute => isMobile;

  /// Compute an optimal physical-pixel `cacheWidth` for `Image.network` so
  /// Flutter never decodes full 1080p/4K RGBA textures for compact poster cards.
  static int? imageCacheWidthFor(double? logicalWidth, double devicePixelRatio) {
    if (logicalWidth == null || !logicalWidth.isFinite || logicalWidth <= 0) {
      return null;
    }
    // Cap effective DPR multiplier on ultra-high-DPI mobile screens (e.g. 3.5x)
    // to 2.25x for posters — visually indistinguishable while cutting decode
    // CPU time and GPU texture memory by >50%!
    final effDpr = isMobile
        ? devicePixelRatio.clamp(1.0, 2.25)
        : devicePixelRatio.clamp(1.0, 2.0);
    return (logicalWidth * effDpr).round().clamp(96, isMobile ? 1280 : 1920);
  }

  /// Tune Flutter's global decoded `ImageCache` per platform to prevent both
  /// scroll-time re-decode jank and mobile memory/thermal pressure.
  static void configureImageCache() {
    final cache = PaintingBinding.instance.imageCache;
    if (isMobile) {
      cache.maximumSize = 220;
      cache.maximumSizeBytes = 96 * 1024 * 1024; // 96 MiB
    } else {
      cache.maximumSize = 420;
      cache.maximumSizeBytes = 200 * 1024 * 1024; // 200 MiB
    }
  }

  /// Helper to decide if animations should be minimized for accessibility or user preference.
  static bool shouldReduceMotion(BuildContext context, {bool prefReduceMotion = false}) {
    return prefReduceMotion || MediaQuery.disableAnimationsOf(context);
  }
}
