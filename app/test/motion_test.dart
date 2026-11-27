import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vedro/core/theme/vedro_motion.dart';
import 'package:vedro/core/theme/vedro_theme.dart';
import 'package:vedro/widgets/vedro_ui.dart';

void main() {
  test('VedroSpringCurve: exact endpoints, critically damped never overshoots, bouncy does', () {
    for (final curve in const [
      VedroSpringCurve.smooth,
      VedroSpringCurve.snappy,
      VedroSpringCurve.bouncy,
      VedroSpringCurve.playful,
      VedroSpringCurve(1.4),
    ]) {
      expect(curve.transform(0.0), 0.0);
      expect(curve.transform(1.0), 1.0);
      // Settled within 0.5 % well before the end (no visible snap at t = 1).
      expect((curve.transform(0.97) - 1.0).abs(), lessThan(0.005), reason: '$curve');
    }

    var prev = 0.0;
    for (var i = 1; i < 100; i++) {
      final v = VedroSpringCurve.smooth.transform(i / 100);
      expect(v, greaterThanOrEqualTo(prev));
      expect(v, lessThanOrEqualTo(1.0));
      prev = v;
    }

    var peak = 0.0;
    for (var i = 1; i < 100; i++) {
      final v = VedroSpringCurve.bouncy.transform(i / 100);
      if (v > peak) peak = v;
    }
    expect(peak, greaterThan(1.01));
    expect(peak, lessThan(1.08));

    // Theme curves are real springs now (safe easeOut for opacity).
    expect(VedroTheme.easeOut, same(VedroSpringCurve.smooth));
    expect(VedroSpring.snappy.settleDuration.inMilliseconds, inInclusiveRange(200, 900));
  });

  testWidgets('PressableScale: instant tap still dips, then springs back with momentum',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: PressableScale(
            onTap: () => taps++,
            pressScale: 0.9,
            child: const SizedBox(width: 120, height: 60, child: Text('卡片')),
          ),
        ),
      ),
    );
    double scale() => tester
        .widget<ScaleTransition>(
          find.descendant(of: find.byType(PressableScale), matching: find.byType(ScaleTransition)),
        )
        .scale
        .value;

    expect(scale(), 1.0);
    await tester.tap(find.byType(PressableScale));
    expect(taps, 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(scale(), lessThan(0.98), reason: 'a quick tap must still read as a visible dip');

    var minSeen = scale();
    var overshoot = false;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final s = scale();
      if (s < minSeen) minSeen = s;
      if (s > 1.0005) overshoot = true;
    }
    expect(minSeen, lessThan(0.95));
    expect(overshoot, isTrue, reason: 'release rebound should overshoot slightly like UIKit');
    await tester.pumpAndSettle();
    expect(scale(), closeTo(1.0, 0.002));
  });

  testWidgets('VedroSegmentedControl: selection pill glides on a spring between segments',
      (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: VedroTheme.dark(),
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => VedroSegmentedControl<int>(
                items: const [(0, '第一季'), (1, '第二季'), (2, '第三季')],
                selected: selected,
                onSelected: (v) => setState(() => selected = v),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Finder pill() => find.descendant(
          of: find.byType(VedroSlidingPillRow),
          matching: find.byType(DecoratedBox),
        );
    final startX = tester.getTopLeft(pill().first).dx;

    await tester.tap(find.text('第三季'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 60));
    final midX = tester.getTopLeft(pill().first).dx;
    await tester.pumpAndSettle();
    final endX = tester.getTopLeft(pill().first).dx;
    final target = tester.getTopLeft(find.text('第三季')).dx;

    expect(selected, 2);
    expect(midX, greaterThan(startX));
    expect(midX, lessThan(endX), reason: 'pill is mid-glide, not teleported');
    expect(endX, lessThan(target));
    expect(target - endX, lessThan(20));
  });
}
