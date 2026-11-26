import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// User-authored DIY skin specification persisted in `VedroPreferences` and shareable via skin code.
class CustomSkinSpec {
  const CustomSkinSpec({
    required this.id,
    required this.name,
    this.isLight = false,
    this.canvasHex = '#0B1020',
    this.surfaceHex = '',
    this.accentHex = '#38BDF8',
    this.accentSecondaryHex = '#818CF8',
    this.ctaStyle = 'accent', // contrast | accent | gradient | outline
    this.frameStyle = 'hairline', // borderless | hairline | neon
    this.cardRadius = 14.0,
    this.pillRadius = 999.0,
    this.ambientGlow = true,
    this.editorialSerif = false,
  });

  final String id;
  final String name;
  final bool isLight;
  final String canvasHex;
  /// Optional explicit surface hex; when empty, auto-derived harmoniously from `canvasHex`.
  final String surfaceHex;
  final String accentHex;
  final String accentSecondaryHex;
  final String ctaStyle;
  final String frameStyle;
  final double cardRadius;
  final double pillRadius;
  final bool ambientGlow;
  final bool editorialSerif;

  CustomSkinSpec copyWith({
    String? id,
    String? name,
    bool? isLight,
    String? canvasHex,
    String? surfaceHex,
    String? accentHex,
    String? accentSecondaryHex,
    String? ctaStyle,
    String? frameStyle,
    double? cardRadius,
    double? pillRadius,
    bool? ambientGlow,
    bool? editorialSerif,
  }) =>
      CustomSkinSpec(
        id: id ?? this.id,
        name: name ?? this.name,
        isLight: isLight ?? this.isLight,
        canvasHex: canvasHex ?? this.canvasHex,
        surfaceHex: surfaceHex ?? this.surfaceHex,
        accentHex: accentHex ?? this.accentHex,
        accentSecondaryHex: accentSecondaryHex ?? this.accentSecondaryHex,
        ctaStyle: ctaStyle ?? this.ctaStyle,
        frameStyle: frameStyle ?? this.frameStyle,
        cardRadius: cardRadius ?? this.cardRadius,
        pillRadius: pillRadius ?? this.pillRadius,
        ambientGlow: ambientGlow ?? this.ambientGlow,
        editorialSerif: editorialSerif ?? this.editorialSerif,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'is_light': isLight,
        'canvas_hex': canvasHex,
        'surface_hex': surfaceHex,
        'accent_hex': accentHex,
        'accent_secondary_hex': accentSecondaryHex,
        'cta_style': ctaStyle,
        'frame_style': frameStyle,
        'card_radius': cardRadius,
        'pill_radius': pillRadius,
        'ambient_glow': ambientGlow,
        'editorial_serif': editorialSerif,
      };

  factory CustomSkinSpec.fromJson(Map<String, dynamic> j) => CustomSkinSpec(
        id: (j['id'] ?? 'custom_${DateTime.now().millisecondsSinceEpoch}').toString(),
        name: (j['name'] ?? '自定义皮肤').toString(),
        isLight: j['is_light'] == true,
        canvasHex: (j['canvas_hex'] ?? '#0B1020').toString(),
        surfaceHex: (j['surface_hex'] ?? '').toString(),
        accentHex: (j['accent_hex'] ?? '#38BDF8').toString(),
        accentSecondaryHex: (j['accent_secondary_hex'] ?? '#818CF8').toString(),
        ctaStyle: (j['cta_style'] ?? 'accent').toString(),
        frameStyle: (j['frame_style'] ?? 'hairline').toString(),
        cardRadius: ((j['card_radius'] as num?)?.toDouble() ?? 14.0).clamp(2.0, 28.0),
        pillRadius: ((j['pill_radius'] as num?)?.toDouble() ?? 999.0).clamp(4.0, 999.0),
        ambientGlow: j['ambient_glow'] != false,
        editorialSerif: j['editorial_serif'] == true,
      );

  String encodeShareCode() {
    final jsonStr = jsonEncode(toJson());
    final b64 = base64Url.encode(utf8.encode(jsonStr));
    return 'VEDRO-SKIN:$b64';
  }

  static CustomSkinSpec? tryDecodeShareCode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      String payload = trimmed;
      if (payload.startsWith('VEDRO-SKIN:')) {
        payload = payload.substring('VEDRO-SKIN:'.length).trim();
        final normalized = base64Url.normalize(payload);
        final decoded = utf8.decode(base64Url.decode(normalized));
        final map = jsonDecode(decoded);
        if (map is Map) {
          return CustomSkinSpec.fromJson(Map<String, dynamic>.from(map));
        }
      } else if (payload.startsWith('{')) {
        final map = jsonDecode(payload);
        if (map is Map) {
          return CustomSkinSpec.fromJson(Map<String, dynamic>.from(map));
        }
      }
    } catch (_) {}
    return null;
  }
}

Color parseHexColor(String hex, Color fallback) {
  final clean = hex.trim().replaceFirst('#', '');
  if (clean.length == 6) {
    final val = int.tryParse('FF$clean', radix: 16);
    if (val != null) return Color(val);
  } else if (clean.length == 8) {
    final val = int.tryParse(clean, radix: 16);
    if (val != null) return Color(val);
  }
  return fallback;
}

String colorToHex6(Color c) {
  final r = (c.r * 255.0).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  final g = (c.g * 255.0).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  final b = (c.b * 255.0).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${r.toUpperCase()}${g.toUpperCase()}${b.toUpperCase()}';
}

Color highContrastOn(Color bg) {
  return bg.computeLuminance() > 0.44 ? const Color(0xFF0F1117) : Colors.white;
}

/// Complete multi-personality skin token system for Vedro.
/// Switching skins transforms canvas atmosphere, light/dark polarity, card geometry,
/// frame borders, CTA personality, pill shapes, glass tint, and editorial typography.
@immutable
class VedroSkin extends ThemeExtension<VedroSkin> {
  const VedroSkin({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.badge,
    required this.isLight,
    required this.canvas,
    required this.canvasGlow,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.field,
    required this.glass,
    required this.glassStrong,
    required this.border,
    required this.borderStrong,
    required this.fg,
    required this.fg2,
    required this.fg3,
    required this.accent,
    required this.accentSecondary,
    this.ctaStyle = 'contrast', // contrast | accent | gradient | outline
    this.frameStyle = 'borderless', // borderless | hairline | neon
    this.cardRadius = 13.0,
    this.pillRadius = 999.0,
    this.ambientGlow = false,
    this.editorialSerif = false,
    this.isCustom = false,
  });

  final String id;
  final String name;
  final String subtitle;
  final String badge;
  final bool isLight;

  final Color canvas;
  final Color canvasGlow;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color field;
  final Color glass;
  final Color glassStrong;
  final Color border;
  final Color borderStrong;

  final Color fg;
  final Color fg2;
  final Color fg3;

  final Color accent;
  final Color accentSecondary;

  final String ctaStyle;
  final String frameStyle;
  final double cardRadius;
  final double pillRadius;
  final bool ambientGlow;
  final bool editorialSerif;
  final bool isCustom;

  static const List<String> serifFontFallback = <String>[
    'Georgia',
    'New York',
    'Songti SC',
    'Source Han Serif SC',
    'Noto Serif CJK SC',
    'STSong',
    'Times New Roman',
    'serif',
  ];

  Brightness get brightness => isLight ? Brightness.light : Brightness.dark;

  Color get primaryCtaBg {
    switch (ctaStyle) {
      case 'accent':
        return accent;
      case 'gradient':
        return accent;
      case 'outline':
        return accent.withValues(alpha: isLight ? 0.14 : 0.20);
      case 'contrast':
      default:
        return isLight ? const Color(0xFF111318) : Colors.white;
    }
  }

  Gradient? get primaryCtaGradient {
    if (ctaStyle != 'gradient') return null;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [accent, accentSecondary],
    );
  }

  Color get primaryCtaFg {
    switch (ctaStyle) {
      case 'accent':
        return highContrastOn(accent);
      case 'gradient':
        final avgLum = (accent.computeLuminance() + accentSecondary.computeLuminance()) / 2.0;
        return avgLum > 0.48 ? const Color(0xFF0F1117) : Colors.white;
      case 'outline':
        return isLight ? accent : Colors.white;
      case 'contrast':
      default:
        return isLight ? Colors.white : const Color(0xFF09090B);
    }
  }

  Border? get primaryCtaBorder {
    if (ctaStyle == 'outline') {
      return Border.all(color: accent.withValues(alpha: 0.72), width: 1.2);
    }
    if (frameStyle == 'neon' && ctaStyle != 'contrast') {
      return Border.all(color: Colors.white.withValues(alpha: 0.28), width: 0.8);
    }
    return null;
  }

  List<BoxShadow> get primaryCtaShadow {
    if (ctaStyle == 'gradient' || frameStyle == 'neon' || ctaStyle == 'accent') {
      return [
        BoxShadow(
          color: accent.withValues(alpha: isLight ? 0.28 : 0.36),
          blurRadius: 22,
          offset: const Offset(0, 7),
        ),
      ];
    }
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: isLight ? 0.14 : 0.36),
        blurRadius: 20,
        offset: const Offset(0, 7),
      ),
    ];
  }

  /// Active segmented / filter / track pill fill & foreground matching the skin's personality.
  Color get activePillBg =>
      (ctaStyle == 'contrast') ? (isLight ? const Color(0xFF111318) : Colors.white) : accent;

  Color get activePillFg => highContrastOn(activePillBg);

  Color get subtleChipBg =>
      isLight ? fg.withValues(alpha: 0.065) : Colors.white.withValues(alpha: 0.09);

  Color get subtleChipHoverBg =>
      isLight ? fg.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.16);

  double radiusForPill(double height) =>
      math.min(pillRadius, height / 2.0);

  Border? cardBorder({bool hovered = false, bool selected = false}) {
    if (selected) {
      final selColor = frameStyle == 'neon' || ctaStyle != 'contrast'
          ? accent.withValues(alpha: 0.82)
          : borderStrong;
      return Border.all(color: selColor, width: 1.25);
    }
    switch (frameStyle) {
      case 'neon':
        return Border.all(
          color: hovered ? accent.withValues(alpha: 0.88) : accent.withValues(alpha: isLight ? 0.28 : 0.32),
          width: hovered ? 1.4 : 1.0,
        );
      case 'hairline':
        return Border.all(
          color: hovered ? borderStrong : border,
          width: hovered ? 1.2 : 0.85,
        );
      case 'borderless':
      default:
        if (hovered) {
          return Border.all(color: borderStrong, width: 1.15);
        }
        return isLight
            ? Border.all(color: Colors.black.withValues(alpha: 0.05), width: 0.6)
            : Border.all(color: Colors.white.withValues(alpha: 0.06), width: 0.5);
    }
  }

  List<BoxShadow> posterShadow({bool hovered = false}) {
    if (frameStyle == 'neon') {
      return [
        BoxShadow(
          color: hovered
              ? accent.withValues(alpha: 0.32)
              : Colors.black.withValues(alpha: isLight ? 0.14 : 0.48),
          blurRadius: hovered ? 26 : 14,
          offset: Offset(0, hovered ? 10 : 6),
        ),
      ];
    }
    if (isLight) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: hovered ? 0.16 : 0.085),
          blurRadius: hovered ? 26 : 16,
          offset: Offset(0, hovered ? 10 : 6),
        ),
      ];
    }
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: hovered ? 0.58 : 0.34),
        blurRadius: hovered ? 24 : 13,
        offset: Offset(0, hovered ? 10 : 5),
      ),
    ];
  }

  TextStyle applyHeadlineMood(TextStyle base) {
    if (!editorialSerif) return base;
    return base.copyWith(
      fontFamily: 'Georgia',
      fontFamilyFallback: serifFontFallback,
      letterSpacing: (base.letterSpacing ?? 0) + 0.25,
    );
  }

  // ===========================================================================
  // 9 Bold Flagship Built-in Skins ("进了不同 App 一样的感觉")
  // ===========================================================================

  /// 1. Apple TV+ Obsidian — Pure #09090B cinema room, monochrome white capsules, borderless soft cards.
  static const VedroSkin obsidian = VedroSkin(
    id: 'obsidian',
    name: '曜石影院',
    subtitle: 'Apple TV+ 极简暗房 · 纯白胶囊无框质感',
    badge: 'TV+ · DARK',
    isLight: false,
    canvas: Color(0xFF09090B),
    canvasGlow: Color(0xFF18181F),
    surface: Color(0xFF141417),
    surface2: Color(0xFF1C1C21),
    surface3: Color(0xFF282830),
    field: Color(0xFF131317),
    glass: Color(0xC2151519),
    glassStrong: Color(0xEE18181D),
    border: Color(0x12FFFFFF),
    borderStrong: Color(0x2EFFFFFF),
    fg: Color(0xFFF5F5F7),
    fg2: Color(0xFFA1A1AA),
    fg3: Color(0xFF71717A),
    accent: Color(0xFF5E9EFF),
    accentSecondary: Color(0xFF0A84FF),
    ctaStyle: 'contrast',
    frameStyle: 'borderless',
    cardRadius: 13.0,
    pillRadius: 999.0,
    ambientGlow: false,
    editorialSerif: false,
  );

  /// 2. Daylight Porcelain — Crisp Apple Music / App Store sunlit white mode, floating white cards & jet ink.
  static const VedroSkin daylight = VedroSkin(
    id: 'daylight',
    name: '纯净昼白',
    subtitle: 'Apple Music 漫射日光浅色 · 悬浮纯白卡片与浓墨排版',
    badge: 'LIGHT · STUDIO',
    isLight: true,
    canvas: Color(0xFFF2F4F8),
    canvasGlow: Color(0xFFDCE7FF),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFE7EAF0),
    surface3: Color(0xFFDADFE8),
    field: Color(0xFFEAECEF),
    glass: Color(0xCCF7F8FB),
    glassStrong: Color(0xF2FFFFFF),
    border: Color(0x140F172A),
    borderStrong: Color(0x2E0F172A),
    fg: Color(0xFF111318),
    fg2: Color(0xFF4B5565),
    fg3: Color(0xFF7B8494),
    accent: Color(0xFF0066FF),
    accentSecondary: Color(0xFF38BDF8),
    ctaStyle: 'contrast',
    frameStyle: 'borderless',
    cardRadius: 16.0,
    pillRadius: 999.0,
    ambientGlow: true,
    editorialSerif: false,
  );

  /// 3. Kinfolk Editorial Paper — Warm ivory magazine light skin with book-plate borders & serif headlines.
  static const VedroSkin editorialPaper = VedroSkin(
    id: 'editorial_paper',
    name: '画报暖纸',
    subtitle: 'Kinfolk 艺术画报浅色 · 暖米羊皮纸与经典衬线字',
    badge: 'LIGHT · SERIF',
    isLight: true,
    canvas: Color(0xFFF7F2E7),
    canvasGlow: Color(0xFFF0DEC2),
    surface: Color(0xFFFFFCF5),
    surface2: Color(0xFFEDE5D5),
    surface3: Color(0xFFE2D7C3),
    field: Color(0xFFEFE8D8),
    glass: Color(0xD4FAF5EB),
    glassStrong: Color(0xF5FFFDF8),
    border: Color(0x223E2E1E),
    borderStrong: Color(0x453E2E1E),
    fg: Color(0xFF211A13),
    fg2: Color(0xFF5C5043),
    fg3: Color(0xFF8A7B6A),
    accent: Color(0xFFC25E28),
    accentSecondary: Color(0xFFD97706),
    ctaStyle: 'accent',
    frameStyle: 'hairline',
    cardRadius: 7.0,
    pillRadius: 8.0,
    ambientGlow: true,
    editorialSerif: true,
  );

  /// 4. Infuse Deep Ocean — Arctic midnight sapphire canvas with frosted oceanic glass & luminous ice-blue pills.
  static const VedroSkin oceanGlass = VedroSkin(
    id: 'ocean_glass',
    name: '深海蓝调',
    subtitle: 'Infuse 北极深海 · 冰川蓝琉璃漫反射与大圆角',
    badge: 'OCEAN · GLASS',
    isLight: false,
    canvas: Color(0xFF06101E),
    canvasGlow: Color(0xFF0EA5E9),
    surface: Color(0xFF0D1D33),
    surface2: Color(0xFF132845),
    surface3: Color(0xFF1B365C),
    field: Color(0xFF0B192C),
    glass: Color(0xC40B1B30),
    glassStrong: Color(0xEE0E213B),
    border: Color(0x2256B8FF),
    borderStrong: Color(0x5238BDF8),
    fg: Color(0xFFF0F7FF),
    fg2: Color(0xFF9CC2E6),
    fg3: Color(0xFF648BB2),
    accent: Color(0xFF38BDF8),
    accentSecondary: Color(0xFF3B82F6),
    ctaStyle: 'accent',
    frameStyle: 'hairline',
    cardRadius: 18.0,
    pillRadius: 999.0,
    ambientGlow: true,
    editorialSerif: false,
  );

  /// 5. Criterion 35mm Film — Warm walnut screening room, Kodak 35mm amber gold accents & sharp gallery frames.
  static const VedroSkin criterionFilm = VedroSkin(
    id: 'criterion_film',
    name: '胶片暗房',
    subtitle: 'Criterion 35mm 放映室 · 暖棕胡桃木与柯达琥珀金',
    badge: 'FILM · 35MM',
    isLight: false,
    canvas: Color(0xFF120E0B),
    canvasGlow: Color(0xFFD97706),
    surface: Color(0xFF1B1510),
    surface2: Color(0xFF261E17),
    surface3: Color(0xFF34291F),
    field: Color(0xFF18120E),
    glass: Color(0xC81B1510),
    glassStrong: Color(0xF0211913),
    border: Color(0x26E5A93C),
    borderStrong: Color(0x66E5A93C),
    fg: Color(0xFFF7EFE2),
    fg2: Color(0xFFC4B5A2),
    fg3: Color(0xFF8C7D6B),
    accent: Color(0xFFE5A93C),
    accentSecondary: Color(0xFFF59E0B),
    ctaStyle: 'accent',
    frameStyle: 'hairline',
    cardRadius: 5.0,
    pillRadius: 7.0,
    ambientGlow: true,
    editorialSerif: true,
  );

  /// 6. Cyber Neon — Deep ultraviolet abyss, angular tech geometry, dual-tone magenta/cyan glow & neon frames.
  static const VedroSkin cyberNeon = VedroSkin(
    id: 'cyber_neon',
    name: '霓虹赛博',
    subtitle: 'Night City 机能风 · 紫外深空、锐利切角与双色霓虹光晕',
    badge: 'CYBER · NEON',
    isLight: false,
    canvas: Color(0xFF080514),
    canvasGlow: Color(0xFFD946EF),
    surface: Color(0xFF120B26),
    surface2: Color(0xFF1B1138),
    surface3: Color(0xFF27184F),
    field: Color(0xFF0F0920),
    glass: Color(0xC8120B28),
    glassStrong: Color(0xF0170E33),
    border: Color(0x3822D3EE),
    borderStrong: Color(0x99F43F5E),
    fg: Color(0xFFF8FAFC),
    fg2: Color(0xFFC4B5FD),
    fg3: Color(0xFF7E74A8),
    accent: Color(0xFFF43F5E),
    accentSecondary: Color(0xFF06B6D4),
    ctaStyle: 'gradient',
    frameStyle: 'neon',
    cardRadius: 6.0,
    pillRadius: 6.0,
    ambientGlow: true,
    editorialSerif: false,
  );

  /// 7. Nordic Aurora — Calm deep pine-emerald sanctuary with mint-jade aurora gradient highlights.
  static const VedroSkin nordicAurora = VedroSkin(
    id: 'nordic_aurora',
    name: '极光森境',
    subtitle: 'Nordic 北境松林 · 墨绿雾面玻璃与翡翠极光渐变',
    badge: 'AURORA · MIST',
    isLight: false,
    canvas: Color(0xFF06130F),
    canvasGlow: Color(0xFF10B981),
    surface: Color(0xFF0E211B),
    surface2: Color(0xFF153027),
    surface3: Color(0xFF1E4236),
    field: Color(0xFF0B1B16),
    glass: Color(0xC60C1E18),
    glassStrong: Color(0xEE10261F),
    border: Color(0x2434D399),
    borderStrong: Color(0x5E34D399),
    fg: Color(0xFFECFDF5),
    fg2: Color(0xFF99C7B5),
    fg3: Color(0xFF5F8D7B),
    accent: Color(0xFF34D399),
    accentSecondary: Color(0xFF14B8A6),
    ctaStyle: 'gradient',
    frameStyle: 'hairline',
    cardRadius: 16.0,
    pillRadius: 999.0,
    ambientGlow: true,
    editorialSerif: false,
  );

  /// 8. Grand Velvet — Royal burgundy opera house with champagne-rose serif typography & plush curves.
  static const VedroSkin grandVelvet = VedroSkin(
    id: 'grand_velvet',
    name: '丝绒歌剧',
    subtitle: 'Grand Opera 皇家剧院 · 勃艮第红丝绒与香槟金衬线',
    badge: 'VELVET · LUXE',
    isLight: false,
    canvas: Color(0xFF14060A),
    canvasGlow: Color(0xFFE11D48),
    surface: Color(0xFF210B12),
    surface2: Color(0xFF2E101A),
    surface3: Color(0xFF3F1724),
    field: Color(0xFF1B090F),
    glass: Color(0xC8210B12),
    glassStrong: Color(0xF0280D16),
    border: Color(0x28FB7185),
    borderStrong: Color(0x66FB7185),
    fg: Color(0xFFFDF2F5),
    fg2: Color(0xFFD8AEB8),
    fg3: Color(0xFF966B76),
    accent: Color(0xFFFB7185),
    accentSecondary: Color(0xFFE11D48),
    ctaStyle: 'accent',
    frameStyle: 'hairline',
    cardRadius: 20.0,
    pillRadius: 999.0,
    ambientGlow: true,
    editorialSerif: true,
  );

  /// 9. Pure OLED Zero — Absolute #000000 zero-nit AMOLED black with Linear-grade 1px precision borders.
  static const VedroSkin pureOled = VedroSkin(
    id: 'pure_oled',
    name: '极夜纯黑',
    subtitle: 'True OLED 零辉度纯黑 · Linear 级 1px 极客几何细线',
    badge: 'OLED · #000',
    isLight: false,
    canvas: Color(0xFF000000),
    canvasGlow: Color(0xFF27272A),
    surface: Color(0xFF0A0A0D),
    surface2: Color(0xFF141418),
    surface3: Color(0xFF1F1F26),
    field: Color(0xFF09090C),
    glass: Color(0xCC09090C),
    glassStrong: Color(0xF20D0D11),
    border: Color(0x24FFFFFF),
    borderStrong: Color(0x48FFFFFF),
    fg: Color(0xFFFAFAFA),
    fg2: Color(0xFFA1A1AA),
    fg3: Color(0xFF63636B),
    accent: Color(0xFFA78BFA),
    accentSecondary: Color(0xFF6366F1),
    ctaStyle: 'contrast',
    frameStyle: 'hairline',
    cardRadius: 8.0,
    pillRadius: 10.0,
    ambientGlow: false,
    editorialSerif: false,
  );

  static const List<VedroSkin> presets = <VedroSkin>[
    obsidian,
    daylight,
    editorialPaper,
    oceanGlass,
    criterionFilm,
    cyberNeon,
    nordicAurora,
    grandVelvet,
    pureOled,
  ];

  static VedroSkin byId(
    String id, {
    List<CustomSkinSpec> customSkins = const [],
  }) {
    for (final c in customSkins) {
      if (c.id == id) return VedroSkin.fromCustom(c);
    }
    for (final p in presets) {
      if (p.id == id) return p;
    }
    return obsidian;
  }

  /// Synthesizes a complete, contrast-balanced `VedroSkin` from a user-created `CustomSkinSpec`.
  factory VedroSkin.fromCustom(CustomSkinSpec spec) {
    final light = spec.isLight;
    final canvas = parseHexColor(
      spec.canvasHex,
      light ? const Color(0xFFF3F4F8) : const Color(0xFF0B1020),
    );
    final accent = parseHexColor(spec.accentHex, const Color(0xFF38BDF8));
    final accent2 = parseHexColor(spec.accentSecondaryHex, accent);

    final hslCanvas = HSLColor.fromColor(canvas);
    final Color autoSurface = light
        ? HSLColor.fromAHSL(
            1.0,
            hslCanvas.hue,
            (hslCanvas.saturation * 0.5).clamp(0.0, 1.0),
            (hslCanvas.lightness + 0.055).clamp(0.0, 1.0),
          ).toColor()
        : HSLColor.fromAHSL(
            1.0,
            hslCanvas.hue,
            (hslCanvas.saturation * 0.88).clamp(0.0, 1.0),
            (hslCanvas.lightness + 0.048).clamp(0.0, 0.35),
          ).toColor();

    final surface = spec.surfaceHex.trim().isNotEmpty
        ? parseHexColor(spec.surfaceHex, autoSurface)
        : autoSurface;
    final hslSurf = HSLColor.fromColor(surface);
    final surface2 = light
        ? HSLColor.fromAHSL(
            1.0,
            hslSurf.hue,
            (hslSurf.saturation * 0.7).clamp(0.0, 1.0),
            (hslSurf.lightness - 0.065).clamp(0.0, 0.96),
          ).toColor()
        : HSLColor.fromAHSL(
            1.0,
            hslSurf.hue,
            (hslSurf.saturation * 0.9).clamp(0.0, 1.0),
            (hslSurf.lightness + 0.045).clamp(0.0, 0.45),
          ).toColor();
    final surface3 = light
        ? HSLColor.fromAHSL(
            1.0,
            hslSurf.hue,
            (hslSurf.saturation * 0.75).clamp(0.0, 1.0),
            (hslSurf.lightness - 0.115).clamp(0.0, 0.92),
          ).toColor()
        : HSLColor.fromAHSL(
            1.0,
            hslSurf.hue,
            (hslSurf.saturation * 0.9).clamp(0.0, 1.0),
            (hslSurf.lightness + 0.095).clamp(0.0, 0.55),
          ).toColor();

    final fg = light ? const Color(0xFF12141A) : const Color(0xFFF6F7FB);
    final fg2 = light
        ? Color.lerp(const Color(0xFF475569), canvas, 0.12)!
        : Color.lerp(const Color(0xFFA8B1C2), accent, 0.14)!;
    final fg3 = light
        ? Color.lerp(const Color(0xFF788497), canvas, 0.15)!
        : Color.lerp(const Color(0xFF6E778A), accent, 0.12)!;

    final borderBase = spec.frameStyle == 'neon'
        ? accent.withValues(alpha: light ? 0.34 : 0.42)
        : (light ? Colors.black.withValues(alpha: 0.09) : Colors.white.withValues(alpha: 0.12));
    final borderStrong = spec.frameStyle == 'neon'
        ? accent2.withValues(alpha: 0.85)
        : (light ? Colors.black.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.28));

    return VedroSkin(
      id: spec.id,
      name: spec.name.trim().isEmpty ? '我的皮肤' : spec.name.trim(),
      subtitle: '${light ? '浅色基底' : '深色基底'} · 自定义专属风格',
      badge: 'DIY · CUSTOM',
      isLight: light,
      canvas: canvas,
      canvasGlow: accent,
      surface: surface,
      surface2: surface2,
      surface3: surface3,
      field: Color.lerp(canvas, surface2, 0.55)!,
      glass: surface.withValues(alpha: light ? 0.82 : 0.78),
      glassStrong: surface.withValues(alpha: light ? 0.95 : 0.93),
      border: borderBase,
      borderStrong: borderStrong,
      fg: fg,
      fg2: fg2,
      fg3: fg3,
      accent: accent,
      accentSecondary: accent2,
      ctaStyle: spec.ctaStyle,
      frameStyle: spec.frameStyle,
      cardRadius: spec.cardRadius,
      pillRadius: spec.pillRadius,
      ambientGlow: spec.ambientGlow,
      editorialSerif: spec.editorialSerif,
      isCustom: true,
    );
  }

  /// Export any built-in or custom skin into an editable `CustomSkinSpec` template!
  CustomSkinSpec toCustomTemplate({String? newId, String? newName}) => CustomSkinSpec(
        id: newId ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
        name: newName ?? '$name · 定制',
        isLight: isLight,
        canvasHex: colorToHex6(canvas),
        surfaceHex: colorToHex6(surface),
        accentHex: colorToHex6(accent),
        accentSecondaryHex: colorToHex6(accentSecondary),
        ctaStyle: ctaStyle,
        frameStyle: frameStyle,
        cardRadius: cardRadius,
        pillRadius: pillRadius,
        ambientGlow: ambientGlow,
        editorialSerif: editorialSerif,
      );

  static VedroSkin of(BuildContext context) =>
      Theme.of(context).extension<VedroSkin>() ?? obsidian;

  @override
  VedroSkin copyWith({
    String? id,
    String? name,
    String? subtitle,
    String? badge,
    bool? isLight,
    Color? canvas,
    Color? canvasGlow,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? field,
    Color? glass,
    Color? glassStrong,
    Color? border,
    Color? borderStrong,
    Color? fg,
    Color? fg2,
    Color? fg3,
    Color? accent,
    Color? accentSecondary,
    String? ctaStyle,
    String? frameStyle,
    double? cardRadius,
    double? pillRadius,
    bool? ambientGlow,
    bool? editorialSerif,
    bool? isCustom,
  }) =>
      VedroSkin(
        id: id ?? this.id,
        name: name ?? this.name,
        subtitle: subtitle ?? this.subtitle,
        badge: badge ?? this.badge,
        isLight: isLight ?? this.isLight,
        canvas: canvas ?? this.canvas,
        canvasGlow: canvasGlow ?? this.canvasGlow,
        surface: surface ?? this.surface,
        surface2: surface2 ?? this.surface2,
        surface3: surface3 ?? this.surface3,
        field: field ?? this.field,
        glass: glass ?? this.glass,
        glassStrong: glassStrong ?? this.glassStrong,
        border: border ?? this.border,
        borderStrong: borderStrong ?? this.borderStrong,
        fg: fg ?? this.fg,
        fg2: fg2 ?? this.fg2,
        fg3: fg3 ?? this.fg3,
        accent: accent ?? this.accent,
        accentSecondary: accentSecondary ?? this.accentSecondary,
        ctaStyle: ctaStyle ?? this.ctaStyle,
        frameStyle: frameStyle ?? this.frameStyle,
        cardRadius: cardRadius ?? this.cardRadius,
        pillRadius: pillRadius ?? this.pillRadius,
        ambientGlow: ambientGlow ?? this.ambientGlow,
        editorialSerif: editorialSerif ?? this.editorialSerif,
        isCustom: isCustom ?? this.isCustom,
      );

  @override
  VedroSkin lerp(ThemeExtension<VedroSkin>? other, double t) {
    if (other is! VedroSkin) return this;
    return VedroSkin(
      id: t < 0.5 ? id : other.id,
      name: t < 0.5 ? name : other.name,
      subtitle: t < 0.5 ? subtitle : other.subtitle,
      badge: t < 0.5 ? badge : other.badge,
      isLight: t < 0.5 ? isLight : other.isLight,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      canvasGlow: Color.lerp(canvasGlow, other.canvasGlow, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      field: Color.lerp(field, other.field, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      glassStrong: Color.lerp(glassStrong, other.glassStrong, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      fg: Color.lerp(fg, other.fg, t)!,
      fg2: Color.lerp(fg2, other.fg2, t)!,
      fg3: Color.lerp(fg3, other.fg3, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSecondary: Color.lerp(accentSecondary, other.accentSecondary, t)!,
      ctaStyle: t < 0.5 ? ctaStyle : other.ctaStyle,
      frameStyle: t < 0.5 ? frameStyle : other.frameStyle,
      cardRadius: cardRadius + (other.cardRadius - cardRadius) * t,
      pillRadius: pillRadius + (other.pillRadius - pillRadius) * t,
      ambientGlow: t < 0.5 ? ambientGlow : other.ambientGlow,
      editorialSerif: t < 0.5 ? editorialSerif : other.editorialSerif,
      isCustom: t < 0.5 ? isCustom : other.isCustom,
    );
  }
}

/// Optional ambient atmospheric canvas wrapper that renders subtle aurora / darkroom glow
/// behind page content when `skin.ambientGlow` is active.
class VedroSkinCanvas extends StatelessWidget {
  const VedroSkinCanvas({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    if (!skin.ambientGlow) {
      return ColoredBox(color: skin.canvas, child: child);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: skin.canvas,
        gradient: RadialGradient(
          center: const Alignment(-0.55, -0.88),
          radius: 1.35,
          colors: [
            Color.lerp(skin.canvas, skin.canvasGlow, skin.isLight ? 0.34 : 0.16)!,
            skin.canvas,
          ],
          stops: const [0.0, 0.85],
        ),
      ),
      child: child,
    );
  }
}
