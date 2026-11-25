import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Vedro design system — restrained, Apple-like cinema aesthetic.
/// Near-monochrome neutral dark canvas, one calm signal-blue accent,
/// depth from hairlines and soft shadows, frosted glass reserved for floating chrome.
class VedroTheme {
  static const Color canvas = Color(0xFF0B0B0D);
  static const Color surface = Color(0xFF141417);
  static const Color surface2 = Color(0xFF1B1C20);
  static const Color surface3 = Color(0xFF25262B);
  static const Color field = Color(0xFF101013);

  static const Color line = Color(0x14FFFFFF); // 8% white hairline
  static const Color lineStrong = Color(0x24FFFFFF); // 14% white hairline

  static const Color fg = Color(0xFFF2F2F4);
  static const Color fg2 = Color(0xFFA8AAB1);
  static const Color fg3 = Color(0xFF7B7D85);

  static const Color accent = Color(0xFF5B9BFF);
  static const Color accentFill = Color(0xFF2F6FE6);
  static const Color danger = Color(0xFFFF6B6F);

  static const Color glass = Color(0xBA141417);
  static const Color glassStrong = Color(0xE618181C);

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      splashFactory: NoSplash.splashFactory,
      highlightColor: const Color(0x0DFFFFFF),
      hoverColor: const Color(0x0AFFFFFF),
      colorScheme: const ColorScheme.dark(
        primary: accentFill,
        onPrimary: Colors.white,
        secondary: accent,
        surface: surface,
        onSurface: fg,
        error: danger,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
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
          letterSpacing: -0.2,
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
          borderSide: const BorderSide(color: accent, width: 1.2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accentFill,
          foregroundColor: Colors.white,
          elevation: 0,
          textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
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
          (states) => states.contains(WidgetState.selected) ? accentFill : surface3,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: lineStrong, width: 0.8),
        ),
      ),
    );
  }
}

/// Global Cupertino-like smooth bouncing scroll behavior across all platforms.
class VedroScrollBehavior extends ScrollBehavior {
  const VedroScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}
