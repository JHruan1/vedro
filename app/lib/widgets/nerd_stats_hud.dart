import 'package:flutter/material.dart';

import '../core/theme/vedro_theme.dart';
import 'vedro_ui.dart';

/// Restrained frosted-glass playback & hardware decode HUD (toggled on demand via `I`).
class NerdStatsHud extends StatelessWidget {
  const NerdStatsHud({super.key, required this.stats});

  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final pb = (stats['playback'] as Map<String, dynamic>?) ?? const {};
    final px = (stats['proxy'] as Map<String, dynamic>?) ?? const {};
    final cache = (px['cache'] as Map<String, dynamic>?) ?? const {};
    final hdr = (pb['hdr_decision'] as Map<String, dynamic>?) ?? const {};
    final audio = (pb['audio_decision'] as Map<String, dynamic>?) ?? const {};

    final cachedMb = (((cache['cached_bytes'] as num?) ?? 0) / (1024 * 1024)).toStringAsFixed(1);
    final mbps = ((px['throughput_mbps'] as num?) ?? 0).toStringAsFixed(1);

    return SizedBox(
      width: 316,
      child: GlassSurface(
        borderRadius: 12,
        padding: const EdgeInsets.all(14),
        color: const Color(0xCC0D0D10),
        child: DefaultTextStyle(
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            height: 1.5,
            color: VedroTheme.fg,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'PLAYBACK INFO',
                style: TextStyle(
                  color: VedroTheme.fg2,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const Divider(color: VedroTheme.line, height: 14),
              _row('Video', '${pb['video_codec'] ?? '-'} · ${pb['width'] ?? 0}×${pb['height'] ?? 0} @ ${((pb['fps'] as num?) ?? 0).toStringAsFixed(1)}'),
              _row('HWDec', '${pb['hwdec_current'] ?? 'auto'} · drop ${pb['dropped_frames'] ?? 0}'),
              _row('HDR', '${hdr['explanation'] ?? 'SDR'}'),
              _row('Audio', '${pb['audio_codec'] ?? '-'} (${pb['audio_channels'] ?? '-'}) · ${audio['summary'] ?? '-'}'),
              _row('Cache', '$cachedMb MB · hits ${cache['hits'] ?? 0}/${cache['misses'] ?? 0}'),
              _row('Net', '${px['active_upstream_connections'] ?? 0}/2 conn · $mbps Mbps'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 54,
            child: Text(k, style: const TextStyle(color: VedroTheme.fg3)),
          ),
          Expanded(child: Text(v, maxLines: 2, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
