import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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
  static const Curve easeOut = Cubic(0.16, 1.0, 0.3, 1.0);
  static const Curve springCurve = Cubic(0.16, 1.0, 0.3, 1.0);

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
      brightness: skin.brightness,
      extensions: <ThemeExtension<dynamic>>[skin],
      scaffoldBackgroundColor: skin.canvas,
      canvasColor: skin.canvas,
      splashFactory: NoSplash.splashFactory,
      highlightColor: skin.fg.withValues(alpha: 0.05),
      hoverColor: skin.fg.withValues(alpha: 0.04),
      colorScheme: scheme,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: _VedroSmoothTransitionsBuilder(),
          TargetPlatform.linux: _VedroSmoothTransitionsBuilder(),
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
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: skin.fg,
          side: BorderSide(color: skin.borderStrong, width: 0.9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(btnRadius)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: skin.fg2),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3.2,
        activeTrackColor: skin.accent,
        inactiveTrackColor: skin.fg.withValues(alpha: 0.18),
        thumbColor: isLight ? skin.accent : Colors.white,
        overlayColor: skin.accent.withValues(alpha: 0.16),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? skin.accent : skin.surface3,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
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

/// Smooth cinema fade + subtle depth-scale page transition for desktop platforms.
class _VedroSmoothTransitionsBuilder extends PageTransitionsBuilder {
  const _VedroSmoothTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
        child: child,
      ),
    );
  }
}

/// Fluid cinema page route with Hero compatibility and Apple quintic ease-out.
Route<T> vedroRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 340),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: VedroTheme.easeOut,
        reverseCurve: Curves.easeInCubic,
      );
      final bgScale = Tween<double>(begin: 1.0, end: 0.985).animate(
        CurvedAnimation(parent: secondaryAnimation, curve: VedroTheme.easeOut),
      );
      return ScaleTransition(
        scale: bgScale,
        child: FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.022),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        ),
      );
    },
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
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}
