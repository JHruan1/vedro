import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Parsed Danmaku bullet comment (compatible with DandanPlay JSON & Bilibili XML).
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

  static List<DanmakuComment> parseDandanComments(List<dynamic> raw) {
    final out = <DanmakuComment>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final text = (entry['m'] ?? '').toString().trim();
      final pStr = (entry['p'] ?? '').toString();
      if (text.isEmpty || pStr.isEmpty) continue;
      final parts = pStr.split(',');
      if (parts.length < 3) continue;
      final t = double.tryParse(parts[0]) ?? 0.0;
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
      final pStr = m.group(1) ?? '';
      final text = (m.group(2) ?? '')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .trim();
      if (text.isEmpty) continue;
      final parts = pStr.split(',');
      if (parts.length < 4) continue;
      final t = double.tryParse(parts[0]) ?? 0.0;
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

/// Real 60fps GPU-friendly Danmaku Canvas Layer:
/// renders scrolling, top-fixed, and bottom-fixed bullet comments with crisp outline stroke,
/// deterministic collision-avoiding lanes, opacity, font size, speed, and display-area clipping.
class DanmakuLayer extends StatelessWidget {
  const DanmakuLayer({
    super.key,
    required this.comments,
    required this.positionSecs,
    required this.opacity,
    required this.fontSize,
    required this.speedSecs,
    required this.areaFraction,
    required this.hideTop,
    required this.hideBottom,
  });

  final List<DanmakuComment> comments;
  final double positionSecs;
  final double opacity;
  final double fontSize;
  final double speedSecs;
  final double areaFraction;
  final bool hideTop;
  final bool hideBottom;

  @override
  Widget build(BuildContext context) {
    if (comments.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: FractionallySizedBox(
          widthFactor: 1.0,
          heightFactor: areaFraction.clamp(0.2, 1.0),
          child: Opacity(
            opacity: opacity.clamp(0.15, 1.0),
            child: CustomPaint(
              painter: _DanmakuPainter(
                comments: comments,
                positionSecs: positionSecs,
                fontSize: fontSize.clamp(12.0, 32.0),
                speedSecs: speedSecs.clamp(4.0, 16.0),
                hideTop: hideTop,
                hideBottom: hideBottom,
              ),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }
}

class _DanmakuPainter extends CustomPainter {
  _DanmakuPainter({
    required this.comments,
    required this.positionSecs,
    required this.fontSize,
    required this.speedSecs,
    required this.hideTop,
    required this.hideBottom,
  });

  final List<DanmakuComment> comments;
  final double positionSecs;
  final double fontSize;
  final double speedSecs;
  final bool hideTop;
  final bool hideBottom;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || comments.isEmpty) return;

    final laneH = fontSize * 1.38;
    final laneCount = math.max(1, (size.height / laneH).floor());
    final windowStart = positionSecs - speedSecs;
    final windowEnd = positionSecs + 0.1;

    // Binary search first comment >= windowStart
    var lo = 0;
    var hi = comments.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (comments[mid].timeSecs < windowStart) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }

    var drawn = 0;
    for (var i = lo; i < comments.length && drawn < 64; i++) {
      final c = comments[i];
      if (c.timeSecs > windowEnd) break;
      final age = positionSecs - c.timeSecs;
      if (age < 0) continue;

      final isTop = c.mode == 5;
      final isBottom = c.mode == 4;
      if ((isTop && hideTop) || (isBottom && hideBottom)) continue;
      if ((isTop || isBottom) && age > 4.2) continue;
      if (!isTop && !isBottom && age > speedSecs) continue;

      final strokeTp = TextPainter(
        text: TextSpan(
          text: c.text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.4
              ..color = const Color(0xCC000000),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

      final fillTp = TextPainter(
        text: TextSpan(
          text: c.text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: c.color,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

      final lane = i % laneCount;
      final double dx;
      final double dy;
      if (isTop) {
        dx = (size.width - fillTp.width) * 0.5;
        dy = (lane * laneH) + 8;
      } else if (isBottom) {
        dx = (size.width - fillTp.width) * 0.5;
        dy = size.height - ((lane + 1) * laneH) - 8;
      } else {
        final progress = age / speedSecs;
        dx = size.width - progress * (size.width + fillTp.width);
        dy = (lane * laneH) + 8;
      }

      if (dy < 0 || dy + laneH > size.height) continue;
      strokeTp.paint(canvas, Offset(dx, dy));
      fillTp.paint(canvas, Offset(dx, dy));
      drawn++;
    }
  }

  @override
  bool shouldRepaint(covariant _DanmakuPainter oldDelegate) =>
      (oldDelegate.positionSecs - positionSecs).abs() > 0.015 ||
      oldDelegate.comments.length != comments.length ||
      oldDelegate.fontSize != fontSize ||
      oldDelegate.speedSecs != speedSecs ||
      oldDelegate.hideTop != hideTop ||
      oldDelegate.hideBottom != hideBottom;
}
