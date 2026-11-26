import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Vedro design system — Apple TV+ / SenPlayer / Forward cinema aesthetic.
/// Near-monochrome neutral dark canvas, one calm signal-blue accent,
/// depth from 1px hairlines and layered soft shadows, frosted glass reserved
/// strictly for floating chrome over full-bleed artwork.
class VedroTheme {
  static const Color canvas = Color(0xFF0B0B0D);
  static const Color surface = Color(0xFF141417);
  static const Color surface2 = Color(0xFF1B1C20);
  static const Color surface3 = Color(0xFF25262B);
  static const Color field = Color(0xFF101013);

  static const Color line = Color(0x13FFFFFF); // ~7.5% hairline
  static const Color lineStrong = Color(0x22FFFFFF); // ~13% hairline
  static const Color hi = Color(0x0FFFFFFF); // top specular highlight

  static const Color fg = Color(0xFFF2F2F4);
  static const Color fg2 = Color(0xFFA8AAB1);
  static const Color fg3 = Color(0xFF85878F);

  static const Color accent = Color(0xFF5B9BFF);
  static const Color accentFill = Color(0xFF2F6FE6);
  static const Color accentSoft = Color(0x245B9BFF);
  static const Color danger = Color(0xFFFF6B6F);

  static const Color glass = Color(0xCC141417);
  static const Color glassStrong = Color(0xF018181C);

  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  static const Curve easeOut = Cubic(0.2, 0.7, 0.2, 1.0);
  static const Curve springCurve = Curves.easeOutExpo;

  static ThemeData dark({
    Color accentColor = accent,
    Color accentFillColor = accentFill,
  }) {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      splashFactory: NoSplash.splashFactory,
      highlightColor: const Color(0x0DFFFFFF),
      hoverColor: const Color(0x0AFFFFFF),
      colorScheme: ColorScheme.dark(
        primary: accentFillColor,
        onPrimary: Colors.white,
        secondary: accentColor,
        surface: surface,
        onSurface: fg,
        error: danger,
      ),
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
        bodyColor: fg,
        displayColor: fg,
      ),
      dividerColor: line,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: fg,
        titleTextStyle: TextStyle(
          color: fg,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.25,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: field,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        labelStyle: const TextStyle(color: fg3, fontSize: 13.5),
        hintStyle: const TextStyle(color: fg3, fontSize: 13.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: line, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: line, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accentColor, width: 1.2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accentFillColor,
          foregroundColor: Colors.white,
          elevation: 0,
          textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3.2,
        activeTrackColor: fg,
        inactiveTrackColor: const Color(0x38FFFFFF),
        thumbColor: fg,
        overlayColor: const Color(0x22FFFFFF),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? accentFillColor : surface3,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: lineStrong, width: 0.8),
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

/// Fluid cinema page route with Hero compatibility and smooth spring ease.
Route<T> vedroRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(curved),
          child: child,
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
