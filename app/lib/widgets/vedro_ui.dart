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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF23252C), Color(0xFF141519)],
        ),
        borderRadius: BorderRadius.circular(size * 0.27),
        border: Border.all(color: VedroTheme.lineStrong, width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x70000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: CustomPaint(painter: _VedroMarkPainter()),
    );
  }
}

/// Subtle breathing aperture mark used during silent startup / auto-restore.
class BreathingBrandMark extends StatefulWidget {
  const BreathingBrandMark({super.key, this.size = 48});
  final double size;

  @override
  State<BreathingBrandMark> createState() => _BreathingBrandMarkState();
}

class _BreathingBrandMarkState extends State<BreathingBrandMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final v = Curves.easeInOutSine.transform(_ctrl.value);
        return Opacity(
          opacity: 0.55 + 0.45 * v,
          child: Transform.scale(scale: 0.96 + 0.05 * v, child: child),
        );
      },
      child: VedroBrandMark(size: widget.size),
    );
  }
}

class _VedroMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.52;
    final cy = size.height * 0.5;
    final r = size.width * 0.21;

    final playPath = Path()
      ..moveTo(cx - r * 0.72, cy - r * 0.92)
      ..lineTo(cx + r * 0.92, cy)
      ..lineTo(cx - r * 0.72, cy + r * 0.92)
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
    this.blur = 26,
    this.color = VedroTheme.glass,
    this.borderColor = VedroTheme.lineStrong,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    return Container(
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            color: color,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Tactile Apple-style damped press + desktop hover lift with hover-state callback.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.onHoverChanged,
    this.hoverScale = 1.028,
    this.pressScale = 0.965,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final ValueChanged<bool>? onHoverChanged;
  final double hoverScale;
  final double pressScale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _hovering = false;
  bool _pressing = false;

  void _setHover(bool v) {
    if (_hovering == v) return;
    setState(() => _hovering = v);
    widget.onHoverChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final targetScale = _pressing
        ? widget.pressScale
        : (_hovering ? widget.hoverScale : 1.0);

    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => _setHover(true),
      onExit: (_) {
        _setHover(false);
        if (_pressing) setState(() => _pressing = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressing = true),
        onTapUp: (_) => setState(() => _pressing = false),
        onTapCancel: () => setState(() => _pressing = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onSecondaryTap: widget.onSecondaryTap,
        child: AnimatedScale(
          scale: targetScale,
          duration: Duration(milliseconds: _pressing ? 110 : 240),
          curve: _pressing ? Curves.easeOutQuad : VedroTheme.springCurve,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Apple TV+ style monochrome hairline technical spec marks (`4K`, `DOLBY VISION`, `DOLBY ATMOS`).
/// Quiet and restrained — used only on Detail & Player HUD, never cluttering posters.
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
          padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2.5),
          decoration: BoxDecoration(
            color: const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0x36FFFFFF), width: 0.7),
          ),
          child: Text(
            _compactLabel(s),
            style: const TextStyle(
              color: Color(0xD9FFFFFF),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.35,
              fontFeatures: [FontFeature.tabularFigures()],
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

/// Apple-style horizontal segmented pill control (for Seasons / Filters).
class VedroSegmentedControl<T> extends StatelessWidget {
  const VedroSegmentedControl({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final List<(T value, String label)> items;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: VedroTheme.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: VedroTheme.line, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: items.map((entry) {
            final (val, label) = entry;
            final active = val == selected;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelected(val),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: VedroTheme.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: active ? VedroTheme.surface3 : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: active ? VedroTheme.lineStrong : Colors.transparent,
                    width: 0.6,
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: active ? VedroTheme.fg : VedroTheme.fg2,
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// Present a frosted dark glass sheet (centered floating HUD panel on desktop, bottom sheet on mobile).
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x8A000000),
    isScrollControlled: true,
    builder: (ctx) {
      final size = MediaQuery.sizeOf(ctx);
      final wide = size.width >= 720;
      return SafeArea(
        top: false,
        child: Align(
          alignment: wide ? Alignment.center : Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, wide ? 24 : 0, 16, wide ? 24 : 14),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: wide ? 480 : 520,
                maxHeight: size.height * 0.80,
              ),
              child: GlassSurface(
                borderRadius: 20,
                blur: 30,
                color: VedroTheme.glassStrong,
                borderColor: const Color(0x28FFFFFF),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!wide) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0x40FFFFFF),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                    Flexible(child: builder(ctx)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
