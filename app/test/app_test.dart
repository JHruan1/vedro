import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vedro/core/ffi/vedro_bridge.dart';
import 'package:vedro/core/models/models.dart';
import 'package:vedro/main.dart';

class _MockVedroCore implements VedroCoreClient {
  @override
  String get coreVersion => '0.1.2-test';

  @override
  Future<dynamic> invoke(String method, [Map<String, dynamic> params = const {}]) async {
    switch (method) {
      case 'version':
        return <String, dynamic>{'version': '0.1.2-test'};
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
              'Name': 'admin',
              'Policy': <String, dynamic>{'IsAdministrator': true},
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
  test('Models parse multi-route profiles, aggregated hits, and GeneratedArt helpers', () {
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
  });

  testWidgets('Launches directly into Home Server Hub (not a login wall), opens Settings & Add Server',
      (tester) async {
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

    final mock = _MockVedroCore();
    await tester.pumpWidget(VedroApp(core: mock));
    await tester.pumpAndSettle();

    // Launches straight into Home Server Hub with Player Settings accessible immediately!
    expect(find.text('添加媒体服务器'), findsOneWidget);
    expect(find.text('播放器设置'), findsOneWidget);

    // Open Add Server frosted sheet and connect
    await tester.tap(find.text('添加媒体服务器'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(1), 'admin');
    await tester.enterText(find.byType(TextField).at(2), 'secret');
    await tester.tap(find.text('连接并添加'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Dune: Part Two'), findsOneWidget);
    expect(find.text('媒体库'), findsWidgets);

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
      expect(cfg['prefer_native_dolby_vision'], isTrue);
    } finally {
      bridge.dispose();
    }
  });
}
