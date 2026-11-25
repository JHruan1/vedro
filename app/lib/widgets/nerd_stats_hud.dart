import 'package:flutter/material.dart';

import '../core/theme/prism_theme.dart';

/// Real-time hardware decoding, Dolby Vision RPU, Dolby Atmos & Rust Stream Proxy telemetry overlay (`I`).
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

    return Container(
      width: 340,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xD90A0E17),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PrismTheme.border),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11.5,
          height: 1.45,
          color: PrismTheme.textPrimary,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PRISM ENGINE TELEMETRY',
              style: TextStyle(
                color: PrismTheme.accent,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const Divider(color: PrismTheme.border, height: 14),
            _row('Decoder', '${pb['video_codec'] ?? '-'} • HW: ${pb['hwdec_current'] ?? 'auto'}'),
            _row('Video', '${pb['width'] ?? 0}x${pb['height'] ?? 0} @ ${((pb['fps'] as num?) ?? 0).toStringAsFixed(2)} fps (drop: ${pb['dropped_frames'] ?? 0})'),
            _row('HDR / DoVi', '${hdr['explanation'] ?? 'SDR'}'),
            _row('Audio / Atmos', '${pb['audio_codec'] ?? '-'} (${pb['audio_channels'] ?? '-'}) • ${audio['summary'] ?? '-'}'),
            _row('Rust Proxy', '$cachedMb MB RAM • hits ${cache['hits'] ?? 0} / miss ${cache['misses'] ?? 0}'),
            _row('Upstream', '${px['active_upstream_connections'] ?? 0}/2 conns • $mbps Mbps • tickets ${px['ticket_rotations'] ?? 0}'),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(k, style: const TextStyle(color: PrismTheme.textSecondary)),
          ),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }
}
