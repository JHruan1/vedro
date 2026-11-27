// Single Source of Truth for Vedro human-readable display formatters
// (ticks/duration, file & quota sizes, transfer throughput, currency, counts, ISO dates).

const int kEmbyTicksPerSecond = 10000000;

String fmtDurationTicks(int? ticks) {
  if (ticks == null || ticks <= 0) return '';
  final minutes = (ticks / kEmbyTicksPerSecond / 60).round();
  if (minutes <= 0) return '';
  if (minutes < 60) return '$minutes 分钟';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m > 0 ? '$h 小时 $m 分' : '$h 小时';
}

String fmtFileSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value < 10 && unit > 0 ? value.toStringAsFixed(1) : value.round()} ${units[unit]}';
}

/// High-precision binary-unit formatter for download quota balances (e.g. `30.00 GB`, `1.25 TB`).
String fmtQuotaBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  if (unit == 0) return '${value.round()} B';
  if (unit >= 3) return '${value.toStringAsFixed(2)} ${units[unit]}';
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}

/// Canonical transfer speed formatter (`B/s`, `KB/s`, `MB/s`) used by player HUD & update downloader.
String fmtTransferSpeed(int bps, {String zeroLabel = '0 KB/s'}) {
  if (bps <= 0) return zeroLabel;
  if (bps < 1024) return '$bps B/s';
  if (bps < 1024 * 1024) {
    return '${(bps / 1024).toStringAsFixed(bps < 10 * 1024 ? 1 : 0)} KB/s';
  }
  return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
}

String fmtTicksClock(int ticks) {
  if (ticks <= 0) return '00:00';
  final total = (ticks / kEmbyTicksPerSecond).floor();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  return h > 0
      ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
      : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String fmtCurrencyUsd(int? amount) {
  if (amount == null || amount <= 0) return '';
  if (amount >= 100000000) {
    return '\$${(amount / 100000000).toStringAsFixed(2)} 亿';
  }
  if (amount >= 10000) {
    return '\$${(amount / 10000).toStringAsFixed(1)} 万';
  }
  return '\$$amount';
}

String fmtCompactCount(int n) {
  if (n >= 10000) {
    return '${(n / 10000).toStringAsFixed(1)}w';
  }
  return '$n';
}

/// Format an ISO-8601 date string (`2024-03-01T00:00:00Z`) into clean `2024-03-01`.
String fmtIsoDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  final s = raw.trim();
  final tIdx = s.indexOf('T');
  final datePart = tIdx > 0 ? s.substring(0, tIdx) : s;
  if (datePart.length >= 10) return datePart.substring(0, 10);
  return datePart;
}
