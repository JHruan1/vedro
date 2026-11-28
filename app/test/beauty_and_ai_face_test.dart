import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vedro/core/ffi/vedro_bridge.dart';
import 'package:vedro/core/models/models.dart';
import 'package:vedro/core/models/preferences.dart';
import 'package:vedro/core/services/ai_face_beauty_manager.dart';
import 'package:vedro/core/theme/vedro_theme.dart';
import 'package:vedro/screens/detail_screen.dart';
import 'package:vedro/screens/settings_screen.dart';
import 'package:vedro/state/app_state.dart';
import 'package:vedro/widgets/ai_face_beauty_overlay.dart';
import 'package:vedro/widgets/ai_face_mpv_shader.dart';
import 'package:vedro/widgets/beauty_control_panel.dart';
import 'package:vedro/widgets/beauty_filter.dart';

class _StubCoreClient implements VedroCoreClient {
  _StubCoreClient({this.handler});

  final Future<dynamic> Function(String method, Map<String, dynamic> params)? handler;

  @override
  String get coreVersion => '1.0.24';

  @override
  int get proxySpeedBps => 0;

  @override
  Future<dynamic> invoke(String method, [Map<String, dynamic> params = const {}]) async {
    if (handler != null) return handler!(method, params);
    return const <String, dynamic>{};
  }

  @override
  List<Map<String, dynamic>> pollEvents() => const [];

  @override
  void dispose() {}
}

void main() {
  group('Plan A AI Face Beauty, Cross-GPU & Compact Beauty Studio (v1.0.22)', () {
    test('VedroPreferences round-trips all Plan A AI face morph fields cleanly', () {
      const defaults = VedroPreferences();
      expect(defaults.aiFaceBeautyEnabled, isFalse);
      expect(defaults.aiFaceUseChinaMirror, isTrue);
      expect(defaults.aiFaceSlim, closeTo(0.30, 0.001));
      expect(defaults.aiFaceBigEyes, closeTo(0.22, 0.001));
      expect(defaults.aiFaceVChin, closeTo(0.18, 0.001));
      expect(defaults.aiFaceLipTint, closeTo(0.16, 0.001));

      final updated = defaults.copyWith(
        aiFaceBeautyEnabled: true,
        aiFaceUseChinaMirror: false,
        aiFaceSlim: 0.65,
        aiFaceBigEyes: 0.48,
        aiFaceVChin: 0.35,
        aiFaceLipTint: 0.42,
      );
      final restored = VedroPreferences.fromJson(updated.toJson());
      expect(restored.aiFaceBeautyEnabled, isTrue);
      expect(restored.aiFaceUseChinaMirror, isFalse);
      expect(restored.aiFaceSlim, closeTo(0.65, 0.001));
      expect(restored.aiFaceBigEyes, closeTo(0.48, 0.001));
      expect(restored.aiFaceVChin, closeTo(0.35, 0.001));
      expect(restored.aiFaceLipTint, closeTo(0.42, 0.001));
    });

    test('AiFaceBeautyModelSpec mirrors prioritize China mirror or HuggingFace cleanly', () {
      final cn = AiFaceBeautyModelSpec.modelUrls(preferChinaMirror: true);
      final global = AiFaceBeautyModelSpec.modelUrls(preferChinaMirror: false);
      expect(cn.first, contains('hf-mirror.com'));
      expect(global.first, contains('huggingface.co'));
      expect(cn.length, greaterThanOrEqualTo(3));
      expect(global.any((u) => u.contains('opencv_zoo')), isTrue);
    });

    test('AiFaceTemporalSmoother interpolates smoothly, fades out when absent, and snaps on scene cut', () {
      final smoother = AiFaceTemporalSmoother();
      final f1 = AiTrackedFace.fromJson({
        'x': 0.30,
        'y': 0.20,
        'w': 0.24,
        'h': 0.40,
        'score': 0.92,
        're_x': 0.38,
        're_y': 0.34,
        'le_x': 0.46,
        'le_y': 0.34,
        'nose_x': 0.42,
        'nose_y': 0.42,
        'rm_x': 0.39,
        'rm_y': 0.49,
        'lm_x': 0.45,
        'lm_y': 0.49,
      });

      smoother.ingestDetection([f1], sceneCut: false);
      expect(smoother.smoothed.length, equals(1));
      expect(smoother.smoothed.first.alpha, lessThan(0.5));
      for (var i = 0; i < 15; i++) {
        smoother.step(0.033);
      }
      expect(smoother.smoothed.first.alpha, greaterThan(0.85));
      // Once converged on a static face, step() returns false so Impeller stops rebuilding shaders!
      for (var i = 0; i < 40; i++) {
        smoother.step(0.033);
      }
      expect(smoother.step(0.033), isFalse);

      // Scene cut clears old face immediately
      smoother.ingestDetection(const [], sceneCut: true);
      expect(smoother.smoothed, isEmpty);
    });

    test('AiFaceMpvShaderBuilder emits valid libmpv //!HOOK MAIN GLSL for Windows/Linux GPU morph', () {
      final face = AiTrackedFace.fromJson({
        'x': 0.32,
        'y': 0.22,
        'w': 0.22,
        'h': 0.38,
        'score': 0.94,
        're_x': 0.39,
        're_y': 0.35,
        'le_x': 0.47,
        'le_y': 0.35,
        'nose_x': 0.43,
        'nose_y': 0.43,
        'rm_x': 0.40,
        'rm_y': 0.50,
        'lm_x': 0.46,
        'lm_y': 0.50,
      });
      expect(
        AiFaceMpvShaderBuilder.buildFaceMorphPassGlsl(morph: AiFaceMorphParams.off, faces: [face]),
        isNull,
      );
      final glsl = AiFaceMpvShaderBuilder.buildFaceMorphPassGlsl(
        morph: AiFaceMorphParams.douyin,
        faces: [face],
      );
      expect(glsl, isNotNull);
      expect(glsl!, contains('//!HOOK MAIN'));
      expect(glsl, contains('//!BIND HOOKED'));
      expect(glsl, contains('HOOKED_pos'));
      expect(glsl, contains('HOOKED_tex(warpedUv)'));
      expect(glsl, contains('vedro_face_lip_tint'));
    });

    test('AiFaceCoordinateMapper projects 2.39:1 letterbox video <-> viewport cleanly', () {
      final f = AiTrackedFace.fromJson({
        'x': 0.40,
        'y': 0.25,
        'w': 0.20,
        'h': 0.50,
        'score': 0.95,
        're_x': 0.46,
        're_y': 0.40,
        'le_x': 0.54,
        'le_y': 0.40,
        'nose_x': 0.50,
        'nose_y': 0.50,
        'rm_x': 0.47,
        'rm_y': 0.62,
        'lm_x': 0.53,
        'lm_y': 0.62,
      });
      // 2.39:1 cinema frame (1920x804) inside 16:9 viewport (1920x1080) -> black bars top & bottom
      final inView = AiFaceCoordinateMapper.videoToViewport(
        f,
        videoW: 1920,
        videoH: 804,
        viewW: 1920,
        viewH: 1080,
        fit: BoxFit.contain,
      );
      expect(inView.noseX, closeTo(0.50, 0.001));
      expect(inView.noseY, closeTo(0.50, 0.001));
      // Top of face in video (y=0.25) shifts inward toward vertical center due to top letterbox bar
      expect(inView.y, greaterThan(0.25));
      expect(inView.h, lessThan(0.50));

      final back = AiFaceCoordinateMapper.viewportToVideo(
        inView,
        videoW: 1920,
        videoH: 804,
        viewW: 1920,
        viewH: 1080,
        fit: BoxFit.contain,
      );
      expect(back.x, closeTo(f.x, 0.001));
      expect(back.y, closeTo(f.y, 0.001));
      expect(back.w, closeTo(f.w, 0.001));
      expect(back.h, closeTo(f.h, 0.001));
      expect(back.reY, closeTo(f.reY, 0.001));
    });

    test('Plan B Douyin presets sit immediately at positions 2 & 3 for instant discovery', () {
      expect(BeautyFilterPreset.all[0].id, equals('off'));
      expect(BeautyFilterPreset.all[1].id, equals('douyin_cream'));
      expect(BeautyFilterPreset.all[2].id, equals('cool_white'));
      expect(BeautyFilterPreset.all[1].label, equals('奶油水光'));
      expect(BeautyFilterPreset.all[2].label, equals('冷白网感'));
    });

    testWidgets('Compact BeautyControlPanel fits landscape phone (844x390) with zero scroll and triggers drag peek',
        (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final telemetry = ValueNotifier<AiFaceTrackTelemetry>(const AiFaceTrackTelemetry());
      addTearDown(telemetry.dispose);

      var draggingSeen = false;
      var releasedSeen = false;
      BeautyFilterParams latestGpu = BeautyFilterParams.off;

      await tester.pumpWidget(
        MaterialApp(
          theme: VedroTheme.dark(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: BeautyControlPanel(
                  gpuPreset: 'off',
                  gpuParams: BeautyFilterParams.off,
                  aiEnabled: false,
                  aiMorph: AiFaceMorphParams.subtle,
                  useChinaMirror: true,
                  telemetryNotifier: telemetry,
                  onSelectGpuPreset: (id) async {
                    latestGpu = BeautyFilterPreset.byId(id).params;
                  },
                  onChangeGpuParams: (next) async {
                    latestGpu = next;
                  },
                  onToggleAiEnabled: (_) async {},
                  onChangeAiMorph: (_) async {},
                  onChangeChinaMirror: (_) {},
                  onSliderDragState: (dragging, {String? label}) {
                    if (dragging) {
                      draggingSeen = true;
                    } else {
                      releasedSeen = true;
                    }
                  },
                  onUpdatePeekLabel: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Panel stays super compact (< 195px tall in landscape -> ZERO scrolling!)
      final panelSize = tester.getSize(find.byKey(const ValueKey('compact-beauty-panel')));
      expect(panelSize.height, lessThan(195.0));

      // Plan B Douyin presets immediately visible without scrolling!
      expect(find.byKey(const ValueKey('beauty-preset-douyin_cream')), findsOneWidget);
      expect(find.byKey(const ValueKey('beauty-preset-cool_white')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('beauty-preset-douyin_cream')));
      await tester.pump();
      expect(latestGpu.smooth, greaterThan(0.7));

      // Dragging the first inline slider fires drag-to-peek and releases cleanly
      final smoothSliderTrack = find.byKey(const ValueKey('beauty-slider-磨皮'));
      expect(smoothSliderTrack, findsOneWidget);
      final gesture = await tester.startGesture(tester.getCenter(smoothSliderTrack));
      await gesture.moveBy(const Offset(48, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(draggingSeen, isTrue);
      expect(releasedSeen, isTrue);

      // Switching to Plan A tab immediately shows the optional download prompt (~228 KB)
      await tester.tap(find.byKey(const ValueKey('beauty-tab-ai')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('beauty-sheet-ai-download-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('beauty-sheet-download-ai-btn')), findsOneWidget);
    });

    testWidgets('SettingsScreen exposes Plan A download & Dolby Vision warning in both 视频设置 and AI 翻译',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final app = VedroAppState(_StubCoreClient());
      app.activeSettingsSection = 'video';
      addTearDown(app.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: VedroTheme.fromSkin(app.prefs.activeSkin),
          home: SettingsScreen(
            appState: app,
            onOpenServerHub: () {},
            onOpenAddServer: ([_]) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Visible in 视频设置 with explicit Dolby Vision / HDR compatibility notice!
      expect(find.byKey(const ValueKey('settings-ai-face-beauty-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('download-ai-face-model-btn')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-face-compatibility-notice')), findsOneWidget);
      expect(find.textContaining('杜比视界 (Dolby Vision)'), findsOneWidget);

      // Also visible in AI 翻译 right under Local Offline ASR!
      final aiTab = find.text('AI 翻译');
      if (aiTab.evaluate().isEmpty) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      await tester.tap(aiTab);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-ai-face-beauty-panel-compact')), findsOneWidget);
      expect(find.byKey(const ValueKey('download-ai-face-model-btn-ai-tab')), findsOneWidget);
      expect(find.textContaining('杜比视界 (Dolby Vision)'), findsOneWidget);
    });
  });

  group('Multi-Version Series Batch Download Regression (v1.0.22)', () {
    test('Same-folder multi-version files get distinct seriesMatchSignature and match across episodes', () {
      final ep1Sources = [
        MediaSourceModel(
          id: 'src-ep1-1080',
          name: 'S01E01',
          path: '/media/Show/Season 1/Show.S01E01.1080p.WEB-DL.mkv',
          container: 'mkv',
          size: 1200000000,
        ),
        MediaSourceModel(
          id: 'src-ep1-4k',
          name: 'S01E01',
          path: '/media/Show/Season 1/Show.S01E01.2160p.DV.HDR.mkv',
          container: 'mkv',
          size: 4800000000,
        ),
      ];
      final ep2Sources = [
        MediaSourceModel(
          id: 'src-ep2-1080',
          name: 'S01E02',
          path: '/media/Show/Season 1/Show.S01E02.1080p.WEB-DL.mkv',
          container: 'mkv',
          size: 1250000000,
        ),
        MediaSourceModel(
          id: 'src-ep2-4k',
          name: 'S01E02',
          path: '/media/Show/Season 1/Show.S01E02.2160p.DV.HDR.mkv',
          container: 'mkv',
          size: 4950000000,
        ),
      ];

      final vers = MediaSourceModel.resolveVersions(ep1Sources, stripEpisodePrefix: true);
      expect(vers.length, equals(2));
      expect(vers[0].seriesMatchSignature, isNot(equals(vers[1].seriesMatchSignature)));

      final matchedV0 = MediaSourceModel.matchVersionForEpisode(
        ep2Sources,
        vers[0],
        fallbackIndex: 0,
        strict: true,
      );
      final matchedV1 = MediaSourceModel.matchVersionForEpisode(
        ep2Sources,
        vers[1],
        fallbackIndex: 1,
        strict: true,
      );
      expect(matchedV0?.source.id, equals('src-ep2-1080'));
      expect(matchedV1?.source.id, equals('src-ep2-4k'));

      // Single-source episode belonging ONLY to 1080p does NOT match 4K in strict mode
      final only1080 = [
        MediaSourceModel(
          id: 'src-ep3-1080',
          name: 'S01E03',
          path: '/media/Show/Season 1/Show.S01E03.1080p.WEB-DL.mkv',
          container: 'mkv',
          size: 1180000000,
        ),
      ];
      expect(
        MediaSourceModel.matchVersionForEpisode(only1080, vers[0], fallbackIndex: 0, strict: true)?.source.id,
        equals('src-ep3-1080'),
      );
      expect(
        MediaSourceModel.matchVersionForEpisode(only1080, vers[1], fallbackIndex: 1, strict: true),
        isNull,
      );
    });

    testWidgets('BatchDownloadDialog updates episode rows, filenames, sizes & count when switching version',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final seriesJson = {
        'Id': 'series-1',
        'Name': '庆余年',
        'Type': 'Series',
        'CanDownload': true,
      };
      final episodesJson = [
        {
          'Id': 'ep-1',
          'Name': '第一集',
          'Type': 'Episode',
          'ParentIndexNumber': 1,
          'IndexNumber': 1,
          'CanDownload': true,
          'MediaSources': [
            {
              'Id': 's1-1080',
              'Name': 'S01E01',
              'Path': '/tv/Qing/S01/Qing.S01E01.1080p.WEB-DL.mkv',
              'Container': 'mkv',
              'Size': 1073741824, // 1.00 GB
            },
            {
              'Id': 's1-4k',
              'Name': 'S01E01',
              'Path': '/tv/Qing/S01/Qing.S01E01.2160p.DV.mkv',
              'Container': 'mkv',
              'Size': 4294967296, // 4.00 GB
            },
          ],
        },
        {
          'Id': 'ep-2',
          'Name': '第二集',
          'Type': 'Episode',
          'ParentIndexNumber': 1,
          'IndexNumber': 2,
          'CanDownload': true,
          'MediaSources': [
            {
              'Id': 's2-1080',
              'Name': 'S01E02',
              'Path': '/tv/Qing/S01/Qing.S01E02.1080p.WEB-DL.mkv',
              'Container': 'mkv',
              'Size': 1073741824, // 1.00 GB
            },
          ],
        },
      ];

      final core = _StubCoreClient(handler: (method, params) async {
        if (method == 'get_item') {
          return {'item': seriesJson, 'similar': const [], 'segments': const []};
        }
        if (method == 'get_seasons') {
          return {
            'Items': [
              {'Id': 'season-1', 'Name': '第一季', 'Type': 'Season', 'IndexNumber': 1},
            ],
          };
        }
        if (method == 'get_episodes') {
          return {'Items': episodesJson};
        }
        if (method == 'get_me_quota') {
          return {
            'limits': {'is_admin': false, 'allow_downloads': true},
            'download_quota': {'Enabled': false},
          };
        }
        return const <String, dynamic>{};
      });
      final app = VedroAppState(core)
        ..userId = 'u1'
        ..connectedUrl = 'https://embygo.example.com'
        ..capabilities = ServerCapabilitiesModel(
          dialect: 'embygo',
          serverId: 'embygo-1',
          serverName: 'EmbyGo Test',
          advertisedVersion: '4.8.11.0',
          supportsTranscoding: false,
          supportsPopular: true,
          supportsSuggestions: true,
          supportsHideFromResume: true,
          usesStreamTickets: true,
        );
      addTearDown(app.dispose);
      await app.refreshMeQuota();

      await tester.pumpWidget(
        MaterialApp(
          theme: VedroTheme.dark(),
          home: DetailScreen(
            item: MediaItemModel.fromJson(seriesJson),
            appState: app,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Batch Download dialog from DetailScreen
      await tester.tap(find.byKey(const ValueKey('detail-batch-download-btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('detail-batch-download-dialog')), findsOneWidget);

      // Initially on Version 0 (1080p): BOTH episodes shown with 1080p filenames & 1.00 GB
      expect(find.byKey(const ValueKey('batch-dl-ep-ep-1-s1-1080')), findsOneWidget);
      expect(find.byKey(const ValueKey('batch-dl-ep-ep-2-s2-1080')), findsOneWidget);
      expect(find.textContaining('当前版本共 2 集'), findsOneWidget);

      // Tap Version 1 (4K DV): list below IMMEDIATELY updates to 4K source (4.0 GB, 1 ep)!
      await tester.tap(find.byKey(const ValueKey('batch-dl-version-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('batch-dl-ep-ep-1-s1-4k')), findsOneWidget);
      expect(find.byKey(const ValueKey('batch-dl-ep-ep-1-s1-1080')), findsNothing);
      expect(find.byKey(const ValueKey('batch-dl-ep-ep-2-s2-1080')), findsNothing);
      expect(find.textContaining('当前版本共 1 集'), findsOneWidget);
    });
  });
}
