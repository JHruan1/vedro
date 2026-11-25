import 'package:flutter/material.dart';

/// Cinema-grade Obsidian Glassmorphic theme inspired by Apple TV+ / Infuse.
class PrismTheme {
  static const Color bg = Color(0xFF07090F);
  static const Color surface = Color(0xFF10141F);
  static const Color surfaceElevated = Color(0xFF171D2D);
  static const Color border = Color(0xFF232C42);
  static const Color accent = Color(0xFF4F8CFF);
  static const Color dolbyGold = Color(0xFFF5B749);
  static const Color atmosCyan = Color(0xFF2DD4BF);
  static const Color hdrPurple = Color(0xFFA78BFA);
  static const Color embygoGreen = Color(0xFF34D399);
  static const Color textPrimary = Color(0xFFF3F6FC);
  static const Color textSecondary = Color(0xFF94A3B8);

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: atmosCyan,
        surface: surface,
        onSurface: textPrimary,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: textPrimary,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: surface,
        selectedIconTheme: IconThemeData(color: accent),
        selectedLabelTextStyle: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        unselectedIconTheme: IconThemeData(color: textSecondary),
        unselectedLabelTextStyle: TextStyle(color: textSecondary),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: Color(0x334F8CFF),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
      ),
    );
  }
}
