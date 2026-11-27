import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/preferences.dart';
import '../core/theme/display_profile.dart';
import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import 'vedro_ui.dart';

/// Unified, Portrait-Native, iOS-Caliber Theme & Appearance Pane.
///
/// Built around 4 Cohesive Master Design Systems (NO exhausting patchwork toggles):
/// 1. `immersive_cinema` — 沉浸影院 (Full-bleed fanart theater stage)
/// 2. `ios_frosted` — iOS 毛玻璃 (Classic frosted vibrancy & soft depth)
/// 3. `ios_liquid_glass` — iOS 液态玻璃 (Optical specular refraction & crystal rim)
/// 4. `material_design` — Material 设计 (MD3 expressive tonal containers)
///
/// Paired with:
/// -的外观模式 (`深色` / `浅色` / `跟随系统`)
/// - 莫奈动态取色 (`随当前页面自动沉浸变色`) + 精选 iOS 主题色板
/// - 严格跟随当前大主题显示的专属细节微调（仅毛玻璃与液态玻璃显示透光度与模糊半径）
class SkinStudioPane extends StatefulWidget {
  const SkinStudioPane({
    super.key,
    required this.appState,
    this.hideHeading = false,
    this.stickyDesktop = false,
    this.platformOverride,
  });

  final VedroAppState appState;
  final bool hideHeading;
  final bool stickyDesktop;
  final String? platformOverride;

  @override
  State<SkinStudioPane> createState() => _SkinStudioPaneState();
}

class _PreviewSampleScene {
  const _PreviewSampleScene({
    required this.id,
    required this.tag,
    required this.title,
    required this.meta,
    required this.seed,
    required this.gradientColors,
  });

  final String id;
  final String tag;
  final String title;
  final String meta;
  final Color seed;
  final List<Color> gradientColors;
}

class _SkinStudioPaneState extends State<SkinStudioPane> {
  int _sampleIdx = 0;

  static const List<_PreviewSampleScene> _samples = [
    _PreviewSampleScene(
      id: 'dune',
      tag: '琥珀金',
      title: '沙丘2',
      meta: '2024 · 科幻 · 4K 杜比视界',
      seed: Color(0xFFE58E26),
      gradientColors: [Color(0xFF4B280D), Color(0xFF8C4A19), Color(0xFF1A110B)],
    ),
    _PreviewSampleScene(
      id: 'blade',
      tag: '冰川青',
      title: '银翼杀手 2049',
      meta: '2017 · 赛博科幻 · TrueHD Atmos',
      seed: Color(0xFF32ADE6),
      gradientColors: [Color(0xFF0A2842), Color(0xFF12527A), Color(0xFF081320)],
    ),
    _PreviewSampleScene(
      id: 'sakura',
      tag: '樱绯粉',
      title: '花束般的恋爱',
      meta: '2021 · 剧情爱情 · BluRay REMUX',
      seed: Color(0xFFFF4D79),
      gradientColors: [Color(0xFF4A152B), Color(0xFF88264E), Color(0xFF1C0C15)],
    ),
  ];

  VedroAppState get appState => widget.appState;

  Future<void> _selectMasterTheme(String masterId, {required bool isMobile}) async {
    HapticFeedback.selectionClick();
    final p = appState.prefs;
    final currentOv = Map<String, dynamic>.from(p.overridesForPlatform(isMobile: isMobile));
    // Clear any conflicting low-level overrides so the chosen Master Theme applies purely
    currentOv
      ..remove('surface_material')
      ..remove('backdrop_mode')
      ..remove('hero_style')
      ..remove('detail_layout')
      ..remove('frame_style')
      ..remove('cta_style');
    await appState.updatePrefs(
      p.copyWith(
        skinId: masterId,
        useSkinGeometry: true,
        skinOverrides: isMobile ? p.skinOverrides : currentOv,
        mobileSkinOverrides: isMobile ? currentOv : p.mobileSkinOverrides,
      ),
    );
  }

  Future<void> _setOverride(String key, dynamic value, {required bool isMobile}) async {
    final p = appState.prefs;
    final next = Map<String, dynamic>.from(p.overridesForPlatform(isMobile: isMobile));
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    await appState.updatePrefs(
      p.copyWith(
        useSkinGeometry: true,
        skinOverrides: isMobile ? p.skinOverrides : next,
        mobileSkinOverrides: isMobile ? next : p.mobileSkinOverrides,
      ),
    );
  }

  Future<void> _openCustomHexDialog(BuildContext context, VedroPreferences p) async {
    final skin = VedroSkin.of(context);
    final initial = p.customAccentHex.isNotEmpty
        ? p.customAccentHex
        : VedroSkin.colorToHex(skin.accent);
    final ctrl = TextEditingController(text: initial);
    final hex = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义主题色'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: skin.fg, fontSize: 14, fontFamily: 'monospace'),
          decoration: const InputDecoration(
            hintText: '#0A84FF',
            labelText: 'HEX 色值',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('应用'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (hex != null && hex.isNotEmpty) {
      final normalized = hex.startsWith('#') ? hex.toUpperCase() : '#${hex.toUpperCase()}';
      await appState.updatePrefs(
        p.copyWith(accentId: 'custom', customAccentHex: normalized),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = appState.prefs;
    final metrics = DisplayMetricsProfile.of(
      context,
      platformOverride: widget.platformOverride,
    );
    final isMobile = metrics.isMobileOs || MediaQuery.sizeOf(context).width < 680;
    final sysBrightness = View.of(context).platformDispatcher.platformBrightness;
    final sample = _samples[_sampleIdx % _samples.length];

    // Preview stage reflects Monet dynamic seed when dynamicMonet is ON!
    final previewSkin = p.activeSkinFor(
      isMobile: isMobile,
      systemBrightness: sysBrightness,
      dynamicSeedOverride: p.dynamicMonet ? sample.seed : null,
    );
    final uiSkin = VedroSkin.of(context);
    final activeMasterId = VedroSkin.normalizeMasterThemeId(p.skinId);

    final previewCard = _ResponsiveStagePreviewCard(
      key: const ValueKey('skin-live-preview-stage'),
      skin: previewSkin,
      prefs: p,
      isMobile: isMobile,
      sample: sample,
      samples: _samples,
      sampleIndex: _sampleIdx,
      onSelectSample: (idx) {
        HapticFeedback.selectionClick();
        setState(() => _sampleIdx = idx);
      },
    );

    final controlsBody = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 4 Cohesive Master Themes (2x2 on Portrait Phone, 4-up on Wide Desktop)
        _SectionLabel('主题风格', trailing: metrics.isMobileOs ? null : Text(
          metrics.summaryLabel,
          style: TextStyle(color: uiSkin.fg3, fontSize: 11.5),
        )),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 780 ? 4 : 2;
            const gap = 10.0;
            final cardW = (constraints.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: VedroSkin.masterThemes.map((themeSpec) {
                final selected = activeMasterId == themeSpec.id && !previewSkin.isCustom;
                return SizedBox(
                  width: cardW,
                  child: _MasterThemeCard(
                    key: ValueKey('skin-preset-${themeSpec.id}'),
                    themeSpec: themeSpec,
                    activeAccent: previewSkin.accent,
                    isLightPreview: previewSkin.isLight,
                    selected: selected,
                    onTap: () => _selectMasterTheme(themeSpec.id, isMobile: isMobile),
                  ),
                );
              }).toList(),
            );
          },
        ),

        const SizedBox(height: 18),

        // 2. 外观与色彩 (Appearance Polarity + Monet Dynamic Color + iOS Color Swatches)
        const _SectionLabel('外观与色彩'),
        VedroAdaptiveSurface(
          borderRadius: uiSkin.cardRadius.clamp(14.0, 22.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '外观模式',
                        style: TextStyle(color: uiSkin.fg, fontSize: 14),
                      ),
                    ),
                    VedroPullDownButton<String>(
                      key: const ValueKey('theme-mode-dropdown'),
                      height: 34,
                      value: p.themeMode,
                      items: const [
                        VedroDropdownItem(
                          value: 'dark',
                          label: '深色',
                          itemKey: ValueKey('theme-mode-dark'),
                        ),
                        VedroDropdownItem(
                          value: 'light',
                          label: '浅色',
                          itemKey: ValueKey('theme-mode-light'),
                        ),
                        VedroDropdownItem(
                          value: 'system',
                          label: '跟随系统',
                          itemKey: ValueKey('theme-mode-system'),
                        ),
                      ],
                      onChanged: (mode) => appState.updatePrefs(
                        p.copyWith(
                          themeMode: mode,
                          skinId: (p.skinId == 'daylight' || p.skinId == 'editorial_paper')
                              ? activeMasterId
                              : p.skinId,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, indent: 16, endIndent: 16, color: uiSkin.border),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '莫奈动态取色',
                            style: TextStyle(color: uiSkin.fg, fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '随当前页面海报自动沉浸变色',
                            style: TextStyle(color: uiSkin.fg3, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Transform.scale(
                      scale: 0.80,
                      child: CupertinoSwitch(
                        key: const ValueKey('theme-monet-switch'),
                        value: p.dynamicMonet,
                        activeTrackColor: uiSkin.accent,
                        onChanged: (v) => appState.updatePrefs(p.copyWith(dynamicMonet: v)),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, indent: 16, endIndent: 16, color: uiSkin.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 13, 16, 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '主题颜色',
                          style: TextStyle(color: uiSkin.fg, fontSize: 14),
                        ),
                        const Spacer(),
                        Text(
                          p.dynamicMonet
                              ? '动态生效中 · 默认色：${p.accentId == 'custom' ? p.customAccentHex : p.accentPalette.label}'
                              : (p.accentId == 'custom' ? p.customAccentHex : p.accentPalette.label),
                          style: TextStyle(color: uiSkin.fg3, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 11,
                      runSpacing: 11,
                      children: [
                        for (final swatch in AccentPalette.all.where((a) => a.id != 'silver'))
                          _ColorSwatchCircle(
                            key: ValueKey('accent-swatch-${swatch.id}'),
                            color: swatch.accent,
                            selected: p.accentId == swatch.id,
                            tooltip: swatch.label,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              appState.updatePrefs(p.copyWith(accentId: swatch.id));
                            },
                          ),
                        _CustomColorCircle(
                          key: const ValueKey('theme-custom-color-btn'),
                          activeHex: p.accentId == 'custom' ? p.customAccentHex : null,
                          onTap: () => _openCustomHexDialog(context, p),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // 3. Theme-Bound Fine-Tuning (ONLY shows options belonging to the active Master Theme!)
        _SectionLabel('${VedroSkin.byId(activeMasterId).name} · 细节'),
        VedroAdaptiveSurface(
          key: ValueKey('theme-details-$activeMasterId'),
          borderRadius: uiSkin.cardRadius.clamp(14.0, 22.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _buildThemeSpecificRows(
              activeMasterId: activeMasterId,
              skin: previewSkin,
              uiSkin: uiSkin,
              prefs: p,
              isMobile: isMobile,
            ),
          ),
        ),

        const SizedBox(height: 18),

        // 4. Platform-Matched Navigation Bar Settings (iOS Clean Grouped Card)
        const _SectionLabel('导航栏'),
        VedroAdaptiveSurface(
          borderRadius: uiSkin.cardRadius.clamp(14.0, 22.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: isMobile
                ? [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('底部导航样式', style: TextStyle(color: uiSkin.fg, fontSize: 14)),
                          ),
                          VedroPullDownButton<String>(
                            key: const ValueKey('mobile-nav-style-dropdown'),
                            height: 34,
                            value: previewSkin.mobileNavStyle,
                            items: const [
                              VedroDropdownItem(value: 'floating_dock', label: 'iOS 悬浮胶囊'),
                              VedroDropdownItem(value: 'full_tab_bar', label: '通栏标签栏'),
                              VedroDropdownItem(value: 'compact_icon_only', label: '极简纯图标'),
                            ],
                            onChanged: (v) => _setOverride('mobile_nav_style', v, isMobile: true),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, indent: 16, endIndent: 16, color: uiSkin.border),
                    _SimpleSwitchRow(
                      switchKey: const ValueKey('nav-auto-shrink-switch'),
                      title: '滑动时收缩导航栏',
                      value: p.autoShrinkNavOnScroll,
                      accent: uiSkin.accent,
                      fg: uiSkin.fg,
                      onChanged: (v) => appState.updatePrefs(p.copyWith(autoShrinkNavOnScroll: v)),
                    ),
                    Divider(height: 1, indent: 16, endIndent: 16, color: uiSkin.border),
                    _SimpleSwitchRow(
                      switchKey: const ValueKey('nav-show-labels-switch'),
                      title: '显示导航栏名称',
                      value: p.showNavLabels,
                      accent: uiSkin.accent,
                      fg: uiSkin.fg,
                      onChanged: (v) => appState.updatePrefs(p.copyWith(showNavLabels: v)),
                    ),
                  ]
                : [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('导航栏位置', style: TextStyle(color: uiSkin.fg, fontSize: 14)),
                          ),
                          VedroPullDownButton<String>(
                            key: const ValueKey('desktop-nav-layout-dropdown'),
                            height: 34,
                            value: previewSkin.navLayout,
                            items: const [
                              VedroDropdownItem(
                                value: 'centered_capsule',
                                label: 'iOS 灵动胶囊岛',
                                itemKey: ValueKey('skin-mod-centered_capsule'),
                              ),
                              VedroDropdownItem(
                                value: 'top_floating',
                                label: '顶部悬浮栏',
                                itemKey: ValueKey('skin-mod-top_floating'),
                              ),
                              VedroDropdownItem(
                                value: 'left_rail',
                                label: '左侧边栏',
                                itemKey: ValueKey('skin-mod-left_rail'),
                              ),
                            ],
                            onChanged: (v) => _setOverride('nav_layout', v, isMobile: false),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, indent: 16, endIndent: 16, color: uiSkin.border),
                    _SimpleSwitchRow(
                      title: '减少界面动态效果',
                      value: p.reduceMotion,
                      accent: uiSkin.accent,
                      fg: uiSkin.fg,
                      onChanged: (v) => appState.updatePrefs(p.copyWith(reduceMotion: v)),
                    ),
                  ],
          ),
        ),
      ],
    );

    if (widget.stickyDesktop && !isMobile) {
      return Column(
        key: const ValueKey('skin-studio-pane'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.hideHeading)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                '应用风格',
                style: uiSkin.applyHeadlineMood(
                  TextStyle(
                    color: uiSkin.fg,
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
          previewCard,
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 56),
              child: controlsBody,
            ),
          ),
        ],
      );
    }

    return Column(
      key: const ValueKey('skin-studio-pane'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.hideHeading)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              '应用风格',
              style: uiSkin.applyHeadlineMood(
                TextStyle(
                  color: uiSkin.fg,
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
        previewCard,
        const SizedBox(height: 18),
        controlsBody,
      ],
    );
  }

  List<Widget> _buildThemeSpecificRows({
    required String activeMasterId,
    required VedroSkin skin,
    required VedroSkin uiSkin,
    required VedroPreferences prefs,
    required bool isMobile,
  }) {
    // 1. iOS Frosted Glass & iOS Liquid Glass -> Translucency & Blur Radius!
    if (activeMasterId == 'ios_frosted' || activeMasterId == 'ios_liquid_glass') {
      // Translucency percentage = (1.0 - surfaceOpacity) mapped intuitively: higher % = more see-through!
      final translucencyPct = ((1.0 - skin.surfaceOpacity) * 100.0).clamp(10.0, 65.0);
      return [
        Padding(
          key: const ValueKey('glass-translucency-slider-row'),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: VedroPrecisionSlider(
            label: '透光率',
            value: translucencyPct,
            min: 12,
            max: 62,
            step: 2,
            defaultValue: activeMasterId == 'ios_liquid_glass' ? 44 : 28,
            valueText: '${translucencyPct.round()}%',
            onChanged: (pct) => _setOverride(
              'surface_opacity',
              (1.0 - pct / 100.0).clamp(0.36, 0.90),
              isMobile: isMobile,
            ),
          ),
        ),
        Divider(height: 1, indent: 16, endIndent: 16, color: uiSkin.border),
        Padding(
          key: const ValueKey('glass-blur-radius-slider-row'),
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
          child: VedroPrecisionSlider(
            label: '模糊半径',
            value: skin.backdropBlur.clamp(12.0, 60.0),
            min: 12,
            max: 60,
            step: 2,
            defaultValue: activeMasterId == 'ios_liquid_glass' ? 30 : 38,
            valueText: '${skin.backdropBlur.round()} px',
            onChanged: (sigma) => _setOverride('backdrop_blur', sigma, isMobile: isMobile),
          ),
        ),
        if (activeMasterId == 'ios_liquid_glass') ...[
          Divider(height: 1, indent: 16, endIndent: 16, color: uiSkin.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text('镜面高光折射', style: TextStyle(color: uiSkin.fg, fontSize: 14)),
                ),
                VedroPullDownButton<String>(
                  key: const ValueKey('liquid-specular-dropdown'),
                  height: 34,
                  value: skin.liquidSpecular,
                  items: const [
                    VedroDropdownItem(value: 'subtle', label: '柔和'),
                    VedroDropdownItem(value: 'standard', label: '标准'),
                    VedroDropdownItem(value: 'vivid', label: '通透高光'),
                  ],
                  onChanged: (v) => _setOverride('liquid_specular', v, isMobile: isMobile),
                ),
              ],
            ),
          ),
        ],
      ];
    }

    // 2. Material Design 3 -> Tonal Chroma, Outline & Corner Radius (NO glass sliders!)
    if (activeMasterId == 'material_design') {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text('色阶浓郁度', style: TextStyle(color: uiSkin.fg, fontSize: 14)),
              ),
              VedroPullDownButton<String>(
                key: const ValueKey('md3-chroma-dropdown'),
                height: 34,
                value: prefs.tonalChroma,
                items: const [
                  VedroDropdownItem(value: 'soft', label: '柔和'),
                  VedroDropdownItem(value: 'standard', label: '标准'),
                  VedroDropdownItem(value: 'vivid', label: '鲜明'),
                ],
                onChanged: (v) => appState.updatePrefs(prefs.copyWith(tonalChroma: v)),
              ),
            ],
          ),
        ),
        Divider(height: 1, indent: 16, endIndent: 16, color: uiSkin.border),
        _SimpleSwitchRow(
          title: '容器细线描边',
          value: skin.frameStyle == 'hairline',
          accent: uiSkin.accent,
          fg: uiSkin.fg,
          onChanged: (on) => _setOverride('frame_style', on ? 'hairline' : 'borderless', isMobile: isMobile),
        ),
        Divider(height: 1, indent: 16, endIndent: 16, color: uiSkin.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
          child: VedroPrecisionSlider(
            label: '圆角弧度',
            value: skin.cardRadius.clamp(12.0, 28.0),
            min: 12,
            max: 28,
            step: 2,
            defaultValue: 20,
            valueText: '${skin.cardRadius.round()} px',
            onChanged: (r) => _setOverride('card_radius', r, isMobile: isMobile),
          ),
        ),
      ];
    }

    // 3. Default Immersive Cinema -> Fanart Atmosphere, Editorial Serif & Corner Radius (NO glass sliders!)
    return [
      _SimpleSwitchRow(
        title: '剧照氛围漫射',
        value: skin.usesBlurredFanart,
        accent: uiSkin.accent,
        fg: uiSkin.fg,
        onChanged: (on) => _setOverride(
          'backdrop_mode',
          on ? 'blurred_fanart' : 'solid_clean',
          isMobile: isMobile,
        ),
      ),
      Divider(height: 1, indent: 16, endIndent: 16, color: uiSkin.border),
      _SimpleSwitchRow(
        switchKey: const ValueKey('cinema-serif-switch'),
        title: '电影衬线大标题',
        value: skin.editorialSerif,
        accent: uiSkin.accent,
        fg: uiSkin.fg,
        onChanged: (on) => _setOverride('editorial_serif', on, isMobile: isMobile),
      ),
      Divider(height: 1, indent: 16, endIndent: 16, color: uiSkin.border),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
        child: VedroPrecisionSlider(
          label: '圆角弧度',
          value: skin.cardRadius.clamp(8.0, 24.0),
          min: 8,
          max: 24,
          step: 1,
          defaultValue: 15,
          valueText: '${skin.cardRadius.round()} px',
          onChanged: (r) => _setOverride('card_radius', r, isMobile: isMobile),
        ),
      ),
    ];
  }
}

/// Portrait-Native Live Interactive Preview Card — renders cleanly on 360px phones AND 4K desktops
/// with ZERO 3-column horizontal squeezing!
class _ResponsiveStagePreviewCard extends StatelessWidget {
  const _ResponsiveStagePreviewCard({
    super.key,
    required this.skin,
    required this.prefs,
    required this.isMobile,
    required this.sample,
    required this.samples,
    required this.sampleIndex,
    required this.onSelectSample,
  });

  final VedroSkin skin;
  final VedroPreferences prefs;
  final bool isMobile;
  final _PreviewSampleScene sample;
  final List<_PreviewSampleScene> samples;
  final int sampleIndex;
  final ValueChanged<int> onSelectSample;

  @override
  Widget build(BuildContext context) {
    final outerR = skin.cardRadius.clamp(16.0, 24.0);
    final isLiquid = skin.isLiquidGlass;
    final isGlass = skin.usesGlassPanels;

    return Theme(
      data: VedroTheme.fromSkin(skin),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(outerR),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: skin.isLight ? 0.10 : 0.36),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(outerR),
          border: Border.all(color: skin.borderStrong, width: 0.9),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Background: Simulated Movie Artwork Stage + Active Theme Atmosphere
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                decoration: BoxDecoration(
                  color: skin.canvas,
                  gradient: skin.usesBlurredFanart || skin.themeFamily == 'immersive_cinema'
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: skin.isLight
                              ? [
                                  Color.lerp(Colors.white, sample.seed, 0.22)!,
                                  Color.lerp(skin.canvas, sample.seed, 0.10)!,
                                  skin.canvas,
                                ]
                              : [
                                  sample.gradientColors[0],
                                  Color.lerp(sample.gradientColors[1], skin.canvas, 0.45)!,
                                  skin.canvas,
                                ],
                        )
                      : RadialGradient(
                          center: const Alignment(-0.5, -0.7),
                          radius: 1.35,
                          colors: [
                            skin.canvasGlow,
                            skin.canvas,
                          ],
                        ),
                ),
              ),
            ),

            Padding(
              padding: EdgeInsets.all(isMobile ? 14 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Bar: Back Glass Circle + Sample Artwork Switcher Pills (Tests Monet Color live!)
                  Row(
                    children: [
                      GlassSurface(
                        borderRadius: 999,
                        blur: 20,
                        padding: const EdgeInsets.all(6.5),
                        child: Icon(Icons.arrow_back_ios_new_rounded, size: 12, color: skin.fg),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: skin.accent.withValues(alpha: skin.isLight ? 0.14 : 0.22),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              isMobile
                                  ? skin.name
                                  : '${skin.name}${prefs.dynamicMonet ? ' · 莫奈动态' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: skin.isLight ? skin.accent : Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      for (var i = 0; i < samples.length; i++)
                        Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                          child: PressableScale(
                            key: ValueKey('preview-scene-${samples[i].id}'),
                            onTap: () => onSelectSample(i),
                            borderRadius: BorderRadius.circular(999),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: EdgeInsets.symmetric(
                                horizontal: isMobile ? 7 : 8.5,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: i == sampleIndex
                                    ? samples[i].seed.withValues(alpha: 0.90)
                                    : (skin.isLight
                                        ? Colors.black.withValues(alpha: 0.06)
                                        : Colors.white.withValues(alpha: 0.10)),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                samples[i].tag,
                                style: TextStyle(
                                  color: i == sampleIndex ? Colors.white : skin.fg2,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Center Hero & Pull-Down Selector Showcase
                  VedroAdaptiveSurface(
                    borderRadius: skin.cardRadius.clamp(12.0, 22.0),
                    blurSigma: skin.backdropBlur.clamp(14.0, 48.0),
                    padding: const EdgeInsets.all(13),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Mini Poster
                            Container(
                              width: 48,
                              height: 68,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  (skin.cardRadius * 0.55).clamp(6.0, 12.0),
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [sample.seed, sample.gradientColors.first],
                                ),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(Icons.movie_creation_rounded, size: 20, color: Colors.white70),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    sample.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: skin.applyHeadlineMood(
                                      TextStyle(
                                        color: skin.fg,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    sample.meta,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: skin.fg2, fontSize: 11.5),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Container(
                                        height: 28,
                                        padding: const EdgeInsets.symmetric(horizontal: 14),
                                        decoration: BoxDecoration(
                                          color: skin.primaryCtaBg,
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        alignment: Alignment.center,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.play_arrow_rounded, size: 15, color: skin.primaryCtaFg),
                                            const SizedBox(width: 3),
                                            Text(
                                              '播放',
                                              style: TextStyle(
                                                color: skin.primaryCtaFg,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _MiniDropdownBadge(label: '4K REMUX', skin: skin),
                                      if (!isMobile) ...[
                                        const SizedBox(width: 6),
                                        _MiniDropdownBadge(label: 'Atmos', skin: skin),
                                        const SizedBox(width: 6),
                                        _MiniDropdownBadge(label: '中英 ASS', skin: skin),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Bottom Simulated iOS Dock / Desktop Capsule Bar
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 360),
                      child: GlassSurface(
                        borderRadius: skin.mobileNavStyle == 'full_tab_bar' && isMobile ? 12 : 999,
                        blur: (isGlass || isLiquid) ? skin.backdropBlur.clamp(16.0, 40.0) : 20,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            for (final (idx, icon, label) in const [
                              (0, Icons.home_rounded, '首页'),
                              (1, Icons.grid_view_rounded, '媒体库'),
                              (2, Icons.search_rounded, '搜索'),
                              (3, Icons.tune_rounded, '设置'),
                            ])
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                                decoration: BoxDecoration(
                                  color: idx == 0
                                      ? (skin.isLight
                                          ? Colors.black.withValues(alpha: 0.06)
                                          : Colors.white.withValues(alpha: 0.12))
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      icon,
                                      size: 14,
                                      color: idx == 0 ? skin.accent : skin.fg3,
                                    ),
                                    if (prefs.showNavLabels &&
                                        !(isMobile && skin.mobileNavStyle == 'compact_icon_only')) ...[
                                      const SizedBox(width: 4),
                                      Text(
                                        label,
                                        style: TextStyle(
                                          color: idx == 0 ? skin.accent : skin.fg3,
                                          fontSize: 11,
                                          fontWeight: idx == 0 ? FontWeight.w600 : FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniDropdownBadge extends StatelessWidget {
  const _MiniDropdownBadge({required this.label, required this.skin});
  final String label;
  final VedroSkin skin;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8.5),
      decoration: BoxDecoration(
        color: skin.unifiedTileColor(),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: skin.isLight ? skin.border : Colors.white.withValues(alpha: 0.14),
          width: 0.7,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: skin.fg2, fontSize: 10.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 2),
          Icon(Icons.keyboard_arrow_down_rounded, size: 12, color: skin.fg3),
        ],
      ),
    );
  }
}

class _MasterThemeCard extends StatelessWidget {
  const _MasterThemeCard({
    super.key,
    required this.themeSpec,
    required this.activeAccent,
    required this.isLightPreview,
    required this.selected,
    required this.onTap,
  });

  final VedroSkin themeSpec;
  final Color activeAccent;
  final bool isLightPreview;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final uiSkin = VedroSkin.of(context);
    final r = uiSkin.cardRadius.clamp(13.0, 20.0);
    final isLiquid = themeSpec.id == 'ios_liquid_glass';
    final isFrosted = themeSpec.id == 'ios_frosted';
    final isMd3 = themeSpec.id == 'material_design';

    final icon = switch (themeSpec.id) {
      'ios_liquid_glass' => Icons.water_drop_outlined,
      'ios_frosted' => Icons.blur_on_rounded,
      'material_design' => Icons.widgets_outlined,
      _ => Icons.movie_filter_outlined,
    };

    return PressableScale(
      onTap: onTap,
      hoverScale: 1.015,
      pressScale: 0.97,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected ? uiSkin.unifiedTileColor(selected: true) : uiSkin.unifiedPanelColor,
          borderRadius: BorderRadius.circular(r),
          border: Border.all(
            color: selected ? uiSkin.accent : uiSkin.border,
            width: selected ? 1.5 : 0.8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Visual Material Swatch Strip
            Container(
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isLightPreview
                      ? [
                          Color.lerp(const Color(0xFFEFF3FA), activeAccent, 0.20)!,
                          Colors.white,
                        ]
                      : [
                          Color.lerp(themeSpec.canvas, activeAccent, isMd3 ? 0.22 : 0.30)!,
                          themeSpec.canvas,
                        ],
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: CustomPaint(
                      foregroundPainter: isLiquid
                          ? LiquidGlassRimPainter(
                              radius: 999,
                              isLight: isLightPreview,
                              accent: activeAccent,
                            )
                          : null,
                      child: Container(
                        height: 26,
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        decoration: BoxDecoration(
                          color: isLightPreview
                              ? Colors.white.withValues(alpha: isLiquid ? 0.55 : (isFrosted ? 0.78 : 0.94))
                              : Colors.white.withValues(alpha: isLiquid ? 0.14 : (isFrosted ? 0.18 : 0.10)),
                          borderRadius: BorderRadius.circular(isMd3 ? 8 : 999),
                          border: isLiquid
                              ? null
                              : Border.all(
                                  color: isLightPreview
                                      ? Colors.black.withValues(alpha: 0.08)
                                      : Colors.white.withValues(alpha: isFrosted ? 0.24 : 0.08),
                                  width: 0.75,
                                ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 13, color: activeAccent),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Container(
                                height: 5,
                                width: 36,
                                decoration: BoxDecoration(
                                  color: (isLightPreview ? Colors.black : Colors.white)
                                      .withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (selected)
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: uiSkin.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: highContrastOn(uiSkin.accent),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              themeSpec.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: uiSkin.fg,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              themeSpec.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: uiSkin.fg3,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorSwatchCircle extends StatelessWidget {
  const _ColorSwatchCircle({
    super.key,
    required this.color,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: PressableScale(
        onTap: onTap,
        hoverScale: 1.08,
        pressScale: 0.92,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: selected
                ? Border.all(color: Colors.white, width: 2.2)
                : Border.all(color: Colors.white.withValues(alpha: 0.16), width: 0.8),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: highContrastOn(color),
                )
              : null,
        ),
      ),
    );
  }
}

class _CustomColorCircle extends StatelessWidget {
  const _CustomColorCircle({
    super.key,
    required this.activeHex,
    required this.onTap,
  });

  final String? activeHex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final selected = activeHex != null && activeHex!.isNotEmpty;
    final customColor = selected ? VedroSkin.parseHex(activeHex!, skin.accent) : null;

    return Tooltip(
      message: '自定义 HEX 颜色',
      child: PressableScale(
        onTap: onTap,
        hoverScale: 1.08,
        pressScale: 0.92,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: customColor,
            gradient: customColor == null
                ? const SweepGradient(
                    colors: [
                      Color(0xFFFF375F),
                      Color(0xFFFF9F0A),
                      Color(0xFF30D158),
                      Color(0xFF32ADE6),
                      Color(0xFF5E5CE6),
                      Color(0xFFBF5AF2),
                      Color(0xFFFF375F),
                    ],
                  )
                : null,
            border: Border.all(
              color: selected ? Colors.white : skin.borderStrong,
              width: selected ? 2.2 : 0.9,
            ),
          ),
          child: Icon(
            selected ? Icons.check_rounded : Icons.colorize_rounded,
            size: 16,
            color: customColor != null ? highContrastOn(customColor) : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title, {this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: skin.fg2,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _SimpleSwitchRow extends StatelessWidget {
  const _SimpleSwitchRow({
    this.switchKey,
    required this.title,
    required this.value,
    required this.accent,
    required this.fg,
    required this.onChanged,
  });

  final Key? switchKey;
  final String title;
  final bool value;
  final Color accent;
  final Color fg;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: TextStyle(color: fg, fontSize: 14)),
          ),
          Transform.scale(
            scale: 0.80,
            child: CupertinoSwitch(
              key: switchKey,
              value: value,
              activeTrackColor: accent,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
