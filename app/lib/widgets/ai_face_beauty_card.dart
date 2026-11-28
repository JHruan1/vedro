import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/services/ai_face_beauty_manager.dart';
import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';
import '../core/utils/formatters.dart';
import '../state/app_state.dart';
import 'ai_face_beauty_overlay.dart';
import 'vedro_ui.dart';

/// Reusable Settings panel for Plan A: On-demand downloadable local AI Face Landmark engine
/// (YuNet ONNX ~228 KB), mirroring the Local Offline ASR download experience.
///
/// Mounted in both `设置 → 视频设置` (with default morph sliders) and `设置 → AI 翻译`
/// (compact model download + toggle card right under local offline ASR).
class AiFaceBeautyModelCard extends StatefulWidget {
  const AiFaceBeautyModelCard({
    super.key,
    required this.appState,
    this.showDefaultSliders = true,
  });

  final VedroAppState appState;
  final bool showDefaultSliders;

  @override
  State<AiFaceBeautyModelCard> createState() => _AiFaceBeautyModelCardState();
}

class _AiFaceBeautyModelCardState extends State<AiFaceBeautyModelCard> {
  @override
  void initState() {
    super.initState();
    unawaited(AiFaceBeautyManager.instance.refreshStatus());
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.appState.prefs;
    final skin = VedroSkin.of(context);
    final accent = Theme.of(context).colorScheme.secondary;

    return ListenableBuilder(
      listenable: AiFaceBeautyManager.instance,
      builder: (context, _) {
        final mgr = AiFaceBeautyManager.instance;
        final sizeStr = mgr.downloadedBytes > 0
            ? fmtFileSize(mgr.downloadedBytes)
            : '约 228 KB';

        return Padding(
          key: widget.showDefaultSliders
              ? const ValueKey('settings-ai-face-beauty-panel')
              : const ValueKey('settings-ai-face-beauty-panel-compact'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Enable toggle row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '启用 AI 人像五官塑形（瘦脸 / 大眼 / V脸 / 唇彩）',
                          style: TextStyle(
                            color: skin.fg,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '默认关闭；仅在开启时加载轻量化本地人脸追踪，关闭时 100% 原生杜比视界直通',
                          style: TextStyle(color: skin.fg3, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Transform.scale(
                    scale: 0.78,
                    child: CupertinoSwitch(
                      key: widget.showDefaultSliders
                          ? const ValueKey('pref-ai-face-enabled')
                          : null,
                      value: p.aiFaceBeautyEnabled,
                      activeTrackColor: skin.accent,
                      onChanged: (v) async {
                        await widget.appState.updatePrefs(
                          p.copyWith(aiFaceBeautyEnabled: v),
                        );
                        if (v && !mgr.isModelDownloaded && !mgr.isDownloading) {
                          unawaited(
                            mgr.downloadModel(useChinaMirror: p.aiFaceUseChinaMirror),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: (mgr.isModelDownloaded ? const Color(0xFF10B981) : accent)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      mgr.isModelDownloaded
                          ? Icons.check_circle_outline_rounded
                          : Icons.face_retouching_natural_rounded,
                      size: 18,
                      color: mgr.isModelDownloaded ? const Color(0xFF10B981) : accent,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                AiFaceBeautyModelSpec.displayName,
                                style: TextStyle(
                                  color: skin.fg,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              mgr.isModelDownloaded ? '已就绪 · $sizeStr' : sizeStr,
                              style: TextStyle(
                                color: mgr.isModelDownloaded
                                    ? const Color(0xFF10B981)
                                    : skin.fg3,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          AiFaceBeautyModelSpec.capabilitiesLabel,
                          style: TextStyle(color: skin.fg3, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Explicit Dolby Vision / HDR invalidation, thermal & multi-GPU notice right at model download
              Container(
                key: const ValueKey('ai-face-compatibility-notice'),
                padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: skin.isLight ? 0.11 : 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.38),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.warning_amber_rounded,
                            size: 15,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            '兼容性与画质说明：开启 AI 五官塑形可能导致杜比视界 (Dolby Vision) / HDR10 原生直通失效（画面降级为 SDR 色调映射，部分安卓机型在采帧回退时会临时切换至 Copy-Back 硬解），同时增加 CPU/GPU 功耗与机身发热。关闭开关或参数归零后将立即 100% 恢复原片杜比/HDR 零拷贝硬解。',
                            style: TextStyle(
                              color: skin.isLight ? const Color(0xFF92400E) : const Color(0xFFFDE68A),
                              fontSize: 11.5,
                              height: 1.42,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Padding(
                      padding: const EdgeInsets.only(left: 22),
                      child: Text(
                        '当前设备 GPU 管线：${AiFaceBeautyShader.activeGpuPipelineLabel}（4K 杜比/HDR 大片建议关闭 AI 五官，改用不影响 HDR 的「方案 B 质感美颜」）',
                        style: TextStyle(
                          color: skin.fg2,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('下载源：', style: TextStyle(color: skin.fg2, fontSize: 12)),
                  ChoiceChip(
                    selected: p.aiFaceUseChinaMirror,
                    label: const Text('国内镜像加速', style: TextStyle(fontSize: 12)),
                    onSelected: (_) => widget.appState.updatePrefs(
                      p.copyWith(aiFaceUseChinaMirror: true),
                    ),
                  ),
                  ChoiceChip(
                    selected: !p.aiFaceUseChinaMirror,
                    label: const Text('HuggingFace 官方', style: TextStyle(fontSize: 12)),
                    onSelected: (_) => widget.appState.updatePrefs(
                      p.copyWith(aiFaceUseChinaMirror: false),
                    ),
                  ),
                ],
              ),
              if (mgr.isDownloading) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: mgr.downloadProgress > 0 ? mgr.downloadProgress : null,
                    minHeight: 5,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        mgr.downloadStage,
                        style: TextStyle(color: skin.fg2, fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: mgr.cancelDownload,
                      child: const Text('取消', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
              if (mgr.downloadError != null && mgr.downloadError!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  mgr.downloadError!,
                  style: const TextStyle(color: VedroTheme.danger, fontSize: 12),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (!mgr.isModelDownloaded)
                    FilledButton.icon(
                      key: widget.showDefaultSliders
                          ? const ValueKey('download-ai-face-model-btn')
                          : const ValueKey('download-ai-face-model-btn-ai-tab'),
                      onPressed: mgr.isDownloading
                          ? null
                          : () => mgr.downloadModel(
                                useChinaMirror: p.aiFaceUseChinaMirror,
                              ),
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: Text(
                        mgr.isDownloading ? '正在下载…' : '一键下载离线人脸模型 (~228 KB)',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      key: widget.showDefaultSliders
                          ? const ValueKey('delete-ai-face-model-btn')
                          : null,
                      onPressed: mgr.isDownloading
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              await mgr.deleteModel();
                              unawaited(
                                widget.appState.core
                                    .invoke('ai_face_unload_model')
                                    .catchError((_) => null),
                              );
                              await widget.appState.updatePrefs(
                                p.copyWith(aiFaceBeautyEnabled: false),
                              );
                              if (context.mounted) {
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('已删除本地 AI 人脸模型')),
                                );
                              }
                            },
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text('删除模型', style: TextStyle(fontSize: 12.5)),
                    ),
                ],
              ),
              if (widget.showDefaultSliders && p.aiFaceBeautyEnabled) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      selected: (p.aiFaceSlim - AiFaceMorphParams.subtle.slimFace).abs() < 0.02 &&
                          (p.aiFaceBigEyes - AiFaceMorphParams.subtle.bigEyes).abs() < 0.02,
                      label: const Text('自然微调', style: TextStyle(fontSize: 12)),
                      onSelected: (_) => widget.appState.updatePrefs(
                        p.copyWith(
                          aiFaceSlim: AiFaceMorphParams.subtle.slimFace,
                          aiFaceBigEyes: AiFaceMorphParams.subtle.bigEyes,
                          aiFaceVChin: AiFaceMorphParams.subtle.vChin,
                          aiFaceLipTint: AiFaceMorphParams.subtle.lipTint,
                        ),
                      ),
                    ),
                    ChoiceChip(
                      selected: (p.aiFaceSlim - AiFaceMorphParams.douyin.slimFace).abs() < 0.02 &&
                          (p.aiFaceBigEyes - AiFaceMorphParams.douyin.bigEyes).abs() < 0.02,
                      label: const Text('网感精修', style: TextStyle(fontSize: 12)),
                      onSelected: (_) => widget.appState.updatePrefs(
                        p.copyWith(
                          aiFaceSlim: AiFaceMorphParams.douyin.slimFace,
                          aiFaceBigEyes: AiFaceMorphParams.douyin.bigEyes,
                          aiFaceVChin: AiFaceMorphParams.douyin.vChin,
                          aiFaceLipTint: AiFaceMorphParams.douyin.lipTint,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                VedroPrecisionSlider(
                  label: 'AI 瘦脸（下颌线收紧）',
                  value: p.aiFaceSlim,
                  min: 0.0,
                  max: 1.0,
                  step: 0.05,
                  defaultValue: 0.30,
                  valueText: '${(p.aiFaceSlim * 100).round()}%',
                  onChanged: (v) => widget.appState.updatePrefs(p.copyWith(aiFaceSlim: v)),
                ),
                VedroPrecisionSlider(
                  label: 'AI 大眼（双眸自然放大）',
                  value: p.aiFaceBigEyes,
                  min: 0.0,
                  max: 1.0,
                  step: 0.05,
                  defaultValue: 0.22,
                  valueText: '${(p.aiFaceBigEyes * 100).round()}%',
                  onChanged: (v) => widget.appState.updatePrefs(p.copyWith(aiFaceBigEyes: v)),
                ),
                VedroPrecisionSlider(
                  label: 'AI V 脸（下巴轻塑）',
                  value: p.aiFaceVChin,
                  min: 0.0,
                  max: 1.0,
                  step: 0.05,
                  defaultValue: 0.18,
                  valueText: '${(p.aiFaceVChin * 100).round()}%',
                  onChanged: (v) => widget.appState.updatePrefs(p.copyWith(aiFaceVChin: v)),
                ),
                VedroPrecisionSlider(
                  label: 'AI 精准唇彩（零溢色护齿）',
                  value: p.aiFaceLipTint,
                  min: 0.0,
                  max: 1.0,
                  step: 0.05,
                  defaultValue: 0.16,
                  valueText: '${(p.aiFaceLipTint * 100).round()}%',
                  onChanged: (v) => widget.appState.updatePrefs(p.copyWith(aiFaceLipTint: v)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
