import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/platform_perf.dart';
import 'vedro_motion.dart';
import 'vedro_skin.dart';

/// Vedro multi-personality design system:
/// - Driven dynamically by `VedroSkin` (`ThemeExtension<VedroSkin>`) supporting 9 flagship skins
///   (including Apple TV+ Dark, Apple Music Daylight Light, Kinfolk Warm Paper, Infuse Ocean,
///   Criterion 35mm Film, Cyber Neon, Nordic Aurora, Grand Velvet, True OLED) + DIY Custom Skins.
class VedroTheme {
  static const Color canvas = Color(0xFF09090B);
  static const Color surface = Color(0xFF141416);
  static const Color surface2 = Color(0xFF1C1C1F);
  static const Color surface3 = Color(0xFF28282D);
  static const Color field = Color(0xFF121215);

  static const Color line = Color(0x0FFFFFFF);
  static const Color lineStrong = Color(0x1CFFFFFF);
  static const Color hi = Color(0x0DFFFFFF);

  static const Color fg = Color(0xFFF5F5F7);
  static const Color fg2 = Color(0xFFA1A1AA);
  static const Color fg3 = Color(0xFF71717A);

  static const Color accent = Color(0xFF5E9EFF);
  static const Color accentFill = Color(0xFF0A84FF);
  static const Color accentSoft = Color(0x220A84FF);
  static const Color danger = Color(0xFFFF453A);

  static const Color glass = Color(0xBF161619);
  static const Color glassStrong = Color(0xEB1A1A1E);

  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  /// Critically damped spring shape (zero overshoot, safe for opacity & color).
  static const Curve easeOut = VedroSpringCurve.smooth;

  /// Real damped-spring shapes (overshoot): use only for scale / position / size.
  static const Curve springCurve = VedroSpringCurve.bouncy;
  static const Curve snappySpring = VedroSpringCurve.snappy;

  static Color highContrastOn(Color bg) =>
      bg.computeLuminance() > 0.52 ? const Color(0xFF09090B) : Colors.white;

  static ThemeData dark({
    Color accentColor = accent,
    Color accentFillColor = accentFill,
  }) {
    return fromSkin(
      VedroSkin.obsidian.copyWith(
        accent: accentColor,
        accentSecondary: accentFillColor,
      ),
    );
  }

  static const List<String> _cjkFallback = [
    'PingFang SC',
    'Hiragino Sans GB',
    'Microsoft YaHei UI',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
    'sans-serif',
  ];

  static ThemeData fromSkin(VedroSkin skin) {
    final isLight = skin.isLight;
    final base = isLight ? ThemeData.light(useMaterial3: true) : ThemeData.dark(useMaterial3: true);
    final btnRadius = skin.pillRadius >= 100 ? 12.0 : skin.pillRadius.clamp(4.0, 18.0);
    final inputRadius = skin.cardRadius.clamp(6.0, 14.0);

    final scheme = isLight
        ? ColorScheme.light(
            primary: skin.accent,
            onPrimary: highContrastOn(skin.accent),
            secondary: skin.accent,
            onSecondary: highContrastOn(skin.accent),
            surface: skin.surface,
            onSurface: skin.fg,
            error: const Color(0xFFDC2626),
          )
        : ColorScheme.dark(
            primary: skin.accentSecondary,
            onPrimary: highContrastOn(skin.accentSecondary),
            secondary: skin.accent,
            onSecondary: highContrastOn(skin.accent),
            surface: skin.surface,
            onSurface: skin.fg,
            error: danger,
          );

    return base.copyWith(
      // Android phones adopt iOS interaction idioms (Cupertino text selection,
      // chevron back buttons, centered titles, edge-swipe back) so both mobile
      // platforms share one Apple-grade feel. Android TV keeps D-Pad idioms.
      platform: (PlatformPerfProfile.isAndroid && !PlatformPerfProfile.isTv)
          ? TargetPlatform.iOS
          : null,
      brightness: skin.brightness,
      extensions: <ThemeExtension<dynamic>>[skin],
      scaffoldBackgroundColor: skin.canvas,
      canvasColor: skin.canvas,
      splashFactory: NoSplash.splashFactory,
      highlightColor: skin.fg.withValues(alpha: 0.05),
      hoverColor: skin.fg.withValues(alpha: 0.04),
      focusColor: skin.accent.withValues(alpha: 0.22),
      colorScheme: scheme,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: VedroDesktopPageTransitionsBuilder(),
          TargetPlatform.linux: VedroDesktopPageTransitionsBuilder(),
        },
      ),
      textTheme: base.textTheme.apply(
        bodyColor: skin.fg,
        displayColor: skin.fg,
        fontFamilyFallback: _cjkFallback,
      ),
      dividerColor: skin.border,
      dividerTheme: DividerThemeData(
        color: skin.border,
        thickness: 0.6,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: skin.fg,
        iconTheme: IconThemeData(color: skin.fg),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
          statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
          systemStatusBarContrastEnforced: false,
          systemNavigationBarContrastEnforced: false,
        ),
        titleTextStyle: skin.applyHeadlineMood(
          TextStyle(
            color: skin.fg,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.25,
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: skin.surface2,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: skin.fg, fontSize: 13.5, fontFamilyFallback: _cjkFallback),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(skin.cardRadius.clamp(8.0, 16.0)),
          side: BorderSide(color: skin.borderStrong, width: 0.8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: skin.field,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        labelStyle: TextStyle(color: skin.fg3, fontSize: 13.5, fontFamilyFallback: _cjkFallback),
        hintStyle: TextStyle(color: skin.fg3, fontSize: 13.5, fontFamilyFallback: _cjkFallback),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: skin.border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: skin.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: skin.accent, width: 1.3),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: skin.accent,
          foregroundColor: highContrastOn(skin.accent),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            fontFamilyFallback: _cjkFallback,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(btnRadius)),
        ).copyWith(
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: isLight ? const Color(0xFF09090B) : Colors.white, width: 2.2);
            }
            return BorderSide.none;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: skin.fg,
          side: BorderSide(color: skin.borderStrong, width: 0.9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(btnRadius)),
        ).copyWith(
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: skin.accent, width: 2.2);
            }
            return BorderSide(color: skin.borderStrong, width: 0.9);
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return skin.accent.withValues(alpha: 0.16);
            }
            return null;
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: skin.fg2).copyWith(
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: skin.accent, width: 1.8);
            }
            return BorderSide.none;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return skin.accent.withValues(alpha: 0.14);
            }
            return null;
          }),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3.2,
        activeTrackColor: skin.accent,
        inactiveTrackColor: skin.fg.withValues(alpha: 0.18),
        thumbColor: isLight ? skin.accent : Colors.white,
        overlayColor: skin.accent.withValues(alpha: 0.22),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? skin.accent : skin.surface3,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused) ? skin.accent : Colors.transparent,
        ),
        trackOutlineWidth: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused) ? 2.0 : 0.0,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isLight ? const Color(0xFF18181B) : skin.surface2,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: skin.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(color: skin.fg, fontSize: 17, fontWeight: FontWeight.w600),
        contentTextStyle: TextStyle(color: skin.fg2, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(skin.cardRadius.clamp(10.0, 22.0)),
          side: BorderSide(color: skin.borderStrong, width: 0.85),
        ),
      ),
    );
  }
}

/// macOS-grade desktop page transition shared by Windows / Linux / macOS routes:
/// the incoming page settles in on a critically damped spring (fade + subtle
/// depth scale + 10px glide) while the outgoing page stays static, so there is
/// never a second full-screen alpha `saveLayer`.
class VedroDesktopPageTransitionsBuilder extends PageTransitionsBuilder {
  const VedroDesktopPageTransitionsBuilder();

  @override
  Duration get transitionDuration => VedroMotion.routeForward;

  @override
  Duration get reverseTransitionDuration => VedroMotion.routeReverse;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      vedroDesktopTransition(animation, child);
}

/// Spring-shaped fade-through-depth transition (desktop routes & dialogs).
Widget vedroDesktopTransition(Animation<double> animation, Widget child) {
  final fade = CurvedAnimation(
    parent: animation,
    curve: const Interval(0.0, 0.62, curve: Curves.easeOut),
    reverseCurve: Curves.easeInCubic,
  );
  final motion = CurvedAnimation(
    parent: animation,
    curve: VedroSpringCurve.snappy,
    reverseCurve: Curves.easeInCubic,
  );
  return FadeTransition(
    opacity: fade,
    child: AnimatedBuilder(
      animation: motion,
      child: child,
      builder: (context, child) {
        final t = motion.value;
        // Fade + 10px rise only — never scale a whole page (hairlines would shimmer).
        return Transform.translate(
          offset: Offset(0.0, ((1 - t) * 10.0).roundToDouble()),
          child: child,
        );
      },
    ),
  );
}

/// Fluid platform-optimal cinema page route:
/// - Mobile (iOS / Android): native `CupertinoPageRoute` with 120Hz hardware-composited
///   slide + interactive edge swipe-back and zero double-fullscreen alpha `saveLayer`.
/// - Desktop (macOS / Windows / Linux): spring-settled fade + depth glide.
Route<T> vedroRoute<T>(Widget page) {
  if (PlatformPerfProfile.preferCupertinoRoute) {
    return CupertinoPageRoute<T>(builder: (_) => page);
  }
  return PageRouteBuilder<T>(
    transitionDuration: VedroMotion.routeForward,
    reverseTransitionDuration: VedroMotion.routeReverse,
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) => vedroDesktopTransition(animation, child),
  );
}

/// Global smooth scroll behavior across desktop & mobile:
/// - Enables smooth touch, trackpad, and mouse drag scrolling on horizontal rails
/// - Suppresses ugly grey desktop horizontal scrollbars inside category rails & filter strips
class VedroScrollBehavior extends MaterialScrollBehavior {
  const VedroScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      };

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    if (details.direction == AxisDirection.left || details.direction == AxisDirection.right) {
      return child;
    }
    return super.buildScrollbar(context, child, details);
  }

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    // Rubber-band bounce everywhere: never the Android glow / stretch indicator.
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
      decelerationRate: ScrollDecelerationRate.normal,
    );
  }
}
