import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FlutterView, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Physical & logical display classification categories across phones, foldables, tablets & desktops.
enum VedroFormFactor {
  compactPhone,
  standardPhone,
  foldableInner,
  tablet,
  desktopStandardDpi,
  desktopHiDpi,
  desktopUltraWide,
}

/// Hardware-aware display metrics & PPI/DPR ergonomic profile.
///
/// Computes platform-specific defaults and layout parameters from:
/// - OS family (`android`, `ios`, `macos`, `windows`, `linux`)
/// - Logical viewport (`width`, `height`, `shortestSide`, `aspectRatio`)
/// - Pixel density (`devicePixelRatio` -> physical resolution & estimated PPI)
/// - Pointer modality (`isTouchPrimary` vs `hasMouseHover`)
class DisplayMetricsProfile {
  const DisplayMetricsProfile({
    required this.platform,
    required this.logicalSize,
    required this.devicePixelRatio,
  });

  final String platform; // android | ios | macos | windows | linux | web
  final Size logicalSize;
  final double devicePixelRatio;

  static String _currentPlatformName() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'linux';
  }

  /// Inspect the live primary `FlutterView` before `BuildContext` is available (e.g. first-launch init).
  factory DisplayMetricsProfile.fromPlatformDispatcher({String? platformOverride}) {
    final FlutterView? view = PlatformDispatcher.instance.views.isNotEmpty
        ? PlatformDispatcher.instance.views.first
        : null;
    final dpr = (view?.devicePixelRatio ?? 1.0).clamp(1.0, 5.0);
    final phys = view?.physicalSize ?? const Size(1280, 800);
    final logical = phys.width > 0 && phys.height > 0
        ? Size(phys.width / dpr, phys.height / dpr)
        : const Size(1280, 800);
    return DisplayMetricsProfile(
      platform: platformOverride ?? _currentPlatformName(),
      logicalSize: logical,
      devicePixelRatio: dpr,
    );
  }

  /// Build from live `MediaQuery` so window resizes, foldable unfold, and multi-monitor DPI hops update live.
  factory DisplayMetricsProfile.of(BuildContext context, {String? platformOverride}) {
    final mq = MediaQuery.of(context);
    return DisplayMetricsProfile(
      platform: platformOverride ?? _currentPlatformName(),
      logicalSize: mq.size,
      devicePixelRatio: mq.devicePixelRatio.clamp(1.0, 5.0),
    );
  }

  bool get isAndroid => platform == 'android';
  bool get isIOS => platform == 'ios';
  bool get isMacOS => platform == 'macos';
  bool get isWindows => platform == 'windows';
  bool get isLinux => platform == 'linux';
  bool get isMobileOs => isAndroid || isIOS;
  bool get isDesktopOs => isMacOS || isWindows || isLinux || platform == 'web';

  double get shortestSide => logicalSize.shortestSide;
  double get longestSide => logicalSize.longestSide;
  int get physicalWidth => (logicalSize.width * devicePixelRatio).round();
  int get physicalHeight => (logicalSize.height * devicePixelRatio).round();

  /// Estimated physical PPI based on OS baseline density bucket × `devicePixelRatio`.
  int get estimatedPpi {
    final base = switch (platform) {
      'android' => 160.0,
      'ios' => 163.0,
      'macos' => 110.0,
      _ => 96.0,
    };
    return (base * devicePixelRatio).round();
  }

  /// True when primary interaction is finger touch without persistent mouse hover (`Android` / `iOS` phones & foldables).
  bool get isTouchPrimary => isMobileOs;

  /// True when mouse pointer hover effects (`hover_reveal`, `cardHoverEffect`) are meaningful.
  bool get supportsMouseHover => !isMobileOs;

  /// True when using compact mobile bottom navigation layout (`width < 820`).
  bool get usesMobileChrome => logicalSize.width < 820;

  VedroFormFactor get formFactor {
    if (isMobileOs) {
      if (shortestSide < 380) return VedroFormFactor.compactPhone;
      if (shortestSide < 580) return VedroFormFactor.standardPhone;
      final ratio = longestSide / math.max(1.0, shortestSide);
      if (shortestSide < 860 && ratio < 1.38) {
        return VedroFormFactor.foldableInner;
      }
      return VedroFormFactor.tablet;
    }
    if (logicalSize.width >= 2040) return VedroFormFactor.desktopUltraWide;
    if (devicePixelRatio >= 1.65) return VedroFormFactor.desktopHiDpi;
    return VedroFormFactor.desktopStandardDpi;
  }

  /// Stable signature for first-run hardware profile initialization.
  String get profileSignature =>
      '$platform:${formFactor.name}:${devicePixelRatio >= 2.5 ? "uhd_ppi" : (devicePixelRatio >= 1.65 ? "hidpi" : "sdpi")}';

  /// Crisp 1-physical-pixel hairline in logical coordinates (`0.5px` on 3x AMOLED, `1.0px` on 1x 1080p).
  double get hairlineWidth {
    if (devicePixelRatio >= 2.6) return 0.55;
    if (devicePixelRatio >= 1.75) return 0.70;
    return 1.0;
  }

  /// Human-readable badge shown in Skin Studio & UI Preferences so the user sees exact screen adaptation.
  String get summaryLabel {
    final osName = switch (platform) {
      'android' => 'Android',
      'ios' => 'iOS',
      'macos' => 'macOS',
      'windows' => 'Windows',
      'linux' => 'Linux',
      _ => 'Web',
    };
    final formName = switch (formFactor) {
      VedroFormFactor.compactPhone => '紧凑屏手机',
      VedroFormFactor.standardPhone => devicePixelRatio >= 2.75 ? '高分超清手机' : '标准屏手机',
      VedroFormFactor.foldableInner => '折叠屏展开态',
      VedroFormFactor.tablet => '平板大屏',
      VedroFormFactor.desktopStandardDpi => '桌面标准屏',
      VedroFormFactor.desktopHiDpi => '桌面 Retina 高分屏',
      VedroFormFactor.desktopUltraWide => '4K / 超宽巨幕桌面',
    };
    return '$osName · $formName · $physicalWidth×$physicalHeight (${devicePixelRatio.toStringAsFixed(devicePixelRatio == devicePixelRatio.roundToDouble() ? 1 : 2)}x · $estimatedPpi PPI)';
  }

  /// Default `skinId` across ALL platforms: Cohesive Immersive Cinema (`immersive_cinema` / `obsidian`).
  String get recommendedSkinId => 'immersive_cinema';

  /// Recommended ergonomic overrides calibrated to screen geometry & DPR — never locks
  /// `surface_material` so switching between the 4 Master Themes stays 100% pure!
  Map<String, dynamic> get recommendedSkinOverrides {
    switch (formFactor) {
      case VedroFormFactor.compactPhone:
        return const {
          'hero_style': 'full_bleed',
          'mobile_nav_style': 'compact_icon_only',
          'touch_feedback': 'spring_haptic',
        };
      case VedroFormFactor.standardPhone:
        return const {
          'hero_style': 'full_bleed',
          'mobile_nav_style': 'floating_dock',
          'touch_feedback': 'spring_haptic',
        };
      case VedroFormFactor.foldableInner:
      case VedroFormFactor.tablet:
        return const {
          'nav_layout': 'centered_capsule',
          'mobile_nav_style': 'floating_dock',
          'touch_feedback': 'spring_haptic',
        };
      case VedroFormFactor.desktopStandardDpi:
      case VedroFormFactor.desktopHiDpi:
        return const {
          'nav_layout': 'centered_capsule',
        };
      case VedroFormFactor.desktopUltraWide:
        return const {
          'nav_layout': 'centered_capsule',
          'grid_density': 'spacious',
        };
    }
  }

  /// Recommended list density based on physical screen estate & PPI.
  String get recommendedListDensity => switch (formFactor) {
        VedroFormFactor.compactPhone => 'compact',
        VedroFormFactor.desktopUltraWide => 'spacious',
        _ => 'comfortable',
      };

  /// Recommended `libmpv` demuxer cache size in MB scaled to device RAM class.
  int get recommendedBufferSizeMb => switch (formFactor) {
        VedroFormFactor.compactPhone => 96,
        VedroFormFactor.standardPhone => 128,
        VedroFormFactor.foldableInner || VedroFormFactor.tablet => 192,
        VedroFormFactor.desktopStandardDpi || VedroFormFactor.desktopHiDpi => 256,
        VedroFormFactor.desktopUltraWide => 384,
      };

  /// Recommended subtitle font scale based on viewing distance & pixel density.
  double get recommendedSubtitleScale => switch (formFactor) {
        VedroFormFactor.compactPhone => 0.95,
        VedroFormFactor.standardPhone => 1.0,
        VedroFormFactor.foldableInner || VedroFormFactor.tablet => 1.05,
        VedroFormFactor.desktopStandardDpi => 1.0,
        VedroFormFactor.desktopHiDpi => 1.04,
        VedroFormFactor.desktopUltraWide => 1.12,
      };

  /// Recommended subtitle outline width (slightly thicker on low-PPI 1.0x LCDs for crisp legibility).
  double get recommendedSubtitleOutline =>
      devicePixelRatio < 1.5 ? 2.8 : (devicePixelRatio >= 2.75 ? 2.2 : 2.4);

  /// Resolution- and PPI-aware poster card width so grids never look cramped on small phones or tiny on 4K.
  double posterWidthFor(String density, {double scale = 1.0}) {
    final wide = !usesMobileChrome;
    final clampedScale = scale.clamp(0.75, 1.25);
    if (!wide) {
      final base = shortestSide < 375
          ? 96.0
          : (shortestSide >= 420 ? 112.0 : 104.0);
      final raw = switch (density) {
        'compact' => base * 0.88,
        'spacious' => base * 1.15,
        _ => base,
      };
      return raw * clampedScale;
    }
    final desktopBase = logicalSize.width >= 2040
        ? 182.0
        : (logicalSize.width >= 1500 ? 164.0 : 150.0);
    final raw = switch (density) {
      'compact' => desktopBase * 0.86,
      'spacious' => desktopBase * 1.15,
      _ => desktopBase,
    };
    return raw * clampedScale;
  }

  /// Optimal grid column count accounting for logical width, padding, poster scale, and form factor.
  int optimalGridColumns(
    double availableWidth,
    String density, {
    double scale = 1.0,
    double? gapOverride,
  }) {
    final targetW = posterWidthFor(density, scale: scale);
    final gap = gapOverride ?? (usesMobileChrome ? 9.0 : 16.0);
    final raw = ((availableWidth + gap) / (targetW + gap)).floor();
    final minCols = usesMobileChrome ? 3 : 4;
    final maxCols = logicalSize.width >= 2040 ? 12 : (usesMobileChrome ? 6 : 10);
    return raw.clamp(minCols, maxCols);
  }

  /// Optimal Hero stage height so tall 20:9 phones and 1:1 foldables always reveal media rails below!
  double optimalHeroHeight({required bool framed}) {
    final h = logicalSize.height;
    switch (formFactor) {
      case VedroFormFactor.compactPhone:
        return (h * (framed ? 0.42 : 0.48)).clamp(280.0, 360.0);
      case VedroFormFactor.standardPhone:
        return (h * (framed ? 0.44 : 0.52)).clamp(310.0, 430.0);
      case VedroFormFactor.foldableInner:
        return (h * 0.42).clamp(300.0, 420.0);
      case VedroFormFactor.tablet:
        return (h * (framed ? 0.50 : 0.58)).clamp(360.0, 520.0);
      case VedroFormFactor.desktopStandardDpi:
      case VedroFormFactor.desktopHiDpi:
        return (h * (framed ? 0.58 : 0.70)).clamp(380.0, 720.0);
      case VedroFormFactor.desktopUltraWide:
        return (h * (framed ? 0.56 : 0.68)).clamp(440.0, 820.0);
    }
  }
}

/// Deterministic, resolution-, PPI-, and OS-`TextScaler`-aware card & grid layout metrics.
///
/// Replaces fragile constant `childAspectRatio` guesses across all `GridView` and horizontal rail
/// containers with an exact two-term geometric identity:
/// `cardHeight = (cardWidth / aspectRatio) + captionHeight(cardWidth, dpr, textScaler)`
/// Paired with `StrutStyle(forceStrutHeight: true)` on card labels, captions (`2024` year, episode
/// counts, etc.) NEVER clip, overflow, or overlap adjacent rows at any resolution, PPI, column count,
/// or system font accessibility scale.
class PosterCardLayout {
  const PosterCardLayout({
    required this.columns,
    required this.cardWidth,
    required this.aspectRatio,
    required this.cardHeight,
    required this.crossSpacing,
    required this.mainSpacing,
    required this.titleFontSize,
    required this.metaFontSize,
    required this.captionTopGap,
    required this.captionMidGap,
    required this.lineHeightMultiplier,
  });

  final int columns;
  final double cardWidth;
  final double aspectRatio;
  final double cardHeight;
  final double crossSpacing;
  final double mainSpacing;
  final double titleFontSize;
  final double metaFontSize;
  final double captionTopGap;
  final double captionMidGap;
  final double lineHeightMultiplier;

  static const double kStrutHeight = 1.28;

  /// Compute exact typography & vertical height for a single card of width `cardWidth`.
  static PosterCardLayout forCardWidth({
    required double cardWidth,
    required double aspectRatio,
    required bool showBelowCaption,
    required TextScaler textScaler,
    double devicePixelRatio = 2.0,
    int columns = 1,
    double crossSpacing = 12.0,
    double mainSpacing = 14.0,
  }) {
    final safeW = math.max(64.0, cardWidth);
    final double titleFs = safeW < 98
        ? 11.8
        : (safeW < 128 ? 12.5 : 13.5);
    final double metaFs = safeW < 98
        ? 10.5
        : (safeW < 128 ? 11.0 : 12.0);
    final double topGap = safeW < 98 ? 5.0 : (safeW < 128 ? 6.0 : 8.0);
    const double midGap = 2.0;

    final double artH = safeW / aspectRatio;
    if (!showBelowCaption) {
      return PosterCardLayout(
        columns: columns,
        cardWidth: safeW,
        aspectRatio: aspectRatio,
        cardHeight: artH.ceilToDouble(),
        crossSpacing: crossSpacing,
        mainSpacing: mainSpacing,
        titleFontSize: titleFs,
        metaFontSize: metaFs,
        captionTopGap: 0,
        captionMidGap: 0,
        lineHeightMultiplier: kStrutHeight,
      );
    }

    final double titleLineH = (textScaler.scale(titleFs) * kStrutHeight).ceilToDouble();
    final double metaLineH = (textScaler.scale(metaFs) * kStrutHeight).ceilToDouble();
    final double safetyPx = devicePixelRatio < 1.5 ? 4.0 : 3.0;
    final double totalH =
        (artH + topGap + titleLineH + midGap + metaLineH + safetyPx).ceilToDouble();

    return PosterCardLayout(
      columns: columns,
      cardWidth: safeW,
      aspectRatio: aspectRatio,
      cardHeight: totalH,
      crossSpacing: crossSpacing,
      mainSpacing: mainSpacing,
      titleFontSize: titleFs,
      metaFontSize: metaFs,
      captionTopGap: topGap,
      captionMidGap: midGap,
      lineHeightMultiplier: kStrutHeight,
    );
  }

  /// Compute exact height for a 16:9 `LibraryCard` (`artHeight + single-line title`).
  static double libraryCardHeight({
    required double cardWidth,
    required TextScaler textScaler,
    double devicePixelRatio = 2.0,
  }) {
    final safeW = math.max(100.0, cardWidth);
    final artH = safeW / (16 / 9);
    final fs = safeW < 195 ? 12.5 : 13.5;
    final topGap = safeW < 195 ? 5.0 : 8.0;
    final lineH = (textScaler.scale(fs) * kStrutHeight).ceilToDouble();
    final safetyPx = devicePixelRatio < 1.5 ? 4.0 : 3.0;
    return (artH + topGap + lineH + safetyPx).ceilToDouble();
  }

  /// Compute complete adaptive Grid metrics (`columns`, `cardWidth`, `cardHeight` for `mainAxisExtent`,
  /// `crossSpacing`, `mainSpacing`) from live `DisplayMetricsProfile`, `availableWidth`, and `TextScaler`.
  static PosterCardLayout forGrid({
    required DisplayMetricsProfile profile,
    required double availableWidth,
    required String density,
    required double scale,
    required double aspectRatio,
    required bool showBelowCaption,
    required double crossSpacing,
    required TextScaler textScaler,
  }) {
    final safeAvail = math.max(140.0, availableWidth);
    final isWideAspect = aspectRatio > 1.2;
    final baseCols = profile.optimalGridColumns(
      safeAvail,
      density,
      scale: scale,
      gapOverride: crossSpacing,
    );
    final cols = isWideAspect
        ? (baseCols ~/ 1.65).clamp(2, 6)
        : baseCols;
    final exactCardW = (safeAvail - crossSpacing * (cols - 1)) / cols;
    final mainSpacing = profile.usesMobileChrome
        ? (crossSpacing + 4.0).clamp(10.0, 18.0)
        : (crossSpacing + 6.0).clamp(14.0, 26.0);
    return forCardWidth(
      cardWidth: exactCardW,
      aspectRatio: aspectRatio,
      showBelowCaption: showBelowCaption,
      textScaler: textScaler,
      devicePixelRatio: profile.devicePixelRatio,
      columns: cols,
      crossSpacing: crossSpacing,
      mainSpacing: mainSpacing,
    );
  }
}
