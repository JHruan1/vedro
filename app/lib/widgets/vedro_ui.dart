import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme/vedro_theme.dart';

/// Restrained monochrome geometric aperture mark for Vedro.
class VedroBrandMark extends StatelessWidget {
  const VedroBrandMark({super.key, this.size = 44});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: VedroTheme.surface2,
        borderRadius: BorderRadius.circular(size * 0.26),
        border: Border.all(color: VedroTheme.lineStrong, width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: CustomPaint(painter: _VedroMarkPainter()),
    );
  }
}

class _VedroMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final r = size.width * 0.22;

    final playPath = Path()
      ..moveTo(cx - r * 0.62, cy - r * 0.92)
      ..lineTo(cx + r * 0.98, cy)
      ..lineTo(cx - r * 0.62, cy + r * 0.92)
      ..close();

    final paint = Paint()
      ..color = VedroTheme.fg
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(playPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Apple-style frosted glass surface reserved for floating chrome (nav bars, sheets, HUD).
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 14,
    this.padding,
    this.blur = 28,
    this.color = VedroTheme.glass,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: VedroTheme.lineStrong, width: 0.6),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Tactile Apple-style spring press + subtle desktop hover lift.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.hoverScale = 1.03,
    this.pressScale = 0.965,
    this.borderRadius = 10,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double hoverScale;
  final double pressScale;
  final double borderRadius;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _hovering = false;
  bool _pressing = false;

  @override
  Widget build(BuildContext context) {
    final targetScale = _pressing
        ? widget.pressScale
        : (_hovering ? widget.hoverScale : 1.0);

    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() {
        _hovering = false;
        _pressing = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressing = true),
        onTapUp: (_) => setState(() => _pressing = false),
        onTapCancel: () => setState(() => _pressing = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: targetScale,
          duration: Duration(milliseconds: _pressing ? 110 : 220),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Apple TV+ style monochrome hairline technical spec marks (`4K`, `DV`, `ATMOS`, `HDR`).
/// Restrained and quiet — used only on Detail & Player HUD, never cluttering posters.
class SpecGlyphRow extends StatelessWidget {
  const SpecGlyphRow({super.key, required this.specs});
  final List<String> specs;

  @override
  Widget build(BuildContext context) {
    if (specs.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: specs.map((s) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0x30FFFFFF), width: 0.7),
          ),
          child: Text(
            _compactLabel(s),
            style: const TextStyle(
              color: VedroTheme.fg,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        );
      }).toList(),
    );
  }

  String _compactLabel(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('dolby vision') || lower == 'dovi') return 'DOLBY VISION';
    if (lower.contains('atmos')) return 'DOLBY ATMOS';
    return raw.toUpperCase();
  }
}

/// Present a frosted dark glass bottom sheet with an Apple grabber handle.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x88000000),
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.75,
            ),
            child: GlassSurface(
              borderRadius: 20,
              color: VedroTheme.glassStrong,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0x40FFFFFF),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Flexible(child: builder(ctx)),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
