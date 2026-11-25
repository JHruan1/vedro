import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vedro/core/ffi/vedro_bridge.dart';
import 'package:vedro/core/models/models.dart';
import 'package:vedro/core/models/preferences.dart';
import 'package:vedro/main.dart';
import 'package:vedro/screens/detail_screen.dart';
import 'package:vedro/state/app_state.dart';
import 'package:vedro/widgets/danmaku_engine.dart';

class _MockVedroCore implements VedroCoreClient {
  _MockVedroCore({this.isAdmin = false});
  final bool isAdmin;

  @override
  String get coreVersion => '0.2.1-test';

  @override
  Future<dynamic> invoke(String method, [Map<String, dynamic> params = const {}]) async {
    switch (method) {
      case 'version':
        return <String, dynamic>{'version': '0.2.1-test'};
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
      case 'get_item':
        return <String, dynamic>{
          'item': <String, dynamic>{
            'Id': 'tv1',
            'Name': '三体',
            'OriginalTitle': '3 Body Problem',
            'Type': 'Series',
            'Overview': '简短的一句话简介，不需要展开按钮。',
            'ProductionYear': 2024,
            'PremiereDate': '2024-03-21T00:00:00Z',
            'Status': 'Continuing',
            'CommunityRating': 8.2,
            'CriticRating': 79.0,
            'OfficialRating': 'TV-MA',
            'ProductionLocations': ['United States'],
            'Studios': [
              {'Name': 'Netflix', 'Id': '1'}
            ],
            'Tags': ['科幻', '宇宙社会学'],
            'Genres': ['科幻', '悬疑'],
            'ProviderIds': {'Tmdb': '108545', 'Imdb': 'tt13016388'},
          },
          'similar': <dynamic>[],
          'segments': <dynamic>[],
        };
      case 'get_seasons':
        return <String, dynamic>{'Items': <dynamic>[]};
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

    // 5. VedroPreferences roundtrip & passcode hashing (including v0.2.0 pro fields)
    const orig = VedroPreferences(
      accentId: 'emerald',
      bufferSizeMb: 256,
      aiEnabled: true,
      aiModel: 'deepseek-chat',
      danmakuEnabled: true,
      danmakuSpeedSecs: 7.0,
      passcodeEnabled: true,
      passcodeHash: 'abc',
      customSkipIntroSecs: 85,
      customSkipOutroSecs: 90,
      rememberBrightness: true,
      savedBrightness: 0.72,
      longPressSpeed: 2.5,
      pinchToZoom: true,
      externalPlayer: 'iina',
      anime4kEnabled: true,
      anime4kMode: 'A+A',
      anime4kOnlyAnime: false,
      customMpvConf: 'interpolation=yes',
      forceAssOverride: true,
      searchHistory: ['沙丘', '进击的巨人'],
      serverCardLayout: 'list',
      serverCardStyles: {
        'srv-1': ServerCardStyle(
          customName: '主力 4K 服',
          subtitle: '香港直连',
          themeId: 'emerald',
          iconId: 'film',
          hideAddress: true,
        ),
      },
    );
    final decoded = VedroPreferences.fromJson(orig.toJson());
    expect(decoded.accentId, equals('emerald'));
    expect(decoded.bufferSizeMb, equals(256));
    expect(decoded.aiModel, equals('deepseek-chat'));
    expect(decoded.danmakuEnabled, isTrue);
    expect(decoded.danmakuSpeedSecs, equals(7.0));
    expect(decoded.customSkipIntroSecs, equals(85));
    expect(decoded.customSkipOutroSecs, equals(90));
    expect(decoded.rememberBrightness, isTrue);
    expect(decoded.savedBrightness, closeTo(0.72, 0.001));
    expect(decoded.longPressSpeed, equals(2.5));
    expect(decoded.externalPlayer, equals('iina'));
    expect(decoded.anime4kEnabled, isTrue);
    expect(decoded.anime4kMode, equals('A+A'));
    expect(decoded.anime4kOnlyAnime, isFalse);
    expect(decoded.customMpvConf, equals('interpolation=yes'));
    expect(decoded.forceAssOverride, isTrue);
    expect(decoded.searchHistory, equals(['沙丘', '进击的巨人']));
    expect(decoded.serverCardLayout, equals('list'));
    expect(decoded.serverCardStyles['srv-1']?.customName, equals('主力 4K 服'));
    expect(decoded.serverCardStyles['srv-1']?.themeId, equals('emerald'));
    expect(decoded.serverCardStyles['srv-1']?.hideAddress, isTrue);

    // 7. Rich NFO metadata parsing
    final series = MediaItemModel.fromJson({
      'Id': 'tv1',
      'Name': '三体',
      'OriginalTitle': '3 Body Problem',
      'Type': 'Series',
      'PremiereDate': '2024-03-21T00:00:00Z',
      'Status': 'Continuing',
      'CriticRating': 79.0,
      'OfficialRating': 'TV-MA',
      'ProductionLocations': ['United States'],
      'Studios': [
        {'Name': 'Netflix', 'Id': '1'}
      ],
      'Tags': ['科幻', '外星文明'],
      'ProviderIds': {'Tmdb': '108545', 'Imdb': 'tt13016388'},
    });
    expect(fmtIsoDate(series.premiereDate), equals('2024-03-21'));
    expect(series.status, equals('Continuing'));
    expect(series.criticRating, equals(79.0));
    expect(series.productionLocations, equals(['United States']));
    expect(series.studios, equals(['Netflix']));
    expect(series.tags, equals(['科幻', '外星文明']));
    expect(series.providerIds['Tmdb'], equals('108545'));
    expect(hashPasscode('1234'), equals(hashPasscode('1234')));
    expect(hashPasscode('1234'), isNot(equals(hashPasscode('4321'))));

    // 6. Real Danmaku parsers (DandanPlay JSON & Bilibili XML)
    final dandan = DanmakuComment.parseDandanComments([
      {'p': '12.5,1,16777215', 'm': '高能预警'},
      {'p': '4.2,5,16711680', 'm': 'OP神曲'},
    ]);
    expect(dandan.length, equals(2));
    expect(dandan.first.text, equals('OP神曲'));
    expect(dandan.first.mode, equals(5));
    expect(dandan.last.timeSecs, closeTo(12.5, 0.01));

    final bili = DanmakuComment.parseBilibiliXml(
      '<i><d p="20.0,4,25,65280,1700000000,0,abc,1">字幕组辛苦 &amp; 感谢</d>'
      '<d p="3.5,1,25,16777215,1700000000,0,def,2">前排打卡</d></i>',
    );
    expect(bili.length, equals(2));
    expect(bili.first.text, equals('前排打卡'));
    expect(bili.last.text, equals('字幕组辛苦 & 感谢'));
    expect(bili.last.mode, equals(4));
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
    await tester.drag(find.byType(ListView).first, const Offset(0, -320));
    await tester.pumpAndSettle();
    expect(find.text('弹幕设置'), findsOneWidget);
    expect(find.text('AI 服务（翻译）'), findsOneWidget);
    expect(find.text('隐私保护'), findsOneWidget);
    expect(find.text('服务器管理台'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Series DetailScreen renders full NFO metadata and hides 展开全部 for short overview',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final app = VedroAppState(_MockVedroCore());
    final stub = MediaItemModel(id: 'tv1', name: '三体', type: 'Series');
    await tester.pumpWidget(MaterialApp(
      home: DetailScreen(item: stub, appState: app),
    ));
    await tester.pumpAndSettle();

    expect(find.text('影片资料与 NFO 信息'), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('# 科幻'), findsOneWidget);
    expect(find.text('TMDB: 108545'), findsOneWidget);
    expect(find.text('2024-03-21'), findsWidgets);
    // Short overview MUST NOT show 展开全部
    expect(find.text('展开全部'), findsNothing);
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
