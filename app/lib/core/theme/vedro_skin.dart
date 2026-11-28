import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../platform/platform_perf.dart';
import 'vedro_liquid_shader.dart';

part 'vedro_oss_themes.dart';

/// Choose high-contrast ink (near-black or pure white) against any background color.
Color highContrastOn(Color bg) =>
    bg.computeLuminance() > 0.52 ? const Color(0xFF09090B) : Colors.white;

/// User-authored or modularly customized skin specification (Jellyfin Skin Manager / Ultrachromic / ElegantFin caliber).
/// Controls NOT ONLY palette & light/dark polarity, but also 8 structural & layout dimensions:
/// - `navLayout`: `'top_floating'` | `'left_rail'` | `'centered_capsule'`
/// - `heroStyle`: `'full_bleed'` | `'framed_stage'` | `'split_showcase'` | `'compact_minimal'`
/// - `detailLayout`: `'apple_immersive'` | `'jellyfin_glass'` | `'centered_editorial'`
/// - `backdropMode`: `'solid_clean'` | `'ambient_orb'` | `'blurred_fanart'`
/// - `cardStyle`: `'classic_below'` | `'overlay_poster'` | `'hover_reveal'`
/// - `cardHoverEffect`: `'lift'` | `'glow_ring'` | `'zoom_art'`
/// - `castStyle`: `'circle_medallion'` | `'portrait_card'` | `'compact_pill'`
/// - `backdropBlur`, `surfaceOpacity`, `preferClearLogo`, `editorialSerif`, `ctaStyle`, `frameStyle`, `cardRadius`, `pillRadius`
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
    this.navLayout = 'top_floating', // top_floating | left_rail | centered_capsule
    this.heroStyle = 'full_bleed', // full_bleed | framed_stage | split_showcase | compact_minimal
    this.detailLayout = 'apple_immersive', // apple_immersive | jellyfin_glass | centered_editorial
    this.backdropMode = 'ambient_orb', // solid_clean | ambient_orb | blurred_fanart
    this.backdropBlur = 38.0,
    this.surfaceOpacity = 0.86,
    this.surfaceMaterial = 'auto', // auto | unified_glass | tinted_acrylic | matte_solid | oled_borderless
    this.posterAspect = 'poster_2_3', // poster_2_3 | landscape_16_9 | cinema_4_5
    this.cardStyle = 'classic_below', // classic_below | overlay_poster | hover_reveal | minimal_clean
    this.cardHoverEffect = 'lift', // lift | glow_ring | zoom_art
    this.badgeStyle = 'glass_pill', // glass_pill | accent_ribbon | minimal_dot | hidden
    this.progressStyle = 'floating_bar', // floating_bar | edge_flush | glow_accent
    this.castStyle = 'circle_medallion', // circle_medallion | portrait_card | compact_pill
    this.osdStyle = 'floating_island', // floating_island | cinema_gradient | minimal_glass
    this.mobileNavStyle = 'floating_dock', // floating_dock | full_tab_bar | compact_icon_only
    this.touchFeedbackStyle = 'spring_haptic', // spring_haptic | subtle_scale | clean_static
    this.showCardRating = true,
    this.preferClearLogo = true,
  });

  final String id;
  final String name;
  final bool isLight;
  final String canvasHex;
  final String surfaceHex;
  final String accentHex;
  final String accentSecondaryHex;
  final String ctaStyle;
  final String frameStyle;
  final double cardRadius;
  final double pillRadius;
  final bool ambientGlow;
  final bool editorialSerif;
  final String navLayout;
  final String heroStyle;
  final String detailLayout;
  final String backdropMode;
  final double backdropBlur;
  final double surfaceOpacity;
  final String surfaceMaterial;
  final String posterAspect;
  final String cardStyle;
  final String cardHoverEffect;
  final String badgeStyle;
  final String progressStyle;
  final String castStyle;
  final String osdStyle;
  final String mobileNavStyle;
  final String touchFeedbackStyle;
  final bool showCardRating;
  final bool preferClearLogo;

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
    String? navLayout,
    String? heroStyle,
    String? detailLayout,
    String? backdropMode,
    double? backdropBlur,
    double? surfaceOpacity,
    String? surfaceMaterial,
    String? posterAspect,
    String? cardStyle,
    String? cardHoverEffect,
    String? badgeStyle,
    String? progressStyle,
    String? castStyle,
    String? osdStyle,
    String? mobileNavStyle,
    String? touchFeedbackStyle,
    bool? showCardRating,
    bool? preferClearLogo,
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
        navLayout: navLayout ?? this.navLayout,
        heroStyle: heroStyle ?? this.heroStyle,
        detailLayout: detailLayout ?? this.detailLayout,
        backdropMode: backdropMode ?? this.backdropMode,
        backdropBlur: backdropBlur ?? this.backdropBlur,
        surfaceOpacity: surfaceOpacity ?? this.surfaceOpacity,
        surfaceMaterial: surfaceMaterial ?? this.surfaceMaterial,
        posterAspect: posterAspect ?? this.posterAspect,
        cardStyle: cardStyle ?? this.cardStyle,
        cardHoverEffect: cardHoverEffect ?? this.cardHoverEffect,
        badgeStyle: badgeStyle ?? this.badgeStyle,
        progressStyle: progressStyle ?? this.progressStyle,
        castStyle: castStyle ?? this.castStyle,
        osdStyle: osdStyle ?? this.osdStyle,
        mobileNavStyle: mobileNavStyle ?? this.mobileNavStyle,
        touchFeedbackStyle: touchFeedbackStyle ?? this.touchFeedbackStyle,
        showCardRating: showCardRating ?? this.showCardRating,
        preferClearLogo: preferClearLogo ?? this.preferClearLogo,
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
        'nav_layout': navLayout,
        'hero_style': heroStyle,
        'detail_layout': detailLayout,
        'backdrop_mode': backdropMode,
        'backdrop_blur': backdropBlur,
        'surface_opacity': surfaceOpacity,
        'surface_material': surfaceMaterial,
        'poster_aspect': posterAspect,
        'card_style': cardStyle,
        'card_hover_effect': cardHoverEffect,
        'badge_style': badgeStyle,
        'progress_style': progressStyle,
        'cast_style': castStyle,
        'osd_style': osdStyle,
        'mobile_nav_style': mobileNavStyle,
        'touch_feedback': touchFeedbackStyle,
        'show_card_rating': showCardRating,
        'prefer_clear_logo': preferClearLogo,
      };

  factory CustomSkinSpec.fromJson(Map<String, dynamic> j) {
    final glow = j['ambient_glow'] != false;
    return CustomSkinSpec(
      id: (j['id'] ?? 'custom_${DateTime.now().millisecondsSinceEpoch}').toString(),
      name: (j['name'] ?? '我的专属皮肤').toString(),
      isLight: j['is_light'] == true,
      canvasHex: (j['canvas_hex'] ?? '#0B1020').toString(),
      surfaceHex: (j['surface_hex'] ?? '').toString(),
      accentHex: (j['accent_hex'] ?? '#38BDF8').toString(),
      accentSecondaryHex: (j['accent_secondary_hex'] ?? '#818CF8').toString(),
      ctaStyle: (j['cta_style'] ?? 'accent').toString(),
      frameStyle: (j['frame_style'] ?? 'hairline').toString(),
      cardRadius: ((j['card_radius'] as num?)?.toDouble() ?? 14.0).clamp(0.0, 28.0),
      pillRadius: ((j['pill_radius'] as num?)?.toDouble() ?? 999.0).clamp(4.0, 999.0),
      ambientGlow: glow,
      editorialSerif: j['editorial_serif'] == true,
      navLayout: (j['nav_layout'] ?? 'top_floating').toString(),
      heroStyle: (j['hero_style'] ?? 'full_bleed').toString(),
      detailLayout: (j['detail_layout'] ?? 'apple_immersive').toString(),
      backdropMode: (j['backdrop_mode'] ?? (glow ? 'blurred_fanart' : 'solid_clean')).toString(),
      backdropBlur: ((j['backdrop_blur'] as num?)?.toDouble() ?? 38.0).clamp(10.0, 64.0),
      surfaceOpacity: ((j['surface_opacity'] as num?)?.toDouble() ?? 0.80).clamp(0.40, 1.0),
      surfaceMaterial: (j['surface_material'] ?? 'auto').toString(),
      posterAspect: (j['poster_aspect'] ?? 'poster_2_3').toString(),
      cardStyle: (j['card_style'] ?? 'classic_below').toString(),
      cardHoverEffect: (j['card_hover_effect'] ?? 'lift').toString(),
      badgeStyle: (j['badge_style'] ?? 'glass_pill').toString(),
      progressStyle: (j['progress_style'] ?? 'floating_bar').toString(),
      castStyle: (j['cast_style'] ?? 'circle_medallion').toString(),
      osdStyle: (j['osd_style'] ?? 'floating_island').toString(),
      mobileNavStyle: (j['mobile_nav_style'] ?? 'floating_dock').toString(),
      touchFeedbackStyle: (j['touch_feedback'] ?? 'spring_haptic').toString(),
      showCardRating: j['show_card_rating'] != false,
      preferClearLogo: j['prefer_clear_logo'] != false,
    );
  }

  /// Portable share code (`VEDRO-SKIN:...`) so users can copy/paste custom skins across devices.
  String encodeShareCode() {
    final payload = jsonEncode(toJson()..remove('id'));
    return 'VEDRO-SKIN:${base64Url.encode(utf8.encode(payload))}';
  }

  static CustomSkinSpec? tryDecodeShareCode(String raw) {
    var clean = raw.trim();
    if (clean.isEmpty) return null;
    if (clean.startsWith('VEDRO-SKIN:')) {
      clean = clean.substring('VEDRO-SKIN:'.length).trim();
    }
    try {
      String jsonText;
      if (clean.startsWith('{')) {
        jsonText = clean;
      } else {
        final pad = (4 - clean.length % 4) % 4;
        jsonText = utf8.decode(base64Url.decode(clean + ('=' * pad)));
      }
      final map = jsonDecode(jsonText);
      if (map is! Map) return null;
      return CustomSkinSpec.fromJson({
        ...Map<String, dynamic>.from(map),
        'id': 'custom_${DateTime.now().millisecondsSinceEpoch}',
      });
    } catch (_) {
      return null;
    }
  }
}

/// Multi-personality structural + visual skin engine (`ThemeExtension<VedroSkin>`).
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
    required this.ctaStyle, // contrast | accent | gradient | outline
    required this.frameStyle, // borderless | hairline | neon
    required this.cardRadius,
    required this.pillRadius,
    required this.ambientGlow,
    required this.editorialSerif,
    this.navLayout = 'top_floating', // top_floating | left_rail | centered_capsule
    this.heroStyle = 'full_bleed', // full_bleed | framed_stage | split_showcase | compact_minimal
    this.detailLayout = 'apple_immersive', // apple_immersive | jellyfin_glass | centered_editorial
    this.backdropMode = 'ambient_orb', // solid_clean | ambient_orb | blurred_fanart
    this.backdropBlur = 38.0,
    this.surfaceOpacity = 0.88,
    this.surfaceMaterial = 'auto', // auto | unified_glass | tinted_acrylic | matte_solid | oled_borderless
    this.posterAspect = 'poster_2_3', // poster_2_3 | landscape_16_9 | cinema_4_5
    this.cardStyle = 'classic_below', // classic_below | overlay_poster | hover_reveal | minimal_clean
    this.cardHoverEffect = 'lift', // lift | glow_ring | zoom_art
    this.badgeStyle = 'glass_pill', // glass_pill | accent_ribbon | minimal_dot | hidden
    this.progressStyle = 'floating_bar', // floating_bar | edge_flush | glow_accent
    this.castStyle = 'circle_medallion', // circle_medallion | portrait_card | compact_pill
    this.osdStyle = 'floating_island', // floating_island | cinema_gradient | minimal_glass
    this.mobileNavStyle = 'floating_dock', // floating_dock | full_tab_bar | compact_icon_only
    this.touchFeedbackStyle = 'spring_haptic', // spring_haptic | subtle_scale | clean_static
    this.themeFamily = 'immersive_cinema', // immersive_cinema | ios_frosted | ios_liquid_glass | material_design
    this.liquidSpecular = 'standard', // subtle | standard | vivid
    this.showCardRating = true,
    this.preferClearLogo = true,
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

  /// `'contrast'` | `'accent'` | `'gradient'` | `'outline'`
  final String ctaStyle;

  /// `'borderless'` | `'hairline'` | `'neon'`
  final String frameStyle;

  final double cardRadius;
  final double pillRadius;
  final bool ambientGlow;
  final bool editorialSerif;

  /// `'top_floating'` | `'left_rail'` | `'centered_capsule'` | `'minimal_auto_hide'`
  final String navLayout;

  /// `'full_bleed'` | `'framed_stage'` | `'split_showcase'` | `'compact_minimal'`
  final String heroStyle;

  /// `'apple_immersive'` | `'jellyfin_glass'` | `'centered_editorial'`
  final String detailLayout;

  /// `'solid_clean'` | `'ambient_orb'` | `'blurred_fanart'`
  final String backdropMode;

  final double backdropBlur;
  final double surfaceOpacity;

  /// `'auto'` | `'unified_glass'` | `'tinted_acrylic'` | `'matte_solid'` | `'oled_borderless'`
  final String surfaceMaterial;

  /// `'poster_2_3'` | `'landscape_16_9'` | `'cinema_4_5'`
  final String posterAspect;

  /// `'classic_below'` | `'overlay_poster'` | `'hover_reveal'` | `'minimal_clean'`
  final String cardStyle;

  /// `'lift'` | `'glow_ring'` | `'zoom_art'`
  final String cardHoverEffect;

  /// `'glass_pill'` | `'accent_ribbon'` | `'minimal_dot'` | `'hidden'`
  final String badgeStyle;

  /// `'floating_bar'` | `'edge_flush'` | `'glow_accent'`
  final String progressStyle;

  /// `'circle_medallion'` | `'portrait_card'` | `'compact_pill'`
  final String castStyle;

  /// `'floating_island'` | `'cinema_gradient'` | `'minimal_glass'`
  final String osdStyle;

  /// `'floating_dock'` | `'full_tab_bar'` | `'compact_icon_only'`
  final String mobileNavStyle;

  /// `'spring_haptic'` | `'subtle_scale'` | `'clean_static'`
  final String touchFeedbackStyle;

  /// Cohesive Master Theme Family:
  /// `'immersive_cinema'` | `'ios_frosted'` | `'ios_liquid_glass'` | `'material_design'`
  final String themeFamily;

  /// Specular refractive rim intensity on Liquid Glass (`'subtle'` | `'standard'` | `'vivid'`).
  final String liquidSpecular;

  final bool showCardRating;
  final bool preferClearLogo;
  final bool isCustom;

  Brightness get brightness => isLight ? Brightness.light : Brightness.dark;

  bool get usesBlurredFanart => backdropMode == 'blurred_fanart';

  /// Resolved surface physics across all 4 Master Themes:
  /// `'liquid_glass'` | `'unified_glass'` | `'tinted_acrylic'` | `'matte_solid'` | `'oled_borderless'`
  String get effectiveSurfaceMaterial {
    if (surfaceMaterial != 'auto' && surfaceMaterial.isNotEmpty) {
      return surfaceMaterial;
    }
    if (themeFamily == 'ios_liquid_glass') return 'liquid_glass';
    if (themeFamily == 'ios_frosted') return 'unified_glass';
    if (themeFamily == 'material_design') return 'matte_solid';
    if (id == 'pure_oled') return 'oled_borderless';
    if (usesBlurredFanart || detailLayout == 'jellyfin_glass') {
      return 'unified_glass';
    }
    if (backdropMode == 'ambient_orb' && !isLight) {
      return 'tinted_acrylic';
    }
    return 'matte_solid';
  }

  bool get isLiquidGlass => effectiveSurfaceMaterial == 'liquid_glass';

  bool get usesGlassPanels =>
      effectiveSurfaceMaterial == 'unified_glass' || effectiveSurfaceMaterial == 'liquid_glass';

  /// Only Frosted Glass & Liquid Glass expose translucency & blur radius sub-settings.
  bool get supportsGlassOptics =>
      themeFamily == 'ios_frosted' || themeFamily == 'ios_liquid_glass' || usesGlassPanels;

  double get mediaAspectRatio {
    switch (posterAspect) {
      case 'landscape_16_9':
        return 16 / 9;
      case 'cinema_4_5':
        return 4 / 5;
      case 'poster_2_3':
      default:
        return 2 / 3;
    }
  }

  /// Harmonized container fill across panels, sections, sidebars, and cards (zero solid-brick clash!).
  Color get unifiedPanelColor {
    switch (effectiveSurfaceMaterial) {
      case 'liquid_glass':
        final base = Color.lerp(
          isLight ? Colors.white : surface,
          accent,
          isLight ? 0.04 : 0.09,
        )!;
        final alpha = isLight
            ? surfaceOpacity.clamp(0.80, 0.94)
            : (surfaceOpacity * 0.96).clamp(0.74, 0.90);
        return base.withValues(alpha: alpha);
      case 'unified_glass':
        final base = Color.lerp(surface, accent, isLight ? 0.03 : 0.07)!;
        final alpha = isLight
            ? surfaceOpacity.clamp(0.82, 0.95)
            : (surfaceOpacity * 0.94).clamp(0.76, 0.92);
        return base.withValues(alpha: alpha);
      case 'tinted_acrylic':
        final base = Color.lerp(surface, canvasGlow, isLight ? 0.08 : 0.12)!;
        return base.withValues(alpha: surfaceOpacity.clamp(0.62, 0.92));
      case 'oled_borderless':
        return isLight
            ? surface.withValues(alpha: 0.72)
            : Colors.white.withValues(alpha: 0.035);
      case 'matte_solid':
      default:
        return surface;
    }
  }

  /// Harmonized nested tile/chip/episode-row fill inside or alongside panels.
  Color unifiedTileColor({bool selected = false, bool hovered = false}) {
    switch (effectiveSurfaceMaterial) {
      case 'liquid_glass':
        if (isLight) {
          if (selected) return accent.withValues(alpha: 0.18);
          if (hovered) return Colors.white.withValues(alpha: 0.74);
          return Colors.white.withValues(alpha: 0.44);
        }
        if (selected) {
          return Color.lerp(Colors.white, accent, 0.46)!.withValues(alpha: 0.24);
        }
        if (hovered) return Colors.white.withValues(alpha: 0.15);
        return Colors.white.withValues(alpha: 0.085);
      case 'unified_glass':
        if (isLight) {
          if (selected) return accent.withValues(alpha: 0.16);
          if (hovered) return Colors.white.withValues(alpha: 0.78);
          return Colors.white.withValues(alpha: 0.52);
        }
        if (selected) {
          return Color.lerp(Colors.white, accent, 0.42)!.withValues(alpha: 0.20);
        }
        if (hovered) return Colors.white.withValues(alpha: 0.13);
        return Colors.white.withValues(alpha: 0.075);
      case 'tinted_acrylic':
        if (selected) {
          return Color.lerp(surface3, accent, 0.24)!
              .withValues(alpha: (surfaceOpacity + 0.06).clamp(0.68, 0.94));
        }
        if (hovered) {
          return surface3.withValues(alpha: surfaceOpacity.clamp(0.64, 0.90));
        }
        return surface2.withValues(alpha: (surfaceOpacity * 0.88).clamp(0.54, 0.86));
      case 'oled_borderless':
        if (selected) return accent.withValues(alpha: 0.18);
        if (hovered) return (isLight ? Colors.black : Colors.white).withValues(alpha: 0.08);
        return (isLight ? Colors.black : Colors.white).withValues(alpha: 0.04);
      case 'matte_solid':
      default:
        if (selected) return surface3;
        if (hovered) return surface2;
        return surface2;
    }
  }

  Color get panelSurface => unifiedPanelColor;

  Color get panelSurface2 => unifiedTileColor(hovered: true);

  /// Resolve active skin from BuildContext (falls back to `obsidian` safely in isolated tests).
  static VedroSkin of(BuildContext context) =>
      Theme.of(context).extension<VedroSkin>() ?? obsidian;

  /// Effective radius for capsules/buttons given a widget height.
  double radiusForPill(double height) => math.min(pillRadius, height / 2);

  /// Primary Play / Main CTA background color (when not using gradient).
  Color get primaryCtaBg {
    switch (ctaStyle) {
      case 'contrast':
        return isLight ? const Color(0xFF111318) : Colors.white;
      case 'outline':
        return accent.withValues(alpha: isLight ? 0.12 : 0.16);
      case 'accent':
      case 'gradient':
      default:
        return accent;
    }
  }

  /// Primary Play / Main CTA foreground icon & label color.
  Color get primaryCtaFg {
    switch (ctaStyle) {
      case 'contrast':
        return isLight ? Colors.white : const Color(0xFF09090B);
      case 'outline':
        return isLight ? accent : Colors.white;
      case 'gradient':
        final mid = Color.lerp(accent, accentSecondary, 0.5)!;
        return mid.computeLuminance() > 0.52 ? const Color(0xFF09090B) : Colors.white;
      case 'accent':
      default:
        return accent.computeLuminance() > 0.52 ? const Color(0xFF09090B) : Colors.white;
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

  Border? get primaryCtaBorder {
    if (ctaStyle == 'outline') {
      return Border.all(color: accent, width: 1.4);
    }
    if (frameStyle == 'neon') {
      return Border.all(color: Colors.white.withValues(alpha: 0.28), width: 0.9);
    }
    return null;
  }

  List<BoxShadow> get primaryCtaShadow {
    if (ctaStyle == 'outline') return const [];
    if (ctaStyle == 'gradient' || frameStyle == 'neon') {
      return [
        BoxShadow(
          color: accent.withValues(alpha: isLight ? 0.28 : 0.38),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ];
    }
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: isLight ? 0.16 : 0.34),
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
    ];
  }

  /// Selected filter/version/track pill background.
  Color get activePillBg => ctaStyle == 'contrast'
      ? (isLight ? const Color(0xFF111318) : Colors.white)
      : accent;

  Color get activePillFg => ctaStyle == 'contrast'
      ? (isLight ? Colors.white : const Color(0xFF09090B))
      : (accent.computeLuminance() > 0.52 ? const Color(0xFF09090B) : Colors.white);

  /// Subtle translucent chip/action surface.
  Color get subtleChipBg => isLight
      ? Colors.black.withValues(alpha: 0.055)
      : Colors.white.withValues(alpha: 0.09);

  Color get subtleChipHoverBg => isLight
      ? Colors.black.withValues(alpha: 0.095)
      : Colors.white.withValues(alpha: 0.16);

  /// Card border decoration respecting `frameStyle`, `effectiveSurfaceMaterial` & `cardHoverEffect`.
  BoxBorder? cardBorder({bool hovered = false, bool selected = false}) {
    if (selected) {
      return Border.all(
        color: ctaStyle == 'contrast' ? fg : accent,
        width: frameStyle == 'neon' ? 1.6 : 1.35,
      );
    }
    if (hovered && cardHoverEffect == 'glow_ring') {
      return Border.all(color: accent, width: 2.0);
    }
    if (effectiveSurfaceMaterial == 'liquid_glass') {
      return Border.all(
        color: isLight
            ? Colors.white.withValues(alpha: hovered ? 0.92 : 0.78)
            : Colors.white.withValues(alpha: hovered ? 0.34 : 0.22),
        width: 1.0,
      );
    }
    if (effectiveSurfaceMaterial == 'unified_glass') {
      return Border.all(
        color: isLight
            ? Colors.white.withValues(alpha: hovered ? 0.85 : 0.65)
            : Colors.white.withValues(alpha: hovered ? 0.24 : 0.14),
        width: 0.9,
      );
    }
    if (effectiveSurfaceMaterial == 'oled_borderless') {
      return Border.all(
        color: (isLight ? Colors.black : Colors.white).withValues(alpha: hovered ? 0.22 : 0.10),
        width: 0.75,
      );
    }
    switch (frameStyle) {
      case 'neon':
        return Border.all(
          color: hovered ? accent : borderStrong,
          width: hovered ? 1.3 : 0.95,
        );
      case 'hairline':
        return Border.all(
          color: hovered ? borderStrong : border,
          width: 0.85,
        );
      case 'borderless':
      default:
        if (hovered) {
          return Border.all(color: borderStrong, width: 0.85);
        }
        return isLight ? Border.all(color: border, width: 0.65) : null;
    }
  }

  /// Card drop shadow respecting light vs dark vs glow_ring/neon mood.
  List<BoxShadow> posterShadow({bool hovered = false}) {
    if (hovered && cardHoverEffect == 'glow_ring') {
      return [
        BoxShadow(
          color: accent.withValues(alpha: isLight ? 0.32 : 0.48),
          blurRadius: 24,
          spreadRadius: 1,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: isLight ? 0.14 : 0.56),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ];
    }
    if (frameStyle == 'neon' && hovered) {
      return [
        BoxShadow(
          color: accent.withValues(alpha: 0.34),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.55),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ];
    }
    if (isLight) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: hovered ? 0.14 : 0.075),
          blurRadius: hovered ? 26 : 16,
          offset: Offset(0, hovered ? 12 : 6),
        ),
      ];
    }
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: hovered ? 0.58 : 0.38),
        blurRadius: hovered ? 28 : 18,
        offset: Offset(0, hovered ? 12 : 8),
      ),
    ];
  }

  /// Apply editorial serif font fallback to major headings when skin specifies `editorialSerif`.
  TextStyle applyHeadlineMood(TextStyle base) {
    if (!editorialSerif) return base;
    return base.copyWith(
      fontFamilyFallback: const [
        'New York',
        'Georgia',
        'Songti SC',
        'STSong',
        'Noto Serif CJK SC',
        'Times New Roman',
        'serif',
      ],
      letterSpacing: (base.letterSpacing ?? -0.5) + 0.35,
    );
  }

  /// Apply interactive modular overrides (Jellyfin Skin Manager style live layout toggles).
  VedroSkin applyOverrides(Map<String, dynamic> o) {
    if (o.isEmpty) return this;
    return copyWith(
      navLayout: o['nav_layout']?.toString(),
      heroStyle: o['hero_style']?.toString(),
      detailLayout: o['detail_layout']?.toString(),
      backdropMode: o['backdrop_mode']?.toString(),
      backdropBlur: (o['backdrop_blur'] as num?)?.toDouble(),
      surfaceOpacity: (o['surface_opacity'] as num?)?.toDouble(),
      surfaceMaterial: o['surface_material']?.toString(),
      posterAspect: o['poster_aspect']?.toString(),
      cardStyle: o['card_style']?.toString(),
      cardHoverEffect: o['card_hover_effect']?.toString(),
      badgeStyle: o['badge_style']?.toString(),
      progressStyle: o['progress_style']?.toString(),
      castStyle: o['cast_style']?.toString(),
      osdStyle: o['osd_style']?.toString(),
      mobileNavStyle: o['mobile_nav_style']?.toString(),
      touchFeedbackStyle: o['touch_feedback']?.toString(),
      showCardRating: o['show_card_rating'] is bool ? o['show_card_rating'] as bool : null,
      preferClearLogo: o['prefer_clear_logo'] is bool ? o['prefer_clear_logo'] as bool : null,
      editorialSerif: o['editorial_serif'] is bool ? o['editorial_serif'] as bool : null,
      ambientGlow: o['ambient_glow'] is bool ? o['ambient_glow'] as bool : null,
      liquidSpecular: o['liquid_specular']?.toString(),
      ctaStyle: o['cta_style']?.toString(),
      frameStyle: o['frame_style']?.toString(),
      cardRadius: (o['card_radius'] as num?)?.toDouble(),
      pillRadius: (o['pill_radius'] as num?)?.toDouble(),
    );
  }

  /// Convert any built-in or custom `VedroSkin` into an editable `CustomSkinSpec` template.
  CustomSkinSpec toCustomSpec({String? newId, String? newName}) => CustomSkinSpec(
        id: newId ?? (isCustom ? id : 'custom_${DateTime.now().millisecondsSinceEpoch}'),
        name: newName ?? (isCustom ? name : '$name · 定制'),
        isLight: isLight,
        canvasHex: colorToHex(canvas),
        surfaceHex: colorToHex(surface),
        accentHex: colorToHex(accent),
        accentSecondaryHex: colorToHex(accentSecondary),
        ctaStyle: ctaStyle,
        frameStyle: frameStyle,
        cardRadius: cardRadius,
        pillRadius: pillRadius,
        ambientGlow: ambientGlow,
        editorialSerif: editorialSerif,
        navLayout: navLayout,
        heroStyle: heroStyle,
        detailLayout: detailLayout,
        backdropMode: backdropMode,
        backdropBlur: backdropBlur,
        surfaceOpacity: surfaceOpacity,
        surfaceMaterial: surfaceMaterial,
        posterAspect: posterAspect,
        cardStyle: cardStyle,
        cardHoverEffect: cardHoverEffect,
        badgeStyle: badgeStyle,
        progressStyle: progressStyle,
        castStyle: castStyle,
        osdStyle: osdStyle,
        mobileNavStyle: mobileNavStyle,
        touchFeedbackStyle: touchFeedbackStyle,
        showCardRating: showCardRating,
        preferClearLogo: preferClearLogo,
      );

  // ===========================================================================
  // 4 Cohesive Master Themes (iOS-Unified Design Language across ALL Platforms)
  // + Legacy Preset Aliases for 100% Backward Compatibility
  // ===========================================================================

  /// Master Theme 1: 沉浸影院 — Default Apple TV+ / Infuse Theater Stage
  static const immersiveCinema = VedroSkin(
    id: 'immersive_cinema',
    name: '沉浸影院',
    subtitle: '剧照漫射 · 暗房沉浸',
    badge: 'CINEMA',
    themeFamily: 'immersive_cinema',
    isLight: false,
    canvas: Color(0xFF09090D),
    canvasGlow: Color(0xFF1A1B28),
    surface: Color(0xFF14151C),
    surface2: Color(0xFF1D1F28),
    surface3: Color(0xFF282B37),
    field: Color(0xFF121319),
    glass: Color(0xCC14151C),
    glassStrong: Color(0xF0181922),
    border: Color(0x16FFFFFF),
    borderStrong: Color(0x2AFFFFFF),
    fg: Color(0xFFF5F5F7),
    fg2: Color(0xFFA8A8B5),
    fg3: Color(0xFF747482),
    accent: Color(0xFF0A84FF),
    accentSecondary: Color(0xFF5E9EFF),
    ctaStyle: 'contrast',
    frameStyle: 'borderless',
    cardRadius: 15.0,
    pillRadius: 999.0,
    ambientGlow: true,
    editorialSerif: false,
    navLayout: 'centered_capsule',
    heroStyle: 'full_bleed',
    detailLayout: 'apple_immersive',
    backdropMode: 'blurred_fanart',
    backdropBlur: 42.0,
    surfaceOpacity: 0.84,
    surfaceMaterial: 'tinted_acrylic',
    cardStyle: 'classic_below',
    cardHoverEffect: 'lift',
    castStyle: 'circle_medallion',
    mobileNavStyle: 'floating_dock',
  );

  /// Alias `obsidian` -> `immersiveCinema` (keeps `id: 'obsidian'` when explicitly queried).
  static const obsidian = VedroSkin(
    id: 'obsidian',
    name: '沉浸影院',
    subtitle: '剧照漫射 · 暗房沉浸',
    badge: 'CINEMA',
    themeFamily: 'immersive_cinema',
    isLight: false,
    canvas: Color(0xFF09090D),
    canvasGlow: Color(0xFF1A1B28),
    surface: Color(0xFF14151C),
    surface2: Color(0xFF1D1F28),
    surface3: Color(0xFF282B37),
    field: Color(0xFF121319),
    glass: Color(0xCC14151C),
    glassStrong: Color(0xF0181922),
    border: Color(0x16FFFFFF),
    borderStrong: Color(0x2AFFFFFF),
    fg: Color(0xFFF5F5F7),
    fg2: Color(0xFFA8A8B5),
    fg3: Color(0xFF747482),
    accent: Color(0xFF0A84FF),
    accentSecondary: Color(0xFF5E9EFF),
    ctaStyle: 'contrast',
    frameStyle: 'borderless',
    cardRadius: 15.0,
    pillRadius: 999.0,
    ambientGlow: true,
    editorialSerif: false,
    navLayout: 'centered_capsule',
    heroStyle: 'full_bleed',
    detailLayout: 'apple_immersive',
    backdropMode: 'blurred_fanart',
    backdropBlur: 40.0,
    surfaceOpacity: 0.78,
    surfaceMaterial: 'unified_glass',
    cardStyle: 'classic_below',
    cardHoverEffect: 'lift',
    castStyle: 'circle_medallion',
    mobileNavStyle: 'floating_dock',
  );

  /// Master Theme 2: iOS 毛玻璃 — Classic iOS / macOS Frosted Vibrancy
  static const iosFrosted = VedroSkin(
    id: 'ios_frosted',
    name: 'iOS 毛玻璃',
    subtitle: '磨砂漫射 · 柔和半透',
    badge: 'FROSTED',
    themeFamily: 'ios_frosted',
    isLight: false,
    canvas: Color(0xFF0A0F1A),
    canvasGlow: Color(0xFF132C4E),
    surface: Color(0xFF121C2D),
    surface2: Color(0xFF19263C),
    surface3: Color(0xFF233450),
    field: Color(0xFF0E1726),
    glass: Color(0xD9101A2B),
    glassStrong: Color(0xF2142034),
    border: Color(0x28FFFFFF),
    borderStrong: Color(0x46FFFFFF),
    fg: Color(0xFFF5F8FF),
    fg2: Color(0xFFA6B4CA),
    fg3: Color(0xFF6E7E97),
    accent: Color(0xFF32ADE6),
    accentSecondary: Color(0xFF0A84FF),
    ctaStyle: 'contrast',
    frameStyle: 'hairline',
    cardRadius: 18.0,
    pillRadius: 999.0,
    ambientGlow: true,
    editorialSerif: false,
    navLayout: 'centered_capsule',
    heroStyle: 'full_bleed',
    detailLayout: 'apple_immersive',
    backdropMode: 'blurred_fanart',
    backdropBlur: 38.0,
    surfaceOpacity: 0.84,
    surfaceMaterial: 'unified_glass',
    cardStyle: 'classic_below',
    cardHoverEffect: 'lift',
    castStyle: 'circle_medallion',
    mobileNavStyle: 'floating_dock',
  );

  /// Master Theme 3: iOS 液态玻璃 — iOS 26 Optical Specular Liquid Glass
  static const iosLiquidGlass = VedroSkin(
    id: 'ios_liquid_glass',
    name: 'iOS 液态玻璃',
    subtitle: '镜面折射 · 灵动通透',
    badge: 'LIQUID GLASS',
    themeFamily: 'ios_liquid_glass',
    liquidSpecular: 'standard',
    isLight: false,
    canvas: Color(0xFF070B14),
    canvasGlow: Color(0xFF142D52),
    surface: Color(0xFF101828),
    surface2: Color(0xFF182338),
    surface3: Color(0xFF22314C),
    field: Color(0xFF0C1320),
    glass: Color(0xCC111B2E),
    glassStrong: Color(0xEB142035),
    border: Color(0x3CFFFFFF),
    borderStrong: Color(0x6BFFFFFF),
    fg: Color(0xFFF8FAFF),
    fg2: Color(0xFFB4C0D6),
    fg3: Color(0xFF7B8AA4),
    accent: Color(0xFF47B5FF),
    accentSecondary: Color(0xFF5E5CE6),
    ctaStyle: 'contrast',
    frameStyle: 'hairline',
    cardRadius: 22.0,
    pillRadius: 999.0,
    ambientGlow: true,
    editorialSerif: false,
    navLayout: 'centered_capsule',
    heroStyle: 'full_bleed',
    detailLayout: 'apple_immersive',
    backdropMode: 'blurred_fanart',
    backdropBlur: 32.0,
    surfaceOpacity: 0.78,
    surfaceMaterial: 'liquid_glass',
    cardStyle: 'classic_below',
    cardHoverEffect: 'lift',
    castStyle: 'circle_medallion',
    mobileNavStyle: 'floating_dock',
  );

  /// Master Theme 4: Material 设计 — Material Design 3 Expressive Tonal Containers
  static const materialDesign = VedroSkin(
    id: 'material_design',
    name: 'Material 设计',
    subtitle: '色阶容器 · 圆润流体',
    badge: 'MATERIAL 3',
    themeFamily: 'material_design',
    isLight: false,
    canvas: Color(0xFF0F1117),
    canvasGlow: Color(0xFF1D2538),
    surface: Color(0xFF181C26),
    surface2: Color(0xFF212634),
    surface3: Color(0xFF2B3244),
    field: Color(0xFF1D222F),
    glass: Color(0xE0181C26),
    glassStrong: Color(0xF51E2330),
    border: Color(0x1EFFFFFF),
    borderStrong: Color(0x34FFFFFF),
    fg: Color(0xFFEFF1F8),
    fg2: Color(0xFFA7B0C2),
    fg3: Color(0xFF737C90),
    accent: Color(0xFF7AA8FF),
    accentSecondary: Color(0xFF4B7BEC),
    ctaStyle: 'accent',
    frameStyle: 'borderless',
    cardRadius: 20.0,
    pillRadius: 999.0,
    ambientGlow: true,
    editorialSerif: false,
    navLayout: 'top_floating',
    heroStyle: 'framed_stage',
    detailLayout: 'apple_immersive',
    backdropMode: 'ambient_orb',
    backdropBlur: 24.0,
    surfaceOpacity: 0.96,
    surfaceMaterial: 'matte_solid',
    cardStyle: 'classic_below',
    cardHoverEffect: 'lift',
    castStyle: 'circle_medallion',
    mobileNavStyle: 'floating_dock',
  );

  /// Curated 8 Master Themes surfaced in Theme Studio:
  /// 4 Platform Design Systems + 4 Iconic Open-Source Community Palettes.
  static const List<VedroSkin> masterThemes = [
    immersiveCinema,
    iosFrosted,
    iosLiquidGlass,
    materialDesign,
    VedroOssThemes.catppuccinMocha,
    VedroOssThemes.rosePineDark,
    VedroOssThemes.nordDark,
    VedroOssThemes.amoledOledDark,
  ];

  /// 2. 纯净昼白 — Apple Music / tvOS Daylight Studio (Light Mode · Framed Sunlit Hero · White Shadow Cards)
  static const daylight = VedroSkin(
    id: 'daylight',
    name: '纯净昼白',
    subtitle: 'Apple Music 漫射浅色 · 悬浮圆角画框轮播 · 纯白卡片',
    badge: 'LIGHT · FRAMED',
    isLight: true,
    canvas: Color(0xFFF2F4F8),
    canvasGlow: Color(0xFFDCE7FF),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFE7ECF3),
    surface3: Color(0xFFD9E1EC),
    field: Color(0xFFEAEFF6),
    glass: Color(0xD9FFFFFF),
    glassStrong: Color(0xF5FFFFFF),
    border: Color(0x140F172A),
    borderStrong: Color(0x260F172A),
    fg: Color(0xFF111318),
    fg2: Color(0xFF4B5565),
    fg3: Color(0xFF7C8698),
    accent: Color(0xFF0066FF),
    accentSecondary: Color(0xFF3B82F6),
    ctaStyle: 'accent',
    frameStyle: 'borderless',
    cardRadius: 15.0,
    pillRadius: 999.0,
    ambientGlow: true,
    editorialSerif: false,
    navLayout: 'top_floating',
    heroStyle: 'framed_stage',
    detailLayout: 'apple_immersive',
    backdropMode: 'ambient_orb',
    cardStyle: 'classic_below',
    cardHoverEffect: 'lift',
    castStyle: 'circle_medallion',
  );

  /// 3. 画报暖纸 — Kinfolk / Letterboxd Editorial Paper (Light Warm Paper · Split Showcase · Centered Detail · Serif)
  static const editorialPaper = VedroSkin(
    id: 'editorial_paper',
    name: '画报暖纸',
    subtitle: 'Kinfolk 双栏画报橱窗 · 居中对称详情页 · 电影衬线字',
    badge: 'SERIF · EDITORIAL',
    isLight: true,
    canvas: Color(0xFFF7F2E7),
    canvasGlow: Color(0xFFEFDFC6),
    surface: Color(0xFFFFFCF5),
    surface2: Color(0xFFEDE5D5),
    surface3: Color(0xFFE0D5C0),
    field: Color(0xFFEFE8D9),
    glass: Color(0xDEFFFCF5),
    glassStrong: Color(0xF7FFFCF5),
    border: Color(0x1C3E2C1C),
    borderStrong: Color(0x363E2C1C),
    fg: Color(0xFF211A13),
    fg2: Color(0xFF5D5042),
    fg3: Color(0xFF8C7D6B),
    accent: Color(0xFFC25E28),
    accentSecondary: Color(0xFFD97736),
    ctaStyle: 'accent',
    frameStyle: 'hairline',
    cardRadius: 7.0,
    pillRadius: 8.0,
    ambientGlow: true,
    editorialSerif: true,
    navLayout: 'top_floating',
    heroStyle: 'split_showcase',
    detailLayout: 'centered_editorial',
    backdropMode: 'ambient_orb',
    cardStyle: 'classic_below',
    cardHoverEffect: 'zoom_art',
    castStyle: 'compact_pill',
  );

  /// 4. 深海流光 — Ultrachromic Blurred Fanart Glass (Centered Capsule Island · Full-Page Fanart Blur · 2:3 Cast)
  static const oceanGlass = VedroSkin(
    id: 'ocean_glass',
    name: '流光琉璃',
    subtitle: '致敬 Ultrachromic · 居中灵动胶囊岛 · 全页毛玻璃剧照沉浸',
    badge: 'ULTRACHROMIC · BLUR',
    isLight: false,
    canvas: Color(0xFF06101E),
    canvasGlow: Color(0xFF0E3358),
    surface: Color(0xFF0D1B2E),
    surface2: Color(0xFF132640),
    surface3: Color(0xFF1C3557),
    field: Color(0xFF0A1626),
    glass: Color(0xBD0B1829),
    glassStrong: Color(0xEE0E1E33),
    border: Color(0x227DD3FC),
    borderStrong: Color(0x457DD3FC),
    fg: Color(0xFFF0F7FF),
    fg2: Color(0xFF9BB4D0),
    fg3: Color(0xFF6480A0),
    accent: Color(0xFF38BDF8),
    accentSecondary: Color(0xFF2563EB),
    ctaStyle: 'accent',
    frameStyle: 'hairline',
    cardRadius: 18.0,
    pillRadius: 999.0,
    ambientGlow: true,
    editorialSerif: false,
    navLayout: 'centered_capsule',
    heroStyle: 'full_bleed',
    detailLayout: 'jellyfin_glass',
    backdropMode: 'blurred_fanart',
    backdropBlur: 42.0,
    surfaceOpacity: 0.72,
    cardStyle: 'classic_below',
    cardHoverEffect: 'glow_ring',
    castStyle: 'portrait_card',
  );

  /// 5. 胶片暗房 — Criterion 35mm Archive (Left Sidebar · Symmetrical Detail · Pure Hover-Reveal Poster Wall)
  static const criterionFilm = VedroSkin(
    id: 'criterion_film',
    name: '胶片暗房',
    subtitle: '左侧放映室边栏 · 居中对称详情页 · 纯海报悬停显字墙',
    badge: '35MM · ARCHIVE',
    isLight: false,
    canvas: Color(0xFF120E0B),
    canvasGlow: Color(0xFF382413),
    surface: Color(0xFF1C1612),
    surface2: Color(0xFF271F19),
    surface3: Color(0xFF362B22),
    field: Color(0xFF17120E),
    glass: Color(0xCC1B1511),
    glassStrong: Color(0xF2201914),
    border: Color(0x24F3D5A5),
    borderStrong: Color(0x42F3D5A5),
    fg: Color(0xFFF7EFE4),
    fg2: Color(0xFFBBA992),
    fg3: Color(0xFF84735E),
    accent: Color(0xFFE5A93C),
    accentSecondary: Color(0xFFC87D28),
    ctaStyle: 'accent',
    frameStyle: 'hairline',
    cardRadius: 5.0,
    pillRadius: 6.0,
    ambientGlow: true,
    editorialSerif: true,
    navLayout: 'left_rail',
    heroStyle: 'split_showcase',
    detailLayout: 'centered_editorial',
    backdropMode: 'ambient_orb',
    cardStyle: 'hover_reveal',
    cardHoverEffect: 'zoom_art',
    castStyle: 'portrait_card',
  );

  /// 6. 霓虹赛博 — Night City HUD (Centered Capsule HUD · Framed Neon Stage · Overlay Posters · Glow Ring)
  static const cyberNeon = VedroSkin(
    id: 'cyber_neon',
    name: '霓虹赛博',
    subtitle: '居中机能胶囊岛 · 霓虹切角画框 · 海报内嵌字与电光环',
    badge: 'CYBER · HUD',
    isLight: false,
    canvas: Color(0xFF080514),
    canvasGlow: Color(0xFF2B0F4C),
    surface: Color(0xFF110B24),
    surface2: Color(0xFF1A1136),
    surface3: Color(0xFF26194D),
    field: Color(0xFF0D081D),
    glass: Color(0xC8110B26),
    glassStrong: Color(0xF0150E2E),
    border: Color(0x3822D3EE),
    borderStrong: Color(0x78F43F5E),
    fg: Color(0xFFF8F7FF),
    fg2: Color(0xFFB8AED8),
    fg3: Color(0xFF7B6FA3),
    accent: Color(0xFFF43F5E),
    accentSecondary: Color(0xFF06B6D4),
    ctaStyle: 'gradient',
    frameStyle: 'neon',
    cardRadius: 6.0,
    pillRadius: 6.0,
    ambientGlow: true,
    editorialSerif: false,
    navLayout: 'centered_capsule',
    heroStyle: 'framed_stage',
    detailLayout: 'jellyfin_glass',
    backdropMode: 'blurred_fanart',
    backdropBlur: 34.0,
    surfaceOpacity: 0.76,
    cardStyle: 'overlay_poster',
    cardHoverEffect: 'glow_ring',
    castStyle: 'compact_pill',
  );

  /// 7. 极光侧栏 — Scyfin / Plex Pro Sidebar (Left Vertical Sidebar · Split Showcase · 2:3 Portrait Cast)
  static const nordicAurora = VedroSkin(
    id: 'nordic_aurora',
    name: '极光侧栏',
    subtitle: '致敬 Scyfin / Plex · 左侧垂直导航栏 · 双栏橱窗与竖版影人卡',
    badge: 'SCYFIN · SIDEBAR',
    isLight: false,
    canvas: Color(0xFF06130F),
    canvasGlow: Color(0xFF0D3B2E),
    surface: Color(0xFF0D1F19),
    surface2: Color(0xFF142D25),
    surface3: Color(0xFF1E4035),
    field: Color(0xFF0A1914),
    glass: Color(0xC40C1D18),
    glassStrong: Color(0xEE10241E),
    border: Color(0x226EE7B7),
    borderStrong: Color(0x456EE7B7),
    fg: Color(0xFFECFDF5),
    fg2: Color(0xFF99C2B3),
    fg3: Color(0xFF618B7C),
    accent: Color(0xFF34D399),
    accentSecondary: Color(0xFF14B8A6),
    ctaStyle: 'gradient',
    frameStyle: 'hairline',
    cardRadius: 14.0,
    pillRadius: 999.0,
    ambientGlow: true,
    editorialSerif: false,
    navLayout: 'left_rail',
    heroStyle: 'split_showcase',
    detailLayout: 'apple_immersive',
    backdropMode: 'ambient_orb',
    cardStyle: 'classic_below',
    cardHoverEffect: 'glow_ring',
    castStyle: 'portrait_card',
  );

  /// 8. 星幕画框 — ElegantFin / Jellyseerr Stage (Framed Panoramic Hero · Overlay Gradient Posters · Fanart Glass)
  static const grandVelvet = VedroSkin(
    id: 'grand_velvet',
    name: '丝绒画框',
    subtitle: '致敬 ElegantFin · 悬浮圆角画框轮播 · 海报内嵌渐变标题',
    badge: 'ELEGANTFIN · STAGE',
    isLight: false,
    canvas: Color(0xFF13070D),
    canvasGlow: Color(0xFF4A1026),
    surface: Color(0xFF200D17),
    surface2: Color(0xFF2E1422),
    surface3: Color(0xFF401D2F),
    field: Color(0xFF1A0A12),
    glass: Color(0xC41E0C15),
    glassStrong: Color(0xEE26101B),
    border: Color(0x24FDA4AF),
    borderStrong: Color(0x48FDA4AF),
    fg: Color(0xFFFFF1F2),
    fg2: Color(0xFFD4A5B0),
    fg3: Color(0xFF946672),
    accent: Color(0xFFFB7185),
    accentSecondary: Color(0xFFE11D48),
    ctaStyle: 'gradient',
    frameStyle: 'borderless',
    cardRadius: 20.0,
    pillRadius: 999.0,
    ambientGlow: true,
    editorialSerif: true,
    navLayout: 'top_floating',
    heroStyle: 'framed_stage',
    detailLayout: 'jellyfin_glass',
    backdropMode: 'blurred_fanart',
    backdropBlur: 44.0,
    surfaceOpacity: 0.74,
    cardStyle: 'overlay_poster',
    cardHoverEffect: 'lift',
    castStyle: 'circle_medallion',
  );

  /// 9. 极夜海报墙 — True OLED `#000000` Poster-Wall Mode (Left Rail · No Hero Clutter · Instant Dense Rails)
  static const pureOled = VedroSkin(
    id: 'pure_oled',
    name: '极夜纯黑',
    subtitle: '零辉度 #000 纯黑 · 极简无轮播直达海报墙 · 1px 极客线框',
    badge: 'OLED · POSTER WALL',
    isLight: false,
    canvas: Color(0xFF000000),
    canvasGlow: Color(0xFF000000),
    surface: Color(0xFF0A0A0C),
    surface2: Color(0xFF121216),
    surface3: Color(0xFF1C1C22),
    field: Color(0xFF08080A),
    glass: Color(0xD808080A),
    glassStrong: Color(0xF50B0B0E),
    border: Color(0x22FFFFFF),
    borderStrong: Color(0x40FFFFFF),
    fg: Color(0xFFFFFFFF),
    fg2: Color(0xFFA1A1AA),
    fg3: Color(0xFF63636B),
    accent: Color(0xFF818CF8),
    accentSecondary: Color(0xFF6366F1),
    ctaStyle: 'contrast',
    frameStyle: 'hairline',
    cardRadius: 8.0,
    pillRadius: 8.0,
    ambientGlow: false,
    editorialSerif: false,
    navLayout: 'left_rail',
    heroStyle: 'compact_minimal',
    detailLayout: 'apple_immersive',
    backdropMode: 'solid_clean',
    cardStyle: 'classic_below',
    cardHoverEffect: 'lift',
    castStyle: 'compact_pill',
  );

  static const List<VedroSkin> presets = [
    obsidian,
    oceanGlass,
    grandVelvet,
    nordicAurora,
    daylight,
    editorialPaper,
    criterionFilm,
    cyberNeon,
    pureOled,
  ];

  static Color parseHex(String hex, Color fallback) {
    final clean = hex.trim().replaceAll('#', '');
    if (clean.length == 6) {
      final v = int.tryParse('FF$clean', radix: 16);
      if (v != null) return Color(v);
    } else if (clean.length == 8) {
      final v = int.tryParse(clean, radix: 16);
      if (v != null) return Color(v);
    }
    return fallback;
  }

  static String colorToHex(Color c) {
    final r = (c.r * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final g = (c.g * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final b = (c.b * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${r.toUpperCase()}${g.toUpperCase()}${b.toUpperCase()}';
  }

  /// Synthesize a complete, harmonious `VedroSkin` from a user-authored `CustomSkinSpec`.
  factory VedroSkin.fromCustom(CustomSkinSpec spec) {
    final light = spec.isLight;
    final canvas = parseHex(spec.canvasHex, light ? const Color(0xFFF3F5F9) : const Color(0xFF0B1020));
    final accent = parseHex(spec.accentHex, const Color(0xFF38BDF8));
    final accent2 = parseHex(spec.accentSecondaryHex, accent);

    final hslCanvas = HSLColor.fromColor(canvas);
    final autoSurface = light
        ? HSLColor.fromAHSL(
            1.0,
            hslCanvas.hue,
            (hslCanvas.saturation * 0.45).clamp(0.0, 1.0),
            (hslCanvas.lightness + 0.065).clamp(0.0, 1.0),
          ).toColor()
        : HSLColor.fromAHSL(
            1.0,
            hslCanvas.hue,
            (hslCanvas.saturation * 0.88).clamp(0.0, 1.0),
            (hslCanvas.lightness + 0.055).clamp(0.0, 0.35),
          ).toColor();

    final surface = spec.surfaceHex.trim().isNotEmpty
        ? parseHex(spec.surfaceHex, autoSurface)
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
            (hslSurf.saturation * 0.92).clamp(0.0, 1.0),
            (hslSurf.lightness + 0.048).clamp(0.0, 0.45),
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

    final navDesc = spec.navLayout == 'left_rail'
        ? '左侧栏'
        : (spec.navLayout == 'centered_capsule' ? '胶囊岛' : '悬浮顶栏');
    final heroDesc = spec.heroStyle == 'framed_stage'
        ? '画框轮播'
        : (spec.heroStyle == 'split_showcase'
            ? '双栏橱窗'
            : (spec.heroStyle == 'compact_minimal' ? '纯海报墙' : '全屏巨幕'));

    return VedroSkin(
      id: spec.id,
      name: spec.name.trim().isEmpty ? '我的皮肤' : spec.name.trim(),
      subtitle: '${light ? '浅色' : '深色'} · $navDesc · $heroDesc',
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
      navLayout: spec.navLayout,
      heroStyle: spec.heroStyle,
      detailLayout: spec.detailLayout,
      backdropMode: spec.backdropMode,
      backdropBlur: spec.backdropBlur,
      surfaceOpacity: spec.surfaceOpacity,
      surfaceMaterial: spec.surfaceMaterial,
      posterAspect: spec.posterAspect,
      cardStyle: spec.cardStyle,
      cardHoverEffect: spec.cardHoverEffect,
      badgeStyle: spec.badgeStyle,
      progressStyle: spec.progressStyle,
      castStyle: spec.castStyle,
      osdStyle: spec.osdStyle,
      mobileNavStyle: spec.mobileNavStyle,
      touchFeedbackStyle: spec.touchFeedbackStyle,
      showCardRating: spec.showCardRating,
      preferClearLogo: spec.preferClearLogo,
      isCustom: true,
    );
  }

  /// Convert any Master Theme cleanly between Dark Mode and refined Light Mode
  /// (using official Light palettes for Catppuccin Latte, Rosé Pine Dawn, Nord Snow Storm, OLED White).
  VedroSkin withPolarity(bool wantLight) {
    if (isLight == wantLight) return this;
    final ossVariant = VedroOssThemes.resolvePolarity(themeFamily, wantLight);
    if (ossVariant != null) return ossVariant;
    if (!wantLight) {
      return switch (themeFamily) {
        'ios_liquid_glass' => iosLiquidGlass,
        'ios_frosted' => iosFrosted,
        'material_design' => materialDesign,
        _ => immersiveCinema,
      };
    }
    final hslAcc = HSLColor.fromColor(accent);
    final lightAccent = HSLColor.fromAHSL(
      1.0,
      hslAcc.hue,
      hslAcc.saturation.clamp(0.55, 0.92),
      0.46,
    ).toColor();
    final lightAccent2 = HSLColor.fromAHSL(
      1.0,
      (hslAcc.hue + 12.0) % 360.0,
      hslAcc.saturation.clamp(0.50, 0.88),
      0.40,
    ).toColor();
    return copyWith(
      isLight: true,
      canvas: themeFamily == 'material_design' ? const Color(0xFFF6F7FB) : const Color(0xFFF2F4F8),
      canvasGlow: Color.lerp(const Color(0xFFE2ECFF), lightAccent, 0.22)!,
      surface: const Color(0xFFFFFFFF),
      surface2: const Color(0xFFE8EDF5),
      surface3: const Color(0xFFDCE3EE),
      field: const Color(0xFFEBEEF5),
      glass: Colors.white.withValues(alpha: isLiquidGlass ? 0.84 : 0.88),
      glassStrong: Colors.white.withValues(alpha: isLiquidGlass ? 0.93 : 0.96),
      border: const Color(0x160F172A),
      borderStrong: const Color(0x280F172A),
      fg: const Color(0xFF111318),
      fg2: const Color(0xFF4B5565),
      fg3: const Color(0xFF7B8698),
      accent: lightAccent,
      accentSecondary: lightAccent2,
    );
  }

  static String normalizeMasterThemeId(String id) {
    switch (id) {
      case 'immersive_cinema':
      case 'obsidian':
      case 'criterion_film':
      case 'grand_velvet':
        return 'immersive_cinema';
      case 'ios_frosted':
      case 'ocean_glass':
      case 'daylight':
      case 'editorial_paper':
        return 'ios_frosted';
      case 'ios_liquid_glass':
      case 'cyber_neon':
        return 'ios_liquid_glass';
      case 'material_design':
        return 'material_design';
      case 'catppuccin':
        return 'catppuccin';
      case 'rose_pine':
        return 'rose_pine';
      case 'nord_frost':
      case 'nordic_aurora':
        return 'nord_frost';
      case 'pure_oled':
        return 'pure_oled';
      default:
        return 'immersive_cinema';
    }
  }

  static VedroSkin byId(
    String id, {
    List<CustomSkinSpec> customSkins = const [],
  }) {
    for (final m in masterThemes) {
      if (m.id == id) return m;
    }
    for (final p in presets) {
      if (p.id == id) return p;
    }
    for (final c in customSkins) {
      if (c.id == id) return VedroSkin.fromCustom(c);
    }
    return immersiveCinema;
  }

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
    String? navLayout,
    String? heroStyle,
    String? detailLayout,
    String? backdropMode,
    double? backdropBlur,
    double? surfaceOpacity,
    String? surfaceMaterial,
    String? posterAspect,
    String? cardStyle,
    String? cardHoverEffect,
    String? badgeStyle,
    String? progressStyle,
    String? castStyle,
    String? osdStyle,
    String? mobileNavStyle,
    String? touchFeedbackStyle,
    String? themeFamily,
    String? liquidSpecular,
    bool? showCardRating,
    bool? preferClearLogo,
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
        navLayout: navLayout ?? this.navLayout,
        heroStyle: heroStyle ?? this.heroStyle,
        detailLayout: detailLayout ?? this.detailLayout,
        backdropMode: backdropMode ?? this.backdropMode,
        backdropBlur: backdropBlur ?? this.backdropBlur,
        surfaceOpacity: surfaceOpacity ?? this.surfaceOpacity,
        surfaceMaterial: surfaceMaterial ?? this.surfaceMaterial,
        posterAspect: posterAspect ?? this.posterAspect,
        cardStyle: cardStyle ?? this.cardStyle,
        cardHoverEffect: cardHoverEffect ?? this.cardHoverEffect,
        badgeStyle: badgeStyle ?? this.badgeStyle,
        progressStyle: progressStyle ?? this.progressStyle,
        castStyle: castStyle ?? this.castStyle,
        osdStyle: osdStyle ?? this.osdStyle,
        mobileNavStyle: mobileNavStyle ?? this.mobileNavStyle,
        touchFeedbackStyle: touchFeedbackStyle ?? this.touchFeedbackStyle,
        themeFamily: themeFamily ?? this.themeFamily,
        liquidSpecular: liquidSpecular ?? this.liquidSpecular,
        showCardRating: showCardRating ?? this.showCardRating,
        preferClearLogo: preferClearLogo ?? this.preferClearLogo,
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
      cardRadius: lerpDoubleD(cardRadius, other.cardRadius, t),
      pillRadius: lerpDoubleD(pillRadius, other.pillRadius, t),
      ambientGlow: t < 0.5 ? ambientGlow : other.ambientGlow,
      editorialSerif: t < 0.5 ? editorialSerif : other.editorialSerif,
      navLayout: t < 0.5 ? navLayout : other.navLayout,
      heroStyle: t < 0.5 ? heroStyle : other.heroStyle,
      detailLayout: t < 0.5 ? detailLayout : other.detailLayout,
      backdropMode: t < 0.5 ? backdropMode : other.backdropMode,
      backdropBlur: lerpDoubleD(backdropBlur, other.backdropBlur, t),
      surfaceOpacity: lerpDoubleD(surfaceOpacity, other.surfaceOpacity, t),
      surfaceMaterial: t < 0.5 ? surfaceMaterial : other.surfaceMaterial,
      posterAspect: t < 0.5 ? posterAspect : other.posterAspect,
      cardStyle: t < 0.5 ? cardStyle : other.cardStyle,
      cardHoverEffect: t < 0.5 ? cardHoverEffect : other.cardHoverEffect,
      badgeStyle: t < 0.5 ? badgeStyle : other.badgeStyle,
      progressStyle: t < 0.5 ? progressStyle : other.progressStyle,
      castStyle: t < 0.5 ? castStyle : other.castStyle,
      osdStyle: t < 0.5 ? osdStyle : other.osdStyle,
      mobileNavStyle: t < 0.5 ? mobileNavStyle : other.mobileNavStyle,
      touchFeedbackStyle: t < 0.5 ? touchFeedbackStyle : other.touchFeedbackStyle,
      themeFamily: t < 0.5 ? themeFamily : other.themeFamily,
      liquidSpecular: t < 0.5 ? liquidSpecular : other.liquidSpecular,
      showCardRating: t < 0.5 ? showCardRating : other.showCardRating,
      preferClearLogo: t < 0.5 ? preferClearLogo : other.preferClearLogo,
      isCustom: t < 0.5 ? isCustom : other.isCustom,
    );
  }

  static double lerpDoubleD(double a, double b, double t) => a + (b - a) * t;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VedroSkin &&
        other.id == id &&
        other.name == name &&
        other.subtitle == subtitle &&
        other.badge == badge &&
        other.isLight == isLight &&
        other.canvas == canvas &&
        other.canvasGlow == canvasGlow &&
        other.surface == surface &&
        other.surface2 == surface2 &&
        other.surface3 == surface3 &&
        other.field == field &&
        other.glass == glass &&
        other.glassStrong == glassStrong &&
        other.border == border &&
        other.borderStrong == borderStrong &&
        other.fg == fg &&
        other.fg2 == fg2 &&
        other.fg3 == fg3 &&
        other.accent == accent &&
        other.accentSecondary == accentSecondary &&
        other.ctaStyle == ctaStyle &&
        other.frameStyle == frameStyle &&
        other.cardRadius == cardRadius &&
        other.pillRadius == pillRadius &&
        other.ambientGlow == ambientGlow &&
        other.editorialSerif == editorialSerif &&
        other.navLayout == navLayout &&
        other.heroStyle == heroStyle &&
        other.detailLayout == detailLayout &&
        other.backdropMode == backdropMode &&
        other.backdropBlur == backdropBlur &&
        other.surfaceOpacity == surfaceOpacity &&
        other.surfaceMaterial == surfaceMaterial &&
        other.posterAspect == posterAspect &&
        other.cardStyle == cardStyle &&
        other.cardHoverEffect == cardHoverEffect &&
        other.badgeStyle == badgeStyle &&
        other.progressStyle == progressStyle &&
        other.castStyle == castStyle &&
        other.osdStyle == osdStyle &&
        other.mobileNavStyle == mobileNavStyle &&
        other.touchFeedbackStyle == touchFeedbackStyle &&
        other.themeFamily == themeFamily &&
        other.liquidSpecular == liquidSpecular &&
        other.showCardRating == showCardRating &&
        other.preferClearLogo == preferClearLogo &&
        other.isCustom == isCustom;
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        name,
        subtitle,
        badge,
        isLight,
        canvas,
        canvasGlow,
        surface,
        surface2,
        surface3,
        field,
        glass,
        glassStrong,
        border,
        borderStrong,
        fg,
        fg2,
        fg3,
        accent,
        accentSecondary,
        ctaStyle,
        frameStyle,
        cardRadius,
        pillRadius,
        ambientGlow,
        editorialSerif,
        navLayout,
        heroStyle,
        detailLayout,
        backdropMode,
        backdropBlur,
        surfaceOpacity,
        surfaceMaterial,
        posterAspect,
        cardStyle,
        cardHoverEffect,
        badgeStyle,
        progressStyle,
        castStyle,
        osdStyle,
        mobileNavStyle,
        touchFeedbackStyle,
        themeFamily,
        liquidSpecular,
        showCardRating,
        preferClearLogo,
        isCustom,
      ]);
}

/// Global atmospheric backdrop canvas:
/// - `'solid_clean'`: pure solid `skin.canvas`
/// - `'ambient_orb'`: dual-tone atmospheric radial color wash
/// - `'blurred_fanart'`: Ultrachromic / Jellyfin full-page blurred fanart backdrop (`backdropImageUrl`)!
class VedroSkinCanvas extends StatelessWidget {
  const VedroSkinCanvas({
    super.key,
    required this.child,
    this.backdropImageUrl,
    this.suppressTopOrb = false,
    this.suppressBottomOrb = false,
  });

  final Widget child;
  final String? backdropImageUrl;
  final bool suppressTopOrb;

  /// Hide the screen-fixed bottom-right glow (e.g. under a full-bleed Home hero,
  /// whose opaque bottom dissolve would otherwise cut the glow with a hard seam).
  final bool suppressBottomOrb;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final showFanart = skin.usesBlurredFanart &&
        backdropImageUrl != null &&
        backdropImageUrl!.trim().isNotEmpty;
    final showOrb = skin.backdropMode == 'ambient_orb' ||
        (skin.ambientGlow && skin.backdropMode != 'solid_clean');

    if (!showFanart && !showOrb) {
      return ColoredBox(color: skin.canvas, child: child);
    }

    return ColoredBox(
      color: skin.canvas,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showFanart)
            Positioned.fill(
              child: RepaintBoundary(
                child: IgnorePointer(
                  child: ClipRect(
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(
                        sigmaX: PlatformPerfProfile.ambientBlurSigma,
                        sigmaY: PlatformPerfProfile.ambientBlurSigma,
                        tileMode: TileMode.clamp,
                      ),
                      child: Image.network(
                        backdropImageUrl!,
                        cacheWidth: 96,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.low,
                        color: Colors.white.withValues(alpha: skin.isLight ? 0.24 : 0.34),
                        colorBlendMode: BlendMode.modulate,
                        frameBuilder: (ctx, img, frame, wasSync) {
                          if (wasSync) return img;
                          return AnimatedOpacity(
                            opacity: frame == null ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOut,
                            child: img,
                          );
                        },
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (showOrb) ...[
            if (!suppressTopOrb)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(-0.72, -0.82),
                        radius: 1.25,
                        colors: [
                          skin.canvasGlow.withValues(alpha: skin.isLight ? 0.36 : 0.28),
                          skin.canvas.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (!suppressBottomOrb)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.85, 0.78),
                      radius: 1.15,
                      colors: [
                        skin.accentSecondary.withValues(alpha: skin.isLight ? 0.09 : 0.12),
                        skin.canvas.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          child,
        ],
      ),
    );
  }
}

/// Cohesive skin-adaptive surface panel that automatically harmonizes Frosted Glass (`unified_glass`),
/// Tinted Acrylic (`tinted_acrylic`), OLED Borderless (`oled_borderless`), and Matte Solid (`matte_solid`)
/// so glass effects NEVER clash awkwardly with opaque solid rectangles!
class VedroAdaptiveSurface extends StatelessWidget {
  const VedroAdaptiveSurface({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.hovered = false,
    this.selected = false,
    this.blurSigma = 22.0,
    this.enableLiveBlur = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;
  final bool hovered;
  final bool selected;
  final double blurSigma;
  final bool enableLiveBlur;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final r = borderRadius ?? skin.cardRadius.clamp(8.0, 20.0);
    final radius = BorderRadius.circular(r);
    final fill = hovered ? skin.unifiedTileColor(hovered: true, selected: selected) : skin.unifiedPanelColor;
    final mat = skin.effectiveSurfaceMaterial;

    if (mat == 'liquid_glass' || mat == 'unified_glass') {
      final isLiquid = mat == 'liquid_glass';
      final specMul = switch (skin.liquidSpecular) {
        'subtle' => 0.65,
        'vivid' => 1.35,
        _ => 1.0,
      };
      final effBlur = PlatformPerfProfile.clampLiveBlur(
        isLiquid ? (skin.backdropBlur * 0.85).clamp(14.0, 48.0) : blurSigma,
      );
      final useLiveBlur =
          enableLiveBlur && !PlatformPerfProfile.isMobile && !PlatformPerfProfile.isTv && effBlur > 0.5;
      final adaptedFill = useLiveBlur
          ? PlatformPerfProfile.adaptGlassFill(fill)
          : fill.withValues(alpha: (fill.a + (skin.isLight ? 0.14 : 0.12)).clamp(0.45, 0.94));
      final surfaceBody = DecoratedBox(
        decoration: BoxDecoration(
          color: adaptedFill,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: isLiquid ? const [0.0, 0.36, 1.0] : const [0.0, 1.0],
            colors: isLiquid
                ? [
                    Colors.white.withValues(
                      alpha: ((skin.isLight ? 0.52 : 0.14) * specMul).clamp(0.04, 0.75),
                    ),
                    Colors.white.withValues(alpha: skin.isLight ? 0.16 : 0.02),
                    skin.accent.withValues(alpha: skin.isLight ? 0.04 : 0.06),
                  ]
                : [
                    Colors.white.withValues(alpha: skin.isLight ? 0.34 : 0.065),
                    Colors.transparent,
                  ],
          ),
        ),
        child: padding != null ? Padding(padding: padding!, child: child) : child,
      );
      return RepaintBoundary(
        child: Container(
        decoration: isLiquid
            ? BoxDecoration(
                borderRadius: radius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: skin.isLight ? 0.08 : 0.28),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              )
            : null,
        foregroundDecoration: isLiquid
            ? null
            : BoxDecoration(
                borderRadius: radius,
                border: skin.cardBorder(hovered: hovered, selected: selected),
              ),
        child: CustomPaint(
          foregroundPainter: isLiquid
              ? LiquidGlassRimPainter(
                  radius: r,
                  isLight: skin.isLight,
                  accent: skin.accent,
                  intensity: specMul,
                  selected: selected,
                )
              : null,
          child: ClipRRect(
            borderRadius: radius,
            child: useLiveBlur
                ? BackdropFilter(
                    filter: VedroLiquidGlassShader.buildBackdropFilter(
                      context: context,
                      isLight: skin.isLight,
                      accent: skin.accent,
                      blurSigma: effBlur,
                      borderRadius: r,
                      enableRefraction: isLiquid,
                      liquidSpecular: skin.liquidSpecular,
                      refractionDp: 10.5,
                      dispersionDp: 1.8,
                    ),
                    child: surfaceBody,
                  )
                : surfaceBody,
          ),
        ),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: skin.cardBorder(hovered: hovered, selected: selected),
      ),
      child: child,
    );
  }
}
