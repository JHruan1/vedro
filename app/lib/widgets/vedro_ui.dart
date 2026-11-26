import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';

/// Signature Anamorphic Cinema 'V' + Play Prism brand mark for Vedro, matching the 5-platform app icon.
class VedroBrandMark extends StatelessWidget {
  const VedroBrandMark({super.key, this.size = 44});
  final double size;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF151C32),
            Color(0xFF0C101E),
            Color(0xFF070911),
          ],
        ),
        borderRadius: BorderRadius.circular(
          skin.cardRadius <= 6 ? (size * 0.20) : (size * 0.26),
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 0.85,
        ),
        boxShadow: [
          BoxShadow(
            color: skin.accent.withValues(alpha: skin.isLight ? 0.18 : 0.28),
            blurRadius: size * 0.38,
            offset: Offset(0, size * 0.14),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _VedroMarkPainter(
          accent: skin.accent,
        ),
      ),
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
  const _VedroMarkPainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.50;
    final cy = size.height * 0.50;
    final u = size.width * 0.33;

    // Subtle optical cinema lens ring
    final ringPaint = Paint()
      ..color = const Color(0x2893C5FD)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.022).clamp(0.6, 1.4)
      ..isAntiAlias = true;
    canvas.drawCircle(Offset(cx, cy), u * 0.88, ringPaint);

    // Upper indigo crown facet
    final crown = Path()
      ..moveTo(cx - u * 0.01, cy - u * 0.02)
      ..lineTo(cx + u * 0.24, cy - u * 0.50)
      ..lineTo(cx + u * 0.50, cy - u * 0.50)
      ..lineTo(cx + u * 0.64, cy - u * 0.02)
      ..close();
    final crownPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomRight,
        colors: [Color(0xFF818CF8), Color(0xFF4F46E5)],
      ).createShader(Rect.fromCenter(center: Offset(cx, cy), width: u * 1.4, height: u * 1.2))
      ..isAntiAlias = true;
    canvas.drawPath(crown, crownPaint);

    // Right warm champagne-gold Cinema Play Prism (▶)
    final rightPrism = Path()
      ..moveTo(cx - u * 0.24, cy + u * 0.54)
      ..lineTo(cx - u * 0.01, cy - u * 0.02)
      ..lineTo(cx + u * 0.24, cy - u * 0.50)
      ..lineTo(cx + u * 0.64, cy - u * 0.02)
      ..close();
    final rightPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFFFFFBEB), Color(0xFFFCD34D), Color(0xFFF59E0B), Color(0xFFEA580C)],
      ).createShader(Rect.fromCenter(center: Offset(cx, cy), width: u * 1.4, height: u * 1.2))
      ..isAntiAlias = true;
    canvas.drawPath(rightPrism, rightPaint);

    // Left sapphire-cyan optical 'V' blade
    final leftWing = Path()
      ..moveTo(cx - u * 0.62, cy - u * 0.50)
      ..lineTo(cx - u * 0.28, cy - u * 0.50)
      ..lineTo(cx + u * 0.06, cy + u * 0.54)
      ..lineTo(cx - u * 0.24, cy + u * 0.54)
      ..close();
    final leftPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFF0F9FF),
          const Color(0xFF7DD3FC),
          Color.lerp(const Color(0xFF38BDF8), accent, 0.35)!,
          const Color(0xFF2563EB),
        ],
      ).createShader(Rect.fromCenter(center: Offset(cx, cy), width: u * 1.4, height: u * 1.2))
      ..isAntiAlias = true;
    canvas.drawPath(leftWing, leftPaint);
  }

  @override
  bool shouldRepaint(covariant _VedroMarkPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

/// Frosted glass surface reserved for floating chrome (nav bars, sheets, HUD).
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 14,
    this.padding,
    this.blur = 26,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final effectiveColor = color ?? skin.glass;
    final effectiveBorder = borderColor ?? skin.borderStrong;
    final radius = BorderRadius.circular(borderRadius);
    return Container(
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: effectiveBorder, width: 0.8),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            color: effectiveColor,
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

/// Borderless technical spec micro-badges (`4K`, `杜比视界`, `杜比全景声`).
class SpecGlyphRow extends StatelessWidget {
  const SpecGlyphRow({super.key, required this.specs, this.forceDarkScrim = false});
  final List<String> specs;
  final bool forceDarkScrim;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final normalized = <String>[];
    final seen = <String>{};
    for (final raw in specs) {
      final clean = _compactLabel(raw);
      if (clean.isEmpty) continue;
      if (seen.add(clean)) {
        normalized.add(clean);
      }
      if (normalized.length >= 5) break;
    }
    if (normalized.isEmpty) return const SizedBox.shrink();

    final chipBg = forceDarkScrim ? const Color(0x22FFFFFF) : skin.subtleChipBg;
    final chipFg = forceDarkScrim ? const Color(0xE8FFFFFF) : skin.fg.withValues(alpha: 0.88);
    final chipBorder = (!forceDarkScrim && skin.frameStyle == 'neon')
        ? Border.all(color: skin.accent.withValues(alpha: 0.35), width: 0.7)
        : null;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: normalized.map((label) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2.5),
          decoration: BoxDecoration(
            color: chipBg,
            borderRadius: BorderRadius.circular(4.5),
            border: chipBorder,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: chipFg,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.25,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
      }).toList(),
    );
  }

  String _compactLabel(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final lower = trimmed.toLowerCase();
    if (lower.contains('dolby vision') || lower == 'dovi' || lower.contains('杜比视界')) {
      return '杜比视界';
    }
    if (lower.contains('atmos') || lower.contains('全景声')) {
      return '杜比全景声';
    }
    if (lower == 'hdr10+' || lower.contains('hdr10+')) return 'HDR10+';
    if (lower == 'hdr' || lower == 'hdr10') return 'HDR10';
    if (lower == '4k' || lower == '2160p' || lower == 'uhd') return '4K';
    if (lower == 'remux') return 'REMUX';
    if (trimmed.length > 14 &&
        (lower.contains('4k') || lower.contains('blu-ray') || lower.contains('remux'))) {
      return '';
    }
    return trimmed.toUpperCase();
  }
}

/// Skin-adaptive horizontal segmented pill control (for Seasons / Filters).
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
    final skin = VedroSkin.of(context);
    final outerR = skin.radiusForPill(38);
    final innerR = skin.radiusForPill(32);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: skin.surface2,
          borderRadius: BorderRadius.circular(outerR),
          border: skin.frameStyle == 'borderless' ? null : Border.all(color: skin.border, width: 0.7),
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6.5),
                decoration: BoxDecoration(
                  color: active ? skin.activePillBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(innerR),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: active ? skin.activePillFg : skin.fg2,
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

/// Choreographed staggered fade + upward glide entrance.
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

/// Tactile precision slider bar with magnetic snap points, live tabular readout, and one-tap reset.
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
    final skin = VedroSkin.of(context);
    final accent = skin.accent;
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
                  style: TextStyle(
                    color: skin.fg2,
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
                          color: skin.subtleChipBg,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '复位',
                          style: TextStyle(color: skin.fg3, fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                decoration: BoxDecoration(
                  color: skin.surface2,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: skin.border, width: 0.7),
                ),
                child: Text(
                  widget.valueText,
                  style: TextStyle(
                    color: skin.fg,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final centerRatio = ((0.0 - widget.min) / span).clamp(0.0, 1.0);
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
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          height: trackH,
                          decoration: BoxDecoration(
                            color: skin.fg.withValues(alpha: skin.isLight ? 0.14 : 0.20),
                            borderRadius: BorderRadius.circular(trackH / 2),
                          ),
                        ),
                        for (final s in widget.snapValues)
                          Positioned(
                            left: (((s - widget.min) / span).clamp(0.0, 1.0) * w - 1)
                                .clamp(0.0, (w - 2).clamp(0.0, w)),
                            child: Container(
                              width: 2,
                              height: trackH + 3,
                              decoration: BoxDecoration(
                                color: skin.fg.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                          ),
                        Positioned(
                          left: fillStart,
                          width: fillWidth.clamp(0.0, w),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 70),
                            height: trackH,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [accent, skin.accentSecondary],
                              ),
                              borderRadius: BorderRadius.circular(trackH / 2),
                            ),
                          ),
                        ),
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
                                  color: accent.withValues(alpha: 0.72),
                                  width: 1.8,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x55000000),
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
                          color: on ? skin.fg : skin.fg3,
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

/// Present a crisp, skin-adaptive modal sheet.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxWidth = 480,
}) {
  final size = MediaQuery.sizeOf(context);
  final wide = size.width >= 720;
  final parentSkin = VedroSkin.of(context);

  if (wide) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: parentSkin.isLight ? 0.36 : 0.62),
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
        final skin = VedroSkin.of(ctx);
        final r = skin.cardRadius.clamp(10.0, 22.0);
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: s.height * 0.86,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: skin.surface,
                borderRadius: BorderRadius.circular(r),
                border: Border.all(color: skin.borderStrong, width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: skin.isLight ? 0.22 : 0.78),
                    blurRadius: 36,
                    offset: const Offset(0, 16),
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
    barrierColor: Colors.black.withValues(alpha: parentSkin.isLight ? 0.36 : 0.65),
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    builder: (ctx) {
      final s = MediaQuery.sizeOf(ctx);
      final skin = VedroSkin.of(ctx);
      final r = skin.cardRadius.clamp(12.0, 22.0);
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 540,
              maxHeight: s.height * 0.84,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: skin.surface,
                borderRadius: BorderRadius.circular(r),
                border: Border.all(color: skin.borderStrong, width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: skin.isLight ? 0.20 : 0.72),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
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
                        color: skin.fg3.withValues(alpha: 0.45),
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
