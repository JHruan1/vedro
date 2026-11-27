import 'dart:ui' show Color;

/// Parsed Danmaku bullet comment (compatible with DandanPlay JSON & Bilibili XML).
///
/// Canonical pure domain model & parser in `core/services/` so `state/` never
/// needs to depend upward on `widgets/`.
class DanmakuComment {
  const DanmakuComment({
    required this.timeSecs,
    required this.mode, // 1=scroll, 4=bottom, 5=top
    required this.color,
    required this.text,
  });

  final double timeSecs;
  final int mode;
  final Color color;
  final String text;

  static const int _maxParsedComments = 20000;

  static String _decodeXmlEntities(String raw) {
    return raw
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
          final cp = int.tryParse(m.group(1)!, radix: 16);
          return cp != null && cp > 0 && cp <= 0x10FFFF ? String.fromCharCode(cp) : '';
        })
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
          final cp = int.tryParse(m.group(1)!);
          return cp != null && cp > 0 && cp <= 0x10FFFF ? String.fromCharCode(cp) : '';
        })
        .trim();
  }

  static List<DanmakuComment> parseDandanComments(List<dynamic> raw) {
    final out = <DanmakuComment>[];
    for (final entry in raw) {
      if (out.length >= _maxParsedComments) break;
      if (entry is! Map) continue;
      final text = (entry['m'] ?? '').toString().trim();
      final pStr = (entry['p'] ?? '').toString();
      if (text.isEmpty || pStr.isEmpty) continue;
      final parts = pStr.split(',');
      if (parts.length < 3) continue;
      final t = double.tryParse(parts[0]);
      if (t == null || !t.isFinite || t < 0) continue;
      final mode = int.tryParse(parts[1]) ?? 1;
      final rgb = int.tryParse(parts[2]) ?? 0xFFFFFF;
      out.add(DanmakuComment(
        timeSecs: t,
        mode: mode,
        color: Color(0xFF000000 | (rgb & 0xFFFFFF)),
        text: text,
      ));
    }
    out.sort((a, b) => a.timeSecs.compareTo(b.timeSecs));
    return out;
  }

  static List<DanmakuComment> parseBilibiliXml(String xml) {
    final out = <DanmakuComment>[];
    final reg = RegExp(r'<d\s+p="([^"]+)"[^>]*>([^<]+)</d>');
    for (final m in reg.allMatches(xml)) {
      if (out.length >= _maxParsedComments) break;
      final pStr = m.group(1) ?? '';
      final text = _decodeXmlEntities(m.group(2) ?? '');
      if (text.isEmpty) continue;
      final parts = pStr.split(',');
      if (parts.length < 4) continue;
      final t = double.tryParse(parts[0]);
      if (t == null || !t.isFinite || t < 0) continue;
      final mode = int.tryParse(parts[1]) ?? 1;
      final rgb = int.tryParse(parts[3]) ?? 0xFFFFFF;
      out.add(DanmakuComment(
        timeSecs: t,
        mode: mode,
        color: Color(0xFF000000 | (rgb & 0xFFFFFF)),
        text: text,
      ));
    }
    out.sort((a, b) => a.timeSecs.compareTo(b.timeSecs));
    return out;
  }
}
