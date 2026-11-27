// Local file / direct URL playback history entry persisted in SQLite KV.

import 'json_helpers.dart';

/// Recent local file or direct network URL playback entry persisted in SQLite KV (`local_history_v1`).
class VedroLocalHistoryEntry {
  const VedroLocalHistoryEntry({
    required this.key,
    required this.title,
    required this.target,
    required this.isNetworkUrl,
    this.positionSecs = 0.0,
    this.durationSecs = 0.0,
    this.playedAtMs = 0,
  });

  final String key;
  final String title;
  final String target;
  final bool isNetworkUrl;
  final double positionSecs;
  final double durationSecs;
  final int playedAtMs;

  double get progress =>
      durationSecs > 0 ? (positionSecs / durationSecs).clamp(0.0, 1.0) : 0.0;

  Map<String, dynamic> toJson() => {
        'key': key,
        'title': title,
        'target': target,
        'is_network_url': isNetworkUrl,
        'position_secs': positionSecs,
        'duration_secs': durationSecs,
        'played_at_ms': playedAtMs,
      };

  factory VedroLocalHistoryEntry.fromJson(Map<String, dynamic> j) => VedroLocalHistoryEntry(
        key: (j['key'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        target: (j['target'] ?? '').toString(),
        isNetworkUrl: j['is_network_url'] == true,
        positionSecs: asJsonDouble(j['position_secs']) ?? 0.0,
        durationSecs: asJsonDouble(j['duration_secs']) ?? 0.0,
        playedAtMs: asJsonInt(j['played_at_ms']) ?? 0,
      );
}
