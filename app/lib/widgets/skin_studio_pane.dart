import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import 'vedro_ui.dart';

/// Bold Multi-Personality Skin Gallery + Full DIY Custom Skin Studio (`设置 → 应用风格`).
class SkinStudioPane extends StatelessWidget {
  const SkinStudioPane({
    super.key,
    required this.appState,
    this.hideHeading = false,
  });

  final VedroAppState appState;
  final bool hideHeading;

  Future<void> _selectSkin(String skinId) async {
    HapticFeedback.selectionClick();
    await appState.updatePrefs(appState.prefs.copyWith(skinId: skinId));
  }

  Future<void> _openEditor(
    BuildContext context, {
    CustomSkinSpec? existing,
    VedroSkin? templateSkin,
  }) async {
    final spec = existing ??
        (templateSkin != null
            ? templateSkin.toCustomTemplate()
            : CustomSkinSpec(
                id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                name: '我的专属皮肤 ${appState.prefs.customSkins.length + 1}',
              ));

    final result = await showDialog<CustomSkinSpec>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _CustomSkinEditorDialog(initial: spec),
    );
    if (result == null) return;

    final p = appState.prefs;
    final list = List<CustomSkinSpec>.from(p.customSkins);
    final idx = list.indexWhere((s) => s.id == result.id);
    if (idx >= 0) {
      list[idx] = result;
    } else {
      list.add(result);
    }
    await appState.updatePrefs(
      p.copyWith(
        customSkins: list,
        skinId: result.id,
        useSkinGeometry: true,
      ),
    );
  }

  Future<void> _deleteCustomSkin(BuildContext context, CustomSkinSpec target) async {
    final p = appState.prefs;
    final nextList = p.customSkins.where((s) => s.id != target.id).toList();
    final nextId = p.skinId == target.id ? 'obsidian' : p.skinId;
    await appState.updatePrefs(
      p.copyWith(customSkins: nextList, skinId: nextId),
    );
  }

  Future<void> _importSkinDialog(BuildContext context) async {
    final skin = VedroSkin.of(context);
    final ctrl = TextEditingController();
    String? err;
    final imported = await showDialog<CustomSkinSpec>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          title: const Text('导入皮肤分享码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '粘贴 VEDRO-SKIN:... 皮肤口令或 JSON 配置，即可一键复刻他人定制的整套界面风格。',
                style: TextStyle(color: skin.fg3, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 3,
                style: TextStyle(color: skin.fg, fontSize: 12.5, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  hintText: 'VEDRO-SKIN:eyJpZCI6...',
                ),
              ),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(err!, style: const TextStyle(color: VedroTheme.danger, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final parsed = CustomSkinSpec.tryDecodeShareCode(ctrl.text);
                if (parsed == null) {
                  setModal(() => err = '无法解析该皮肤码，请检查是否复制完整');
                  return;
                }
                final fresh = parsed.copyWith(
                  id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                );
                Navigator.pop(ctx, fresh);
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
        useSkinGeometry: true,
      ),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入并切换至皮肤「${imported.name}」')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = appState.prefs;
    final activeSkin = p.activeSkin;
    final skin = VedroSkin.of(context);

    return Column(
      key: const ValueKey('skin-studio-pane'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hideHeading)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '应用风格与皮肤工坊',
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
                        '9 套截然不同的旗舰级视觉人格（涵盖昼白杂志、深海琉璃、35mm 胶片、赛博霓虹与纯黑 OLED），并支持从零自由定制专属皮肤',
                        style: TextStyle(color: skin.fg3, fontSize: 13, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Top DIY Banner CTA: Create or Import Custom Skin
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(skin.surface, skin.accent, skin.isLight ? 0.10 : 0.16)!,
                skin.surface,
              ],
            ),
            borderRadius: BorderRadius.circular(skin.cardRadius.clamp(10.0, 20.0)),
            border: skin.cardBorder(selected: activeSkin.isCustom),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
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
                            fontSize: 15.5,
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
                            'DIY',
                            style: TextStyle(
                              color: skin.accent,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '自由调配深浅基底、画布色、卡片色、双色渐变按钮、锐利切角或超椭圆圆角、霓虹边框与衬线电影标题，还可分享皮肤口令。',
                      style: TextStyle(color: skin.fg2, fontSize: 12.5, height: 1.45),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _importSkinDialog(context),
                    icon: const Icon(Icons.download_done_rounded, size: 16),
                    label: const Text('导入皮肤码', style: TextStyle(fontSize: 13)),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('open-diy-skin-editor-btn'),
                    style: FilledButton.styleFrom(
                      backgroundColor: skin.primaryCtaBg,
                      foregroundColor: skin.primaryCtaFg,
                    ),
                    onPressed: () => _openEditor(context, templateSkin: activeSkin),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('自己设置新皮肤', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ),

        // User's Saved Custom Skins (if any)
        if (p.customSkins.isNotEmpty) ...[
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '我的自制皮肤 (${p.customSkins.length})',
              style: TextStyle(
                color: skin.fg2,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (ctx, c) {
              final cols = c.maxWidth >= 680 ? 3 : (c.maxWidth >= 420 ? 2 : 1);
              const gap = 12.0;
              final cardW = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: p.customSkins.map((spec) {
                  final built = VedroSkin.fromCustom(spec);
                  final selected = p.skinId == spec.id;
                  return SizedBox(
                    width: cardW,
                    child: _SkinPreviewCard(
                      previewSkin: built,
                      selected: selected,
                      onTap: () => _selectSkin(spec.id),
                      onEdit: () => _openEditor(context, existing: spec),
                      onShare: () {
                        Clipboard.setData(ClipboardData(text: spec.encodeShareCode()));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已复制「${spec.name}」的皮肤分享码')),
                        );
                      },
                      onDelete: () => _deleteCustomSkin(context, spec),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],

        // 9 Built-in Flagship Skins Gallery
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              Text(
                '官方大胆风格预设 (${VedroSkin.presets.length})',
                style: TextStyle(
                  color: skin.fg2,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '当前：${activeSkin.name}',
                style: TextStyle(color: skin.accent, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (ctx, c) {
            final cols = c.maxWidth >= 680 ? 3 : (c.maxWidth >= 420 ? 2 : 1);
            const gap = 12.0;
            final cardW = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: VedroSkin.presets.map((preset) {
                final selected = p.skinId == preset.id;
                return SizedBox(
                  width: cardW,
                  child: _SkinPreviewCard(
                    key: ValueKey('skin-preset-${preset.id}'),
                    previewSkin: preset,
                    selected: selected,
                    onTap: () => _selectSkin(preset.id),
                    onFork: () => _openEditor(context, templateSkin: preset),
                  ),
                );
              }).toList(),
            );
          },
        ),

        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            '细节微调与动效',
            style: TextStyle(
              color: skin.fg2,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: skin.surface,
            borderRadius: BorderRadius.circular(skin.cardRadius.clamp(10.0, 18.0)),
            border: skin.cardBorder(),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '跟随所选皮肤的专属圆角与几何造型',
                            style: TextStyle(color: skin.fg, fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '开启时胶片风呈硬朗画框、赛博风呈锐利机能角、深海风呈大圆角；关闭可统一手动指定海报圆角',
                            style: TextStyle(color: skin.fg3, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Transform.scale(
                      scale: 0.78,
                      child: CupertinoSwitch(
                        value: p.useSkinGeometry,
                        activeTrackColor: skin.accent,
                        onChanged: (v) => appState.updatePrefs(p.copyWith(useSkinGeometry: v)),
                      ),
                    ),
                  ],
                ),
              ),
              if (!p.useSkinGeometry) ...[
                Divider(height: 1, indent: 16, endIndent: 16, color: skin.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: VedroPrecisionSlider(
                    label: '手动覆盖海报圆角',
                    valueText: '${p.cardRadius.round()} px',
                    value: p.cardRadius.clamp(4.0, 24.0),
                    min: 4.0,
                    max: 24.0,
                    step: 2.0,
                    defaultValue: 12.0,
                    ticks: const [
                      (4.0, '4px'),
                      (8.0, '8px'),
                      (12.0, '12px'),
                      (18.0, '18px'),
                      (24.0, '24px'),
                    ],
                    onChanged: (v) => appState.updatePrefs(p.copyWith(cardRadius: v)),
                  ),
                ),
              ],
              Divider(height: 1, indent: 16, endIndent: 16, color: skin.border),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('减弱动态效果', style: TextStyle(color: skin.fg, fontSize: 14)),
                          const SizedBox(height: 2),
                          Text(
                            '降低页面切换动效幅度以获得更干脆的响应',
                            style: TextStyle(color: skin.fg3, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Transform.scale(
                      scale: 0.78,
                      child: CupertinoSwitch(
                        value: p.reduceMotion,
                        activeTrackColor: skin.accent,
                        onChanged: (v) => appState.updatePrefs(p.copyWith(reduceMotion: v)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Rich Miniature App Mockup Card previewing a `VedroSkin`'s actual canvas, glow,
/// serif/sans typography, card frame, poster geometry, and primary Play button!
class _SkinPreviewCard extends StatefulWidget {
  const _SkinPreviewCard({
    super.key,
    required this.previewSkin,
    required this.selected,
    required this.onTap,
    this.onFork,
    this.onEdit,
    this.onShare,
    this.onDelete,
  });

  final VedroSkin previewSkin;
  final bool selected;
  final VoidCallback onTap;
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
    final s = widget.previewSkin;
    final outerR = s.cardRadius.clamp(8.0, 20.0);
    final miniCardR = (s.cardRadius * 0.55).clamp(3.0, 11.0);
    final miniPillR = s.radiusForPill(22);

    return PressableScale(
      onTap: widget.onTap,
      onHoverChanged: (v) => setState(() => _hovered = v),
      hoverScale: 1.018,
      pressScale: 0.975,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: VedroTheme.easeOut,
        decoration: BoxDecoration(
          color: hostSkin.surface,
          borderRadius: BorderRadius.circular(outerR),
          border: Border.all(
            color: widget.selected
                ? s.accent
                : (_hovered ? hostSkin.borderStrong : hostSkin.border),
            width: widget.selected ? 1.8 : 0.9,
          ),
          boxShadow: widget.selected
              ? [
                  BoxShadow(
                    color: s.accent.withValues(alpha: hostSkin.isLight ? 0.20 : 0.28),
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
            // Miniature App Stage Preview
            SizedBox(
              height: 118,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: s.canvas,
                  gradient: s.ambientGlow
                      ? RadialGradient(
                          center: const Alignment(-0.55, -0.85),
                          radius: 1.3,
                          colors: [
                            Color.lerp(s.canvas, s.canvasGlow, s.isLight ? 0.42 : 0.26)!,
                            s.canvas,
                          ],
                        )
                      : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Mini Header Bar
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: s.surface2,
                              borderRadius: BorderRadius.circular(miniPillR),
                              border: s.frameStyle == 'borderless'
                                  ? null
                                  : Border.all(color: s.border, width: 0.7),
                            ),
                            child: Text(
                              s.badge,
                              style: TextStyle(
                                color: s.ctaStyle == 'contrast' ? s.fg2 : s.accent,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (widget.selected)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: s.activePillBg,
                                borderRadius: BorderRadius.circular(miniPillR),
                              ),
                              child: Text(
                                '使用中',
                                style: TextStyle(
                                  color: s.activePillFg,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      // Mini Hero Title + Play Pill + 2 Mini Poster Cards
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Cinema',
                                  maxLines: 1,
                                  style: s.applyHeadlineMood(
                                    TextStyle(
                                      color: s.fg,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.3,
                                      height: 1.1,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '4K · 杜比视界',
                                  style: TextStyle(color: s.fg3, fontSize: 9.5),
                                ),
                                const SizedBox(height: 7),
                                Container(
                                  height: 22,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: s.primaryCtaBg,
                                    gradient: s.primaryCtaGradient,
                                    borderRadius: BorderRadius.circular(miniPillR),
                                    border: s.primaryCtaBorder,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.play_arrow_rounded, size: 13, color: s.primaryCtaFg),
                                      const SizedBox(width: 2),
                                      Text(
                                        '播放',
                                        style: TextStyle(
                                          color: s.primaryCtaFg,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Two miniature poster tiles showing surface + frameStyle + cardRadius
                          for (var k = 0; k < 2; k++) ...[
                            if (k > 0) const SizedBox(width: 6),
                            Container(
                              width: 34,
                              height: 50,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: k == 0
                                      ? [s.surface3, s.surface]
                                      : [
                                          Color.lerp(s.surface2, s.accent, 0.32)!,
                                          s.surface,
                                        ],
                                ),
                                borderRadius: BorderRadius.circular(miniCardR),
                                border: s.cardBorder(hovered: k == 1 && s.frameStyle == 'neon'),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: s.isLight ? 0.08 : 0.30),
                                    blurRadius: 6,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Footer Metadata + Quick Actions
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              color: hostSkin.surface,
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
                            fontWeight: FontWeight.w600,
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
                      message: '以此风格为模板自定义',
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

/// Interactive DIY Skin Creator Dialog with Live Preview, HSV Spectrum Sliders, Swatches & Geometry Controls.
class _CustomSkinEditorDialog extends StatefulWidget {
  const _CustomSkinEditorDialog({required this.initial});
  final CustomSkinSpec initial;

  @override
  State<_CustomSkinEditorDialog> createState() => _CustomSkinEditorDialogState();
}

class _CustomSkinEditorDialogState extends State<_CustomSkinEditorDialog> {
  late CustomSkinSpec _spec;
  late final TextEditingController _nameCtrl;
  String _editingColorSlot = 'accent'; // canvas | surface | accent | accent2

  static const _canvasSwatchesDark = <String>[
    '#09090B', '#000000', '#06101E', '#080514', '#120E0B', '#06130F', '#14060A', '#0F172A', '#18122B',
  ];
  static const _canvasSwatchesLight = <String>[
    '#F2F4F8', '#FFFFFF', '#F7F2E7', '#EEF6FF', '#F3FAF6', '#FDF2F6', '#F5F3FF', '#FAF5EE', '#ECFDF5',
  ];
  static const _accentSwatches = <String>[
    '#38BDF8', '#0A84FF', '#F43F5E', '#E5A93C', '#34D399', '#A78BFA', '#FB7185', '#22D3EE', '#F97316', '#111318',
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

  String _currentHexForSlot(String slot) {
    final preview = VedroSkin.fromCustom(_spec);
    return switch (slot) {
      'canvas' => colorToHex6(preview.canvas),
      'surface' => colorToHex6(preview.surface),
      'accent2' => colorToHex6(preview.accentSecondary),
      _ => colorToHex6(preview.accent),
    };
  }

  void _applyHexToSlot(String slot, String hex) {
    setState(() {
      _spec = switch (slot) {
        'canvas' => _spec.copyWith(canvasHex: hex),
        'surface' => _spec.copyWith(surfaceHex: hex),
        'accent2' => _spec.copyWith(accentSecondaryHex: hex),
        _ => _spec.copyWith(accentHex: hex),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final hostSkin = VedroSkin.of(context);
    final liveSkin = VedroSkin.fromCustom(_spec.copyWith(name: _nameCtrl.text));
    final activeColor = parseHexColor(_currentHexForSlot(_editingColorSlot), liveSkin.accent);
    final hsv = HSVColor.fromColor(activeColor);
    final swatches = _editingColorSlot == 'canvas' || _editingColorSlot == 'surface'
        ? (_spec.isLight ? _canvasSwatchesLight : _canvasSwatchesDark)
        : _accentSwatches;

    return Dialog(
      key: const ValueKey('diy-skin-editor-dialog'),
      backgroundColor: hostSkin.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: hostSkin.borderStrong, width: 1.0),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.palette_outlined, size: 20, color: liveSkin.accent),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '自定义皮肤工坊',
                      style: TextStyle(
                        color: hostSkin.fg,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      final code = _spec.copyWith(name: _nameCtrl.text).encodeShareCode();
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('皮肤分享码已复制到剪贴板')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: const Text('复制皮肤码', style: TextStyle(fontSize: 12)),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: hostSkin.fg2),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Live Real-Time Interactive Preview Stage
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 124,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: liveSkin.canvas,
                  gradient: liveSkin.ambientGlow
                      ? RadialGradient(
                          center: const Alignment(-0.5, -0.8),
                          radius: 1.35,
                          colors: [
                            Color.lerp(liveSkin.canvas, liveSkin.canvasGlow, liveSkin.isLight ? 0.40 : 0.24)!,
                            liveSkin.canvas,
                          ],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(liveSkin.cardRadius.clamp(6.0, 20.0)),
                  border: Border.all(color: liveSkin.borderStrong, width: 1.0),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _nameCtrl.text.trim().isEmpty ? '我的专属皮肤' : _nameCtrl.text.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: liveSkin.applyHeadlineMood(
                              TextStyle(
                                color: liveSkin.fg,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '实时预览 · 4K Dolby Vision · 双声道与外挂字幕',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: liveSkin.fg2, fontSize: 11.5),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Container(
                                height: 30,
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                decoration: BoxDecoration(
                                  color: liveSkin.primaryCtaBg,
                                  gradient: liveSkin.primaryCtaGradient,
                                  borderRadius: BorderRadius.circular(liveSkin.radiusForPill(30)),
                                  border: liveSkin.primaryCtaBorder,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.play_arrow_rounded, size: 16, color: liveSkin.primaryCtaFg),
                                    const SizedBox(width: 3),
                                    Text(
                                      '立即播放',
                                      style: TextStyle(
                                        color: liveSkin.primaryCtaFg,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                height: 30,
                                padding: const EdgeInsets.symmetric(horizontal: 11),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: liveSkin.surface2,
                                  borderRadius: BorderRadius.circular(liveSkin.radiusForPill(30)),
                                  border: liveSkin.cardBorder(),
                                ),
                                child: Text(
                                  '简体中文 ASS',
                                  style: TextStyle(color: liveSkin.fg, fontSize: 11, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 64,
                      height: 92,
                      decoration: BoxDecoration(
                        color: liveSkin.surface,
                        borderRadius: BorderRadius.circular(liveSkin.cardRadius.clamp(4.0, 18.0)),
                        border: liveSkin.cardBorder(hovered: liveSkin.frameStyle == 'neon'),
                        boxShadow: liveSkin.posterShadow(),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.movie_filter_rounded, size: 24, color: liveSkin.accent),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Name & Light/Dark Base
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _nameCtrl,
                            onChanged: (_) => setState(() {}),
                            style: TextStyle(color: hostSkin.fg, fontSize: 13.5),
                            decoration: const InputDecoration(
                              labelText: '皮肤名称',
                              hintText: '例如：午夜赛博 / 暖阳书房',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment<bool>(value: false, label: Text('深色暗房', style: TextStyle(fontSize: 12))),
                            ButtonSegment<bool>(value: true, label: Text('浅色昼白', style: TextStyle(fontSize: 12))),
                          ],
                          selected: {_spec.isLight},
                          onSelectionChanged: (s) {
                            final nextLight = s.first;
                            setState(() {
                              _spec = _spec.copyWith(
                                isLight: nextLight,
                                canvasHex: nextLight ? '#F2F4F8' : '#0B1020',
                                surfaceHex: '',
                              );
                            });
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // 2. Color Slots Selector + Interactive HSV Picker
                    Row(
                      children: [
                        Text(
                          '色彩通道定制',
                          style: TextStyle(color: hostSkin.fg2, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        if (_editingColorSlot == 'surface' && _spec.surfaceHex.isNotEmpty)
                          GestureDetector(
                            onTap: () => setState(() => _spec = _spec.copyWith(surfaceHex: '')),
                            child: Text(
                              '恢复自动和谐面板色',
                              style: TextStyle(color: liveSkin.accent, fontSize: 11.5),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (slot, label, col) in [
                          ('canvas', '画布背景', liveSkin.canvas),
                          ('surface', '卡片面板', liveSkin.surface),
                          ('accent', '主强调色', liveSkin.accent),
                          ('accent2', '副渐变色', liveSkin.accentSecondary),
                        ])
                          GestureDetector(
                            onTap: () => setState(() => _editingColorSlot = slot),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                              decoration: BoxDecoration(
                                color: _editingColorSlot == slot ? hostSkin.surface3 : hostSkin.surface2,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _editingColorSlot == slot ? liveSkin.accent : hostSkin.border,
                                  width: _editingColorSlot == slot ? 1.3 : 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: col,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 0.8),
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    label,
                                    style: TextStyle(
                                      color: hostSkin.fg,
                                      fontSize: 12.5,
                                      fontWeight: _editingColorSlot == slot ? FontWeight.w600 : FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: hostSkin.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: hostSkin.border, width: 0.7),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              for (final hex in swatches)
                                GestureDetector(
                                  onTap: () => _applyHexToSlot(_editingColorSlot, hex),
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: parseHexColor(hex, Colors.blue),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: _currentHexForSlot(_editingColorSlot) == hex.toUpperCase()
                                            ? hostSkin.fg
                                            : hostSkin.borderStrong,
                                        width: _currentHexForSlot(_editingColorSlot) == hex.toUpperCase() ? 2.0 : 0.8,
                                      ),
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 6),
                              Text(
                                _currentHexForSlot(_editingColorSlot),
                                style: TextStyle(
                                  color: hostSkin.fg2,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          VedroPrecisionSlider(
                            label: '色相 (Hue)',
                            valueText: '${hsv.hue.round()}°',
                            value: hsv.hue,
                            min: 0,
                            max: 360,
                            step: 1,
                            onChanged: (h) {
                              final next = hsv.withHue(h.clamp(0.0, 360.0)).toColor();
                              _applyHexToSlot(_editingColorSlot, colorToHex6(next));
                            },
                          ),
                          VedroPrecisionSlider(
                            label: '饱和度 (Saturation)',
                            valueText: '${(hsv.saturation * 100).round()}%',
                            value: hsv.saturation,
                            min: 0,
                            max: 1,
                            step: 0.02,
                            onChanged: (sat) {
                              final next = hsv.withSaturation(sat.clamp(0.0, 1.0)).toColor();
                              _applyHexToSlot(_editingColorSlot, colorToHex6(next));
                            },
                          ),
                          VedroPrecisionSlider(
                            label: '明度 (Brightness)',
                            valueText: '${(hsv.value * 100).round()}%',
                            value: hsv.value,
                            min: 0,
                            max: 1,
                            step: 0.02,
                            onChanged: (val) {
                              final next = hsv.withValue(val.clamp(0.0, 1.0)).toColor();
                              _applyHexToSlot(_editingColorSlot, colorToHex6(next));
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 3. Button CTA Style & Frame Border Style
                    Text(
                      '主按钮风格',
                      style: TextStyle(color: hostSkin.fg2, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (id, label) in const [
                          ('contrast', '高反差纯白/纯黑'),
                          ('accent', '主题亮色实心'),
                          ('gradient', '双色流光渐变'),
                          ('outline', '通透琉璃描边'),
                        ])
                          _SmallOptionPill(
                            label: label,
                            selected: _spec.ctaStyle == id,
                            onTap: () => setState(() => _spec = _spec.copyWith(ctaStyle: id)),
                          ),
                      ],
                    ),

                    const SizedBox(height: 14),
                    Text(
                      '卡片边框性格',
                      style: TextStyle(color: hostSkin.fg2, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (id, label) in const [
                          ('borderless', '无框柔和阴影 (Apple)'),
                          ('hairline', '1px 精致建筑细线'),
                          ('neon', '主题色霓虹描边光晕'),
                        ])
                          _SmallOptionPill(
                            label: label,
                            selected: _spec.frameStyle == id,
                            onTap: () => setState(() => _spec = _spec.copyWith(frameStyle: id)),
                          ),
                      ],
                    ),

                    const SizedBox(height: 14),
                    Text(
                      '按钮与胶囊切角',
                      style: TextStyle(color: hostSkin.fg2, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (r, label) in const [
                          (6.0, '硬朗机能切角 (6px)'),
                          (12.0, '温润圆角矩形 (12px)'),
                          (999.0, '全圆跑道胶囊 (Capsule)'),
                        ])
                          _SmallOptionPill(
                            label: label,
                            selected: (_spec.pillRadius - r).abs() < 2.0,
                            onTap: () => setState(() => _spec = _spec.copyWith(pillRadius: r)),
                          ),
                      ],
                    ),

                    const SizedBox(height: 10),
                    VedroPrecisionSlider(
                      label: '卡片与海报圆角',
                      valueText: '${_spec.cardRadius.round()} px',
                      value: _spec.cardRadius,
                      min: 2.0,
                      max: 26.0,
                      step: 1.0,
                      defaultValue: 14.0,
                      ticks: const [
                        (4.0, '胶片 4px'),
                        (8.0, '极客 8px'),
                        (14.0, '标准 14px'),
                        (20.0, '圆润 20px'),
                        (26.0, '超椭圆'),
                      ],
                      onChanged: (v) => setState(() => _spec = _spec.copyWith(cardRadius: v)),
                    ),

                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SwitchListTile.adaptive(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text('顶部极光氛围背光', style: TextStyle(color: hostSkin.fg, fontSize: 13)),
                            value: _spec.ambientGlow,
                            activeColor: liveSkin.accent,
                            onChanged: (v) => setState(() => _spec = _spec.copyWith(ambientGlow: v)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SwitchListTile.adaptive(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text('电影画报衬线标题', style: TextStyle(color: hostSkin.fg, fontSize: 13)),
                            value: _spec.editorialSerif,
                            activeColor: liveSkin.accent,
                            onChanged: (v) => setState(() => _spec = _spec.copyWith(editorialSerif: v)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Footer Save Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
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
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                    ),
                    onPressed: () {
                      final finalName = _nameCtrl.text.trim().isEmpty ? '我的专属皮肤' : _nameCtrl.text.trim();
                      Navigator.pop(context, _spec.copyWith(name: finalName));
                    },
                    icon: const Icon(Icons.check_rounded, size: 17),
                    label: const Text('保存并启用皮肤', style: TextStyle(fontWeight: FontWeight.w700)),
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

class _SmallOptionPill extends StatelessWidget {
  const _SmallOptionPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
        decoration: BoxDecoration(
          color: selected ? skin.activePillBg : skin.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? Colors.transparent : skin.border, width: 0.7),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? skin.activePillFg : skin.fg2,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
