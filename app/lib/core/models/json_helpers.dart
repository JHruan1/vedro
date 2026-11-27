// Canonical JSON parsing & display-text normalization helpers.

Map<String, dynamic> asJsonMap(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const {};
}

Map<String, dynamic>? asJsonMapOrNull(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

List<dynamic> asJsonList(dynamic raw) => raw is List ? raw : const [];

int? asJsonInt(dynamic raw) {
  if (raw is int) return raw;
  if (raw is num && raw.isFinite) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim());
  return null;
}

double? asJsonDouble(dynamic raw) {
  if (raw is num && raw.isFinite) return raw.toDouble();
  if (raw is String) {
    final parsed = double.tryParse(raw.trim());
    if (parsed != null && parsed.isFinite) return parsed;
  }
  return null;
}

/// Deterministic low-chroma hue pair matching embygo Web's `GeneratedArt`,
/// so an item without cover art gets a calm, permanent two-tone gradient.
(double, double) deterministicHues(String seed) {
  final s = seed.isEmpty ? '?' : seed;
  var hash = 0;
  for (var i = 0; i < s.length; i++) {
    hash = ((hash * 31) + s.codeUnitAt(i)) & 0xFFFFFFFF;
  }
  return ((hash % 360).toDouble(), ((hash >> 9) % 360).toDouble());
}

/// Clean display initials for missing artwork (2 CJK chars or 2 latin/number tokens).
String artworkInitials(String? name) {
  final trimmed = (name ?? '?').trim();
  if (trimmed.isEmpty) return '?';
  if (RegExp(r'[\u3400-\u9FFF]').hasMatch(trimmed)) {
    return trimmed.length > 2 ? trimmed.substring(0, 2) : trimmed;
  }
  final words = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).toList();
  final buf = StringBuffer();
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    if (i > 0 && RegExp(r'^\d+$').hasMatch(w)) {
      buf.write(w);
    } else if (w.isNotEmpty) {
      buf.write(w[0]);
    }
  }
  final out = buf.toString().toUpperCase();
  return out.isEmpty ? '?' : out;
}

String localizeAirDay(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'monday':
      return '周一';
    case 'tuesday':
      return '周二';
    case 'wednesday':
      return '周三';
    case 'thursday':
      return '周四';
    case 'friday':
      return '周五';
    case 'saturday':
      return '周六';
    case 'sunday':
      return '周日';
    default:
      return raw.trim();
  }
}

String localizePersonRole(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  switch (raw.trim().toLowerCase()) {
    case 'actor':
      return '演员';
    case 'director':
      return '导演';
    case 'writer':
      return '编剧';
    case 'producer':
      return '制片人';
    case 'composer':
      return '配乐';
    case 'gueststar':
    case 'guest star':
      return '客串';
    case 'creator':
      return '主创';
    case 'conductor':
      return '指挥';
    case 'lyricist':
      return '作词';
    default:
      return raw.trim();
  }
}

/// Strip HTML tags & collapse messy scraper line breaks so overviews read cleanly.
String cleanOverviewText(String? raw) {
  if (raw == null) return '';
  var s = raw
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  return s;
}
