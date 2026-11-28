import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vedro/core/theme/vedro_theme.dart';
import 'package:vedro/core/utils/stream_error_policy.dart';
import 'package:vedro/widgets/vedro_ui.dart';

void main() {
  group('PlayerStreamErrorPolicy', () {
    test('ignores external subtitle and attachment load errors', () {
      for (final msg in [
        'Can not open external file https://emby.example/Videos/1/Subtitles/3/Stream.srt',
        'Failed to open https://cdn.example/subs/movie.ass',
        'Error loading external track: .vtt timeout',
        'Subtitle track failed to decode',
      ]) {
        expect(
          PlayerStreamErrorPolicy.classify(
            msg,
            isLocalFile: false,
            hwDecodeEnabled: true,
            hwFallbackAttempted: false,
          ),
          PlayerStreamErrorAction.ignore,
          reason: 'Should ignore non-fatal subtitle error: $msg',
        );
      }
    });

    test('distinguishes hard open failure vs transient tcp/eof probe warning', () {
      expect(
        PlayerStreamErrorPolicy.classify(
          'Failed to open http://127.0.0.1:41234/stream/abc',
          isLocalFile: false,
          hwDecodeEnabled: true,
          hwFallbackAttempted: false,
        ),
        PlayerStreamErrorAction.hardOpenFailure,
      );
      expect(
        PlayerStreamErrorPolicy.classify(
          'tcp: Connection reset by peer',
          isLocalFile: false,
          hwDecodeEnabled: true,
          hwFallbackAttempted: false,
        ),
        PlayerStreamErrorAction.transientNetwork,
      );
      expect(
        PlayerStreamErrorPolicy.graceWindowMs(PlayerStreamErrorAction.hardOpenFailure),
        lessThan(
          PlayerStreamErrorPolicy.graceWindowMs(PlayerStreamErrorAction.transientNetwork),
        ),
      );
    });

    test('detects self-recovery when playback advances or duration resolves', () {
      // Transient tcp/eof during initial cloud-drive probe, then video starts & resolves duration
      expect(
        PlayerStreamErrorPolicy.hasSelfRecovered(
          action: PlayerStreamErrorAction.transientNetwork,
          anchorPosSecs: 0.0,
          currentPosSecs: 0.0,
          hadDuration: false,
          currentDurationSecs: 3600.0,
          paused: false,
        ),
        isTrue,
      );
      // Playback actively moved forward by >= 0.35s
      expect(
        PlayerStreamErrorPolicy.hasSelfRecovered(
          action: PlayerStreamErrorAction.hardOpenFailure,
          anchorPosSecs: 10.0,
          currentPosSecs: 10.5,
          hadDuration: true,
          currentDurationSecs: 3600.0,
          paused: false,
        ),
        isTrue,
      );
      // Still stuck at 0s with no duration -> genuine failure, needs reconnect
      expect(
        PlayerStreamErrorPolicy.hasSelfRecovered(
          action: PlayerStreamErrorAction.hardOpenFailure,
          anchorPosSecs: 0.0,
          currentPosSecs: 0.0,
          hadDuration: false,
          currentDurationSecs: 0.0,
          paused: false,
        ),
        isFalse,
      );
    });

    test('Continue Watching resume grace window, active throughput recovery, deferral & EOF guard', () {
      // Resume extends transient grace window so multi-GB byte seeks never false-toast at 1.5s
      expect(
        PlayerStreamErrorPolicy.graceWindowMs(
          PlayerStreamErrorAction.transientNetwork,
          isResumingOrSeeking: true,
        ),
        greaterThanOrEqualTo(4500),
      );

      // Duration already parsed from header (hadDuration=true) while seeking to 25:30;
      // Rust StreamProxy actively downloading resume chunk -> stream is healthy, do NOT reconnect!
      expect(
        PlayerStreamErrorPolicy.hasSelfRecovered(
          action: PlayerStreamErrorAction.transientNetwork,
          anchorPosSecs: 0.0,
          currentPosSecs: 0.0,
          hadDuration: true,
          currentDurationSecs: 3600.0,
          paused: false,
          proxySpeedBps: 8 * 1024 * 1024,
          buffering: true,
          isResumingOrSeeking: true,
          resumeTargetSecs: 1530.0,
        ),
        isTrue,
      );

      // Buffer grew during grace window -> self-recovered silently
      expect(
        PlayerStreamErrorPolicy.hasSelfRecovered(
          action: PlayerStreamErrorAction.transientNetwork,
          anchorPosSecs: 1530.0,
          currentPosSecs: 1530.0,
          hadDuration: true,
          currentDurationSecs: 3600.0,
          paused: false,
          anchorBufferedSecs: 1530.0,
          currentBufferedSecs: 1534.5,
        ),
        isTrue,
      );

      // Quiet deferral while buffering with active proxy speed (capped at 2 defers)
      expect(
        PlayerStreamErrorPolicy.shouldDeferReconnect(
          action: PlayerStreamErrorAction.transientNetwork,
          paused: false,
          proxySpeedBps: 512 * 1024,
          buffering: true,
          isResumingOrSeeking: false,
          deferCount: 0,
        ),
        isTrue,
      );
      expect(
        PlayerStreamErrorPolicy.shouldDeferReconnect(
          action: PlayerStreamErrorAction.transientNetwork,
          paused: false,
          proxySpeedBps: 512 * 1024,
          buffering: true,
          isResumingOrSeeking: false,
          deferCount: 2,
        ),
        isFalse,
      );

      // EOF-near-end resume guard prevents seeking into the final 8s of an episode
      expect(
        PlayerStreamErrorPolicy.sanitizeResumeSecs(resumeSecs: 2.0, totalDurationSecs: 2700.0),
        isNull,
      );
      expect(
        PlayerStreamErrorPolicy.sanitizeResumeSecs(resumeSecs: 2695.0, totalDurationSecs: 2700.0),
        isNull,
      );
      expect(
        PlayerStreamErrorPolicy.sanitizeResumeSecs(resumeSecs: 1530.0, totalDurationSecs: 2700.0),
        closeTo(1530.0, 0.001),
      );
    });
  });

  testWidgets('showGlassSheet hides foreground UI while dragging VedroPrecisionSlider and restores on release',
      (tester) async {
    final peekNotifier = ValueNotifier<bool>(false);
    final labelNotifier = ValueNotifier<String?>(null);
    double sliderVal = 0.4;

    await tester.pumpWidget(
      MaterialApp(
        theme: VedroTheme.dark(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  showGlassSheet<void>(
                    context: ctx,
                    forceDark: true,
                    peekVideoNotifier: peekNotifier,
                    peekLabelNotifier: labelNotifier,
                    builder: (_) => StatefulBuilder(
                      builder: (_, setModal) => Padding(
                        padding: const EdgeInsets.all(16),
                        child: VedroPrecisionSlider(
                          label: '磨皮（肤质保边）',
                          value: sliderVal,
                          min: 0.0,
                          max: 1.0,
                          step: 0.05,
                          valueText: '${(sliderVal * 100).round()}%',
                          onDragStateChanged: (dragging) {
                            peekNotifier.value = dragging;
                            labelNotifier.value = dragging ? '磨皮 ${(sliderVal * 100).round()}%' : null;
                          },
                          onChanged: (v) {
                            setModal(() => sliderVal = v);
                            if (peekNotifier.value) {
                              labelNotifier.value = '磨皮 ${(v * 100).round()}%';
                            }
                          },
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(peekNotifier.value, isFalse);

    final sliderTrack = find
        .descendant(
          of: find.byType(VedroPrecisionSlider),
          matching: find.byType(GestureDetector),
        )
        .last;
    final sliderCenter = tester.getCenter(sliderTrack);
    final gesture = await tester.startGesture(sliderCenter);
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 200));

    // Foreground sheet must fade to 0.0 while dragging and show the compact live peek pill!
    expect(peekNotifier.value, isTrue);
    expect(sliderVal, greaterThan(0.4));
    expect(find.byKey(const ValueKey('sheet-peek-live-pill')), findsOneWidget);
    final fade = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first);
    expect(fade.opacity, equals(0.0));

    // Continue dragging while hidden (proving Opacity 0.0 keeps horizontal drag alive!)
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 60));
    expect(peekNotifier.value, isTrue);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));

    // Releasing the finger restores the sheet cleanly!
    expect(peekNotifier.value, isFalse);
    final fadeAfter = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first);
    expect(fadeAfter.opacity, equals(1.0));

    peekNotifier.dispose();
    labelNotifier.dispose();
  });
}
