import 'package:flutter/widgets.dart';

import '../platform/platform_perf.dart';

/// Drop-in [ScrollController] that gives Windows / Linux / macOS mouse wheels
/// the buttery, momentum-like glide of a macOS trackpad.
///
/// Flutter applies each wheel notch as an instant `jumpTo`, which reads as
/// stutter on 60–165 Hz desktop panels. On desktop this controller instead
/// accumulates notch deltas into a moving target and eases toward it, so rapid
/// wheel spins blend into one continuous motion. Mobile & TV are untouched.
class VedroScrollController extends ScrollController {
  VedroScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
    super.onAttach,
    super.onDetach,
  });

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    if (!PlatformPerfProfile.isDesktop || PlatformPerfProfile.isTv) {
      return super.createScrollPosition(physics, context, oldPosition);
    }
    return _SmoothWheelScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class _SmoothWheelScrollPosition extends ScrollPositionWithSingleContext {
  _SmoothWheelScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  static const Duration _glide = Duration(milliseconds: 340);
  static const Curve _glideCurve = Cubic(0.22, 0.85, 0.32, 1.0);

  double? _wheelTarget;
  bool _wheelAnimating = false;

  @override
  void pointerScroll(double delta) {
    if (delta == 0.0) {
      goBallistic(0.0);
      return;
    }
    final base = (_wheelAnimating && _wheelTarget != null) ? _wheelTarget! : pixels;
    final target = (base + delta).clamp(minScrollExtent, maxScrollExtent).toDouble();
    if ((target - pixels).abs() < 0.5 && !_wheelAnimating) return;
    _wheelTarget = target;
    _wheelAnimating = true;
    animateTo(target, duration: _glide, curve: _glideCurve).whenComplete(() {
      if (_wheelTarget == target) {
        _wheelAnimating = false;
        _wheelTarget = null;
      }
    });
  }

  @override
  void beginActivity(ScrollActivity? newActivity) {
    // Any non-wheel interaction (drag, fling, programmatic jump) cancels the glide target.
    if (newActivity is! DrivenScrollActivity) {
      _wheelAnimating = false;
      _wheelTarget = null;
    }
    super.beginActivity(newActivity);
  }
}
