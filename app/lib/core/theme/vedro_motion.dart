import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../platform/platform_perf.dart';

/// Vedro unified physics motion system (Apple / SwiftUI parity on every OS).
///
/// The root cause of "stiff" Flutter motion is fixed-duration cubic tweens that
/// restart from zero velocity whenever they are interrupted. iOS / macOS instead
/// drive almost every transition with damped springs that *preserve velocity*
/// on retarget, so presses, hovers, tab indicators and sheets feel continuous.
///
/// - [VedroSpring] mirrors SwiftUI's `.spring(response:dampingFraction:)`.
/// - [VedroSpringCurve] is the analytic, normalized spring shape usable anywhere
///   a [Curve] is accepted (route transitions, `AnimatedFoo`, `animateTo`).
/// - [VedroSpringDriver] retargets an unbounded [AnimationController] with a
///   real [SpringSimulation] while carrying over the current velocity.
@immutable
class VedroSpring {
  const VedroSpring({required this.response, required this.dampingFraction});

  /// Seconds for one undamped oscillation (SwiftUI `response`).
  final double response;

  /// 1.0 = critically damped (no overshoot); < 1.0 = bouncy.
  final double dampingFraction;

  /// Fast finger-down dip (no overshoot).
  static const press = VedroSpring(response: 0.20, dampingFraction: 1.0);

  /// Finger-up rebound with a lively, short overshoot (iOS button release).
  static const release = VedroSpring(response: 0.40, dampingFraction: 0.62);

  /// Default interactive spring (SwiftUI `.snappy`).
  static const snappy = VedroSpring(response: 0.32, dampingFraction: 0.84);

  /// Selection indicators / liquid tab lens (slight playful overshoot).
  static const indicator = VedroSpring(response: 0.38, dampingFraction: 0.76);

  /// Pop-in for menus, popovers and peek previews (SwiftUI `.bouncy`).
  static const bouncy = VedroSpring(response: 0.44, dampingFraction: 0.70);

  /// Layout & large surfaces (SwiftUI `.smooth`).
  static const smooth = VedroSpring(response: 0.46, dampingFraction: 1.0);

  /// Long-press peek swell.
  static const gentle = VedroSpring(response: 0.55, dampingFraction: 0.86);

  SpringDescription get description => SpringDescription.withDampingRatio(
        mass: 1.0,
        stiffness: math.pow(2 * math.pi / response, 2).toDouble(),
        ratio: dampingFraction,
      );

  /// Time until the spring is visually settled (≈0.1 % residual).
  Duration get settleDuration {
    final w0 = 2 * math.pi / response;
    final z = dampingFraction;
    final decay = z <= 1.0 ? z * w0 : w0 * (z - math.sqrt(z * z - 1));
    final secs = (6.9 / decay).clamp(0.12, 1.6);
    return Duration(microseconds: (secs * 1e6).round());
  }

  /// Normalized curve with the same shape (pair it with [settleDuration]).
  VedroSpringCurve get curve => VedroSpringCurve(dampingFraction);

  SpringSimulation simulate(double from, double to, double velocity) => SpringSimulation(
        description,
        from,
        to,
        velocity,
        tolerance: const Tolerance(distance: 0.0004, velocity: 0.004),
      );
}

/// Analytic damped-harmonic-oscillator curve normalized to settle at `t = 1`.
///
/// Unlike `Cubic` overshoot approximations, the derivative is continuous and
/// the tail decays exponentially — exactly like UIKit / SwiftUI springs.
/// Underdamped (`dampingFraction < 1`) curves overshoot `1.0`: never feed them
/// straight into an opacity.
class VedroSpringCurve extends Curve {
  const VedroSpringCurve(this.dampingFraction);

  final double dampingFraction;

  /// Critically damped: silky ease-out with zero overshoot (safe for opacity).
  static const smooth = VedroSpringCurve(1.0);

  /// Tiny 0.4 % overshoot, reads as "settling into place".
  static const snappy = VedroSpringCurve(0.86);

  /// ~3 % overshoot: tab pills, cards, popovers.
  static const bouncy = VedroSpringCurve(0.74);

  /// ~8 % overshoot: playful pop-ins (FAB, badges).
  static const playful = VedroSpringCurve(0.62);

  /// Envelope decay rate in normalized time; e^-8.5 ≈ 0.02 % residual at t = 1.
  static const double _lambda = 8.5;

  @override
  double transformInternal(double t) {
    final z = dampingFraction;
    if (z < 0.999) {
      final w0 = _lambda / z;
      final wd = w0 * math.sqrt(1 - z * z);
      final env = math.exp(-_lambda * t);
      return 1 - env * (math.cos(wd * t) + (_lambda / wd) * math.sin(wd * t));
    }
    if (z <= 1.001) {
      return 1 - math.exp(-_lambda * t) * (1 + _lambda * t);
    }
    // Overdamped: slow root decays at `_lambda`.
    final s = math.sqrt(z * z - 1);
    final w0 = _lambda / (z - s);
    final r1 = -w0 * (z - s);
    final r2 = -w0 * (z + s);
    return 1 - (r2 * math.exp(r1 * t) - r1 * math.exp(r2 * t)) / (r2 - r1);
  }

  @override
  String toString() => 'VedroSpringCurve($dampingFraction)';
}

/// Retargetable spring driver over an unbounded [AnimationController]:
/// interrupting an in-flight animation keeps its momentum (no velocity snap).
class VedroSpringDriver {
  VedroSpringDriver({required TickerProvider vsync, double initialValue = 0.0})
      : controller = AnimationController.unbounded(vsync: vsync, value: initialValue);

  final AnimationController controller;
  double? _target;

  double get value => controller.value;
  double get target => _target ?? controller.value;
  Animation<double> get animation => controller;

  void animateTo(double target, VedroSpring spring, {bool immediate = false}) {
    if (_target == target && (controller.isAnimating || controller.value == target)) return;
    _target = target;
    if (immediate) {
      controller.value = target;
      return;
    }
    controller.animateWith(spring.simulate(controller.value, target, controller.velocity));
  }

  void jumpTo(double value) {
    _target = value;
    controller.value = value;
  }

  void dispose() => controller.dispose();
}

/// Motion helpers shared by widgets.
abstract final class VedroMotion {
  /// Whether motion should be collapsed (OS accessibility or tests that disable animation).
  static bool reduced(BuildContext context) => PlatformPerfProfile.shouldReduceMotion(context);

  /// Spring-shaped page/route timing (forward, reverse).
  static const Duration routeForward = Duration(milliseconds: 420);
  static const Duration routeReverse = Duration(milliseconds: 260);
}
