import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vedro/core/ffi/vedro_bridge.dart';
import 'package:vedro/core/models/models.dart';
import 'package:vedro/core/models/preferences.dart';
import 'package:vedro/main.dart';
import 'package:vedro/state/app_state.dart';

class _MockVedroCore implements VedroCoreClient {
  _MockVedroCore({this.isAdmin = false});
  final bool isAdmin;

  @override
  String get coreVersion => '0.1.3-test';

  @override
  Future<dynamic> invoke(String method, [Map<String, dynamic> params = const {}]) async {
    switch (method) {
      case 'version':
        return <String, dynamic>{'version': '0.1.3-test'};
      case 'list_servers':
        return <dynamic>[];
      case 'get_settings':
        return <String, dynamic>{
          'hwdec': 'auto_zero_copy',
          'prefer_native_dolby_vision': true,
          'tone_mapping': 'bt2446a',
          'audio_mode': 'auto',
          'display': <String, dynamic>{'supports_hdr10': true},
        };
      case 'get_kv':
        return <String, dynamic>{'value': null};
      case 'set_kv':
        return <String, dynamic>{'saved': true};
      case 'discover_servers':
        return <dynamic>[];
      case 'connect_server':
        return <String, dynamic>{
          'capabilities': <String, dynamic>{
            'dialect': 'embygo',
            'server_id': 'embygo-1',
            'server_name': 'My EmbyGo',
            'advertised_version': '4.8.11.0',
            'supports_transcoding': false,
            'supports_popular': true,
            'supports_suggestions': true,
            'supports_hide_from_resume': true,
            'uses_stream_tickets': true,
          },
        };
      case 'login':
        return <String, dynamic>{
          'auth': <String, dynamic>{
            'AccessToken': 'tok',
            'User': <String, dynamic>{
              'Id': 'u1',
              'Name': isAdmin ? 'admin' : 'viewer',
              'Policy': <String, dynamic>{'IsAdministrator': isAdmin},
            },
          },
          'capabilities': <String, dynamic>{
            'dialect': 'embygo',
            'server_id': 'embygo-1',
            'server_name': 'My EmbyGo',
            'advertised_version': '4.8.11.0',
            'supports_transcoding': false,
            'supports_popular': true,
            'supports_suggestions': true,
            'supports_hide_from_resume': true,
            'uses_stream_tickets': true,
          },
        };
      case 'get_home':
        return <String, dynamic>{
          'views': [
            <String, dynamic>{
              'Id': 'lib1',
              'Name': '电影',
              'Type': 'CollectionFolder',
              'CollectionType': 'movies',
              'ImageTags': <String, dynamic>{'Primary': 'lib-cover-tag'},
            },
          ],
          'popular': [
            <String, dynamic>{
              'Id': 'm1',
              'Name': 'Dune: Part Two',
              'Type': 'Movie',
              'ProductionYear': 2024,
              'CommunityRating': 8.6,
              'Overview': '4K UHD Blu-ray Remux with Dolby Vision & Dolby Atmos.',
              'BackdropImageTags': <dynamic>['bd-tag-1'],
              'MediaSources': [
                <String, dynamic>{
                  'Id': 'ms1',
                  'Name': 'Dune.Part.Two.2024.2160p.UHD.REMUX.DV.TrueHD.Atmos.mkv',
                  'Container': 'mkv',
                }
              ],
            }
          ],
          'resume': <dynamic>[],
          'next_up': <dynamic>[],
          'suggestions': <dynamic>[],
          'favorites': <dynamic>[],
          'latest_by_library': <dynamic>[],
        };
      default:
        return <String, dynamic>{};
    }
  }

  @override
  List<Map<String, dynamic>> pollEvents() => const [];

  @override
  void dispose() {}
}

void main() {
  test('Models, HomeSectionConfig defaults, libraryCoverUrl, cleanOverview & VedroPreferences', () {
    // 1. Multi-route profiles & GeneratedArt
    final srv = SavedServerProfile.fromJson({
      'id': 's1',
      'name': 'Main',
      'url': 'https://line1.example.com',
      'dialect': 'embygo',
      'active_route_id': 'r2',
      'routes': [
        {'id': 'r1', 'name': 'CF 线路', 'url': 'https://line1.example.com'},
        {'id': 'r2', 'name': '香港直连', 'url': 'https://hk.example.com'},
      ],
    });
    expect(srv.routes.length, equals(2));
    expect(srv.activeRoute?.name, equals('香港直连'));
    expect(artworkInitials('沙丘2'), equals('沙丘'));
    expect(artworkInitials('Episode 101'), equals('E101'));
    expect(deterministicHues('abc'), equals(deterministicHues('abc')));

    // 2. Default Home section order: libraries -> resume -> next_up -> favorites -> latest; suggestions OFF
    final defs = HomeSectionConfig.defaults;
    expect(defs.map((d) => d.id).toList(),
        equals(['libraries', 'resume', 'next_up', 'favorites', 'latest', 'suggestions']));
    expect(defs.where((d) => d.visible).map((d) => d.id).toList(),
        equals(['libraries', 'resume', 'next_up', 'favorites', 'latest']));
    expect(defs.firstWhere((d) => d.id == 'suggestions').visible, isFalse);

    // 3. Overview HTML cleaner
    expect(cleanOverviewText('<p>Hello<br/>World &amp; <b>Cinema</b></p>'),
        equals('Hello\nWorld & Cinema'));

    // 4. Library server cover resolution
    final app = VedroAppState(_MockVedroCore());
    app.connectedUrl = 'https://media.example.com';
    final lib = MediaItemModel.fromJson({
      'Id': 'lib1',
      'Name': '电影',
      'Type': 'CollectionFolder',
      'ImageTags': {'Primary': 'cover123'},
    });
    expect(app.libraryCoverUrl(lib), contains('/Items/lib1/Images/Primary?tag=cover123'));
    expect(app.wideArt(lib)?.isPoster, isFalse);

    // 5. VedroPreferences roundtrip & passcode hashing
    const orig = VedroPreferences(
      accentId: 'emerald',
      bufferSizeMb: 256,
      aiEnabled: true,
      aiModel: 'deepseek-chat',
      danmakuEnabled: true,
      passcodeEnabled: true,
      passcodeHash: 'abc',
    );
    final decoded = VedroPreferences.fromJson(orig.toJson());
    expect(decoded.accentId, equals('emerald'));
    expect(decoded.bufferSizeMb, equals(256));
    expect(decoded.aiModel, equals('deepseek-chat'));
    expect(decoded.danmakuEnabled, isTrue);
    expect(hashPasscode('1234'), equals(hashPasscode('1234')));
    expect(hashPasscode('1234'), isNot(equals(hashPasscode('4321'))));
  });

  testWidgets(
      'Launches into Home Server Hub, connects, renders landscape Hero + hides Admin Console for regular users',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.vedro.player/hardware'),
      (call) async => <String, dynamic>{
        'supports_hdr10': true,
        'supports_hlg': true,
        'supports_native_dolby_vision': true,
        'supports_atmos_bitstream': true,
        'max_luminance_nits': 1600,
        'refresh_rate_hz': 120.0,
      },
    );

    final mock = _MockVedroCore(isAdmin: false);
    await tester.pumpWidget(VedroApp(core: mock));
    await tester.pumpAndSettle();

    expect(find.text('添加媒体服务器'), findsOneWidget);
    expect(find.text('播放器设置'), findsOneWidget);

    await tester.tap(find.text('添加媒体服务器'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(1), 'viewer');
    await tester.enterText(find.byType(TextField).at(2), 'secret');
    await tester.tap(find.text('连接并添加'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Dune: Part Two'), findsOneWidget);
    expect(find.text('媒体库'), findsWidgets);
    expect(find.text('猜你喜欢'), findsNothing);

    // Open Settings and verify rich categories are present while Admin Console is strictly hidden
    await tester.tap(find.text('设置').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('应用风格'), findsOneWidget);
    expect(find.text('模块配置'), findsOneWidget);
    expect(find.text('列表配置'), findsOneWidget);
    expect(find.text('播放设置'), findsOneWidget);
    expect(find.text('弹幕设置'), findsOneWidget);
    expect(find.text('AI 服务（翻译）'), findsOneWidget);
    expect(find.text('隐私保护'), findsOneWidget);
    expect(find.text('服务器管理台'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test('Direct dart:ffi integration loads REAL compiled Rust libvedro_ffi.so', () async {
    final soPath = Platform.environment['VEDRO_FFI_PATH'] ?? '../target/release/libvedro_ffi.so';
    if (!File(soPath).existsSync()) {
      return;
    }
    final bridge = VedroFfiBridge.open(libraryPath: soPath);
    try {
      expect(bridge.coreVersion, isNotEmpty);
      final ver = await bridge.invoke('version') as Map<String, dynamic>;
      expect(ver['proxy_addr'].toString(), startsWith('127.0.0.1:'));
      final cfg = await bridge.invoke('get_settings') as Map<String, dynamic>;
      expect(cfg['hwdec'], equals('auto_zero_copy'));
      await bridge.invoke('set_kv', {'key': 'test_k', 'value': {'ok': true}});
      final kv = await bridge.invoke('get_kv', {'key': 'test_k'}) as Map<String, dynamic>;
      expect(kv['value'], equals({'ok': true}));
    } finally {
      bridge.dispose();
    }
  });
}
