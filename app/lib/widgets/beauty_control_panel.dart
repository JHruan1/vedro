import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/services/ai_face_beauty_manager.dart';
import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';
import 'ai_face_beauty_overlay.dart';
import 'beauty_filter.dart';
import 'vedro_ui.dart';

/// Compact, zero-scroll Portrait Beauty Studio sheet for [PlayerScreen].
///
/// Organizes both beauty pipelines into 2 crisp tabs so landscape phones (~360dp tall)
/// and portrait phones NEVER need to scroll just to find presets or adjust sliders:
/// - Tab 0 (`质感美颜 · GPU`, Plan B): Douyin-style 2-Pass GPU skin/glow presets
///   (`奶油水光`, `冷白网感`, etc.) + 4 inline sliders (2x2 grid on landscape!).
/// - Tab 1 (`AI 五官`, Plan A): On-demand downloadable YuNet ONNX face landmark engine
///   unlocking real-time GPU Slim Face / Big Eyes / V-Chin / Precision Lip Tint.
class BeautyControlPanel extends StatefulWidget {
  const BeautyControlPanel({
    super.key,
    required this.gpuPreset,
    required this.gpuParams,
    required this.aiEnabled,
    required this.aiMorph,
    required this.useChinaMirror,
    required this.telemetryNotifier,
    required this.onSelectGpuPreset,
    required this.onChangeGpuParams,
    required this.onToggleAiEnabled,
    required this.onChangeAiMorph,
    required this.onChangeChinaMirror,
    required this.onSliderDragState,
    required this.onUpdatePeekLabel,
  });

  final String gpuPreset;
  final BeautyFilterParams gpuParams;
  final bool aiEnabled;
  final AiFaceMorphParams aiMorph;
  final bool useChinaMirror;
  final ValueNotifier<AiFaceTrackTelemetry> telemetryNotifier;

  final Future<void> Function(String presetId) onSelectGpuPreset;
  final Future<void> Function(BeautyFilterParams next) onChangeGpuParams;
  final Future<void> Function(bool enabled) onToggleAiEnabled;
  final Future<void> Function(AiFaceMorphParams next) onChangeAiMorph;
  final ValueChanged<bool> onChangeChinaMirror;
  final void Function(bool dragging, {String? label}) onSliderDragState;
  final ValueChanged<String> onUpdatePeekLabel;

  @override
  State<BeautyControlPanel> createState() => _BeautyControlPanelState();
}

class _BeautyControlPanelState extends State<BeautyControlPanel> {
  late int _tabIndex;
  late String _gpuPreset;
  late BeautyFilterParams _gpuParams;
  late bool _aiEnabled;
  late AiFaceMorphParams _aiMorph;
  late bool _useChinaMirror;

  @override
  void initState() {
    super.initState();
    _gpuPreset = widget.gpuPreset;
    _gpuParams = widget.gpuParams;
    _aiEnabled = widget.aiEnabled;
    _aiMorph = widget.aiMorph;
    _useChinaMirror = widget.useChinaMirror;
    // Default to Plan B (GPU Quality Beauty); open Plan A directly if only Plan A is active.
    _tabIndex = (!_gpuParams.isActive && _aiEnabled && _aiMorph.isActive) ? 1 : 0;
    unawaited(AiFaceBeautyManager.instance.refreshStatus());
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    final hasActiveInTab = _tabIndex == 0
        ? _gpuParams.isActive
        : (_aiEnabled && _aiMorph.isActive);

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoCol = constraints.maxWidth >= 460;
        return Padding(
          key: const ValueKey('compact-beauty-panel'),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Single compact header: 2-Tab switcher + Reset + Thermal info tooltip
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1D27),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x24FFFFFF), width: 0.7),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _BeautyTabChip(
                              key: const ValueKey('beauty-tab-gpu'),
                              label: '质感美颜 · GPU',
                              selected: _tabIndex == 0,
                              activeDot: _gpuParams.isActive,
                              accent: accent,
                              onTap: () => setState(() => _tabIndex = 0),
                            ),
                          ),
                          Expanded(
                            child: ListenableBuilder(
                              listenable: AiFaceBeautyManager.instance,
                              builder: (_, __) => _BeautyTabChip(
                                key: const ValueKey('beauty-tab-ai'),
                                label: 'AI 五官 · 瘦脸大眼',
                                selected: _tabIndex == 1,
                                activeDot: _aiEnabled &&
                                    _aiMorph.isActive &&
                                    AiFaceBeautyManager.instance.isModelDownloaded,
                                accent: accent,
                                onTap: () => setState(() => _tabIndex = 1),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (hasActiveInTab) ...[
                    const SizedBox(width: 8),
                    PressableScale(
                      onTap: () async {
                        if (_tabIndex == 0) {
                          setState(() {
                            _gpuPreset = 'off';
                            _gpuParams = BeautyFilterParams.off;
                          });
                          await widget.onSelectGpuPreset('off');
                        } else {
                          setState(() => _aiMorph = AiFaceMorphParams.off);
                          await widget.onChangeAiMorph(AiFaceMorphParams.off);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0x1EFFFFFF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '归零',
                          style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  Tooltip(
                    message: _tabIndex == 0
                        ? BeautyFilterEngine.thermalNotice
                        : '注意：开启 AI 五官塑形可能导致杜比视界 (Dolby Vision) / HDR 原生直通降级为 SDR，并增加功耗与发热；关闭或归零即刻 100% 恢复原生杜比/HDR 直通。',
                    triggerMode: TooltipTriggerMode.tap,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.info_outline_rounded, size: 16, color: Color(0x99FFFFFF)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_tabIndex == 0)
                _buildGpuBeautyTab(accent, twoCol: twoCol)
              else
                _buildAiFaceTab(accent, twoCol: twoCol),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGpuBeautyTab(Color accent, {required bool twoCol}) {
    Future<void> updateChannel(BeautyFilterParams next) async {
      final preset = next.isActive ? 'custom' : 'off';
      setState(() {
        _gpuPreset = preset;
        _gpuParams = next;
      });
      await widget.onChangeGpuParams(next);
    }

    final sliders = [
      _CompactBeautySlider(
        label: '磨皮',
        value: _gpuParams.smooth,
        accent: accent,
        onDragStateChanged: (d) =>
            widget.onSliderDragState(d, label: '磨皮 ${(_gpuParams.smooth * 100).round()}%'),
        onChanged: (v) {
          widget.onUpdatePeekLabel('磨皮 ${(v * 100).round()}%');
          unawaited(updateChannel(_gpuParams.copyWith(smooth: v)));
        },
      ),
      _CompactBeautySlider(
        label: '美白',
        value: _gpuParams.whiten,
        accent: accent,
        onDragStateChanged: (d) =>
            widget.onSliderDragState(d, label: '美白 ${(_gpuParams.whiten * 100).round()}%'),
        onChanged: (v) {
          widget.onUpdatePeekLabel('美白 ${(v * 100).round()}%');
          unawaited(updateChannel(_gpuParams.copyWith(whiten: v)));
        },
      ),
      _CompactBeautySlider(
        label: '粉嫩',
        value: _gpuParams.rosy,
        accent: accent,
        onDragStateChanged: (d) =>
            widget.onSliderDragState(d, label: '粉嫩 ${(_gpuParams.rosy * 100).round()}%'),
        onChanged: (v) {
          widget.onUpdatePeekLabel('粉嫩 ${(v * 100).round()}%');
          unawaited(updateChannel(_gpuParams.copyWith(rosy: v)));
        },
      ),
      _CompactBeautySlider(
        label: '亮眼',
        value: _gpuParams.clarity,
        accent: accent,
        onDragStateChanged: (d) =>
            widget.onSliderDragState(d, label: '亮眼 ${(_gpuParams.clarity * 100).round()}%'),
        onChanged: (v) {
          widget.onUpdatePeekLabel('亮眼 ${(v * 100).round()}%');
          unawaited(updateChannel(_gpuParams.copyWith(clarity: v)));
        },
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Single horizontal preset strip — zero multi-line wrapping!
        SizedBox(
          height: 30,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: BeautyFilterPreset.all.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, idx) {
              final preset = BeautyFilterPreset.all[idx];
              final selected = preset.id == 'off'
                  ? !_gpuParams.isActive
                  : (_gpuPreset == preset.id && _gpuParams.isActive);
              final isDouyin = preset.id == 'douyin_cream' || preset.id == 'cool_white';
              return _CompactPresetChip(
                key: ValueKey('beauty-preset-${preset.id}'),
                label: isDouyin ? '✦ ${preset.label}' : preset.label,
                selected: selected,
                accent: accent,
                onTap: () async {
                  setState(() {
                    _gpuPreset = preset.id;
                    _gpuParams = preset.params;
                  });
                  await widget.onSelectGpuPreset(preset.id);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        if (twoCol) ...[
          Row(
            children: [
              Expanded(child: sliders[0]),
              const SizedBox(width: 14),
              Expanded(child: sliders[1]),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: sliders[2]),
              const SizedBox(width: 14),
              Expanded(child: sliders[3]),
            ],
          ),
        ] else ...[
          sliders[0],
          sliders[1],
          sliders[2],
          sliders[3],
        ],
      ],
    );
  }

  Widget _buildAiFaceTab(Color accent, {required bool twoCol}) {
    return ListenableBuilder(
      listenable: AiFaceBeautyManager.instance,
      builder: (context, _) {
        final mgr = AiFaceBeautyManager.instance;
        if (!mgr.isModelDownloaded) {
          return Container(
            key: const ValueKey('beauty-sheet-ai-download-card'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF191C26),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x28FFFFFF), width: 0.7),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.face_retouching_natural_rounded, size: 17, color: accent),
                    const SizedBox(width: 7),
                    const Expanded(
                      child: Text(
                        '需下载本地 AI 人脸模型（约 228 KB）',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _CompactPresetChip(
                      label: _useChinaMirror ? '国内镜像' : 'HF 官方',
                      selected: false,
                      accent: accent,
                      onTap: () {
                        final next = !_useChinaMirror;
                        setState(() => _useChinaMirror = next);
                        widget.onChangeChinaMirror(next);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                const Text(
                  'YuNet 本地离线追踪人脸五官，解锁瘦脸/大眼/V脸/唇彩；注意开启后可能导致杜比视界/HDR 直通降级为 SDR，关闭即恢复原片直通（详见「设置 → 视频设置」）。',
                  style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 11.5, height: 1.35),
                ),
                if (mgr.isDownloading) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: mgr.downloadProgress > 0 ? mgr.downloadProgress : null,
                      minHeight: 4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mgr.downloadStage,
                    style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 11),
                  ),
                ],
                if (mgr.downloadError != null && mgr.downloadError!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    mgr.downloadError!,
                    style: const TextStyle(color: VedroTheme.danger, fontSize: 11),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('beauty-sheet-download-ai-btn'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      onPressed: mgr.isDownloading
                          ? null
                          : () async {
                              await mgr.downloadModel(useChinaMirror: _useChinaMirror);
                              if (mgr.isModelDownloaded && mounted) {
                                final initialMorph = _aiMorph.isActive
                                    ? _aiMorph
                                    : AiFaceMorphParams.subtle;
                                setState(() {
                                  _aiEnabled = true;
                                  _aiMorph = initialMorph;
                                });
                                await widget.onChangeAiMorph(initialMorph);
                                await widget.onToggleAiEnabled(true);
                              }
                            },
                      icon: const Icon(Icons.download_rounded, size: 15),
                      label: Text(
                        mgr.isDownloading ? '下载中…' : '一键下载并开启 (228 KB)',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    if (mgr.isDownloading) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: mgr.cancelDownload,
                        child: const Text('取消', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          );
        }

        Future<void> updateMorph(AiFaceMorphParams next) async {
          final autoEnable = next.isActive && !_aiEnabled;
          setState(() {
            _aiMorph = next;
            if (autoEnable) _aiEnabled = true;
          });
          await widget.onChangeAiMorph(next);
          if (autoEnable) {
            await widget.onToggleAiEnabled(true);
          }
        }

        final sliders = [
          _CompactBeautySlider(
            label: '瘦脸',
            value: _aiMorph.slimFace,
            accent: accent,
            onDragStateChanged: (d) =>
                widget.onSliderDragState(d, label: 'AI 瘦脸 ${(_aiMorph.slimFace * 100).round()}%'),
            onChanged: (v) {
              widget.onUpdatePeekLabel('AI 瘦脸 ${(v * 100).round()}%');
              unawaited(updateMorph(_aiMorph.copyWith(slimFace: v)));
            },
          ),
          _CompactBeautySlider(
            label: '大眼',
            value: _aiMorph.bigEyes,
            accent: accent,
            onDragStateChanged: (d) =>
                widget.onSliderDragState(d, label: 'AI 大眼 ${(_aiMorph.bigEyes * 100).round()}%'),
            onChanged: (v) {
              widget.onUpdatePeekLabel('AI 大眼 ${(v * 100).round()}%');
              unawaited(updateMorph(_aiMorph.copyWith(bigEyes: v)));
            },
          ),
          _CompactBeautySlider(
            label: 'V 脸',
            value: _aiMorph.vChin,
            accent: accent,
            onDragStateChanged: (d) =>
                widget.onSliderDragState(d, label: 'AI V 脸 ${(_aiMorph.vChin * 100).round()}%'),
            onChanged: (v) {
              widget.onUpdatePeekLabel('AI V 脸 ${(v * 100).round()}%');
              unawaited(updateMorph(_aiMorph.copyWith(vChin: v)));
            },
          ),
          _CompactBeautySlider(
            label: '唇彩',
            value: _aiMorph.lipTint,
            accent: accent,
            onDragStateChanged: (d) =>
                widget.onSliderDragState(d, label: 'AI 精准唇彩 ${(_aiMorph.lipTint * 100).round()}%'),
            onChanged: (v) {
              widget.onUpdatePeekLabel('AI 精准唇彩 ${(v * 100).round()}%');
              unawaited(updateMorph(_aiMorph.copyWith(lipTint: v)));
            },
          ),
        ];

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Single compact toggle + preset + live tracking status row
            Row(
              children: [
                Transform.scale(
                  scale: 0.72,
                  alignment: Alignment.centerLeft,
                  child: CupertinoSwitch(
                    value: _aiEnabled,
                    activeTrackColor: accent,
                    onChanged: (v) async {
                      setState(() => _aiEnabled = v);
                      if (v && !_aiMorph.isActive) {
                        setState(() => _aiMorph = AiFaceMorphParams.subtle);
                        await widget.onChangeAiMorph(AiFaceMorphParams.subtle);
                      }
                      await widget.onToggleAiEnabled(v);
                    },
                  ),
                ),
                _CompactPresetChip(
                  label: '自然微调',
                  selected: _aiEnabled && _aiMorph == AiFaceMorphParams.subtle,
                  accent: accent,
                  onTap: () => unawaited(updateMorph(AiFaceMorphParams.subtle)),
                ),
                const SizedBox(width: 6),
                _CompactPresetChip(
                  label: '网感精修',
                  selected: _aiEnabled && _aiMorph == AiFaceMorphParams.douyin,
                  accent: accent,
                  onTap: () => unawaited(updateMorph(AiFaceMorphParams.douyin)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ValueListenableBuilder<AiFaceTrackTelemetry>(
                    valueListenable: widget.telemetryNotifier,
                    builder: (_, t, __) => Text(
                      t.statusBadge(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: t.trackedFaces > 0
                            ? const Color(0xFF34D399)
                            : const Color(0x99FFFFFF),
                        fontSize: 11,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (twoCol) ...[
              Row(
                children: [
                  Expanded(child: sliders[0]),
                  const SizedBox(width: 14),
                  Expanded(child: sliders[1]),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(child: sliders[2]),
                  const SizedBox(width: 14),
                  Expanded(child: sliders[3]),
                ],
              ),
            ] else ...[
              sliders[0],
              sliders[1],
              sliders[2],
              sliders[3],
            ],
          ],
        );
      },
    );
  }
}

class _BeautyTabChip extends StatelessWidget {
  const _BeautyTabChip({
    super.key,
    required this.label,
    required this.selected,
    required this.activeDot,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool activeDot;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.24) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: selected ? Border.all(color: accent.withValues(alpha: 0.65), width: 0.8) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xB3FFFFFF),
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (activeDot) ...[
              const SizedBox(width: 5),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompactPresetChip extends StatelessWidget {
  const _CompactPresetChip({
    super.key,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      hoverScale: 1.03,
      pressScale: 0.94,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.24) : const Color(0x18FFFFFF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.72) : const Color(0x20FFFFFF),
            width: 0.75,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: selected ? accent : const Color(0xECFFFFFF),
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Ultra-compact 34dp inline slider tailored for the landscape/portrait Beauty Sheet.
/// Supports drag-to-peek (`onDragStateChanged`) so the sheet vanishes while dragging!
class _CompactBeautySlider extends StatefulWidget {
  const _CompactBeautySlider({
    required this.label,
    required this.value,
    required this.accent,
    required this.onChanged,
    required this.onDragStateChanged,
  });

  final String label;
  final double value;
  final Color accent;
  final ValueChanged<double> onChanged;
  final ValueChanged<bool> onDragStateChanged;

  @override
  State<_CompactBeautySlider> createState() => _CompactBeautySliderState();
}

class _CompactBeautySliderState extends State<_CompactBeautySlider> {
  bool _dragging = false;

  void _setDragging(bool active) {
    if (_dragging == active) return;
    if (mounted) {
      setState(() => _dragging = active);
    } else {
      _dragging = active;
    }
    widget.onDragStateChanged(active);
  }

  @override
  void dispose() {
    if (_dragging) {
      _dragging = false;
      widget.onDragStateChanged(false);
    }
    super.dispose();
  }

  void _updateDx(double dx, double width) {
    if (width <= 0) return;
    final raw = (dx / width).clamp(0.0, 1.0);
    final stepped = ((raw * 20).round() / 20.0).clamp(0.0, 1.0);
    if ((stepped - widget.value).abs() > 1e-4) {
      if (stepped == 0.0 || stepped == 0.5 || stepped == 1.0) {
        HapticFeedback.selectionClick();
      }
      widget.onChanged(stepped);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final ratio = widget.value.clamp(0.0, 1.0);
    final trackH = _dragging ? 5.5 : 4.0;

    return SizedBox(
      height: 34,
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              widget.label,
              maxLines: 1,
              style: const TextStyle(
                color: Color(0xDCFFFFFF),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: LayoutBuilder(
              builder: (_, constraints) {
                final w = constraints.maxWidth;
                return GestureDetector(
                  key: ValueKey('beauty-slider-${widget.label}'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _updateDx(d.localPosition.dx, w),
                  onHorizontalDragStart: (d) {
                    _setDragging(true);
                    _updateDx(d.localPosition.dx, w);
                  },
                  onHorizontalDragUpdate: (d) => _updateDx(d.localPosition.dx, w),
                  onHorizontalDragEnd: (_) => _setDragging(false),
                  onHorizontalDragCancel: () => _setDragging(false),
                  child: SizedBox(
                    height: 32,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(
                          height: trackH,
                          decoration: BoxDecoration(
                            color: const Color(0x30FFFFFF),
                            borderRadius: BorderRadius.circular(trackH / 2),
                          ),
                        ),
                        Container(
                          height: trackH,
                          width: w * ratio,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [widget.accent, skin.accentSecondary],
                            ),
                            borderRadius: BorderRadius.circular(trackH / 2),
                          ),
                        ),
                        Positioned(
                          left: (w * ratio - 7).clamp(0.0, (w - 14).clamp(0.0, w)),
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: widget.accent.withValues(alpha: 0.78),
                                width: 1.6,
                              ),
                              boxShadow: const [
                                BoxShadow(color: Color(0x55000000), blurRadius: 6),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 34,
            child: Text(
              '${(ratio * 100).round()}%',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xCCFFFFFF),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
