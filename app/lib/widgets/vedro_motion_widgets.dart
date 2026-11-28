import 'package:flutter/material.dart';

import '../core/theme/vedro_motion.dart';

/// Horizontal selection row with a physics-driven "liquid" selection pill that
/// glides (and morphs width) between items on a velocity-preserving spring —
/// the signature iOS segmented control / macOS toolbar / iOS 26 tab-bar feel.
///
/// Children are measured outside any inner press transforms, so tapping (which
/// dips the child via `PressableScale`) never makes the pill wobble.
class VedroSlidingPillRow extends StatefulWidget {
  const VedroSlidingPillRow({
    super.key,
    required this.children,
    required this.selectedIndex,
    required this.pillDecoration,
    this.spacing = 0,
    this.expand = false,
    this.pillInsets = EdgeInsets.zero,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final List<Widget> children;

  /// `null` or out-of-range hides the pill (e.g. no tab of this row is active).
  final int? selectedIndex;
  final Decoration pillDecoration;
  final double spacing;

  /// Stretch children equally (`Expanded`) across the available width.
  final bool expand;

  /// Inset applied to the measured child rect before drawing the pill.
  final EdgeInsets pillInsets;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  State<VedroSlidingPillRow> createState() => _VedroSlidingPillRowState();
}

class _VedroSlidingPillRowState extends State<VedroSlidingPillRow> with TickerProviderStateMixin {
  late final VedroSpringDriver _left = VedroSpringDriver(vsync: this);
  late final VedroSpringDriver _width = VedroSpringDriver(vsync: this);
  late final VedroSpringDriver _top = VedroSpringDriver(vsync: this);
  late final VedroSpringDriver _height = VedroSpringDriver(vsync: this);
  List<GlobalKey> _keys = const [];
  bool _measured = false;
  bool _measureScheduled = false;
  int? _lastIndex;

  @override
  void initState() {
    super.initState();
    _syncKeys();
  }

  void _syncKeys() {
    if (_keys.length != widget.children.length) {
      _keys = List<GlobalKey>.generate(
        widget.children.length,
        (i) => i < _keys.length ? _keys[i] : GlobalKey(debugLabel: 'vedro-pill-item-$i'),
      );
    }
  }

  @override
  void didUpdateWidget(covariant VedroSlidingPillRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncKeys();
  }

  @override
  void dispose() {
    _left.dispose();
    _width.dispose();
    _top.dispose();
    _height.dispose();
    super.dispose();
  }

  bool get _hasSelection {
    final idx = widget.selectedIndex;
    return idx != null && idx >= 0 && idx < widget.children.length;
  }

  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      _measure();
    });
  }

  void _measure() {
    if (!mounted || !_hasSelection) return;
    final stackBox = context.findRenderObject() as RenderBox?;
    final itemBox = _keys[widget.selectedIndex!].currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || itemBox == null || !stackBox.hasSize || !itemBox.hasSize) return;
    final origin = itemBox.localToGlobal(Offset.zero, ancestor: stackBox);
    final rect = widget.pillInsets.deflateRect(origin & itemBox.size);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final indexChanged = _lastIndex != null && _lastIndex != widget.selectedIndex;
    _lastIndex = widget.selectedIndex;
    if (!_measured) {
      _left.jumpTo(rect.left);
      _width.jumpTo(rect.width);
      _top.jumpTo(rect.top);
      _height.jumpTo(rect.height);
      setState(() => _measured = true);
      return;
    }
    // Pure relayout (window resize / label change) snaps; only a selection change glides.
    final immediate = reduce || !indexChanged && !_left.controller.isAnimating;
    _left.animateTo(rect.left, VedroSpring.indicator, immediate: immediate);
    _width.animateTo(rect.width, VedroSpring.indicator, immediate: immediate);
    _top.animateTo(rect.top, VedroSpring.smooth, immediate: immediate);
    _height.animateTo(rect.height, VedroSpring.smooth, immediate: immediate);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, _) {
        _scheduleMeasure();
        final row = <Widget>[];
        for (var i = 0; i < widget.children.length; i++) {
          if (i > 0 && widget.spacing > 0 && !widget.expand) {
            row.add(SizedBox(width: widget.spacing));
          }
          final keyed = KeyedSubtree(key: _keys[i], child: widget.children[i]);
          row.add(widget.expand ? Expanded(child: keyed) : keyed);
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (_measured)
              AnimatedBuilder(
                animation: Listenable.merge([
                  _left.animation,
                  _width.animation,
                  _top.animation,
                  _height.animation,
                ]),
                builder: (context, child) => Positioned(
                  left: _left.value,
                  top: _top.value,
                  width: _width.value.clamp(0.0, double.infinity),
                  height: _height.value.clamp(0.0, double.infinity),
                  child: child!,
                ),
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _hasSelection ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    curve: VedroSpringCurve.smooth,
                    child: DecoratedBox(decoration: widget.pillDecoration),
                  ),
                ),
              ),
            Row(
              mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: widget.crossAxisAlignment,
              children: row,
            ),
          ],
        );
      },
    );
  }
}

/// Spring-choreographed entrance (fade + upward glide) with an optional delay.
/// Timer-free: the delay lives inside one controller's `Interval`, so it never
/// leaves pending timers behind and is cheap to stagger across many sections.
class VedroEntrance extends StatefulWidget {
  const VedroEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 560),
    this.offsetY = 18.0,
    this.fromScale = 1.0,
    this.enabled = true,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offsetY;
  final double fromScale;
  final bool enabled;

  @override
  State<VedroEntrance> createState() => _VedroEntranceState();
}

class _VedroEntranceState extends State<VedroEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.delay + widget.duration,
  );
  late final double _start =
      widget.delay.inMicroseconds / (widget.delay + widget.duration).inMicroseconds;
  late final Animation<double> _fade = CurvedAnimation(
    parent: _ctrl,
    curve: Interval(_start, (_start + (1 - _start) * 0.5).clamp(0.0, 1.0), curve: Curves.easeOut),
  );
  late final Animation<double> _motion = CurvedAnimation(
    parent: _ctrl,
    curve: Interval(_start, 1.0, curve: VedroSpringCurve.snappy),
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _ctrl.forward();
    } else {
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || VedroMotion.reduced(context)) return widget.child;
    return AnimatedBuilder(
      animation: _ctrl,
      child: widget.child,
      builder: (context, child) {
        // Keep a stable Opacity → Transform tree (identity when settled) so the
        // child's State is never remounted when the entrance completes.
        // Snap vertical glide to whole pixels and skip matrix scale when 1.0 so
        // 0.5–1px hairlines never shimmer during section entrances.
        final m = _ctrl.isCompleted ? 1.0 : _motion.value;
        final dy = ((1 - m) * widget.offsetY).roundToDouble();
        final scale = widget.fromScale + (1 - widget.fromScale) * m;
        return Opacity(
          opacity: _fade.value.clamp(0.0, 1.0),
          child: (widget.fromScale - 1.0).abs() < 1e-4
              ? Transform.translate(
                  offset: Offset(0.0, dy),
                  child: child,
                )
              : Transform(
                  alignment: Alignment.topCenter,
                  transform: Matrix4.identity()
                    ..translateByDouble(0.0, dy, 0.0, 1.0)
                    ..scaleByDouble(scale, scale, 1.0, 1.0),
                  child: child,
                ),
        );
      },
    );
  }
}
