import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// Choreographed staggered fade + upward glide entrance (Apple TV+ / Linear style).
/// Automatically skips delay/motion inside widget tests or when OS disableAnimations is active.
class VedroStaggeredEntrance extends StatefulWidget {
  const VedroStaggeredEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.offsetY = 12.0,
    this.reduceMotion = false,
  });

  final Widget child;
  final int index;
  final double offsetY;
  final bool reduceMotion;

  @override
  State<VedroStaggeredEntrance> createState() => _VedroStaggeredEntranceState();
}

class _VedroStaggeredEntranceState extends State<VedroStaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _curved;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _curved = CurvedAnimation(parent: _ctrl, curve: VedroTheme.easeOut);
    if (widget.reduceMotion) {
      _ctrl.value = 1.0;
    } else {
      final delayMs = (widget.index.clamp(0, 6)) * 38;
      if (delayMs == 0) {
        _ctrl.forward();
      } else {
        Future<void>.delayed(Duration(milliseconds: delayMs), () {
          if (mounted) _ctrl.forward();
        });
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reduceMotion || MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _curved,
      builder: (_, child) {
        final v = _curved.value;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1.0 - v) * widget.offsetY),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Tactile Apple TV+ / IINA precision slider bar with magnetic snap points,
/// optional bi-directional center origin (`centeredOrigin = true`), live tabular readout,
/// clickable tick marks, and one-tap reset.
class VedroPrecisionSlider extends StatefulWidget {
  const VedroPrecisionSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.valueText,
    required this.onChanged,
    this.defaultValue,
    this.step,
    this.snapValues = const [],
    this.ticks = const [],
    this.centeredOrigin = false,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String valueText;
  final ValueChanged<double> onChanged;
  final double? defaultValue;
  final double? step;
  final List<double> snapValues;
  final List<(double value, String label)> ticks;
  final bool centeredOrigin;

  @override
  State<VedroPrecisionSlider> createState() => _VedroPrecisionSliderState();
}

class _VedroPrecisionSliderState extends State<VedroPrecisionSlider> {
  bool _hovering = false;
  bool _dragging = false;

  double _quantize(double raw) {
    var v = raw.clamp(widget.min, widget.max);
    final span = (widget.max - widget.min).abs();
    if (span > 0) {
      for (final snap in widget.snapValues) {
        if ((v - snap).abs() <= span * 0.022) {
          return snap.clamp(widget.min, widget.max);
        }
      }
    }
    if (widget.step != null && widget.step! > 0) {
      final steps = ((v - widget.min) / widget.step!).round();
      v = (widget.min + steps * widget.step!).clamp(widget.min, widget.max);
    }
    return v;
  }

  void _handleDx(double dx, double width) {
    if (width <= 0) return;
    final ratio = (dx / width).clamp(0.0, 1.0);
    final raw = widget.min + ratio * (widget.max - widget.min);
    final next = _quantize(raw);
    if ((next - widget.value).abs() > 1e-4) {
      for (final s in widget.snapValues) {
        if ((next - s).abs() < 1e-4 && (widget.value - s).abs() >= 1e-4) {
          HapticFeedback.selectionClick();
          break;
        }
      }
      widget.onChanged(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    final span = (widget.max - widget.min) <= 0 ? 1.0 : (widget.max - widget.min);
    final ratio = ((widget.value - widget.min) / span).clamp(0.0, 1.0);
    final active = _hovering || _dragging;
    final trackH = active ? 6.5 : 4.5;
    final canReset = widget.defaultValue != null &&
        (widget.value - widget.defaultValue!).abs() > (widget.step ?? 0.01) * 0.6;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    color: VedroTheme.fg2,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (canReset)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onChanged(widget.defaultValue!);
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0x18FFFFFF),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          '复位',
                          style: TextStyle(color: VedroTheme.fg3, fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2230),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0x22FFFFFF), width: 0.7),
                ),
                child: Text(
                  widget.valueText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final centerRatio =
                  ((0.0 - widget.min) / span).clamp(0.0, 1.0);
              final fillStart = widget.centeredOrigin
                  ? ((ratio < centerRatio ? ratio : centerRatio) * w)
                  : 0.0;
              final fillWidth = widget.centeredOrigin
                  ? ((ratio - centerRatio).abs() * w)
                  : (ratio * w);

              return MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hovering = true),
                onExit: (_) => setState(() => _hovering = false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _handleDx(d.localPosition.dx, w),
                  onHorizontalDragStart: (d) {
                    setState(() => _dragging = true);
                    _handleDx(d.localPosition.dx, w);
                  },
                  onHorizontalDragUpdate: (d) => _handleDx(d.localPosition.dx, w),
                  onHorizontalDragEnd: (_) => setState(() => _dragging = false),
                  onHorizontalDragCancel: () => setState(() => _dragging = false),
                  child: SizedBox(
                    height: 26,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.centerLeft,
                      children: [
                        // Base track
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          height: trackH,
                          decoration: BoxDecoration(
                            color: const Color(0x28FFFFFF),
                            borderRadius: BorderRadius.circular(trackH / 2),
                          ),
                        ),
                        // Snap detent ticks on track
                        for (final s in widget.snapValues)
                          Positioned(
                            left: (((s - widget.min) / span).clamp(0.0, 1.0) * w - 1)
                                .clamp(0.0, (w - 2).clamp(0.0, w)),
                            child: Container(
                              width: 2,
                              height: trackH + 3,
                              decoration: BoxDecoration(
                                color: const Color(0x55FFFFFF),
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                          ),
                        // Active fill
                        Positioned(
                          left: fillStart,
                          width: fillWidth.clamp(0.0, w),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 70),
                            height: trackH,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [accent, Colors.white.withValues(alpha: 0.95)],
                              ),
                              borderRadius: BorderRadius.circular(trackH / 2),
                            ),
                          ),
                        ),
                        // Tactile thumb
                        Positioned(
                          left: (w * ratio - 8).clamp(0.0, (w - 16).clamp(0.0, w)),
                          child: AnimatedScale(
                            scale: _dragging ? 1.18 : (active ? 1.06 : 0.94),
                            duration: const Duration(milliseconds: 140),
                            curve: VedroTheme.easeOut,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: accent.withValues(alpha: 0.55),
                                  width: 1.5,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x88000000),
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          if (widget.ticks.isNotEmpty) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: widget.ticks.map((t) {
                final on = (widget.value - t.$1).abs() < 0.03;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onChanged(t.$1);
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                      child: Text(
                        t.$2,
                        style: TextStyle(
                          color: on ? Colors.white : VedroTheme.fg3,
                          fontSize: 11,
                          fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

/// Present a crisp, high-contrast solid elevated modal sheet:
/// - On desktop/wide screens: uses `showGeneralDialog(barrierDismissible: true)` with smooth
///   scale + fade animation so clicking ANYWHERE outside (or pressing Esc) dismisses cleanly.
/// - On mobile: uses `showModalBottomSheet(isDismissible: true, enableDrag: true)`.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final size = MediaQuery.sizeOf(context);
  final wide = size.width >= 720;

  if (wide) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: const Color(0x9E000000),
      transitionDuration: const Duration(milliseconds: 230),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: VedroTheme.easeOut,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, _, __) {
        final s = MediaQuery.sizeOf(ctx);
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 480,
              maxHeight: s.height * 0.84,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF161821),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF2F3346), width: 1.0),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xC8000000),
                    blurRadius: 36,
                    offset: Offset(0, 16),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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

  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xA6000000),
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    builder: (ctx) {
      final s = MediaQuery.sizeOf(ctx);
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 540,
              maxHeight: s.height * 0.82,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF161821),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF2D3142), width: 1.0),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xB8000000),
                    blurRadius: 32,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3E4357),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
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
