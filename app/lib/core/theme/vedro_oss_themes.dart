part of 'vedro_skin.dart';

/// Curated Open-Source Community Master Themes with authentic official Dark & Light palettes.
///
/// Grounded in flagship MIT-licensed open-source color systems:
/// - **Catppuccin** (`catppuccin/catppuccin`, Mocha ↔ Latte)
/// - **Rosé Pine** (`rose-pine/rose-pine-theme`, Main ↔ Dawn)
/// - **Nord** (`nordtheme/nord`, Polar Night ↔ Snow Storm)
/// - **AMOLED Pure OLED** (inspired by Fladder / Infuse true-black `#000000` mode)
class VedroOssThemes {
  VedroOssThemes._();

  /// 5. Catppuccin 柔彩 — Official Catppuccin Mocha (Dark) / Latte (Light)
  static const catppuccinMocha = VedroSkin(
    id: 'catppuccin',
    name: 'Catppuccin 柔彩',
    subtitle: 'Mocha / Latte · 低眩光粉彩',
    badge: 'CATPPUCCIN',
    themeFamily: 'catppuccin',
    isLight: false,
    canvas: Color(0xFF1E1E2E), // Mocha Base
    canvasGlow: Color(0xFF312A48), // Soft Mauve aura
    surface: Color(0xFF181825), // Mocha Mantle
    surface2: Color(0xFF313244), // Mocha Surface0
    surface3: Color(0xFF45475A), // Mocha Surface1
    field: Color(0xFF11111B), // Mocha Crust
    glass: Color(0xE0181825),
    glassStrong: Color(0xF51E1E2E),
    border: Color(0x28CDD6F4),
    borderStrong: Color(0x48CBA6F7),
    fg: Color(0xFFCDD6F4), // Mocha Text
    fg2: Color(0xFFBAC2DE), // Mocha Subtext1
    fg3: Color(0xFF9399B2), // Mocha Overlay2
    accent: Color(0xFFCBA6F7), // Mocha Mauve
    accentSecondary: Color(0xFF89B4FA), // Mocha Blue
    ctaStyle: 'accent',
    frameStyle: 'hairline',
    cardRadius: 18.0,
    pillRadius: 999.0,
    ambientGlow: true,
    editorialSerif: false,
    navLayout: 'centered_capsule',
    heroStyle: 'framed_stage',
    detailLayout: 'apple_immersive',
    backdropMode: 'ambient_orb',
    backdropBlur: 28.0,
    surfaceOpacity: 0.94,
    surfaceMaterial: 'tinted_acrylic',
    cardStyle: 'classic_below',
    cardHoverEffect: 'lift',
    castStyle: 'circle_medallion',
    mobileNavStyle: 'floating_dock',
  );

  static const catppuccinLatte = VedroSkin(
    id: 'catppuccin',
    name: 'Catppuccin 柔彩',
    subtitle: 'Mocha / Latte · 低眩光粉彩',
    badge: 'CATPPUCCIN',
    themeFamily: 'catppuccin',
    isLight: true,
    canvas: Color(0xFFEFF1F5), // Latte Base
    canvasGlow: Color(0xFFE3D8F8),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFE6E9EF), // Latte Mantle
    surface3: Color(0xFFDCE0E8), // Latte Crust
    field: Color(0xFFE6E9EF),
    glass: Color(0xE8EFF1F5),
    glassStrong: Color(0xF7FFFFFF),
    border: Color(0x1E4C4F69),
    borderStrong: Color(0x388839EF),
    fg: Color(0xFF4C4F69), // Latte Text
    fg2: Color(0xFF5C5F77), // Latte Subtext1
    fg3: Color(0xFF7C7F93), // Latte Overlay2
    accent: Color(0xFF8839EF), // Latte Mauve
    accentSecondary: Color(0xFF1E66F5), // Latte Blue
    ctaStyle: 'accent',
    frameStyle: 'hairline',
    cardRadius: 18.0,
    pillRadius: 999.0,
    ambientGlow: true,
    editorialSerif: false,
    navLayout: 'centered_capsule',
    heroStyle: 'framed_stage',
    detailLayout: 'apple_immersive',
    backdropMode: 'ambient_orb',
    backdropBlur: 28.0,
    surfaceOpacity: 0.94,
    surfaceMaterial: 'matte_solid',
    cardStyle: 'classic_below',
    cardHoverEffect: 'lift',
    castStyle: 'circle_medallion',
    mobileNavStyle: 'floating_dock',
  );

  /// 6. Rosé Pine 玫瑰松 — Official Rosé Pine Main (Dark) / Dawn (Light)
  static const rosePineDark = VedroSkin(
    id: 'rose_pine',
    name: 'Rosé Pine 玫瑰松',
    subtitle: '松烟暖调 · 电影画报美学',
    badge: 'ROSÉ PINE',
    themeFamily: 'rose_pine',
    isLight: false,
    canvas: Color(0xFF191724), // Base
    canvasGlow: Color(0xFF39273B), // Warm Rose-Iris glow
    surface: Color(0xFF1F1D2E), // Surface
    surface2: Color(0xFF26233A), // Overlay
    surface3: Color(0xFF34304C), // Highlight Med
    field: Color(0xFF1B1927),
    glass: Color(0xE01F1D2E),
    glassStrong: Color(0xF526233A),
    border: Color(0x28EBBCBA),
    borderStrong: Color(0x4CEBBCBA),
    fg: Color(0xFFE0DEF4), // Text
    fg2: Color(0xFFA8A3C2), // Subtle (boosted readability)
    fg3: Color(0xFF7B7696), // Muted
    accent: Color(0xFFEBBCBA), // Rose
    accentSecondary: Color(0xFFC4A7E7), // Iris
    ctaStyle: 'accent',
    frameStyle: 'hairline',
    cardRadius: 14.0,
    pillRadius: 999.0,
    ambientGlow: true,
    editorialSerif: true,
    navLayout: 'top_floating',
    heroStyle: 'full_bleed',
    detailLayout: 'apple_immersive',
    backdropMode: 'blurred_fanart',
    backdropBlur: 36.0,
    surfaceOpacity: 0.90,
    surfaceMaterial: 'tinted_acrylic',
    cardStyle: 'classic_below',
    cardHoverEffect: 'lift',
    castStyle: 'circle_medallion',
    mobileNavStyle: 'floating_dock',
  );

  static const rosePineDawn = VedroSkin(
    id: 'rose_pine',
    name: 'Rosé Pine 玫瑰松',
    subtitle: '松烟暖调 · 电影画报美学',
    badge: 'ROSÉ PINE',
    themeFamily: 'rose_pine',
    isLight: true,
    canvas: Color(0xFFFAF4ED), // Dawn Base
    canvasGlow: Color(0xFFF2E2D8),
    surface: Color(0xFFFFFDF9), // Dawn Surface
    surface2: Color(0xFFF2E9E1), // Dawn Overlay
    surface3: Color(0xFFE4D8CE), // Dawn Highlight
    field: Color(0xFFF4EDE8),
    glass: Color(0xE8FAF4ED),
    glassStrong: Color(0xF7FFFDF9),
    border: Color(0x20575279),
    borderStrong: Color(0x3CD7827E),
    fg: Color(0xFF575279), // Dawn Text
    fg2: Color(0xFF797593), // Dawn Subtle
    fg3: Color(0xFF9893A5), // Dawn Muted
    accent: Color(0xFFD7827E), // Dawn Rose
    accentSecondary: Color(0xFF907AA9), // Dawn Iris
    ctaStyle: 'accent',
    frameStyle: 'hairline',
    cardRadius: 14.0,
    pillRadius: 999.0,
    ambientGlow: true,
    editorialSerif: true,
    navLayout: 'top_floating',
    heroStyle: 'full_bleed',
    detailLayout: 'apple_immersive',
    backdropMode: 'ambient_orb',
    backdropBlur: 30.0,
    surfaceOpacity: 0.95,
    surfaceMaterial: 'matte_solid',
    cardStyle: 'classic_below',
    cardHoverEffect: 'lift',
    castStyle: 'circle_medallion',
    mobileNavStyle: 'floating_dock',
  );

  /// 7. Nord 极地霜蓝 — Official Nord Polar Night (Dark) / Snow Storm (Light)
  static const nordDark = VedroSkin(
    id: 'nord_frost',
    name: 'Nord 极地霜蓝',
    subtitle: '北欧极简冷调 · 冰川层级',
    badge: 'NORD',
    themeFamily: 'nord_frost',
    isLight: false,
    canvas: Color(0xFF242933), // Deepened Polar Night for cinema contrast
    canvasGlow: Color(0xFF2E4054),
    surface: Color(0xFF2E3440), // Nord0
    surface2: Color(0xFF3B4252), // Nord1
    surface3: Color(0xFF434C5E), // Nord2
    field: Color(0xFF2B303B),
    glass: Color(0xE02E3440),
    glassStrong: Color(0xF53B4252),
    border: Color(0x28D8DEE9),
    borderStrong: Color(0x4A88C0D0),
    fg: Color(0xFFECEFF4), // Nord6
    fg2: Color(0xFFD8DEE9), // Nord4
    fg3: Color(0xFF8F9BB3),
    accent: Color(0xFF88C0D0), // Nord8 Frost Cyan
    accentSecondary: Color(0xFF81A1C1), // Nord9 Frost Blue
    ctaStyle: 'accent',
    frameStyle: 'hairline',
    cardRadius: 14.0,
    pillRadius: 999.0,
    ambientGlow: true,
    editorialSerif: false,
    navLayout: 'top_floating',
    heroStyle: 'framed_stage',
    detailLayout: 'apple_immersive',
    backdropMode: 'ambient_orb',
    backdropBlur: 28.0,
    surfaceOpacity: 0.95,
    surfaceMaterial: 'matte_solid',
    cardStyle: 'classic_below',
    cardHoverEffect: 'lift',
    castStyle: 'circle_medallion',
    mobileNavStyle: 'floating_dock',
  );

  static const nordLight = VedroSkin(
    id: 'nord_frost',
    name: 'Nord 极地霜蓝',
    subtitle: '北欧极简冷调 · 冰川层级',
    badge: 'NORD',
    themeFamily: 'nord_frost',
    isLight: true,
    canvas: Color(0xFFECEFF4), // Nord6 Snow Storm
    canvasGlow: Color(0xFFD8E4F0),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFE5E9F0), // Nord5
    surface3: Color(0xFFD8DEE9), // Nord4
    field: Color(0xFFE5E9F0),
    glass: Color(0xE8ECEFF4),
    glassStrong: Color(0xF7FFFFFF),
    border: Color(0x1E2E3440),
    borderStrong: Color(0x385E81AC),
    fg: Color(0xFF2E3440), // Nord0
    fg2: Color(0xFF434C5E), // Nord2
    fg3: Color(0xFF6B768C),
    accent: Color(0xFF5E81AC), // Nord10 Deep Frost
    accentSecondary: Color(0xFF81A1C1), // Nord9
    ctaStyle: 'accent',
    frameStyle: 'hairline',
    cardRadius: 14.0,
    pillRadius: 999.0,
    ambientGlow: true,
    editorialSerif: false,
    navLayout: 'top_floating',
    heroStyle: 'framed_stage',
    detailLayout: 'apple_immersive',
    backdropMode: 'ambient_orb',
    backdropBlur: 28.0,
    surfaceOpacity: 0.95,
    surfaceMaterial: 'matte_solid',
    cardStyle: 'classic_below',
    cardHoverEffect: 'lift',
    castStyle: 'circle_medallion',
    mobileNavStyle: 'floating_dock',
  );

  /// 8. AMOLED 极夜纯黑 — True #000000 OLED (Dark) / Minimal Crisp White (Light)
  static const amoledOledDark = VedroSkin(
    id: 'pure_oled',
    name: 'AMOLED 纯黑',
    subtitle: '零辉度 #000 · 1px 极客线框',
    badge: 'OLED',
    themeFamily: 'pure_oled',
    isLight: false,
    canvas: Color(0xFF000000),
    canvasGlow: Color(0xFF000000),
    surface: Color(0xFF0A0A0D),
    surface2: Color(0xFF141419),
    surface3: Color(0xFF1E1E26),
    field: Color(0xFF08080B),
    glass: Color(0xE008080A),
    glassStrong: Color(0xF50C0C10),
    border: Color(0x26FFFFFF),
    borderStrong: Color(0x46FFFFFF),
    fg: Color(0xFFFFFFFF),
    fg2: Color(0xFFA8A8B3),
    fg3: Color(0xFF6E6E78),
    accent: Color(0xFF818CF8),
    accentSecondary: Color(0xFF6366F1),
    ctaStyle: 'contrast',
    frameStyle: 'hairline',
    cardRadius: 12.0,
    pillRadius: 999.0,
    ambientGlow: false,
    editorialSerif: false,
    navLayout: 'centered_capsule',
    heroStyle: 'full_bleed',
    detailLayout: 'apple_immersive',
    backdropMode: 'solid_clean',
    backdropBlur: 20.0,
    surfaceOpacity: 0.96,
    surfaceMaterial: 'oled_borderless',
    cardStyle: 'classic_below',
    cardHoverEffect: 'lift',
    castStyle: 'circle_medallion',
    mobileNavStyle: 'floating_dock',
  );

  static const amoledOledLight = VedroSkin(
    id: 'pure_oled',
    name: 'AMOLED 纯黑',
    subtitle: '零辉度 #000 · 1px 极客线框',
    badge: 'OLED',
    themeFamily: 'pure_oled',
    isLight: true,
    canvas: Color(0xFFFFFFFF),
    canvasGlow: Color(0xFFF4F4F6),
    surface: Color(0xFFF6F6F8),
    surface2: Color(0xFFECECF0),
    surface3: Color(0xFFE0E0E7),
    field: Color(0xFFF2F2F5),
    glass: Color(0xECFFFFFF),
    glassStrong: Color(0xFAFFFFFF),
    border: Color(0x1C09090B),
    borderStrong: Color(0x3609090B),
    fg: Color(0xFF09090B),
    fg2: Color(0xFF52525B),
    fg3: Color(0xFF71717A),
    accent: Color(0xFF4F46E5),
    accentSecondary: Color(0xFF6366F1),
    ctaStyle: 'contrast',
    frameStyle: 'hairline',
    cardRadius: 12.0,
    pillRadius: 999.0,
    ambientGlow: false,
    editorialSerif: false,
    navLayout: 'centered_capsule',
    heroStyle: 'full_bleed',
    detailLayout: 'apple_immersive',
    backdropMode: 'solid_clean',
    backdropBlur: 20.0,
    surfaceOpacity: 0.96,
    surfaceMaterial: 'matte_solid',
    cardStyle: 'classic_below',
    cardHoverEffect: 'lift',
    castStyle: 'circle_medallion',
    mobileNavStyle: 'floating_dock',
  );

  /// Resolve official Dark or Light variant for any open-source community theme family.
  static VedroSkin? resolvePolarity(String themeFamily, bool wantLight) {
    return switch (themeFamily) {
      'catppuccin' => wantLight ? catppuccinLatte : catppuccinMocha,
      'rose_pine' => wantLight ? rosePineDawn : rosePineDark,
      'nord_frost' => wantLight ? nordLight : nordDark,
      'pure_oled' => wantLight ? amoledOledLight : amoledOledDark,
      _ => null,
    };
  }
}
