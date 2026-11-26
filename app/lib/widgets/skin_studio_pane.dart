import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import 'vedro_ui.dart';

/// Jellyfin Skin Manager (`Ultrachromic` / `ElegantFin` / `Scyfin`) caliber Skin Store & Modular Layout Studio.
/// Lets users switch between 9 structurally distinct skins, tweak live structural addons (navigation layout,
/// hero stage, detail page composition, full-page fanart blur, poster card anatomy, hover effects, cast style),
/// author full custom skins from scratch or templates, and share `VEDRO-SKIN:...` codes.
class SkinStudioPane extends StatelessWidget {
  const SkinStudioPane({
    super.key,
    required this.appState,
    this.hideHeading = false,
  });

  final VedroAppState appState;
  final bool hideHeading;

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
          cardStyle: 'overlay_poster',
          cardHoverEffect: 'glow_ring',
          castStyle: 'portrait_card',
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
                  '粘贴好友分享或跨设备导出的 VEDRO-SKIN:... 皮肤码（包含完整导航布局、轮播样式、卡片结构与配色）：',
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
        if (!hideHeading)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '皮肤管理与模块化布局工坊',
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
                  '参考 Jellyfin Skin Manager / Ultrachromic / ElegantFin / Scyfin：不仅切换色彩，更可自由组合导航栏位置、首页轮播形态、详情页毛玻璃构图、海报卡片结构与演员卡样式',
                  style: TextStyle(color: skin.fg3, fontSize: 13, height: 1.45),
                ),
              ],
            ),
          ),

        // 1. Top DIY Banner CTA: Create or Import Custom Skin
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: skin.panelSurface,
            borderRadius: BorderRadius.circular(skin.cardRadius.clamp(10.0, 20.0)),
            border: Border.all(color: skin.borderStrong, width: 0.9),
          ),
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 470),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_fix_high_rounded, size: 17, color: skin.accent),
                        const SizedBox(width: 7),
                        Text(
                          '自定义皮肤工坊',
                          style: TextStyle(
                            color: skin.fg,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: skin.accent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'SKIN MANAGER',
                            style: TextStyle(
                              color: skin.accent,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '支持自由拼装「左侧栏 / 灵动胶囊岛 / 悬浮顶栏」「悬浮画框 / 双栏橱窗 / 全屏巨幕」「全页剧照毛玻璃」「海报内嵌渐变字 / 纯图悬停显字」及完整配色口令分享。',
                      style: TextStyle(color: skin.fg2, fontSize: 12.5, height: 1.45),
                    ),
                  ],
                ),
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
              final cols = c.maxWidth >= 760 ? 3 : (c.maxWidth >= 480 ? 2 : 1);
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
              '官方多架构皮肤库 (${VedroSkin.presets.length})',
              style: TextStyle(color: skin.fg2, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              '当前：${activeSkin.name}${hasOverrides ? "（已微调模块）" : ""}',
              style: TextStyle(color: skin.accent, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (ctx, c) {
            final cols = c.maxWidth >= 760 ? 3 : (c.maxWidth >= 480 ? 2 : 1);
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

        const SizedBox(height: 28),

        // 4. Jellyfin Skin Manager Style Live Modular Customizer!
        Container(
          key: const ValueKey('skin-modular-addons-panel'),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: skin.panelSurface,
            borderRadius: BorderRadius.circular(skin.cardRadius.clamp(10.0, 20.0)),
            border: skin.cardBorder(),
          ),
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
                            '模块化布局与组件自定义（实时生效）',
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
                        '在当前皮肤之上单独混搭导航栏位置、轮播构图、详情页毛玻璃、海报卡片解剖与演员卡样式',
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
                          label: const Text('恢复该皮肤默认'),
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

              _ModuleOptionRow(
                title: '导航栏架构',
                subtitle: '切换全站顶栏、左侧垂直边栏（Scyfin/Plex）或居中灵动胶囊岛',
                value: activeSkin.navLayout,
                options: const [
                  ('top_floating', '顶部悬浮栏', Icons.web_asset_rounded),
                  ('left_rail', '左侧垂直边栏', Icons.view_sidebar_rounded),
                  ('centered_capsule', '居中灵动胶囊岛', Icons.smart_button_rounded),
                ],
                onChanged: (v) => _setOverride('nav_layout', v),
              ),
              const Divider(height: 22),

              _ModuleOptionRow(
                title: '首页轮播舞台形态',
                subtitle: '全屏巨幕、ElegantFin 圆角画框、双栏杂志橱窗或无轮播直达海报墙',
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
                subtitle: 'Apple TV+ 沉浸式、Ultrachromic 毛玻璃悬浮卡片或居中对称画报式',
                value: activeSkin.detailLayout,
                options: const [
                  ('apple_immersive', '影院沉浸式', Icons.movie_creation_outlined),
                  ('jellyfin_glass', '毛玻璃悬浮卡片', Icons.blur_on_rounded),
                  ('centered_editorial', '居中对称画报', Icons.format_align_center_rounded),
                ],
                onChanged: (v) => _setOverride('detail_layout', v),
              ),
              const Divider(height: 22),

              _ModuleOptionRow(
                title: '全局背景氛围引擎',
                subtitle: '开启「全页剧照毛玻璃」后，首页与详情页滚动全程呈现高斯模糊电影背景',
                value: activeSkin.backdropMode,
                options: const [
                  ('solid_clean', '纯净实色画布', Icons.crop_square_rounded),
                  ('ambient_orb', '双色流光漫反射', Icons.gradient_rounded),
                  ('blurred_fanart', '全页剧照毛玻璃', Icons.deblur_rounded),
                ],
                onChanged: (v) => _setOverride('backdrop_mode', v),
              ),

              if (activeSkin.usesBlurredFanart || activeSkin.detailLayout == 'jellyfin_glass') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
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
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '毛玻璃卡片不透明度：${(activeSkin.surfaceOpacity * 100).round()}%',
                            style: TextStyle(color: skin.fg2, fontSize: 12),
                          ),
                          Slider(
                            value: activeSkin.surfaceOpacity.clamp(0.50, 0.98),
                            min: 0.50,
                            max: 0.98,
                            onChanged: (v) => _setOverride('surface_opacity', v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              const Divider(height: 22),

              _ModuleOptionRow(
                title: '海报卡片文字结构',
                subtitle: '经典图下标题、ElegantFin 海报内嵌渐变标题或纯海报悬停浮现',
                value: activeSkin.cardStyle,
                options: const [
                  ('classic_below', '经典图下文字', Icons.subtitles_outlined),
                  ('overlay_poster', '海报内嵌渐变字', Icons.branding_watermark_outlined),
                  ('hover_reveal', '纯海报悬停显字', Icons.visibility_outlined),
                ],
                onChanged: (v) => _setOverride('card_style', v),
              ),
              const Divider(height: 22),

              _ModuleOptionRow(
                title: '海报悬停动效',
                subtitle: '控制鼠标悬停或聚焦卡片时的交互反馈',
                value: activeSkin.cardHoverEffect,
                options: const [
                  ('lift', '轻盈悬浮抬升', Icons.open_in_new_rounded),
                  ('glow_ring', '主题色电光环', Icons.flare_rounded),
                  ('zoom_art', '内景微距缩放', Icons.zoom_in_rounded),
                ],
                onChanged: (v) => _setOverride('card_hover_effect', v),
              ),
              const Divider(height: 22),

              _ModuleOptionRow(
                title: '演职人员展示形态',
                subtitle: '切换圆形肖像勋章、Jellyfin 2:3 竖版写真卡或紧凑胶囊名牌',
                value: activeSkin.castStyle,
                options: const [
                  ('circle_medallion', '圆形头像勋章', Icons.account_circle_outlined),
                  ('portrait_card', '2:3 竖版写真卡', Icons.portrait_rounded),
                  ('compact_pill', '紧凑胶囊名牌', Icons.badge_outlined),
                ],
                onChanged: (v) => _setOverride('cast_style', v),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // 5. Typography, Geometry & Motion Switches
        Container(
          decoration: BoxDecoration(
            color: skin.panelSurface,
            borderRadius: BorderRadius.circular(skin.cardRadius.clamp(10.0, 18.0)),
            border: skin.cardBorder(),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
              SwitchListTile.adaptive(
                value: activeSkin.preferClearLogo,
                onChanged: (v) => _setOverride('prefer_clear_logo', v),
                title: Text(
                  '优先展示电影/剧集透明艺术 Logo (ClearLogo)',
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
                  '使用电影画报衬线标题字体 (Editorial Serif)',
                  style: TextStyle(color: skin.fg, fontSize: 13.5, fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  '为片名与栏目标题启用经典杂志衬线字重',
                  style: TextStyle(color: skin.fg3, fontSize: 12),
                ),
              ),
              Divider(height: 1, color: skin.border),
              SwitchListTile.adaptive(
                value: p.useSkinGeometry,
                onChanged: (v) => appState.updatePrefs(p.copyWith(useSkinGeometry: v)),
                title: Text(
                  '跟随所选皮肤的专属圆角与几何造型',
                  style: TextStyle(color: skin.fg, fontSize: 13.5, fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  '开启时胶片风呈 5px 画框、赛博风呈 6px 切角、丝绒风呈 20px 圆弧；关闭则统一手动指定圆角',
                  style: TextStyle(color: skin.fg3, fontSize: 12),
                ),
              ),
              if (!p.useSkinGeometry) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Row(
                    children: [
                      Text('全局统一圆角', style: TextStyle(color: skin.fg2, fontSize: 12.5)),
                      Expanded(
                        child: Slider(
                          value: p.cardRadius.clamp(0.0, 26.0),
                          min: 0,
                          max: 26,
                          divisions: 26,
                          onChanged: (v) => appState.updatePrefs(p.copyWith(cardRadius: v)),
                        ),
                      ),
                      Text(
                        '${p.cardRadius.round()} px',
                        style: TextStyle(color: skin.fg, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
              Divider(height: 1, color: skin.border),
              SwitchListTile.adaptive(
                value: p.reduceMotion,
                onChanged: (v) => appState.updatePrefs(p.copyWith(reduceMotion: v)),
                title: Text(
                  '减弱动态效果',
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
                  color: selected ? skin.activePillBg : skin.surface2,
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

/// Miniature live-rendered preview card depicting each skin's ACTUAL structural silhouette
/// (`left_rail` sidebar vs `centered_capsule` island vs `framed_stage` vs `split_showcase` + palette!).
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
          color: hostSkin.panelSurface,
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
            // Miniature Structural App Stage
            SizedBox(
              height: 118,
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
                          color: s.surface,
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
                                if (isCapsuleNav)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: s.surface2,
                                      borderRadius: BorderRadius.circular(99),
                                      border: Border.all(color: s.borderStrong, width: 0.6),
                                    ),
                                    child: Text(
                                      s.badge,
                                      style: TextStyle(
                                        color: s.accent,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: s.surface2,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      s.badge,
                                      style: TextStyle(
                                        color: s.fg2,
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
                                            color: s.surface.withValues(alpha: 0.8),
                                            borderRadius: BorderRadius.circular(miniCardR),
                                            border: Border.all(color: s.border, width: 0.6),
                                          )
                                        : null,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Cinema',
                                          style: s.applyHeadlineMood(
                                            TextStyle(
                                              color: s.fg,
                                              fontSize: 14,
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
                                      alignment: Alignment.bottomLeft,
                                      padding: const EdgeInsets.all(3),
                                      child: s.cardStyle == 'overlay_poster'
                                          ? Container(
                                              height: 3,
                                              width: 16,
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(alpha: 0.85),
                                                borderRadius: BorderRadius.circular(1.5),
                                              ),
                                            )
                                          : null,
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

            // Footer Metadata & Actions
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

/// Full DIY Skin Studio Dialog with Structural Layout Tabs + HSV Color Spectrum + Live Preview.
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
                    // Live Structural Preview Card
                    _SkinPreviewCard(
                      skinPreview: liveSkin,
                      selected: true,
                      onSelect: () {},
                    ),
                    const SizedBox(height: 16),

                    // Name + Light/Dark Base
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
                      ],
                      (v) => _spec = _spec.copyWith(navLayout: v),
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
                      '详情页构图 & 背景引擎',
                      _spec.detailLayout,
                      const [
                        ('apple_immersive', '影院沉浸式'),
                        ('jellyfin_glass', '毛玻璃悬浮卡片'),
                        ('centered_editorial', '居中对称画报'),
                      ],
                      (v) => _spec = _spec.copyWith(
                        detailLayout: v,
                        backdropMode: v == 'jellyfin_glass' ? 'blurred_fanart' : _spec.backdropMode,
                      ),
                    ),
                    _chipPicker(
                      hostSkin,
                      liveSkin,
                      '海报卡片结构',
                      _spec.cardStyle,
                      const [
                        ('classic_below', '图下标题'),
                        ('overlay_poster', '海报内嵌渐变字'),
                        ('hover_reveal', '纯海报悬停显字'),
                      ],
                      (v) => _spec = _spec.copyWith(cardStyle: v),
                    ),
                    _chipPicker(
                      hostSkin,
                      liveSkin,
                      '演职人员样式',
                      _spec.castStyle,
                      const [
                        ('circle_medallion', '圆形头像勋章'),
                        ('portrait_card', '2:3 竖版写真卡'),
                        ('compact_pill', '紧凑胶囊名牌'),
                      ],
                      (v) => _spec = _spec.copyWith(castStyle: v),
                    ),
                    _chipPicker(
                      hostSkin,
                      liveSkin,
                      '主按钮风格 & 卡片边框',
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
