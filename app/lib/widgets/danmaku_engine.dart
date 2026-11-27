import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/services/danmaku_parser.dart';

export '../core/services/danmaku_parser.dart';

/// Cached stroke + fill TextPainter pair so scrolling Danmaku never re-runs
/// expensive text shaping & layout 128× per frame.
class _CachedBulletPainters {
  _CachedBulletPainters(this.stroke, this.fill);
  final TextPainter stroke;
  final TextPainter fill;

  void dispose() {
    stroke.dispose();
    fill.dispose();
  }
}

class _DanmakuLayoutCache {
  static const int _maxEntries = 180;
  final LinkedHashMap<String, _CachedBulletPainters> _cache = LinkedHashMap();
  double _cachedFontSize = -1;
  double _cachedOpacity = -1;

  void clear() {
    for (final entry in _cache.values) {
      entry.dispose();
    }
    _cache.clear();
  }

  void syncParams(double fontSize, double opacity) {
    if ((fontSize - _cachedFontSize).abs() > 0.05 ||
        (opacity - _cachedOpacity).abs() > 0.02) {
      clear();
      _cachedFontSize = fontSize;
      _cachedOpacity = opacity;
    }
  }

  _CachedBulletPainters getOrLayout(DanmakuComment c, double fontSize, double opacity) {
    final key = '${c.color.toARGB32()}:${c.text}';
    final existing = _cache.remove(key);
    if (existing != null) {
      _cache[key] = existing;
      return existing;
    }
    final alpha = opacity.clamp(0.15, 1.0);
    final strokeTp = TextPainter(
      text: TextSpan(
        text: c.text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4
            ..color = Color.fromRGBO(0, 0, 0, (0.80 * alpha).clamp(0.0, 1.0)),
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
          color: c.color.withValues(alpha: alpha),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final entry = _CachedBulletPainters(strokeTp, fillTp);
    if (_cache.length >= _maxEntries) {
      final oldest = _cache.remove(_cache.keys.first);
      oldest?.dispose();
    }
    _cache[key] = entry;
    return entry;
  }
}

/// Real GPU-friendly Danmaku Canvas Layer:
/// renders scrolling, top-fixed, and bottom-fixed bullet comments with cached
/// `TextPainter` layouts (properly disposed to prevent Skia/Impeller paragraph leaks),
/// baked opacity (zero offscreen `Opacity` `saveLayer`), and `RepaintBoundary` isolation.
class DanmakuLayer extends StatefulWidget {
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
  State<DanmakuLayer> createState() => _DanmakuLayerState();
}

class _DanmakuLayerState extends State<DanmakuLayer> {
  final _DanmakuLayoutCache _layoutCache = _DanmakuLayoutCache();

  @override
  void dispose() {
    _layoutCache.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.comments.isEmpty) return const SizedBox.shrink();
    return RepaintBoundary(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topCenter,
          child: FractionallySizedBox(
            widthFactor: 1.0,
            heightFactor: widget.areaFraction.clamp(0.2, 1.0),
            child: CustomPaint(
              painter: _DanmakuPainter(
                comments: widget.comments,
                positionSecs: widget.positionSecs,
                opacity: widget.opacity.clamp(0.15, 1.0),
                fontSize: widget.fontSize.clamp(12.0, 32.0),
                speedSecs: widget.speedSecs.clamp(4.0, 16.0),
                hideTop: widget.hideTop,
                hideBottom: widget.hideBottom,
                layoutCache: _layoutCache,
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
    required this.opacity,
    required this.fontSize,
    required this.speedSecs,
    required this.hideTop,
    required this.hideBottom,
    required this.layoutCache,
  });

  final List<DanmakuComment> comments;
  final double positionSecs;
  final double opacity;
  final double fontSize;
  final double speedSecs;
  final bool hideTop;
  final bool hideBottom;
  final _DanmakuLayoutCache layoutCache;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || comments.isEmpty) return;
    if (!positionSecs.isFinite) return;

    final safeFontSize = fontSize.isFinite ? fontSize.clamp(12.0, 32.0) : 18.0;
    final safeSpeed = speedSecs.isFinite ? speedSecs.clamp(4.0, 20.0) : 9.0;
    layoutCache.syncParams(safeFontSize, opacity);

    final laneH = safeFontSize * 1.38;
    final laneCount = math.max(1, (size.height / laneH).floor());
    final maxWindow = math.max(safeSpeed, 4.2);
    final windowStart = positionSecs - maxWindow;
    final windowEnd = positionSecs + 0.1;

    // Binary search first comment >= windowStart and last comment <= windowEnd
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
    var endIdx = lo;
    while (endIdx < comments.length && comments[endIdx].timeSecs <= windowEnd) {
      endIdx++;
    }
    if (endIdx <= lo) return;

    // Separate occupancy trackers prevent overlapping bullets & prioritize newest bullets on dense scenes.
    final scrollLaneRightEdge = List<double>.filled(laneCount, -1e9);
    final topLaneBusy = List<bool>.filled(laneCount, false);
    final bottomLaneBusy = List<bool>.filled(laneCount, false);

    // Draw newest bullets first (or at most 48) so high-energy moments don't drop current reactions.
    final startIdx = math.max(lo, endIdx - 96);
    var drawn = 0;
    for (var i = endIdx - 1; i >= startIdx && drawn < 48; i--) {
      final c = comments[i];
      final age = positionSecs - c.timeSecs;
      if (age < 0) continue;

      final isTop = c.mode == 5;
      final isBottom = c.mode == 4;
      if ((isTop && hideTop) || (isBottom && hideBottom)) continue;
      if ((isTop || isBottom) && age > 4.2) continue;
      if (!isTop && !isBottom && age > safeSpeed) continue;

      final painters = layoutCache.getOrLayout(c, safeFontSize, opacity);
      final bulletW = painters.fill.width;
      final double dx;
      final double dy;

      if (isTop) {
        final lane = topLaneBusy.indexWhere((b) => !b);
        if (lane < 0) continue;
        topLaneBusy[lane] = true;
        dx = (size.width - bulletW) * 0.5;
        dy = (lane * laneH) + 8;
      } else if (isBottom) {
        final lane = bottomLaneBusy.indexWhere((b) => !b);
        if (lane < 0) continue;
        bottomLaneBusy[lane] = true;
        dx = (size.width - bulletW) * 0.5;
        dy = size.height - ((lane + 1) * laneH) - 8;
      } else {
        final progress = age / safeSpeed;
        dx = size.width - progress * (size.width + bulletW);
        // Find a scroll lane where this bullet does not horizontally collide with an already-placed newer bullet.
        var chosenLane = -1;
        final preferred = i % laneCount;
        for (var offset = 0; offset < laneCount; offset++) {
          final lane = (preferred + offset) % laneCount;
          if (dx + bulletW + 18.0 < scrollLaneRightEdge[lane] || scrollLaneRightEdge[lane] < -1e8) {
            chosenLane = lane;
            break;
          }
        }
        if (chosenLane < 0) continue;
        // Track leftmost edge of newer bullets placed on this lane so older (further left) bullets don't overlap them.
        scrollLaneRightEdge[chosenLane] =
            scrollLaneRightEdge[chosenLane] < -1e8 ? dx : math.min(scrollLaneRightEdge[chosenLane], dx);
        dy = (chosenLane * laneH) + 8;
      }

      if (dy < 0 || dy + laneH > size.height) continue;
      painters.stroke.paint(canvas, Offset(dx, dy));
      painters.fill.paint(canvas, Offset(dx, dy));
      drawn++;
    }
  }

  @override
  bool shouldRepaint(covariant _DanmakuPainter oldDelegate) =>
      (oldDelegate.positionSecs - positionSecs).abs() > 0.025 ||
      !identical(oldDelegate.comments, comments) ||
      oldDelegate.comments.length != comments.length ||
      oldDelegate.fontSize != fontSize ||
      oldDelegate.opacity != opacity ||
      oldDelegate.speedSecs != speedSecs ||
      oldDelegate.hideTop != hideTop ||
      oldDelegate.hideBottom != hideBottom;
}
