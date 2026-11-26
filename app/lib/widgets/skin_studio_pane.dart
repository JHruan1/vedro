import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import 'vedro_artwork.dart';
import 'vedro_ui.dart';

/// Jellyfin Skin Manager (`Ultrachromic` / `ElegantFin` / `Scyfin` / `MediaBar`) Studio:
/// - Real-time Interactive Cinema Preview Stage right inside Settings (`首页舞台` / `详情与多版本` / `播放器 HUD`)
/// - 14 customizable architectural, material, card, badge, progress, typography & OSD dimensions
/// - Unified Frosted Glass / Tinted Acrylic / Matte Solid / OLED Borderless material engine (zero solid-card clash!)
/// - Full DIY Custom Skin Editor & `VEDRO-SKIN:...` portable share codes
class SkinStudioPane extends StatefulWidget {
  const SkinStudioPane({
    super.key,
    required this.appState,
    this.hideHeading = false,
  });

  final VedroAppState appState;
  final bool hideHeading;

  @override
  State<SkinStudioPane> createState() => _SkinStudioPaneState();
}

class _SkinStudioPaneState extends State<SkinStudioPane> {
  String _previewScene = 'home'; // 'home' | 'detail' | 'player'

  VedroAppState get appState => widget.appState;

  Future<void> _openEditor(
    BuildContext context, {
    CustomSkinSpec? existing,
    VedroSkin? forkFrom,
  }) async {
    final seed = existing ??
        forkFrom?.toCustomSpec(
          newId: 'custom_${DateTime.now().millisecondsSinceEpoch}',
          newName: '${forkFrom.name} · 定制',
        ) ??
        const CustomSkinSpec(
          id: '',
          name: '我的专属皮肤',
          isLight: false,
          canvasHex: '#0B1020',
          accentHex: '#38BDF8',
          accentSecondaryHex: '#818CF8',
          ctaStyle: 'gradient',
          frameStyle: 'hairline',
          cardRadius: 16,
          pillRadius: 999,
          ambientGlow: true,
          editorialSerif: false,
          navLayout: 'centered_capsule',
          heroStyle: 'framed_stage',
          detailLayout: 'jellyfin_glass',
          backdropMode: 'blurred_fanart',
          surfaceMaterial: 'unified_glass',
          posterAspect: 'poster_2_3',
          cardStyle: 'overlay_poster',
          cardHoverEffect: 'glow_ring',
          badgeStyle: 'glass_pill',
          progressStyle: 'glow_accent',
          castStyle: 'portrait_card',
          osdStyle: 'minimal_glass',
          showCardRating: true,
        ).copyWith(id: 'custom_${DateTime.now().millisecondsSinceEpoch}');

    final saved = await showDialog<CustomSkinSpec>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _CustomSkinEditorDialog(initial: seed),
    );
    if (saved == null) return;

    final p = appState.prefs;
    final list = [...p.customSkins];
    final idx = list.indexWhere((c) => c.id == saved.id);
    if (idx >= 0) {
      list[idx] = saved;
    } else {
      list.add(saved);
    }
    await appState.updatePrefs(
      p.copyWith(
        customSkins: list,
        skinId: saved.id,
        skinOverrides: const {},
        useSkinGeometry: true,
      ),
    );
  }

  Future<void> _openImportDialog(BuildContext context) async {
    final skin = VedroSkin.of(context);
    final ctrl = TextEditingController();
    String? errText;
    final imported = await showDialog<CustomSkinSpec>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: skin.surface2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: skin.borderStrong),
          ),
          title: Text(
            '导入皮肤口令',
            style: TextStyle(color: skin.fg, fontSize: 17, fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '粘贴好友分享或跨设备导出的 VEDRO-SKIN:... 皮肤码（包含完整导航骨架、表面材质、海报结构与配色）：',
                  style: TextStyle(color: skin.fg2, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  autofocus: true,
                  style: TextStyle(color: skin.fg, fontSize: 12.5, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: 'VEDRO-SKIN:eyJuYW1lIjoi...',
                    errorText: errText,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = CustomSkinSpec.tryDecodeShareCode(ctrl.text);
                if (parsed == null) {
                  setSt(() => errText = '皮肤口令格式无效，请检查后重试');
                  return;
                }
                Navigator.pop(ctx, parsed);
              },
              child: const Text('导入并启用'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (imported == null) return;
    final p = appState.prefs;
    await appState.updatePrefs(
      p.copyWith(
        customSkins: [...p.customSkins, imported],
        skinId: imported.id,
        skinOverrides: const {},
        useSkinGeometry: true,
      ),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入并切换至皮肤「${imported.name}」')),
      );
    }
  }

  void _setOverride(String key, dynamic value) {
    final p = appState.prefs;
    final next = Map<String, dynamic>.from(p.skinOverrides);
    next[key] = value;
    appState.updatePrefs(p.copyWith(skinOverrides: next));
  }

  void _applyCornerPreset(double radius, double pill) {
    final p = appState.prefs;
    final next = Map<String, dynamic>.from(p.skinOverrides);
    next['card_radius'] = radius;
    next['pill_radius'] = pill;
    appState.updatePrefs(
      p.copyWith(
        useSkinGeometry: true,
        skinOverrides: next,
      ),
    );
  }

  String _activeCornerBucket(VedroSkin s) {
    final r = s.cardRadius;
    if (r <= 4.5) return 'sharp';
    if (r <= 9.5) return 'cinema';
    if (r <= 16.5) return 'modern';
    return 'pebble';
  }

  @override
  Widget build(BuildContext context) {
    final p = appState.prefs;
    final activeSkin = p.activeSkin;
    final skin = VedroSkin.of(context);
    final hasOverrides = p.skinOverrides.isNotEmpty;

    return Column(
      key: const ValueKey('skin-studio-pane'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.hideHeading)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Wrap(
              spacing: 16,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '皮肤管理与实时预览工坊',
                      style: skin.applyHeadlineMood(
                        TextStyle(
                          color: skin.fg,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '完整吸收 Jellyfin Skin Manager / Ultrachromic / ElegantFin / Scyfin：所见即所得实时预览 14 维布局、统一磨砂材质、画幅、角标与播放器 OSD',
                      style: TextStyle(color: skin.fg3, fontSize: 12.5, height: 1.45),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('import-skin-code-btn'),
                      onPressed: () => _openImportDialog(context),
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: const Text('导入皮肤码'),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('open-diy-skin-editor-btn'),
                      style: FilledButton.styleFrom(
                        backgroundColor: skin.primaryCtaBg,
                        foregroundColor: skin.primaryCtaFg,
                      ),
                      onPressed: () => _openEditor(context, forkFrom: activeSkin),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('新建自定义皮肤'),
                    ),
                  ],
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('import-skin-code-btn'),
                  onPressed: () => _openImportDialog(context),
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('导入皮肤码'),
                ),
                FilledButton.icon(
                  key: const ValueKey('open-diy-skin-editor-btn'),
                  style: FilledButton.styleFrom(
                    backgroundColor: skin.primaryCtaBg,
                    foregroundColor: skin.primaryCtaFg,
                  ),
                  onPressed: () => _openEditor(context, forkFrom: activeSkin),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('新建自定义皮肤'),
                ),
              ],
            ),
          ),

        // 1. LIVE INTERACTIVE CINEMA PREVIEW MONITOR (never guess blindly in Settings!)
        _LiveSkinInteractiveStage(
          key: const ValueKey('skin-live-preview-stage'),
          skin: activeSkin,
          appState: appState,
          scene: _previewScene,
          hasOverrides: hasOverrides,
          onSelectScene: (sc) => setState(() => _previewScene = sc),
          onResetOverrides: () => appState.updatePrefs(p.copyWith(skinOverrides: const {})),
          onSaveAsSkin: () => _openEditor(context, forkFrom: activeSkin),
        ),

        const SizedBox(height: 22),

        // 2. Custom Skins Section (when user has created or imported any)
        if (p.customSkins.isNotEmpty) ...[
          Text(
            '我的专属皮肤 (${p.customSkins.length})',
            style: TextStyle(color: skin.fg2, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (ctx, c) {
              final cols = c.maxWidth >= 860 ? 3 : (c.maxWidth >= 480 ? 2 : 1);
              const gap = 12.0;
              final cardW = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: 12,
                children: p.customSkins.map((spec) {
                  final customSkin = VedroSkin.fromCustom(spec);
                  final selected = p.skinId == spec.id;
                  return SizedBox(
                    width: cardW,
                    child: _SkinPreviewCard(
                      key: ValueKey('skin-custom-${spec.id}'),
                      skinPreview: customSkin,
                      selected: selected,
                      onSelect: () => appState.updatePrefs(
                        p.copyWith(skinId: spec.id, skinOverrides: const {}, useSkinGeometry: true),
                      ),
                      onEdit: () => _openEditor(context, existing: spec),
                      onShare: () {
                        Clipboard.setData(ClipboardData(text: spec.encodeShareCode()));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已复制「${spec.name}」皮肤分享口令到剪贴板')),
                        );
                      },
                      onDelete: () {
                        final remaining = p.customSkins.where((x) => x.id != spec.id).toList();
                        appState.updatePrefs(
                          p.copyWith(
                            customSkins: remaining,
                            skinId: p.skinId == spec.id ? 'obsidian' : p.skinId,
                          ),
                        );
                      },
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 24),
        ],

        // 3. 9 Built-in Structural + Aesthetic Presets
        Row(
          children: [
            Text(
              '官方多架构皮肤预设 (${VedroSkin.presets.length})',
              style: TextStyle(color: skin.fg2, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              '当前：${activeSkin.name}${hasOverrides ? "（已自定义混搭）" : ""}',
              style: TextStyle(color: skin.accent, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (ctx, c) {
            final cols = c.maxWidth >= 860 ? 3 : (c.maxWidth >= 480 ? 2 : 1);
            const gap = 12.0;
            final cardW = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: 12,
              children: VedroSkin.presets.map((preset) {
                final selected = p.skinId == preset.id;
                return SizedBox(
                  width: cardW,
                  child: _SkinPreviewCard(
                    key: ValueKey('skin-preset-${preset.id}'),
                    skinPreview: preset,
                    selected: selected,
                    onSelect: () => appState.updatePrefs(
                      p.copyWith(skinId: preset.id, skinOverrides: const {}, useSkinGeometry: true),
                    ),
                    onFork: () => _openEditor(context, forkFrom: preset),
                  ),
                );
              }).toList(),
            );
          },
        ),

        const SizedBox(height: 26),

        // 4. Complete 14-Dimension Jellyfin Skin Manager Customizer
        VedroAdaptiveSurface(
          key: const ValueKey('skin-modular-addons-panel'),
          padding: const EdgeInsets.all(20),
          borderRadius: skin.cardRadius.clamp(10.0, 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.widgets_outlined, size: 17, color: skin.accent),
                          const SizedBox(width: 7),
                          Text(
                            'Jellyfin 全维度组件与材质混搭台（上方预览窗同步联动）',
                            style: TextStyle(
                              color: skin.fg,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '切换任一参数均保持在当前页面原地生效，不会跳出或重置滚动位置',
                        style: TextStyle(color: skin.fg3, fontSize: 12),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasOverrides)
                        TextButton.icon(
                          onPressed: () =>
                              appState.updatePrefs(p.copyWith(skinOverrides: const {})),
                          icon: const Icon(Icons.restart_alt_rounded, size: 15),
                          label: const Text('重置混搭'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => _openEditor(context, forkFrom: activeSkin),
                        icon: const Icon(Icons.save_outlined, size: 15),
                        label: const Text('另存为新皮肤'),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 18),
              _CategoryBanner(
                icon: Icons.layers_outlined,
                label: '一、导航骨架与表面毛玻璃材质（消除纯色割裂感）',
                skin: skin,
              ),
              const SizedBox(height: 12),

              _ModuleOptionRow(
                title: '导航栏架构',
                subtitle: '切换悬浮顶栏、Scyfin 左侧垂直栏、Ultrachromic 灵动胶囊岛或沉浸自动收纳栏',
                value: activeSkin.navLayout,
                options: const [
                  ('top_floating', '顶部悬浮栏', Icons.web_asset_rounded),
                  ('left_rail', '左侧垂直边栏', Icons.view_sidebar_rounded),
                  ('centered_capsule', '居中灵动胶囊岛', Icons.smart_button_rounded),
                  ('minimal_auto_hide', '沉浸自动半隐顶栏', Icons.visibility_off_outlined),
                ],
                onChanged: (v) => _setOverride('nav_layout', v),
              ),
              const Divider(height: 22),

              _ModuleOptionRow(
                title: '全局表面材质引擎（解决毛玻璃与纯色卡片混搭割裂）',
                subtitle: '控制详情面板、剧集行、版本卡、设置框与背景的融合质感，让卡片与毛玻璃浑然一体',
                value: activeSkin.effectiveSurfaceMaterial,
                options: const [
                  ('unified_glass', '全站统一磨砂琉璃', Icons.blur_circular_rounded),
                  ('tinted_acrylic', '微透亚克力混色', Icons.filter_b_and_w_rounded),
                  ('matte_solid', '温润哑光实色', Icons.rectangle_rounded),
                  ('oled_borderless', '无界暗场隐形框', Icons.border_clear_rounded),
                ],
                onChanged: (v) => _setOverride('surface_material', v),
              ),
              const Divider(height: 22),

              _ModuleOptionRow(
                title: '全局背景氛围引擎',
                subtitle: '纯净画布、双色极光漫反射或全页高斯模糊电影剧照背景',
                value: activeSkin.backdropMode,
                options: const [
                  ('solid_clean', '纯净实色画布', Icons.crop_square_rounded),
                  ('ambient_orb', '双色流光漫反射', Icons.gradient_rounded),
                  ('blurred_fanart', '全页剧照毛玻璃', Icons.deblur_rounded),
                ],
                onChanged: (v) => _setOverride('backdrop_mode', v),
              ),

              if (activeSkin.usesBlurredFanart ||
                  activeSkin.effectiveSurfaceMaterial == 'unified_glass' ||
                  activeSkin.effectiveSurfaceMaterial == 'tinted_acrylic') ...[
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (ctx, c) {
                    final stackSliders = c.maxWidth < 520;
                    final blurCol = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '背景模糊半径：${activeSkin.backdropBlur.round()} px',
                          style: TextStyle(color: skin.fg2, fontSize: 12),
                        ),
                        Slider(
                          value: activeSkin.backdropBlur.clamp(12.0, 60.0),
                          min: 12,
                          max: 60,
                          onChanged: (v) => _setOverride('backdrop_blur', v),
                        ),
                      ],
                    );
                    final alphaCol = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '卡片透光浓度：${(activeSkin.surfaceOpacity * 100).round()}%',
                          style: TextStyle(color: skin.fg2, fontSize: 12),
                        ),
                        Slider(
                          value: activeSkin.surfaceOpacity.clamp(0.45, 0.98),
                          min: 0.45,
                          max: 0.98,
                          onChanged: (v) => _setOverride('surface_opacity', v),
                        ),
                      ],
                    );
                    if (stackSliders) {
                      return Column(children: [blurCol, alphaCol]);
                    }
                    return Row(
                      children: [
                        Expanded(child: blurCol),
                        const SizedBox(width: 16),
                        Expanded(child: alphaCol),
                      ],
                    );
                  },
                ),
              ],

              const SizedBox(height: 16),
              _CategoryBanner(
                icon: Icons.movie_filter_outlined,
                label: '二、首页巨幕舞台与详情页构图（MediaBar / ElegantFin）',
                skin: skin,
              ),
              const SizedBox(height: 12),

              _ModuleOptionRow(
                title: '首页轮播舞台形态',
                subtitle: '全屏沉浸巨幕、ElegantFin 圆角画框、双栏杂志画报或无轮播直达海报墙',
                value: activeSkin.heroStyle,
                options: const [
                  ('full_bleed', '全屏沉浸巨幕', Icons.panorama_wide_angle_select_rounded),
                  ('framed_stage', '圆角悬浮画框', Icons.crop_16_9_rounded),
                  ('split_showcase', '双栏画报橱窗', Icons.vertical_split_rounded),
                  ('compact_minimal', '极简纯海报墙', Icons.apps_rounded),
                ],
                onChanged: (v) => _setOverride('hero_style', v),
              ),
              const Divider(height: 22),

              _ModuleOptionRow(
                title: '详情页构图模式',
                subtitle: '自动同步预览窗「详情与多版本」视图',
                value: activeSkin.detailLayout,
                options: const [
                  ('apple_immersive', '影院沉浸式', Icons.movie_creation_outlined),
                  ('jellyfin_glass', '毛玻璃悬浮仓', Icons.blur_on_rounded),
                  ('centered_editorial', '居中对称画报', Icons.format_align_center_rounded),
                ],
                onChanged: (v) {
                  setState(() => _previewScene = 'detail');
                  _setOverride('detail_layout', v);
                },
              ),
              const Divider(height: 22),

              _ModuleOptionRow(
                title: '演职人员卡片样式',
                subtitle: '切换圆形肖像勋章、Jellyfin 2:3 竖版写真卡或紧凑胶囊名牌',
                value: activeSkin.castStyle,
                options: const [
                  ('circle_medallion', '圆形头像勋章', Icons.account_circle_outlined),
                  ('portrait_card', '2:3 竖版写真卡', Icons.portrait_rounded),
                  ('compact_pill', '紧凑胶囊名牌', Icons.badge_outlined),
                ],
                onChanged: (v) {
                  setState(() => _previewScene = 'detail');
                  _setOverride('cast_style', v);
                },
              ),

              const SizedBox(height: 18),
              _CategoryBanner(
                icon: Icons.style_outlined,
                label: '三、海报画幅、圆角、角标与进度条（Ultrachromic 全套定制）',
                skin: skin,
              ),
              const SizedBox(height: 12),

              _ModuleOptionRow(
                title: '海报墙画幅比例',
                subtitle: '支持经典 2:3 竖版海报、16:9 横版宽幅剧照墙或 4:5 艺术画册比例',
                value: activeSkin.posterAspect,
                options: const [
                  ('poster_2_3', '2:3 竖版海报', Icons.crop_portrait_rounded),
                  ('landscape_16_9', '16:9 横版剧照墙', Icons.crop_16_9_rounded),
                  ('cinema_4_5', '4:5 画册比例', Icons.crop_din_rounded),
                ],
                onChanged: (v) {
                  setState(() => _previewScene = 'home');
                  _setOverride('poster_aspect', v);
                },
              ),
              const Divider(height: 22),

              _ModuleOptionRow(
                title: '海报卡片标题结构',
                subtitle: '经典图下双行字、海报内嵌渐变字、悬停显字或零文字纯海报画廊',
                value: activeSkin.cardStyle,
                options: const [
                  ('classic_below', '经典图下文字', Icons.subtitles_outlined),
                  ('overlay_poster', '海报内嵌渐变字', Icons.branding_watermark_outlined),
                  ('hover_reveal', '悬停浮现文字', Icons.visibility_outlined),
                  ('minimal_clean', '纯净无字画廊', Icons.image_outlined),
                ],
                onChanged: (v) {
                  setState(() => _previewScene = 'home');
                  _setOverride('card_style', v);
                },
              ),
              const Divider(height: 22),

              _ModuleOptionRow(
                title: '海报墙排版密度',
                subtitle: '调节单行容纳的海报数量与间距呼吸感',
                value: p.skinOverrides['grid_density']?.toString() ?? p.listDensity,
                options: const [
                  ('spacious', '画廊宽松大卡', Icons.view_comfortable_rounded),
                  ('comfortable', '标准均衡比例', Icons.grid_view_rounded),
                  ('compact', '发烧友紧凑墙', Icons.view_compact_alt_rounded),
                ],
                onChanged: (v) => _setOverride('grid_density', v),
              ),
              const Divider(height: 22),

              _ModuleOptionRow(
                title: '全局圆角体系预设（Ultrachromic Rounding）',
                subtitle: '一键切换胶片锐角、现代圆角或鹅卵石大圆角',
                value: _activeCornerBucket(activeSkin),
                options: const [
                  ('sharp', '锐利直角 (3px)', Icons.crop_sharp),
                  ('cinema', '影院微圆 (8px)', Icons.rounded_corner_rounded),
                  ('modern', '现代均衡 (14px)', Icons.check_box_outline_blank_rounded),
                  ('pebble', '鹅卵石超圆 (22px)', Icons.circle_outlined),
                ],
                onChanged: (v) {
                  switch (v) {
                    case 'sharp':
                      _applyCornerPreset(3.0, 6.0);
                      break;
                    case 'cinema':
                      _applyCornerPreset(8.0, 10.0);
                      break;
                    case 'modern':
                      _applyCornerPreset(14.0, 999.0);
                      break;
                    case 'pebble':
                      _applyCornerPreset(22.0, 999.0);
                      break;
                  }
                },
              ),
              const Divider(height: 22),

              _ModuleOptionRow(
                title: '未看集数与已看角标样式',
                subtitle: '自定义海报右上角状态指示器风格',
                value: activeSkin.badgeStyle,
                options: const [
                  ('glass_pill', '毛玻璃胶囊', Icons.lens_blur_rounded),
                  ('accent_ribbon', '强调色丝带角标', Icons.bookmark_rounded),
                  ('minimal_dot', '极简发光圆点', Icons.fiber_manual_record_rounded),
                  ('hidden', '纯净隐藏角标', Icons.visibility_off_rounded),
                ],
                onChanged: (v) {
                  setState(() => _previewScene = 'home');
                  _setOverride('badge_style', v);
                },
              ),
              const Divider(height: 22),

              _ModuleOptionRow(
                title: '播放进度条样式',
                subtitle: '控制「继续观看」与海报底部的观看进度条外观',
                value: activeSkin.progressStyle,
                options: const [
                  ('floating_bar', '底部悬浮圆角条', Icons.linear_scale_rounded),
                  ('edge_flush', '贴底满宽极细线', Icons.horizontal_rule_rounded),
                  ('glow_accent', '电光辉光进度条', Icons.bolt_rounded),
                ],
                onChanged: (v) {
                  setState(() => _previewScene = 'home');
                  _setOverride('progress_style', v);
                },
              ),
              const Divider(height: 22),

              _ModuleOptionRow(
                title: '卡片悬停反馈动效',
                subtitle: '鼠标悬停或焦点落上时的动态交互反馈',
                value: activeSkin.cardHoverEffect,
                options: const [
                  ('lift', '弹簧悬浮抬升', Icons.open_in_new_rounded),
                  ('glow_ring', '主题电光环描边', Icons.flare_rounded),
                  ('zoom_art', '内景微距缩放', Icons.zoom_in_rounded),
                ],
                onChanged: (v) => _setOverride('card_hover_effect', v),
              ),

              const SizedBox(height: 18),
              _CategoryBanner(
                icon: Icons.play_circle_outline_rounded,
                label: '四、播放器控制栏（OSD）与品牌排版开关',
                skin: skin,
              ),
              const SizedBox(height: 12),

              _ModuleOptionRow(
                title: '播放器 HUD 控制栏风格',
                subtitle: '自动同步预览窗「播放器 HUD」场景',
                value: activeSkin.osdStyle,
                options: const [
                  ('floating_island', '灵动悬浮控制台', Icons.space_bar_rounded),
                  ('cinema_gradient', '影院全宽底栏', Icons.video_label_rounded),
                  ('minimal_glass', 'Ultrachromic 琉璃舱', Icons.blur_linear_rounded),
                ],
                onChanged: (v) {
                  setState(() => _previewScene = 'player');
                  _setOverride('osd_style', v);
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 5. Typography, Rating Badge & Motion Switches
        VedroAdaptiveSurface(
          borderRadius: skin.cardRadius.clamp(10.0, 18.0),
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  value: activeSkin.showCardRating,
                  onChanged: (v) {
                    setState(() => _previewScene = 'home');
                    _setOverride('show_card_rating', v);
                  },
                  title: Text(
                    '在海报左上角展示 TMDB 评分角标',
                    style: TextStyle(color: skin.fg, fontSize: 13.5, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    '开启后浏览海报墙即可直观看到影片评分',
                    style: TextStyle(color: skin.fg3, fontSize: 12),
                  ),
                ),
                Divider(height: 1, color: skin.border),
                SwitchListTile.adaptive(
                  value: activeSkin.preferClearLogo,
                  onChanged: (v) => _setOverride('prefer_clear_logo', v),
                  title: Text(
                    '优先展示电影/剧集透明艺术片名 (ClearLogo)',
                    style: TextStyle(color: skin.fg, fontSize: 13.5, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    '关闭后统一使用当前皮肤字体排印大标题',
                    style: TextStyle(color: skin.fg3, fontSize: 12),
                  ),
                ),
                Divider(height: 1, color: skin.border),
                SwitchListTile.adaptive(
                  value: activeSkin.editorialSerif,
                  onChanged: (v) => _setOverride('editorial_serif', v),
                  title: Text(
                    '启用电影画报衬线标题字体 (Editorial Serif)',
                    style: TextStyle(color: skin.fg, fontSize: 13.5, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    '为片名与栏目标题启用经典杂志衬线字重',
                    style: TextStyle(color: skin.fg3, fontSize: 12),
                  ),
                ),
                Divider(height: 1, color: skin.border),
                SwitchListTile.adaptive(
                  value: p.reduceMotion,
                  onChanged: (v) => appState.updatePrefs(p.copyWith(reduceMotion: v)),
                  title: Text(
                    '减弱界面动态过渡效果',
                    style: TextStyle(color: skin.fg, fontSize: 13.5, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    '降低页面切换动效幅度以获得更干脆的响应',
                    style: TextStyle(color: skin.fg3, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryBanner extends StatelessWidget {
  const _CategoryBanner({
    required this.icon,
    required this.label,
    required this.skin,
  });

  final IconData icon;
  final String label;
  final VedroSkin skin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: skin.accent.withValues(alpha: skin.isLight ? 0.09 : 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: skin.accent),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: skin.isLight ? skin.fg : Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Real-Time Interactive Cinema Preview Monitor embedded directly inside Settings!
/// Renders live Home / Detail / Player scenes using the exact active `VedroSkin` tokens,
/// real connected media artwork (or rich procedural cinema art), and cohesive material physics.
class _LiveSkinInteractiveStage extends StatefulWidget {
  const _LiveSkinInteractiveStage({
    super.key,
    required this.skin,
    required this.appState,
    required this.scene,
    required this.hasOverrides,
    required this.onSelectScene,
    required this.onResetOverrides,
    required this.onSaveAsSkin,
  });

  final VedroSkin skin;
  final VedroAppState appState;
  final String scene;
  final bool hasOverrides;
  final ValueChanged<String> onSelectScene;
  final VoidCallback onResetOverrides;
  final VoidCallback onSaveAsSkin;

  @override
  State<_LiveSkinInteractiveStage> createState() => _LiveSkinInteractiveStageState();
}

class _LiveSkinInteractiveStageState extends State<_LiveSkinInteractiveStage> {
  int _hoveredPosterIdx = 1;
  int _previewVersionIdx = 0;

  MediaItemModel? _sampleHeroItem() {
    for (final list in [
      widget.appState.popular,
      widget.appState.resume,
      widget.appState.favorites,
    ]) {
      if (list.isNotEmpty) return list.first;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.skin;
    final sample = _sampleHeroItem();
    final heroTitle = sample?.displayName ?? '星际穿越 · Interstellar';
    final fanartUrl = sample != null ? widget.appState.backdropArt(sample)?.url : null;
    final outerR = s.cardRadius.clamp(12.0, 22.0);
    final matLabel = switch (s.effectiveSurfaceMaterial) {
      'unified_glass' => '全站磨砂琉璃',
      'tinted_acrylic' => '微透亚克力',
      'oled_borderless' => '无界隐形框',
      _ => '温润哑光实色',
    };

    return Container(
      decoration: BoxDecoration(
        color: s.unifiedPanelColor,
        borderRadius: BorderRadius.circular(outerR),
        border: Border.all(color: s.accent.withValues(alpha: 0.42), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: s.isLight ? 0.08 : 0.36),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Studio Monitor Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: s.unifiedTileColor(),
              border: Border(bottom: BorderSide(color: s.border, width: 0.7)),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: s.accent, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '实时效果预览窗 · ${s.name}',
                      style: TextStyle(
                        color: s.fg,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: s.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        matLabel,
                        style: TextStyle(
                          color: s.accent,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final tab in const [
                      ('home', '首页舞台', Icons.home_rounded),
                      ('detail', '详情与多版本', Icons.dynamic_feed_rounded),
                      ('player', '播放器 HUD', Icons.play_circle_fill_rounded),
                    ])
                      GestureDetector(
                        key: ValueKey('skin-preview-tab-${tab.$1}'),
                        onTap: () => widget.onSelectScene(tab.$1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: widget.scene == tab.$1 ? s.activePillBg : Colors.transparent,
                            borderRadius: BorderRadius.circular(s.radiusForPill(26)),
                            border: widget.scene == tab.$1
                                ? null
                                : Border.all(color: s.border, width: 0.7),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                tab.$3,
                                size: 13,
                                color: widget.scene == tab.$1 ? s.activePillFg : s.fg2,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                tab.$2,
                                style: TextStyle(
                                  color: widget.scene == tab.$1 ? s.activePillFg : s.fg2,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Live Simulated Cinema Viewport
          SizedBox(
            height: 286,
            child: Theme(
              data: VedroTheme.fromSkin(s),
              child: Builder(
                builder: (innerCtx) => _buildSceneCanvas(innerCtx, s, heroTitle, fanartUrl),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSceneCanvas(
    BuildContext context,
    VedroSkin s,
    String heroTitle,
    String? fanartUrl,
  ) {
    final isLeftRail = s.navLayout == 'left_rail';
    final isCapsule = s.navLayout == 'centered_capsule';

    return DecoratedBox(
      decoration: BoxDecoration(color: s.canvas),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Simulated Backdrop Engine (`solid_clean` | `ambient_orb` | `blurred_fanart`)
          if (s.usesBlurredFanart)
            Positioned.fill(
              child: ClipRect(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: (s.backdropBlur * 0.55).clamp(8.0, 32.0),
                    sigmaY: (s.backdropBlur * 0.55).clamp(8.0, 32.0),
                  ),
                  child: Opacity(
                    opacity: s.isLight ? 0.34 : 0.45,
                    child: fanartUrl != null && fanartUrl.isNotEmpty
                        ? Image.network(
                            fanartUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => GeneratedArt(seed: heroTitle),
                          )
                        : GeneratedArt(seed: heroTitle),
                  ),
                ),
              ),
            )
          else if (s.backdropMode == 'ambient_orb')
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.55, -0.65),
                    radius: 1.3,
                    colors: [
                      s.canvasGlow.withValues(alpha: s.isLight ? 0.52 : 0.42),
                      s.accentSecondary.withValues(alpha: 0.12),
                      s.canvas,
                    ],
                  ),
                ),
              ),
            ),

          if (widget.scene == 'player')
            _buildPlayerOsdPreview(s, heroTitle, fanartUrl)
          else
            Row(
              children: [
                if (isLeftRail)
                  Container(
                    width: 58,
                    decoration: BoxDecoration(
                      color: s.unifiedPanelColor,
                      border: Border(right: BorderSide(color: s.border, width: 0.7)),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    child: Column(
                      children: [
                        const VedroBrandMark(size: 24),
                        const SizedBox(height: 14),
                        for (final ic in [
                          (Icons.home_rounded, true),
                          (Icons.grid_view_rounded, false),
                          (Icons.bookmark_rounded, false),
                          (Icons.tune_rounded, false),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: Container(
                              width: 34,
                              height: 28,
                              decoration: BoxDecoration(
                                color: ic.$2 ? s.activePillBg : Colors.transparent,
                                borderRadius: BorderRadius.circular(s.cardRadius.clamp(4.0, 9.0)),
                              ),
                              child: Icon(
                                ic.$1,
                                size: 15,
                                color: ic.$2 ? s.activePillFg : s.fg3,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            isLeftRail ? 14 : 46,
                            16,
                            12,
                          ),
                          child: widget.scene == 'detail'
                              ? _buildDetailPreview(s, heroTitle)
                              : _buildHomePreview(s, heroTitle, fanartUrl),
                        ),
                      ),
                      if (!isLeftRail)
                        Positioned(
                          top: 8,
                          left: isCapsule ? 48 : 14,
                          right: isCapsule ? 48 : 14,
                          child: Center(
                            child: Container(
                              height: 30,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: isCapsule
                                    ? s.unifiedPanelColor
                                    : (s.navLayout == 'minimal_auto_hide'
                                        ? s.unifiedPanelColor.withValues(alpha: 0.45)
                                        : s.unifiedPanelColor),
                                borderRadius: BorderRadius.circular(
                                  isCapsule ? s.radiusForPill(30) : s.cardRadius.clamp(6.0, 12.0),
                                ),
                                border: s.cardBorder(),
                              ),
                              child: Row(
                                mainAxisSize: isCapsule ? MainAxisSize.min : MainAxisSize.max,
                                children: [
                                  const VedroBrandMark(size: 18),
                                  const SizedBox(width: 8),
                                  for (final item in [('首页', true), ('媒体库', false), ('设置', false)])
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Text(
                                        item.$1,
                                        style: TextStyle(
                                          color: item.$2 ? s.fg : s.fg3,
                                          fontSize: 11,
                                          fontWeight: item.$2 ? FontWeight.w700 : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  if (!isCapsule) const Spacer(),
                                  Icon(Icons.search_rounded, size: 14, color: s.fg2),
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
        ],
      ),
    );
  }

  Widget _buildHomePreview(VedroSkin s, String heroTitle, String? fanartUrl) {
    final cardR = s.cardRadius.clamp(2.0, 22.0);
    final pillR = s.radiusForPill(26);
    final isWideCard = s.posterAspect == 'landscape_16_9';
    final cardW = isWideCard ? 116.0 : (s.posterAspect == 'cinema_4_5' ? 78.0 : 70.0);
    final cardH = isWideCard ? 66.0 : 94.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero Stage Preview (`full_bleed` | `framed_stage` | `split_showcase` | `compact_minimal`)
        if (s.heroStyle != 'compact_minimal')
          Expanded(
            child: Container(
              margin: EdgeInsets.only(bottom: 10, left: s.heroStyle == 'framed_stage' ? 4 : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(
                  s.heroStyle == 'full_bleed' ? 8 : cardR,
                ),
                border: s.heroStyle == 'framed_stage' || s.heroStyle == 'split_showcase'
                    ? s.cardBorder(hovered: true)
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GeneratedArt(seed: '$heroTitle-hero'),
                  if (fanartUrl != null && fanartUrl.isNotEmpty)
                    Image.network(
                      fanartUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          s.canvas.withValues(alpha: s.isLight ? 0.88 : 0.82),
                          s.canvas.withValues(alpha: 0.22),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (s.preferClearLogo) ...[
                                    Icon(Icons.auto_awesome_rounded, size: 14, color: s.accent),
                                    const SizedBox(width: 4),
                                  ],
                                  Flexible(
                                    child: Text(
                                      heroTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: s.applyHeadlineMood(
                                        TextStyle(
                                          color: s.fg,
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Container(
                                height: 24,
                                padding: const EdgeInsets.symmetric(horizontal: 11),
                                decoration: BoxDecoration(
                                  color: s.primaryCtaBg,
                                  gradient: s.primaryCtaGradient,
                                  borderRadius: BorderRadius.circular(pillR),
                                  border: s.primaryCtaBorder,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.play_arrow_rounded, size: 14, color: s.primaryCtaFg),
                                    const SizedBox(width: 3),
                                    Text(
                                      '立即播放',
                                      style: TextStyle(
                                        color: s.primaryCtaFg,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (s.heroStyle == 'split_showcase')
                          Container(
                            width: 58,
                            height: 82,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(cardR * 0.6),
                              border: s.cardBorder(selected: true),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: GeneratedArt(seed: '$heroTitle-poster'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Poster Rail Preview showing live aspect, badges, rating, progress bar & hover effect!
        Text(
          '热门院线 · 悬停卡片体验交互动效',
          style: s.applyHeadlineMood(
            TextStyle(color: s.fg, fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: cardH + (s.cardStyle == 'classic_below' ? 20 : 4),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 5,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, idx) {
              final hovered = _hoveredPosterIdx == idx;
              final titles = const ['沙丘 2', '奥本海默', '银翼杀手 2049', '盗梦空间', '蜘蛛侠：纵横宇宙'];
              final ratings = const ['8.8', '8.9', '8.6', '9.1', '8.7'];
              return MouseRegion(
                onEnter: (_) => setState(() => _hoveredPosterIdx = idx),
                child: AnimatedScale(
                  scale: hovered && s.cardHoverEffect == 'lift' ? 1.04 : 1.0,
                  duration: const Duration(milliseconds: 160),
                  child: SizedBox(
                    width: cardW,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: cardW,
                          height: cardH,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(cardR * 0.72),
                            boxShadow: s.posterShadow(hovered: hovered),
                          ),
                          foregroundDecoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(cardR * 0.72),
                            border: s.cardBorder(hovered: hovered),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              AnimatedScale(
                                scale: hovered && s.cardHoverEffect == 'zoom_art' ? 1.08 : 1.0,
                                duration: const Duration(milliseconds: 200),
                                child: GeneratedArt(
                                  seed: 'preview-card-$idx',
                                ),
                              ),
                              if (s.cardStyle == 'overlay_poster' ||
                                  (s.cardStyle == 'hover_reveal' && hovered))
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.fromLTRB(6, 14, 6, 5),
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [Colors.transparent, Color(0xE605060A)],
                                      ),
                                    ),
                                    child: Text(
                                      titles[idx],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              if (s.badgeStyle != 'hidden' && s.showCardRating)
                                Positioned(
                                  top: 4,
                                  left: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xAA09090B),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.star_rounded,
                                          size: 10,
                                          color: Color(0xFFFBBF24),
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          ratings[idx],
                                          style: const TextStyle(
                                            color: Color(0xFFFBBF24),
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (s.badgeStyle != 'hidden' && idx < 2)
                                Positioned(
                                  top: s.badgeStyle == 'accent_ribbon' ? 0 : 4,
                                  right: s.badgeStyle == 'accent_ribbon' ? 0 : 4,
                                  child: s.badgeStyle == 'minimal_dot'
                                      ? Container(
                                          width: 7,
                                          height: 7,
                                          decoration: BoxDecoration(
                                            color: s.accent,
                                            shape: BoxShape.circle,
                                          ),
                                        )
                                      : Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4.5,
                                            vertical: 1.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: s.badgeStyle == 'accent_ribbon'
                                                ? s.accent
                                                : const Color(0xAA09090B),
                                            borderRadius: s.badgeStyle == 'accent_ribbon'
                                                ? const BorderRadius.only(
                                                    bottomLeft: Radius.circular(6),
                                                  )
                                                : BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            idx == 0 ? '3' : '✓',
                                            style: TextStyle(
                                              color: s.badgeStyle == 'accent_ribbon'
                                                  ? highContrastOn(s.accent)
                                                  : Colors.white,
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                ),
                              if (idx == 0)
                                Positioned(
                                  left: s.progressStyle == 'edge_flush' ? 0 : 5,
                                  right: s.progressStyle == 'edge_flush' ? 0 : 5,
                                  bottom: s.progressStyle == 'edge_flush' ? 0 : 4,
                                  child: Container(
                                    decoration: s.progressStyle == 'glow_accent'
                                        ? BoxDecoration(
                                            boxShadow: [
                                              BoxShadow(
                                                color: s.accent.withValues(alpha: 0.8),
                                                blurRadius: 6,
                                              ),
                                            ],
                                          )
                                        : null,
                                    child: LinearProgressIndicator(
                                      value: 0.62,
                                      minHeight: 2.8,
                                      backgroundColor: const Color(0x44FFFFFF),
                                      color: s.accent,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (s.cardStyle == 'classic_below') ...[
                          const SizedBox(height: 4),
                          Text(
                            titles[idx],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: s.fg,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDetailPreview(VedroSkin s, String heroTitle) {
    final isCentered = s.detailLayout == 'centered_editorial';
    final isGlass = s.detailLayout == 'jellyfin_glass';
    final r = s.cardRadius.clamp(6.0, 18.0);

    final versions = const [
      ('4K DoVi · TrueHD Atmos', ['国语配音 5.1', '英语全景声'], ['简英特效 ASS', '繁体中文']),
      ('1080p BluRay · 国粤双语', ['粤语原声 FLAC', '国语配音'], ['粤语字幕 SRT']),
    ];
    final activeV = versions[_previewVersionIdx];

    return Column(
      crossAxisAlignment: isCentered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        // Hero Card (harmonized with `VedroAdaptiveSurface`!)
        Container(
          padding: EdgeInsets.all(isGlass ? 11 : 4),
          decoration: isGlass
              ? BoxDecoration(
                  color: s.unifiedPanelColor,
                  borderRadius: BorderRadius.circular(r),
                  border: s.cardBorder(),
                )
              : null,
          child: Row(
            mainAxisAlignment: isCentered ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 66,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(r * 0.55),
                  border: s.cardBorder(),
                ),
                clipBehavior: Clip.antiAlias,
                child: GeneratedArt(seed: '$heroTitle-cov'),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment:
                      isCentered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                  children: [
                    Text(
                      heroTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: s.applyHeadlineMood(
                        TextStyle(color: s.fg, fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '2024 · 科幻 / 冒险 · ',
                          style: TextStyle(color: s.fg2, fontSize: 10.5),
                        ),
                        const Icon(Icons.star_rounded, size: 11.5, color: Color(0xFFFBBF24)),
                        const SizedBox(width: 2),
                        Text(
                          '8.9 · 4K 杜比视界',
                          style: TextStyle(color: s.fg2, fontSize: 10.5),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Harmonized Multi-Version & Track Panel Preview (interactive!)
        Expanded(
          child: VedroAdaptiveSurface(
            padding: const EdgeInsets.all(10),
            borderRadius: r,
            blurSigma: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    for (var i = 0; i < versions.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _previewVersionIdx = i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                            decoration: BoxDecoration(
                              color: s.unifiedTileColor(selected: _previewVersionIdx == i),
                              borderRadius: BorderRadius.circular(r * 0.55),
                              border: s.cardBorder(selected: _previewVersionIdx == i),
                            ),
                            child: Text(
                              '版本 ${i + 1}：${versions[i].$1}',
                              style: TextStyle(
                                color: _previewVersionIdx == i ? s.fg : s.fg2,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('音轨/字幕：', style: TextStyle(color: s.fg3, fontSize: 10.5)),
                    for (final a in activeV.$2)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: a == activeV.$2.first ? s.activePillBg : s.unifiedTileColor(),
                          borderRadius: BorderRadius.circular(s.radiusForPill(20)),
                        ),
                        child: Text(
                          a,
                          style: TextStyle(
                            color: a == activeV.$2.first ? s.activePillFg : s.fg2,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    for (final sub in activeV.$3)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: s.unifiedTileColor(),
                          borderRadius: BorderRadius.circular(s.radiusForPill(20)),
                        ),
                        child: Text(sub, style: TextStyle(color: s.fg2, fontSize: 10)),
                      ),
                  ],
                ),
                // Cast style mini-row
                Row(
                  children: [
                    Text('演职员：', style: TextStyle(color: s.fg3, fontSize: 10.5)),
                    const SizedBox(width: 6),
                    for (final actor in const ['马修·麦康纳', '安妮·海瑟薇', '杰西卡·查斯坦'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: s.unifiedTileColor(),
                            borderRadius: BorderRadius.circular(
                              s.castStyle == 'circle_medallion'
                                  ? 99
                                  : (s.castStyle == 'portrait_card' ? 6 : 99),
                            ),
                            border: s.cardBorder(),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: s.castStyle == 'portrait_card' ? 11 : 13,
                                height: s.castStyle == 'portrait_card' ? 15 : 13,
                                decoration: BoxDecoration(
                                  color: s.accent.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(
                                    s.castStyle == 'portrait_card' ? 3 : 99,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(actor, style: TextStyle(color: s.fg, fontSize: 10)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerOsdPreview(VedroSkin s, String heroTitle, String? fanartUrl) {
    final osd = s.osdStyle;
    final isFull = osd == 'cinema_gradient';
    final isMinimalGlass = osd == 'minimal_glass';

    return Stack(
      fit: StackFit.expand,
      children: [
        GeneratedArt(seed: '$heroTitle-frame'),
        if (fanartUrl != null && fanartUrl.isNotEmpty)
          Image.network(
            fanartUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(color: Color(0x40000000)),
        ),
        Positioned(
          top: 14,
          left: 16,
          child: GlassSurface(
            borderRadius: 99,
            blur: 20,
            color: const Color(0xAA0C0F18),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              '$heroTitle · 4K DoVi · TrueHD Atmos',
              style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        Positioned(
          left: isFull ? 0 : (isMinimalGlass ? 64 : 28),
          right: isFull ? 0 : (isMinimalGlass ? 64 : 28),
          bottom: isFull ? 0 : 16,
          child: GlassSurface(
            borderRadius: isFull ? 0 : (isMinimalGlass ? 26 : s.cardRadius.clamp(12.0, 22.0)),
            blur: isFull ? 12 : 34,
            color: isFull
                ? const Color(0xE807080D)
                : (isMinimalGlass
                    ? Color.lerp(const Color(0xAA0B101D), s.accent, 0.14)!
                    : const Color(0xCC11131B)),
            borderColor: isMinimalGlass
                ? s.accent.withValues(alpha: 0.38)
                : const Color(0x28FFFFFF),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text('00:42:18', style: TextStyle(color: Colors.white70, fontSize: 10.5)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: 0.44,
                          minHeight: 4,
                          backgroundColor: const Color(0x38FFFFFF),
                          color: s.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text('-01:26:40', style: TextStyle(color: Colors.white70, fontSize: 10.5)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0x24FFFFFF),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Text('1.0×', style: TextStyle(color: Colors.white, fontSize: 10.5)),
                    ),
                    const Spacer(),
                    const Icon(Icons.replay_10_rounded, size: 18, color: Colors.white70),
                    const SizedBox(width: 12),
                    Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.pause_rounded, size: 18, color: Color(0xFF09090B)),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.forward_10_rounded, size: 18, color: Colors.white70),
                    const Spacer(),
                    for (final b in const ['弹幕', '字幕', '音轨'])
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0x22FFFFFF),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(b, style: const TextStyle(color: Colors.white, fontSize: 10)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ModuleOptionRow extends StatelessWidget {
  const _ModuleOptionRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final String value;
  final List<(String id, String label, IconData icon)> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(color: skin.fg, fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(color: skin.fg3, fontSize: 11.5)),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((opt) {
            final selected = value == opt.$1;
            return PressableScale(
              key: ValueKey('skin-mod-${opt.$1}'),
              onTap: () => onChanged(opt.$1),
              hoverScale: 1.02,
              pressScale: 0.97,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: VedroTheme.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
                decoration: BoxDecoration(
                  color: selected ? skin.activePillBg : skin.unifiedTileColor(),
                  borderRadius: BorderRadius.circular(skin.radiusForPill(34)),
                  border: (!selected && skin.frameStyle != 'borderless')
                      ? Border.all(color: skin.border, width: 0.75)
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      opt.$3,
                      size: 14.5,
                      color: selected ? skin.activePillFg : skin.fg2,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      opt.$2,
                      style: TextStyle(
                        color: selected ? skin.activePillFg : skin.fg2,
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// Miniature live-rendered preview card depicting each skin's ACTUAL structural silhouette.
class _SkinPreviewCard extends StatefulWidget {
  const _SkinPreviewCard({
    super.key,
    required this.skinPreview,
    required this.selected,
    required this.onSelect,
    this.onFork,
    this.onEdit,
    this.onShare,
    this.onDelete,
  });

  final VedroSkin skinPreview;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onFork;
  final VoidCallback? onEdit;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;

  @override
  State<_SkinPreviewCard> createState() => _SkinPreviewCardState();
}

class _SkinPreviewCardState extends State<_SkinPreviewCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hostSkin = VedroSkin.of(context);
    final s = widget.skinPreview;
    final outerR = hostSkin.cardRadius.clamp(10.0, 18.0);
    final miniCardR = s.cardRadius.clamp(3.0, 10.0);
    final miniPillR = s.radiusForPill(20);
    final isLeftRail = s.navLayout == 'left_rail';
    final isCapsuleNav = s.navLayout == 'centered_capsule';

    return PressableScale(
      onTap: widget.onSelect,
      onHoverChanged: (v) => setState(() => _hovered = v),
      hoverScale: 1.015,
      pressScale: 0.98,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: VedroTheme.easeOut,
        decoration: BoxDecoration(
          color: hostSkin.unifiedPanelColor,
          borderRadius: BorderRadius.circular(outerR),
          border: Border.all(
            color: widget.selected
                ? hostSkin.accent
                : (_hovered ? hostSkin.borderStrong : hostSkin.border),
            width: widget.selected ? 1.6 : 0.85,
          ),
          boxShadow: widget.selected
              ? [
                  BoxShadow(
                    color: hostSkin.accent.withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 114,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: s.canvas,
                  gradient: s.ambientGlow || s.usesBlurredFanart
                      ? RadialGradient(
                          center: const Alignment(-0.55, -0.7),
                          radius: 1.35,
                          colors: [
                            s.canvasGlow.withValues(alpha: s.isLight ? 0.55 : 0.50),
                            s.canvas,
                          ],
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    if (isLeftRail)
                      Container(
                        width: 22,
                        decoration: BoxDecoration(
                          color: s.unifiedPanelColor,
                          border: Border(right: BorderSide(color: s.border, width: 0.6)),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: s.accent,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(height: 6),
                            for (var k = 0; k < 3; k++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 5),
                                child: Container(
                                  width: 11,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: k == 0 ? s.fg : s.fg3.withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: s.unifiedTileColor(),
                                    borderRadius: BorderRadius.circular(isCapsuleNav ? 99 : 4),
                                    border: isCapsuleNav
                                        ? Border.all(color: s.borderStrong, width: 0.6)
                                        : null,
                                  ),
                                  child: Text(
                                    s.badge,
                                    style: TextStyle(
                                      color: isCapsuleNav ? s.accent : s.fg2,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                if (widget.selected)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: s.activePillBg,
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: Text(
                                      '使用中',
                                      style: TextStyle(
                                        color: s.activePillFg,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const Spacer(),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: s.heroStyle == 'framed_stage'
                                        ? const EdgeInsets.all(6)
                                        : EdgeInsets.zero,
                                    decoration: s.heroStyle == 'framed_stage'
                                        ? BoxDecoration(
                                            color: s.unifiedPanelColor,
                                            borderRadius: BorderRadius.circular(miniCardR),
                                            border: s.cardBorder(),
                                          )
                                        : null,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Vedro',
                                          style: s.applyHeadlineMood(
                                            TextStyle(
                                              color: s.fg,
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          height: 19,
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                          decoration: BoxDecoration(
                                            color: s.primaryCtaBg,
                                            gradient: s.primaryCtaGradient,
                                            borderRadius: BorderRadius.circular(miniPillR),
                                            border: s.primaryCtaBorder,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.play_arrow_rounded, size: 11, color: s.primaryCtaFg),
                                              const SizedBox(width: 2),
                                              Text(
                                                '播放',
                                                style: TextStyle(
                                                  color: s.primaryCtaFg,
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 7),
                                for (var idx = 0; idx < 2; idx++)
                                  Padding(
                                    padding: EdgeInsets.only(left: idx == 0 ? 0 : 5),
                                    child: Container(
                                      width: 27,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(miniCardR),
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: idx == 0
                                              ? [s.surface3, s.surface]
                                              : [s.accent.withValues(alpha: 0.42), s.surface2],
                                        ),
                                        border: s.cardBorder(hovered: idx == 1),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: hostSkin.fg,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: hostSkin.fg3, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onFork != null)
                    Tooltip(
                      message: '以此皮肤为模板深度定制',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: widget.onFork,
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: Icon(Icons.tune_rounded, size: 15, color: hostSkin.fg3),
                        ),
                      ),
                    ),
                  if (widget.onEdit != null)
                    Tooltip(
                      message: '编辑皮肤',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: widget.onEdit,
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: Icon(Icons.edit_outlined, size: 15, color: hostSkin.fg2),
                        ),
                      ),
                    ),
                  if (widget.onShare != null)
                    Tooltip(
                      message: '复制皮肤分享码',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: widget.onShare,
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: Icon(Icons.ios_share_rounded, size: 15, color: hostSkin.fg2),
                        ),
                      ),
                    ),
                  if (widget.onDelete != null)
                    Tooltip(
                      message: '删除此皮肤',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: widget.onDelete,
                        child: const Padding(
                          padding: EdgeInsets.all(5),
                          child: Icon(Icons.delete_outline_rounded, size: 15, color: VedroTheme.danger),
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

/// Full DIY Skin Studio Dialog with Structural Layout + Material + HSV Color Spectrum + Live Preview.
class _CustomSkinEditorDialog extends StatefulWidget {
  const _CustomSkinEditorDialog({required this.initial});
  final CustomSkinSpec initial;

  @override
  State<_CustomSkinEditorDialog> createState() => _CustomSkinEditorDialogState();
}

class _CustomSkinEditorDialogState extends State<_CustomSkinEditorDialog> {
  late CustomSkinSpec _spec;
  late final TextEditingController _nameCtrl;
  String _editingColorSlot = 'accent';

  static const _swatches = <String>[
    '#09090B', '#06101E', '#080514', '#120E0B', '#06130F', '#14060A',
    '#F2F4F8', '#F7F2E7', '#EEF5F0', '#FFF7ED',
    '#38BDF8', '#0A84FF', '#818CF8', '#A855F7', '#F43F5E', '#FB7185',
    '#E5A93C', '#C25E28', '#34D399', '#14B8A6', '#F97316', '#EAB308',
  ];

  @override
  void initState() {
    super.initState();
    _spec = widget.initial;
    _nameCtrl = TextEditingController(text: _spec.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Color _currentSlotColor(VedroSkin live) {
    switch (_editingColorSlot) {
      case 'canvas':
        return live.canvas;
      case 'surface':
        return live.surface;
      case 'accent2':
        return live.accentSecondary;
      case 'accent':
      default:
        return live.accent;
    }
  }

  void _updateSlotHex(String hex) {
    setState(() {
      switch (_editingColorSlot) {
        case 'canvas':
          _spec = _spec.copyWith(canvasHex: hex);
          break;
        case 'surface':
          _spec = _spec.copyWith(surfaceHex: hex);
          break;
        case 'accent2':
          _spec = _spec.copyWith(accentSecondaryHex: hex);
          break;
        case 'accent':
        default:
          _spec = _spec.copyWith(accentHex: hex);
          break;
      }
    });
  }

  Widget _chipPicker(
    VedroSkin host,
    VedroSkin live,
    String label,
    String current,
    List<(String, String)> opts,
    ValueChanged<String> onPick,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: host.fg2, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: opts.map((o) {
              final on = current == o.$1;
              return GestureDetector(
                onTap: () => setState(() => onPick(o.$1)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: on ? live.accent : host.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: on ? live.accent : host.border),
                  ),
                  child: Text(
                    o.$2,
                    style: TextStyle(
                      color: on ? VedroTheme.highContrastOn(live.accent) : host.fg2,
                      fontSize: 12,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hostSkin = VedroSkin.of(context);
    final liveSkin = VedroSkin.fromCustom(_spec.copyWith(name: _nameCtrl.text));
    final activeColor = _currentSlotColor(liveSkin);
    final hsv = HSVColor.fromColor(activeColor);

    return Dialog(
      backgroundColor: hostSkin.surface2,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: hostSkin.borderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 780),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.palette_outlined, size: 20, color: liveSkin.accent),
                  const SizedBox(width: 9),
                  Text(
                    '全维度皮肤创作工坊',
                    style: TextStyle(
                      color: hostSkin.fg,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: hostSkin.fg2),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: hostSkin.border),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SkinPreviewCard(
                      skinPreview: liveSkin,
                      selected: true,
                      onSelect: () {},
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _nameCtrl,
                            onChanged: (v) => setState(() => _spec = _spec.copyWith(name: v)),
                            style: TextStyle(color: hostSkin.fg, fontSize: 14),
                            decoration: const InputDecoration(labelText: '皮肤名称'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('深色')),
                            ButtonSegment(value: true, label: Text('浅色')),
                          ],
                          selected: {_spec.isLight},
                          onSelectionChanged: (s) {
                            final toLight = s.first;
                            setState(() {
                              _spec = _spec.copyWith(
                                isLight: toLight,
                                canvasHex: toLight ? '#F4F6FA' : '#0B1020',
                                surfaceHex: '',
                              );
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _chipPicker(
                      hostSkin,
                      liveSkin,
                      '导航栏架构',
                      _spec.navLayout,
                      const [
                        ('top_floating', '顶部悬浮栏'),
                        ('left_rail', '左侧垂直边栏'),
                        ('centered_capsule', '居中胶囊岛'),
                        ('minimal_auto_hide', '自动半隐顶栏'),
                      ],
                      (v) => _spec = _spec.copyWith(navLayout: v),
                    ),
                    _chipPicker(
                      hostSkin,
                      liveSkin,
                      '表面材质引擎',
                      liveSkin.effectiveSurfaceMaterial,
                      const [
                        ('unified_glass', '统一磨砂琉璃'),
                        ('tinted_acrylic', '微透亚克力'),
                        ('matte_solid', '温润哑光实色'),
                        ('oled_borderless', '无界隐形框'),
                      ],
                      (v) => _spec = _spec.copyWith(surfaceMaterial: v),
                    ),
                    _chipPicker(
                      hostSkin,
                      liveSkin,
                      '首页轮播舞台',
                      _spec.heroStyle,
                      const [
                        ('full_bleed', '全屏巨幕'),
                        ('framed_stage', '圆角画框 (ElegantFin)'),
                        ('split_showcase', '双栏杂志橱窗'),
                        ('compact_minimal', '极简无轮播'),
                      ],
                      (v) => _spec = _spec.copyWith(heroStyle: v),
                    ),
                    _chipPicker(
                      hostSkin,
                      liveSkin,
                      '海报画幅与标题结构',
                      _spec.cardStyle,
                      const [
                        ('classic_below', '图下标题'),
                        ('overlay_poster', '内嵌渐变字'),
                        ('hover_reveal', '悬停显字'),
                        ('minimal_clean', '纯净无字'),
                      ],
                      (v) => _spec = _spec.copyWith(cardStyle: v),
                    ),
                    _chipPicker(
                      hostSkin,
                      liveSkin,
                      '主按钮风格',
                      _spec.ctaStyle,
                      const [
                        ('contrast', '黑白高反差'),
                        ('accent', '主题强调色'),
                        ('gradient', '双色电光渐变'),
                        ('outline', '极简线框'),
                      ],
                      (v) => _spec = _spec.copyWith(ctaStyle: v),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '色彩光谱调配',
                      style: TextStyle(color: hostSkin.fg2, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final slot in [
                          ('accent', '主强调色', liveSkin.accent),
                          ('accent2', '副渐变色', liveSkin.accentSecondary),
                          ('canvas', '画布背景', liveSkin.canvas),
                          ('surface', '卡片底色', liveSkin.surface),
                        ])
                          GestureDetector(
                            onTap: () => setState(() => _editingColorSlot = slot.$1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                              decoration: BoxDecoration(
                                color: _editingColorSlot == slot.$1 ? hostSkin.surface3 : hostSkin.surface,
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                  color: _editingColorSlot == slot.$1 ? liveSkin.accent : hostSkin.border,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: slot.$3,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white30),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(slot.$2, style: TextStyle(color: hostSkin.fg, fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: _swatches.map((hex) {
                        final col = VedroSkin.parseHex(hex, Colors.blue);
                        return GestureDetector(
                          onTap: () => _updateSlotHex(hex),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: col,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white38, width: 0.8),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    Slider(
                      value: hsv.hue.clamp(0.0, 360.0),
                      min: 0,
                      max: 360,
                      onChanged: (h) =>
                          _updateSlotHex(VedroSkin.colorToHex(hsv.withHue(h).toColor())),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: hostSkin.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    key: const ValueKey('save-diy-skin-btn'),
                    style: FilledButton.styleFrom(
                      backgroundColor: liveSkin.primaryCtaBg,
                      foregroundColor: liveSkin.primaryCtaFg,
                    ),
                    onPressed: () {
                      final finalName =
                          _nameCtrl.text.trim().isEmpty ? '我的专属皮肤' : _nameCtrl.text.trim();
                      Navigator.pop(context, _spec.copyWith(name: finalName));
                    },
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('保存并启用皮肤'),
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
