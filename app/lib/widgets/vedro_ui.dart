import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/platform/platform_perf.dart';
import '../core/theme/vedro_liquid_shader.dart';
import '../core/theme/vedro_motion.dart';
import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';
import 'vedro_motion_widgets.dart';

export 'vedro_motion_widgets.dart';

part 'vedro_pulldown_menu.dart';

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
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    final curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine);
    _opacity = Tween<double>(begin: 0.55, end: 1.0).animate(curved);
    _scale = Tween<double>(begin: 0.96, end: 1.01).animate(curved);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _opacity,
        child: ScaleTransition(
          scale: _scale,
          child: VedroBrandMark(size: widget.size),
        ),
      ),
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
    this.enableBlur = true,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final bool enableBlur;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final isLiquid = skin.isLiquidGlass;
    final specMul = switch (skin.liquidSpecular) {
      'subtle' => 0.72,
      'vivid' => 1.32,
      _ => 1.0,
    };
    final hasLiquidGpu = isLiquid && VedroLiquidGlassShader.isAvailable;
    final effBlur = !enableBlur
        ? 0.0
        : (hasLiquidGpu
            ? VedroLiquidGlassShader.gpuBlurSigma(VedroGlassDensity.chrome)
            : PlatformPerfProfile.clampLiveBlur(blur));
    final rawColor = color ?? skin.glass;
    final effectiveColor = (isLiquid && enableBlur)
        ? VedroLiquidGlassShader.liquidFillColor(
            isLight: skin.isLight,
            canvas: skin.canvas,
            surface: skin.surface,
            surface2: skin.surface2,
            density: VedroGlassDensity.chrome,
          )
        : PlatformPerfProfile.adaptGlassFill(rawColor);
    final effectiveBorder = borderColor ?? skin.borderStrong;
    final radius = BorderRadius.circular(borderRadius);
    final inner = DecoratedBox(
      decoration: BoxDecoration(
        color: effectiveColor,
        gradient: isLiquid
            ? VedroLiquidGlassShader.liquidSheenGradient(
                isLight: skin.isLight,
                accent: skin.accent,
                intensity: specMul,
              )
            : null,
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: child,
      ),
    );

    return RepaintBoundary(
      child: Container(
        decoration: isLiquid
            ? BoxDecoration(
                borderRadius: radius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: skin.isLight ? 0.12 : 0.34),
                    blurRadius: PlatformPerfProfile.isMobile ? 12 : 24,
                    offset: Offset(0, PlatformPerfProfile.isMobile ? 5 : 8),
                  ),
                ],
              )
            : null,
        foregroundDecoration: isLiquid
            ? null
            : BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: effectiveBorder, width: 0.8),
              ),
        child: CustomPaint(
          foregroundPainter: isLiquid
              ? LiquidGlassRimPainter(
                  radius: borderRadius,
                  isLight: skin.isLight,
                  accent: skin.accent,
                  intensity: specMul,
                )
              : null,
          child: VedroLiquidGlassBackdrop(
            borderRadius: borderRadius,
            blurSigma: effBlur,
            enableRefraction: enableBlur && isLiquid,
            isLight: skin.isLight,
            accent: skin.accent,
            liquidSpecular: skin.liquidSpecular,
            density: VedroGlassDensity.chrome,
            child: inner,
          ),
        ),
      ),
    );
  }
}

/// Exact on-screen bounding rect of a keyed box relative to the root Overlay,
/// accounting for any active ancestor `Transform.scale` / translation so Peek & Pop
/// previews start pixel-identical with zero jump or aspect-ratio distortion.
Rect? vedroGlobalRectOfKey(BuildContext context, GlobalKey key) {
  final box = key.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize || !box.attached) return null;
  final overlay =
      Overlay.maybeOf(context, rootOverlay: true)?.context.findRenderObject() as RenderBox?;
  return MatrixUtils.transformRect(box.getTransformTo(overlay), Offset.zero & box.size);
}

/// Hero flight shuttle that keeps poster artwork strictly rounded (and framed)
/// during BOTH push (entering DetailScreen) AND pop (flying back to the card),
/// always flying the ALREADY-DECODED source (`fromHeroContext`) poster inside a
/// tight `SizedBox.expand` so the image NEVER vanishes into an empty bordered box
/// while the destination route hydrates.
HeroFlightShuttleBuilder vedroRoundedHeroShuttleBuilder(
  double borderRadius, {
  BoxBorder? border,
}) {
  final radius = BorderRadius.circular(borderRadius);
  return (
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final sourceHero = fromHeroContext.widget as Hero;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(borderRadius: radius, border: border),
      child: ClipRRect(
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: SizedBox.expand(child: sourceHero.child),
        ),
      ),
    );
  };
}

/// Tactile Apple-style damped press + progressive long-press peek lift + desktop hover lift + 10-foot TV D-Pad focus ring.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onLongPressWithRect,
    this.onSecondaryTap,
    this.onSecondaryTapWithRect,
    this.onHoverChanged,
    this.onFocusChanged,
    this.hoverScale = 1.028,
    this.pressScale = 0.965,
    this.peekScale = 1.032,
    this.autofocus = false,
    this.canRequestFocus = true,
    this.focusNode,
    this.borderRadius,
    this.showFocusRing = true,
    this.primaryFocusRingOnly = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(Rect anchorRect)? onLongPressWithRect;
  final VoidCallback? onSecondaryTap;
  final void Function(Rect anchorRect)? onSecondaryTapWithRect;
  final ValueChanged<bool>? onHoverChanged;
  final ValueChanged<bool>? onFocusChanged;
  final double hoverScale;
  final double pressScale;
  final double peekScale;
  final bool autofocus;
  final bool canRequestFocus;
  final FocusNode? focusNode;
  final BorderRadius? borderRadius;
  final bool showFocusRing;
  final bool primaryFocusRingOnly;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _ContextMenuIntent extends Intent {
  const _ContextMenuIntent();
}

class _PressableScaleState extends State<PressableScale> with SingleTickerProviderStateMixin {
  static const Map<ShortcutActivator, Intent> _kActivateShortcuts = {
    SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.contextMenu): _ContextMenuIntent(),
    SingleActivator(LogicalKeyboardKey.info): _ContextMenuIntent(),
    SingleActivator(LogicalKeyboardKey.gameButtonX): _ContextMenuIntent(),
  };

  bool _hovering = false;
  bool _pressing = false;
  bool _peeking = false;
  bool _focused = false;
  bool _showFocusHighlight = false;
  Timer? _peekChargeTimer;
  Timer? _releaseTimer;
  DateTime? _pressStartedAt;
  FocusNode? _internalFocusNode;

  /// Physics-driven scale: retargets keep momentum, so a quick tap dips and
  /// rebounds with a short natural overshoot exactly like UIKit buttons.
  late final VedroSpringDriver _scale = VedroSpringDriver(vsync: this, initialValue: 1.0);

  /// Minimum time a press stays visibly "down" so instant taps still read.
  static const Duration _minPressVisible = Duration(milliseconds: 85);

  bool get _hasLongPress => widget.onLongPress != null || widget.onLongPressWithRect != null;
  bool get _hasSecondaryTap =>
      widget.onSecondaryTap != null || widget.onSecondaryTapWithRect != null;

  FocusNode get _effectiveFocusNode =>
      widget.focusNode ?? (_internalFocusNode ??= FocusNode(debugLabel: 'pressable_scale'));

  @override
  void dispose() {
    _peekChargeTimer?.cancel();
    _releaseTimer?.cancel();
    _scale.dispose();
    _internalFocusNode?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PressableScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hoverScale != widget.hoverScale ||
        oldWidget.pressScale != widget.pressScale ||
        oldWidget.peekScale != widget.peekScale) {
      _syncScale();
    }
  }

  bool get _focusRingActive {
    final hasFocusForRing = widget.primaryFocusRingOnly
        ? (_focused && _effectiveFocusNode.hasPrimaryFocus)
        : _focused;
    return hasFocusForRing && (_showFocusHighlight || PlatformPerfProfile.isTv);
  }

  double get _targetScale {
    final focusScale = widget.hoverScale > 1.0 ? widget.hoverScale : 1.018;
    if (_peeking) return widget.peekScale;
    if (_pressing) return widget.pressScale;
    if (_focusRingActive) return focusScale;
    if (_hovering) return widget.hoverScale;
    return 1.0;
  }

  void _syncScale() {
    if (!mounted) return;
    final target = _targetScale;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final current = _scale.value;
    final VedroSpring spring;
    if (_peeking) {
      spring = VedroSpring.gentle;
    } else if (target < current - 1e-4) {
      spring = VedroSpring.press;
    } else if (_pressing || _hovering || _focusRingActive) {
      spring = VedroSpring.snappy;
    } else {
      spring = VedroSpring.release;
    }
    _scale.animateTo(target, spring, immediate: reduce);
  }

  Rect? _currentGlobalRect() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return null;
    final overlay =
        Overlay.maybeOf(context, rootOverlay: true)?.context.findRenderObject() as RenderBox?;
    return MatrixUtils.transformRect(box.getTransformTo(overlay), Offset.zero & box.size);
  }

  void _startPress() {
    _peekChargeTimer?.cancel();
    _releaseTimer?.cancel();
    _pressStartedAt = DateTime.now();
    setState(() {
      _pressing = true;
      _peeking = false;
    });
    _syncScale();
    if (_hasLongPress) {
      // Progressive iOS Peek & Pop charge-up: after initial tactile press dip,
      // gently swell the card so it feels alive right before popping into the menu.
      _peekChargeTimer = Timer(const Duration(milliseconds: 200), () {
        if (!mounted || !_pressing) return;
        HapticFeedback.selectionClick();
        setState(() => _peeking = true);
        _syncScale();
      });
    }
  }

  void _endPress({bool immediate = false}) {
    _peekChargeTimer?.cancel();
    if (!_pressing && !_peeking) return;
    final started = _pressStartedAt;
    final held = started == null ? _minPressVisible : DateTime.now().difference(started);
    if (!immediate && !_peeking && held < _minPressVisible) {
      // Let an instant tap register a visible dip before the spring rebound.
      _releaseTimer?.cancel();
      _releaseTimer = Timer(_minPressVisible - held, () => _endPress(immediate: true));
      return;
    }
    _releaseTimer?.cancel();
    setState(() {
      _pressing = false;
      _peeking = false;
    });
    _syncScale();
  }

  void _triggerLongPress() {
    _endPress(immediate: true);
    if (widget.onLongPressWithRect != null) {
      final rect = _currentGlobalRect();
      if (rect != null) {
        widget.onLongPressWithRect!(rect);
        return;
      }
    }
    widget.onLongPress?.call();
  }

  void _triggerSecondaryTap() {
    _endPress(immediate: true);
    if (widget.onSecondaryTapWithRect != null) {
      final rect = _currentGlobalRect();
      if (rect != null) {
        widget.onSecondaryTapWithRect!(rect);
        return;
      }
    }
    if (widget.onSecondaryTap != null) {
      widget.onSecondaryTap!();
    } else if (widget.onLongPressWithRect != null) {
      final rect = _currentGlobalRect();
      if (rect != null) {
        widget.onLongPressWithRect!(rect);
        return;
      }
    } else {
      widget.onLongPress?.call();
    }
  }

  void _setHover(bool v) {
    if (_hovering == v) return;
    setState(() => _hovering = v);
    _syncScale();
    widget.onHoverChanged?.call(v);
  }

  void _setFocus(bool v) {
    final effective = widget.primaryFocusRingOnly ? (v && _effectiveFocusNode.hasPrimaryFocus) : v;
    if (_focused == effective) return;
    setState(() => _focused = effective);
    _syncScale();
    widget.onFocusChanged?.call(effective);
    if (effective) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_focused) return;
        if (Scrollable.maybeOf(context) != null) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.45,
            duration: const Duration(milliseconds: 170),
            curve: VedroTheme.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final focusActive = _focusRingActive;

    Widget content = widget.child;
    if (focusActive && widget.showFocusRing) {
      final skin = VedroSkin.of(context);
      final ringRadius =
          widget.borderRadius ?? BorderRadius.circular(skin.cardRadius.clamp(8.0, 16.0));
      final ringColor = skin.isLight
          ? skin.accent
          : (PlatformPerfProfile.isTv ? Colors.white : skin.accent);
      content = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: ringRadius,
          border: Border.all(
            color: ringColor.withValues(alpha: 0.96),
            width: PlatformPerfProfile.isTv ? 2.6 : 2.0,
          ),
          boxShadow: [
            BoxShadow(
              color: skin.accent.withValues(alpha: PlatformPerfProfile.isTv ? 0.36 : 0.24),
              blurRadius: PlatformPerfProfile.isTv ? 14 : 10,
              spreadRadius: 0.5,
            ),
          ],
        ),
        child: content,
      );
    }

    final interactive = widget.onTap != null || _hasLongPress || _hasSecondaryTap;
    Widget result = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: interactive ? (_) => _startPress() : null,
      onTapUp: interactive ? (_) => _endPress() : null,
      onTapCancel: interactive ? () => _endPress(immediate: true) : null,
      onTap: widget.onTap,
      onLongPress: _hasLongPress ? _triggerLongPress : null,
      onSecondaryTap: (_hasSecondaryTap || _hasLongPress) ? _triggerSecondaryTap : null,
      child: ScaleTransition(
        scale: _scale.animation,
        child: content,
      ),
    );

    if (widget.canRequestFocus && interactive) {
      result = FocusableActionDetector(
        focusNode: _effectiveFocusNode,
        autofocus: widget.autofocus,
        shortcuts: _kActivateShortcuts,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
          _ContextMenuIntent: CallbackAction<_ContextMenuIntent>(
            onInvoke: (_) {
              if (_hasLongPress) {
                _triggerLongPress();
              } else {
                _triggerSecondaryTap();
              }
              return null;
            },
          ),
        },
        mouseCursor: widget.onTap != null && !PlatformPerfProfile.isMobile
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        onShowHoverHighlight: PlatformPerfProfile.isMobile
            ? null
            : (v) {
                _setHover(v);
                if (!v && (_pressing || _peeking)) _endPress(immediate: true);
              },
        onShowFocusHighlight: (v) {
          if (_showFocusHighlight != v) {
            setState(() => _showFocusHighlight = v);
            _syncScale();
          }
        },
        onFocusChange: _setFocus,
        child: result,
      );
      return result;
    }

    if (PlatformPerfProfile.isMobile) {
      return result;
    }

    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => _setHover(true),
      onExit: (_) {
        _setHover(false);
        if (_pressing) _endPress(immediate: true);
      },
      child: result,
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
    final selectedIdx = items.indexWhere((e) => e.$1 == selected);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: skin.surface2,
          borderRadius: BorderRadius.circular(outerR),
          border: skin.frameStyle == 'borderless' ? null : Border.all(color: skin.border, width: 0.7),
        ),
        child: VedroSlidingPillRow(
          selectedIndex: selectedIdx < 0 ? null : selectedIdx,
          pillDecoration: BoxDecoration(
            color: skin.activePillBg,
            borderRadius: BorderRadius.circular(innerR),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: skin.isLight ? 0.10 : 0.28),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          children: [
            for (final (val, label) in items)
              PressableScale(
                onTap: () {
                  if (val != selected) HapticFeedback.selectionClick();
                  onSelected(val);
                },
                hoverScale: 1.0,
                pressScale: 0.95,
                borderRadius: BorderRadius.circular(innerR),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6.5),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    curve: VedroTheme.easeOut,
                    style: TextStyle(
                      color: val == selected ? skin.activePillFg : skin.fg2,
                      fontSize: 13,
                      fontWeight: val == selected ? FontWeight.w600 : FontWeight.w500,
                      fontFamilyFallback: DefaultTextStyle.of(context).style.fontFamilyFallback,
                    ),
                    child: Text(label),
                  ),
                ),
              ),
          ],
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

class _VedroStaggeredEntranceState extends State<VedroStaggeredEntrance> {
  @override
  Widget build(BuildContext context) {
    return VedroEntrance(
      delay: Duration(milliseconds: widget.index.clamp(0, 8) * 36),
      duration: const Duration(milliseconds: 480),
      offsetY: widget.offsetY,
      enabled: !widget.reduceMotion,
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
    this.onDragStateChanged,
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
  final ValueChanged<bool>? onDragStateChanged;
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
  bool _focused = false;

  void _setDragging(bool active) {
    if (_dragging == active) return;
    if (mounted) {
      setState(() => _dragging = active);
    } else {
      _dragging = active;
    }
    widget.onDragStateChanged?.call(active);
  }

  @override
  void dispose() {
    if (_dragging) {
      _dragging = false;
      widget.onDragStateChanged?.call(false);
    }
    super.dispose();
  }

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

  void _stepBy(int direction) {
    final span = (widget.max - widget.min).abs();
    if (span <= 0) return;
    final delta = (widget.step != null && widget.step! > 0) ? widget.step! : (span / 20.0);
    final next = (widget.value + direction * delta).clamp(widget.min, widget.max);
    final quantized = _quantize(next);
    if ((quantized - widget.value).abs() > 1e-4) {
      HapticFeedback.selectionClick();
      widget.onChanged(quantized);
    }
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
    final active = _hovering || _dragging || _focused;
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
                  child: PressableScale(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onChanged(widget.defaultValue!);
                    },
                    hoverScale: 1.03,
                    pressScale: 0.94,
                    borderRadius: BorderRadius.circular(5),
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
          Focus(
            onFocusChange: (hasFocus) {
              if (_focused != hasFocus) setState(() => _focused = hasFocus);
              if (hasFocus) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || !_focused) return;
                  if (Scrollable.maybeOf(context) != null) {
                    Scrollable.ensureVisible(
                      context,
                      alignment: 0.45,
                      duration: const Duration(milliseconds: 170),
                      curve: VedroTheme.easeOut,
                    );
                  }
                });
              }
            },
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent || event is KeyRepeatEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  if (widget.value <= widget.min + 1e-4) {
                    // Release D-Pad Left at minimum so TV users can escape back to the sidebar!
                    return KeyEventResult.ignored;
                  }
                  _stepBy(-1);
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  if (widget.value >= widget.max - 1e-4) {
                    return KeyEventResult.ignored;
                  }
                  _stepBy(1);
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: _focused
                    ? Border.all(
                        color: skin.isLight ? skin.accent : Colors.white.withValues(alpha: 0.9),
                        width: 1.8,
                      )
                    : null,
              ),
              child: LayoutBuilder(
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
                        _setDragging(true);
                        _handleDx(d.localPosition.dx, w);
                      },
                      onHorizontalDragUpdate: (d) => _handleDx(d.localPosition.dx, w),
                      onHorizontalDragEnd: (_) => _setDragging(false),
                      onHorizontalDragCancel: () => _setDragging(false),
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
            ),
          ),
          if (widget.ticks.isNotEmpty) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: widget.ticks.map((t) {
                final on = (widget.value - t.$1).abs() < 0.03;
                return PressableScale(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onChanged(t.$1);
                  },
                  hoverScale: 1.03,
                  pressScale: 0.95,
                  borderRadius: BorderRadius.circular(5),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
/// Pass `forceDark: true` from always-dark overlays like `PlayerScreen` so white text & controls
/// remain crisp even when the user's global theme is Light Mode!
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxWidth = 480,
  bool forceDark = false,
  ValueListenable<bool>? peekVideoNotifier,
  ValueListenable<String?>? peekLabelNotifier,
}) {
  final size = MediaQuery.sizeOf(context);
  final wide = size.width >= 720;
  final parentTheme = Theme.of(context);
  final parentSkin = VedroSkin.of(context);
  final effectiveSkin =
      forceDark && parentSkin.isLight ? parentSkin.withPolarity(false) : parentSkin;
  final effectiveTheme =
      forceDark && parentSkin.isLight ? VedroTheme.fromSkin(effectiveSkin) : parentTheme;

  Widget wrapTheme(Widget child) => Theme(data: effectiveTheme, child: child);

  Widget wrapPeekSurface(BuildContext ctx, Widget surfaceChild, {required double barrierAlpha}) {
    if (peekVideoNotifier == null) return surfaceChild;
    return ValueListenableBuilder<bool>(
      valueListenable: peekVideoNotifier,
      builder: (_, peeking, child) => Stack(
        fit: StackFit.expand,
        children: [
          // Custom dismissible scrim that smoothly disappears while peeking video!
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: peeking ? null : () => Navigator.of(ctx).maybePop(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: VedroTheme.easeOut,
              color: Colors.black.withValues(alpha: peeking ? 0.0 : barrierAlpha),
            ),
          ),
          // Keep slider GestureDetector alive at opacity 0.0 so continuous dragging never drops!
          AnimatedOpacity(
            opacity: peeking ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 140),
            curve: VedroTheme.easeOut,
            child: child,
          ),
          if (peeking && peekLabelNotifier != null)
            Positioned(
              top: MediaQuery.paddingOf(ctx).top + 16,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: ValueListenableBuilder<String?>(
                    valueListenable: peekLabelNotifier,
                    builder: (_, label, __) {
                      if (label == null || label.isEmpty) return const SizedBox.shrink();
                      return Container(
                        key: const ValueKey('sheet-peek-live-pill'),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xCC101218),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0x38FFFFFF), width: 0.7),
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
      child: surfaceChild,
    );
  }

  Widget buildSheetSurface({
    required VedroSkin skin,
    required double radius,
    required double blurFactor,
    double shellOpacity = 1.0,
    required Widget child,
  }) {
    final isLiquid = skin.isLiquidGlass;
    final isFrosted = skin.usesGlassPanels && !isLiquid;
    final isGlassTheme = isLiquid || isFrosted;
    final op = shellOpacity.clamp(0.0, 1.0);
    final baseSigma = isLiquid && VedroLiquidGlassShader.isAvailable
        ? VedroLiquidGlassShader.gpuBlurSigma(VedroGlassDensity.menu)
        : (isGlassTheme ? PlatformPerfProfile.clampLiveBlur(20.0) : 0.0);
    final liveSigma = baseSigma * blurFactor.clamp(0.0, 1.0);
    final baseColor = skin.isLight
        ? (isGlassTheme ? Colors.white : skin.surface)
        : Color.lerp(skin.surface2, skin.surface, 0.36)!;
    final rawFillColor = isLiquid
        ? VedroLiquidGlassShader.liquidFillColor(
            isLight: skin.isLight,
            canvas: skin.canvas,
            surface: skin.surface,
            surface2: skin.surface2,
            density: VedroGlassDensity.menu,
          )
        : (isFrosted
            ? baseColor.withValues(alpha: skin.isLight ? 0.89 : 0.87)
            : skin.surface);
    final fillColor = rawFillColor.withValues(alpha: (rawFillColor.a * op).clamp(0.0, 1.0));

    final body = DecoratedBox(
      decoration: BoxDecoration(
        color: fillColor,
        gradient: isLiquid
            ? VedroLiquidGlassShader.liquidSheenGradient(
                isLight: skin.isLight,
                accent: skin.accent,
                intensity: 1.1,
                opacityFactor: op,
              )
            : null,
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: (skin.isLight ? 0.18 : 0.64) * op),
            blurRadius: 34,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: CustomPaint(
        foregroundPainter: isLiquid
            ? LiquidGlassRimPainter(
                radius: radius,
                isLight: skin.isLight,
                accent: skin.accent,
                intensity: 1.15 * op,
              )
            : null,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: isLiquid
              ? const BoxDecoration()
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: (isFrosted
                            ? (skin.isLight
                                ? Colors.black.withValues(alpha: 0.09)
                                : Colors.white.withValues(alpha: 0.22))
                            : skin.borderStrong)
                        .withValues(
                      alpha: ((isFrosted
                                  ? (skin.isLight ? 0.09 : 0.22)
                                  : skin.borderStrong.a) *
                              op)
                          .clamp(0.0, 1.0),
                    ),
                    width: isFrosted ? 0.85 : 1.0,
                  ),
                ),
          child: VedroLiquidGlassBackdrop(
            borderRadius: radius,
            blurSigma: liveSigma,
            enableRefraction: isLiquid,
            isLight: skin.isLight,
            accent: skin.accent,
            liquidSpecular: skin.liquidSpecular,
            density: VedroGlassDensity.menu,
            suspendDuringPageTransition: false,
            intensityOverride: isLiquid ? (1.15 * op).clamp(0.4, 1.35) : null,
            child: body,
          ),
        ),
      ),
    );
  }

  if (wide) {
    final barrierAlpha = effectiveSkin.isLight ? 0.36 : 0.62;
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: peekVideoNotifier == null,
      barrierLabel: 'Dismiss',
      barrierColor: peekVideoNotifier != null
          ? Colors.transparent
          : Colors.black.withValues(alpha: barrierAlpha),
      transitionDuration: const Duration(milliseconds: 240),
      // ZERO outer FadeTransition/Opacity SaveLayer around BackdropFilter so macOS/Windows
      // sheets blur & refract pixel-accurately from Frame 0 with zero flash or offset!
      transitionBuilder: (ctx, animation, _, child) {
        if (MediaQuery.maybeDisableAnimationsOf(ctx) ?? false) return child;
        final pop = CurvedAnimation(
          parent: animation,
          curve: const Cubic(0.22, 1.0, 0.36, 1.0),
          reverseCurve: Curves.easeInCubic,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(pop),
          child: child,
        );
      },
      pageBuilder: (ctx, animation, __) {
        final s = MediaQuery.sizeOf(ctx);
        final skin = effectiveSkin;
        final r = skin.cardRadius.clamp(12.0, 22.0);
        final dialogWidget = Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: s.height * 0.86,
            ),
            child: AnimatedBuilder(
              animation: animation,
              builder: (_, child) {
                final t = animation.value.clamp(0.0, 1.0);
                final shellOp = (t / 0.35).clamp(0.0, 1.0);
                final contentOp = ((t - 0.06) / 0.48).clamp(0.0, 1.0);
                return buildSheetSurface(
                  skin: skin,
                  radius: r,
                  blurFactor: 0.45 + 0.55 * t,
                  shellOpacity: shellOp,
                  child: Opacity(opacity: contentOp, child: child!),
                );
              },
              child: Builder(
                builder: (innerCtx) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: builder(innerCtx)),
                  ],
                ),
              ),
            ),
          ),
        );
        return wrapTheme(wrapPeekSurface(ctx, dialogWidget, barrierAlpha: barrierAlpha));
      },
    );
  }

  final mobileBarrierAlpha = effectiveSkin.isLight ? 0.36 : 0.65;
  if (peekVideoNotifier != null) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (ctx, animation, __) {
        final s = MediaQuery.sizeOf(ctx);
        final skin = effectiveSkin;
        final r = skin.cardRadius.clamp(12.0, 22.0);
        final slideAnim = CurvedAnimation(
          parent: animation,
          curve: const Cubic(0.22, 1.0, 0.36, 1.0),
          reverseCurve: Curves.easeInCubic,
        );
        final sheetCard = Align(
          alignment: Alignment.bottomCenter,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.16), end: Offset.zero)
                .animate(slideAnim),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 540,
                    maxHeight: s.height * 0.84,
                  ),
                  child: buildSheetSurface(
                    skin: skin,
                    radius: r,
                    blurFactor: 1.0,
                    child: Builder(
                      builder: (innerCtx) => Column(
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
                          Flexible(child: builder(innerCtx)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        return wrapTheme(wrapPeekSurface(ctx, sheetCard, barrierAlpha: mobileBarrierAlpha));
      },
    );
  }

  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: mobileBarrierAlpha),
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    // Crisp linear-decelerate rise, brisk dismissal.
    sheetAnimationStyle: AnimationStyle(
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 200),
      curve: const Cubic(0.22, 1.0, 0.36, 1.0),
      reverseCurve: Curves.easeInCubic,
    ),
    builder: (ctx) {
      final s = MediaQuery.sizeOf(ctx);
      final skin = effectiveSkin;
      final r = skin.cardRadius.clamp(12.0, 22.0);
      return wrapTheme(
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 540,
                maxHeight: s.height * 0.84,
              ),
              child: buildSheetSurface(
                skin: skin,
                radius: r,
                blurFactor: 1.0,
                child: Builder(
                  builder: (innerCtx) => Column(
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
                      Flexible(child: builder(innerCtx)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}


/// Unified spring-presented dialog (drop-in for `showDialog`) used app-wide so
/// every alert / form / lightbox shares the same iOS / macOS presentation:
/// quick fade-in with a spring-settled depth pop, brisk fade-out on dismissal.
/// Captures inherited themes exactly like `showDialog` (e.g. the always-dark player).
Future<T?> showVedroDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  bool useRootNavigator = true,
  bool useSafeArea = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  final skin = VedroSkin.of(context);
  return navigator.push<T>(
    RawDialogRoute<T>(
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: barrierColor ?? Colors.black.withValues(alpha: skin.isLight ? 0.32 : 0.56),
      transitionDuration: const Duration(milliseconds: 440),
      pageBuilder: (ctx, _, __) {
        final dialog = themes.wrap(Builder(builder: builder));
        return useSafeArea ? SafeArea(child: dialog) : dialog;
      },
      transitionBuilder: vedroDialogTransition,
    ),
  );
}

/// Shared dialog presentation: fade + spring depth pop (overshoot-free opacity).
Widget vedroDialogTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
  final fade = CurvedAnimation(
    parent: animation,
    curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    reverseCurve: Curves.easeInCubic,
  );
  final pop = CurvedAnimation(
    parent: animation,
    curve: VedroSpringCurve.bouncy,
    reverseCurve: Curves.easeInCubic,
  );
  return FadeTransition(
    opacity: fade,
    child: ScaleTransition(
      scale: Tween<double>(begin: 0.92, end: 1.0).animate(pop),
      child: child,
    ),
  );
}

/// Safely owns dialog/sheet controllers (e.g. [TextEditingController]) and disposes them
/// in [State.dispose] AFTER the route exit animation finishes, avoiding "used after disposed"
/// crashes during modal dismissal.
class VedroControllerScope<T> extends StatefulWidget {
  const VedroControllerScope({
    super.key,
    required this.create,
    required this.dispose,
    required this.builder,
  });

  final T Function() create;
  final void Function(T value) dispose;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<VedroControllerScope<T>> createState() => _VedroControllerScopeState<T>();
}

class _VedroControllerScopeState<T> extends State<VedroControllerScope<T>> {
  late final T _value;

  @override
  void initState() {
    super.initState();
    _value = widget.create();
  }

  @override
  void dispose() {
    widget.dispose(_value);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
