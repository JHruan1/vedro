import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vedro/core/ffi/vedro_bridge.dart';
import 'package:vedro/core/models/models.dart';
import 'package:vedro/core/models/preferences.dart';
import 'package:vedro/core/theme/vedro_skin.dart';
import 'package:vedro/core/theme/vedro_theme.dart';
import 'package:vedro/main.dart';
import 'package:vedro/screens/detail_screen.dart';
import 'package:vedro/screens/settings_screen.dart';
import 'package:vedro/screens/shell_screen.dart';
import 'package:vedro/state/app_state.dart';
import 'package:vedro/widgets/danmaku_engine.dart';
import 'package:vedro/widgets/server_card_grid.dart';
import 'package:vedro/widgets/vedro_ui.dart';

class _MockVedroCore implements VedroCoreClient {
  _MockVedroCore({
    this.isAdmin = false,
    this.dialect = 'embygo',
    this.canDownload = true,
    this.enableContentDownloading = false,
    this.meQuotaJson,
  });
  final bool isAdmin;
  final String dialect;
  final bool canDownload;
  final bool enableContentDownloading;
  final Map<String, dynamic>? meQuotaJson;
  int probeMediaSourceCalls = 0;

  @override
  String get coreVersion => '0.2.2-test';

  @override
  Future<dynamic> invoke(String method, [Map<String, dynamic> params = const {}]) async {
    switch (method) {
      case 'version':
        return <String, dynamic>{'version': '0.2.2-test'};
      case 'get_me_quota':
        return meQuotaJson;
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
            'dialect': dialect,
            'server_id': 'embygo-1',
            'server_name': dialect == 'embygo' ? 'My EmbyGo' : 'Standard Emby',
            'advertised_version': '4.8.11.0',
            'supports_transcoding': dialect != 'embygo',
            'supports_popular': dialect == 'embygo',
            'supports_suggestions': true,
            'supports_hide_from_resume': true,
            'uses_stream_tickets': dialect == 'embygo',
          },
        };
      case 'login':
        return <String, dynamic>{
          'auth': <String, dynamic>{
            'AccessToken': 'tok',
            'User': <String, dynamic>{
              'Id': 'u1',
              'Name': isAdmin ? 'admin' : 'viewer',
              'Policy': <String, dynamic>{
                'IsAdministrator': isAdmin,
                'EnableContentDownloading': enableContentDownloading,
              },
            },
          },
          'capabilities': <String, dynamic>{
            'dialect': dialect,
            'server_id': 'embygo-1',
            'server_name': dialect == 'embygo' ? 'My EmbyGo' : 'Standard Emby',
            'advertised_version': '4.8.11.0',
            'supports_transcoding': dialect != 'embygo',
            'supports_popular': dialect == 'embygo',
            'supports_suggestions': true,
            'supports_hide_from_resume': true,
            'uses_stream_tickets': dialect == 'embygo',
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
        if (params['item_id'] == 'm-probe-ver') {
          return <String, dynamic>{
            'item': <String, dynamic>{
              'Id': 'm-probe-ver',
              'Name': '星际穿越',
              'Type': 'Movie',
              'CanDownload': true,
              'Overview': '切换不同版本时，音轨与字幕随片源实时联动且零网盘预读。',
              'ProductionYear': 2014,
              'CommunityRating': 9.4,
              'MediaSources': <dynamic>[
                <String, dynamic>{
                  'Id': 'ver-uhd',
                  'Name': '4K UHD REMUX',
                  'Container': 'mkv',
                  'Size': 68000000000,
                  'MediaStreams': <dynamic>[
                    <String, dynamic>{'Index': 0, 'Type': 'Video', 'Codec': 'hevc', 'Height': 2160},
                    <String, dynamic>{'Index': 1, 'Type': 'Audio', 'Language': 'eng', 'Codec': 'truehd', 'DisplayTitle': 'English TrueHD Atmos 7.1'},
                    <String, dynamic>{'Index': 2, 'Type': 'Subtitle', 'Language': 'chi', 'Codec': 'ass', 'DisplayTitle': '简英双语特效 ASS'},
                  ],
                },
                <String, dynamic>{
                  'Id': 'ver-dub',
                  'Name': '1080p 国粤双语版',
                  'Path': '/mnt/cloud/Interstellar.1080p.BluRay.国粤双语.特效字幕.mkv',
                  'Container': 'mkv',
                  'Size': 16000000000,
                  'MediaStreams': <dynamic>[],
                },
                <String, dynamic>{
                  'Id': 'ver-raw',
                  'Name': '1080p 生肉无字版',
                  'Container': 'mp4',
                  'Size': 6000000000,
                  'MediaStreams': <dynamic>[
                    <String, dynamic>{'Index': 0, 'Type': 'Video', 'Codec': 'h264', 'Height': 1080},
                    <String, dynamic>{'Index': 1, 'Type': 'Audio', 'Language': 'jpn', 'Codec': 'aac', 'DisplayTitle': '日语原声 AAC 2.0'},
                  ],
                },
              ],
            },
            'similar': <dynamic>[],
            'segments': <dynamic>[],
          };
        }
        if (params['item_id'] == 'm-5ver') {
          return <String, dynamic>{
            'item': <String, dynamic>{
              'Id': 'm-5ver',
              'Name': '奥本海默',
              'OriginalTitle': 'Oppenheimer',
              'Type': 'Movie',
              'CanDownload': canDownload,
              'Overview': '五版本同源碰撞（空 Id + 相同 Name + 未探测字幕）回归测试。',
              'ProductionYear': 2023,
              'CommunityRating': 8.9,
              'MediaSources': <dynamic>[
                <String, dynamic>{
                  'Id': '',
                  'Name': 'MKV',
                  'Path': '/mnt/media/Movies/Oppenheimer.2023.UHD.BluRay.REMUX.DV.TrueHD.Atmos-Framestor/Oppenheimer.mkv',
                  'Container': 'mkv',
                  'Size': 84000000000,
                  'Bitrate': 71000000,
                  'MediaStreams': <dynamic>[],
                },
                <String, dynamic>{
                  'Id': '',
                  'Name': 'MKV',
                  'Path': '/mnt/media/Movies/Oppenheimer.2023.2160p.WEB-DL.DoVi.HDR10.DDP5.1-FLUX/Oppenheimer.mkv',
                  'Container': 'mkv',
                  'Size': 29500000000,
                  'Bitrate': 24800000,
                  'MediaStreams': <dynamic>[],
                },
                <String, dynamic>{
                  'Id': '',
                  'Name': 'MKV',
                  'Path': '/mnt/media/Movies/Oppenheimer.2023.IMAX.1080p.BluRay.x265.10bit-Tigole/Oppenheimer.mkv',
                  'Container': 'mkv',
                  'Size': 16200000000,
                  'Bitrate': 13200000,
                  'MediaStreams': <dynamic>[],
                },
                <String, dynamic>{
                  'Id': '',
                  'Name': 'MKV',
                  'Path': '/mnt/media/Movies/Oppenheimer.2023.1080p.BluRay.x264.CHS.ENG-BtsHD/Oppenheimer.mkv',
                  'Container': 'mkv',
                  'Size': 12800000000,
                  'Bitrate': 10400000,
                  'MediaStreams': <dynamic>[],
                },
                <String, dynamic>{
                  'Id': '',
                  'Name': 'MP4',
                  'Path': '/mnt/media/Movies/Oppenheimer.2023.720p.AAC.Mobile/Oppenheimer.mp4',
                  'Container': 'mp4',
                  'Size': 3800000000,
                  'Bitrate': 3100000,
                  'MediaStreams': <dynamic>[],
                },
              ],
            },
            'similar': <dynamic>[],
            'segments': <dynamic>[],
          };
        }
        if (params['item_id'] == 'tv-5ver') {
          return <String, dynamic>{
            'item': <String, dynamic>{
              'Id': 'tv-5ver',
              'Name': '幕府将军',
              'OriginalTitle': 'Shōgun',
              'Type': 'Series',
              'CanDownload': canDownload,
              'Overview': '五版本剧集（相同 Name: S01E01 + 空 MediaStreams）单选与字幕测试。',
              'ProductionYear': 2024,
              'CommunityRating': 9.1,
            },
            'similar': <dynamic>[],
            'segments': <dynamic>[],
          };
        }
        if (params['item_id'] == 'm1') {
          return <String, dynamic>{
            'item': <String, dynamic>{
              'Id': 'm1',
              'Name': '沙丘2',
              'OriginalTitle': 'Dune: Part Two',
              'Type': 'Movie',
              'CanDownload': canDownload,
              'Overview': '保罗·厄崔迪与弗雷曼人联手展开复仇。',
              'ProductionYear': 2024,
              'CommunityRating': 8.6,
              'MediaSources': <dynamic>[
                <String, dynamic>{
                  'Id': 'src-dv',
                  'Name': '4K · Dolby Vision · TrueHD Atmos · REMUX',
                  'Container': 'mkv',
                  'Size': 73400320000,
                  'Bitrate': 64200000,
                  'MediaStreams': <dynamic>[
                    <String, dynamic>{'Index': 0, 'Type': 'Video', 'Codec': 'hevc', 'Height': 2160},
                    <String, dynamic>{'Index': 1, 'Type': 'Audio', 'Language': 'eng', 'Codec': 'truehd', 'DisplayTitle': 'English TrueHD Atmos'},
                    <String, dynamic>{'Index': 2, 'Type': 'Subtitle', 'Language': 'chi', 'DisplayTitle': '简体中文 ASS'},
                  ],
                },
                <String, dynamic>{
                  'Id': 'src-sdr',
                  'Name': '1080p · BluRay · x264',
                  'Container': 'mkv',
                  'Size': 14200000000,
                  'Bitrate': 11800000,
                },
              ],
            },
            'similar': <dynamic>[],
            'segments': <dynamic>[],
          };
        }
        return <String, dynamic>{
          'item': <String, dynamic>{
            'Id': 'tv1',
            'Name': '三体',
            'OriginalTitle': '3 Body Problem',
            'Type': 'Series',
            'CanDownload': canDownload,
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
      case 'probe_servers_status':
        return <String, dynamic>{
          'srv-1': <String, dynamic>{
            'server_id': 'srv-1',
            'online': true,
            'latency_ms': 28,
            'movie_count': 420,
            'series_count': 85,
            'episode_count': 3120,
          },
          'srv-2': <String, dynamic>{
            'server_id': 'srv-2',
            'online': false,
            'latency_ms': null,
            'error': '连接超时',
          },
        };
      case 'get_seasons':
        return <String, dynamic>{
          'Items': <dynamic>[
            <String, dynamic>{
              'Id': 's1',
              'Name': '第 1 季',
              'Type': 'Season',
              'IndexNumber': 1,
              'Overview': '第一季 NFO 季度简介测试。',
              'PremiereDate': '2024-03-21T00:00:00Z',
            },
          ],
        };
      case 'get_episodes':
        if (params['series_id'] == 'tv-5ver') {
          return <String, dynamic>{
            'Items': List<Map<String, dynamic>>.generate(5, (i) {
              final epNum = i + 1;
              final epCode = 'S01E0$epNum';
              return <String, dynamic>{
                'Id': 'shogun-ep$epNum',
                'Name': '第 $epNum 章',
                'Type': 'Episode',
                'CanDownload': canDownload,
                'SeriesId': 'tv-5ver',
                'SeriesName': '幕府将军',
                'ParentIndexNumber': 1,
                'IndexNumber': epNum,
                'MediaSourceCount': 5,
                'MediaSources': <dynamic>[
                  <String, dynamic>{
                    'Id': '',
                    'Name': epCode,
                    'Path': '/mnt/tv/Shogun.2024.2160p.DSNP.WEB-DL.DV.HDR.DDP5.1.Atmos-FLUX/Season 1/$epCode.mkv',
                    'Container': 'mkv',
                    'Size': 9200000000,
                    'Bitrate': 26500000,
                  },
                  <String, dynamic>{
                    'Id': '',
                    'Name': epCode,
                    'Path': '/mnt/tv/Shogun.2024.2160p.SDR.HEVC-NTb/Season 1/$epCode.mkv',
                    'Container': 'mkv',
                    'Size': 7400000000,
                    'Bitrate': 21000000,
                  },
                  <String, dynamic>{
                    'Id': '',
                    'Name': epCode,
                    'Path': '/mnt/tv/Shogun.2024.1080p.WEB-DL.x265.10bit-HHWEB/Season 1/$epCode.mkv',
                    'Container': 'mkv',
                    'Size': 3100000000,
                    'Bitrate': 8500000,
                  },
                  <String, dynamic>{
                    'Id': '',
                    'Name': epCode,
                    'Path': '/mnt/tv/Shogun.2024.1080p.CHS.JPN.Bilingual-Nekomoe/Season 1/$epCode.mkv',
                    'Container': 'mkv',
                    'Size': 2400000000,
                    'Bitrate': 6800000,
                  },
                  <String, dynamic>{
                    'Id': '',
                    'Name': epCode,
                    'Path': '/mnt/tv/Shogun.2024.720p.AAC.Mini/Season 1/$epCode.mp4',
                    'Container': 'mp4',
                    'Size': 980000000,
                    'Bitrate': 2600000,
                  },
                ],
              };
            }),
          };
        }
        return <String, dynamic>{
          'Items': List<Map<String, dynamic>>.generate(120, (i) {
            final epNum = i + 1;
            return <String, dynamic>{
              'Id': 'ep$epNum',
              'Name': epNum == 1 ? '倒计时' : '第 $epNum 集剧情',
              'Type': 'Episode',
              'CanDownload': canDownload,
              'SeriesId': 'tv1',
              'SeriesName': '三体',
              'ParentIndexNumber': 1,
              'IndexNumber': epNum,
              'MediaSourceCount': epNum == 1 ? 2 : 1,
              'MediaSources': epNum == 1
                  ? <dynamic>[
                      <String, dynamic>{
                        'Id': 'ms-4k',
                        'Name': '4K · Dolby Vision · Atmos',
                        'Container': 'mkv',
                        'Size': 8589934592,
                        'Bitrate': 28500000,
                      },
                      <String, dynamic>{
                        'Id': 'ms-1080',
                        'Name': '1080p · BluRay · x265',
                        'Container': 'mkv',
                        'Size': 2147483648,
                        'Bitrate': 7200000,
                      },
                    ]
                  : <dynamic>[],
            };
          }),
        };
      case 'danmaku_fetch':
        return <String, dynamic>{
          'episode_title': '弹弹play · 三体 第1话',
          'comments': <dynamic>[
            <String, dynamic>{'p': '3.2,1,16777215', 'm': '物理学不存在了'},
            <String, dynamic>{'p': '8.5,5,16711680', 'm': '整个宇宙将为你闪烁'},
          ],
        };
      case 'danmaku_search':
        return <String, dynamic>{
          'candidates': <dynamic>[
            <String, dynamic>{
              'provider': 'bilibili_pgc',
              'provider_label': '哔哩哔哩 · 剧集',
              'title': '三体',
              'episodes': <dynamic>[
                <String, dynamic>{
                  'target_id': '998877',
                  'number': 1,
                  'title': '第1话 倒计时',
                },
              ],
            },
          ],
        };
      case 'danmaku_load_target':
        return <String, dynamic>{
          'episode_title': '哔哩哔哩 · 三体 第1话',
          'raw': '<i><d p="1.5,1,25,16777215,1700000000,0,abc,1">B站弹幕加载成功</d></i>',
        };
      case 'probe_media_source':
        probeMediaSourceCalls += 1;
        final itemId = params['item_id']?.toString() ?? '';
        final msId = params['media_source_id']?.toString() ?? '';
        if (itemId == 'm-probe-ver') {
          if (msId == 'ver-uhd') {
            return <String, dynamic>{
              'probed': true,
              'media_source': <String, dynamic>{
                'Id': 'ver-uhd',
                'MediaStreams': <dynamic>[
                  <String, dynamic>{'Index': 0, 'Type': 'Video', 'Codec': 'hevc', 'Height': 2160},
                  <String, dynamic>{'Index': 1, 'Type': 'Audio', 'Language': 'eng', 'Codec': 'truehd', 'DisplayTitle': 'English TrueHD Atmos 7.1'},
                  <String, dynamic>{'Index': 2, 'Type': 'Subtitle', 'Language': 'chi', 'Codec': 'ass', 'DisplayTitle': '简英双语特效 ASS'},
                ],
              },
            };
          }
          if (msId == 'ver-dub') {
            return <String, dynamic>{
              'probed': true,
              'media_source': <String, dynamic>{
                'Id': 'ver-dub',
                'MediaStreams': <dynamic>[
                  <String, dynamic>{'Index': 0, 'Type': 'Video', 'Codec': 'hevc', 'Height': 1080},
                  <String, dynamic>{'Index': 1, 'Type': 'Audio', 'Language': 'chi', 'Codec': 'eac3', 'DisplayTitle': '国语配音 EAC3 5.1'},
                  <String, dynamic>{'Index': 2, 'Type': 'Audio', 'Language': 'yue', 'Codec': 'flac', 'DisplayTitle': '粤语原声 FLAC 2.0'},
                  <String, dynamic>{'Index': 3, 'Type': 'Subtitle', 'Language': 'cht', 'Codec': 'srt', 'DisplayTitle': '繁体中文 SRT'},
                ],
              },
            };
          }
          if (msId == 'ver-raw') {
            return <String, dynamic>{
              'probed': true,
              'media_source': <String, dynamic>{
                'Id': 'ver-raw',
                'MediaStreams': <dynamic>[
                  <String, dynamic>{'Index': 0, 'Type': 'Video', 'Codec': 'h264', 'Height': 1080},
                  <String, dynamic>{'Index': 1, 'Type': 'Audio', 'Language': 'jpn', 'Codec': 'aac', 'DisplayTitle': '日语原声 AAC 2.0'},
                ],
              },
            };
          }
        }
        return <String, dynamic>{};
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

  testWidgets('Series DetailScreen renders Poster Cover, Backdrop, Series Version Selector & NFO',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final app = VedroAppState(_MockVedroCore());
    final stub = MediaItemModel(id: 'tv1', name: '三体', type: 'Series');
    await tester.pumpWidget(MaterialApp(
      home: DetailScreen(item: stub, appState: app),
    ));
    await tester.pumpAndSettle();

    // Dedicated Poster Cover & Backdrop Banner MUST both be rendered
    expect(find.byKey(const ValueKey('detail-backdrop-banner')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-poster-cover')), findsOneWidget);
    // Series multi-version selector MUST be clearly visible and switchable
    expect(find.byKey(const ValueKey('detail-version-selector')), findsOneWidget);
    expect(find.text('选择剧集片源版本 (2)'), findsOneWidget);
    expect(find.text('4K · Dolby Vision · Atmos'), findsOneWidget);
    expect(find.text('1080p · BluRay · x265'), findsOneWidget);

    await tester.tap(find.text('1080p · BluRay · x265'));
    await tester.pumpAndSettle();

    // 120-episode Series auto-switches to compact range pills (1-50, 51-100, 101-120) + Season NFO
    expect(find.text('共 120 集'), findsOneWidget);
    expect(find.text('1-50'), findsOneWidget);
    expect(find.text('51-100'), findsOneWidget);
    expect(find.text('101-120'), findsOneWidget);
    expect(find.text('第一季 NFO 季度简介测试。'), findsOneWidget);

    // Clicking More sheet on desktop (1280px) & clicking outside MUST dismiss cleanly!
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    expect(find.text('更多操作'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('更多操作'), findsNothing);

    expect(find.text('影片资料与 NFO 信息'), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('# 科幻'), findsOneWidget);
    expect(find.text('TMDB: 108545'), findsOneWidget);
    expect(find.text('2024-03-21'), findsWidgets);
    // Short overview MUST NOT show 展开全部
    expect(find.text('展开全部'), findsNothing);
  });

  testWidgets('ServerCardGrid probes and displays online/offline status & Movie/Series counts',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final app = VedroAppState(_MockVedroCore());
    app.savedServers = [
      SavedServerProfile(id: 'srv-1', name: '主力服', url: 'https://s1.example.com', dialect: 'embygo'),
      SavedServerProfile(id: 'srv-2', name: '备用服', url: 'https://s2.example.com', dialect: 'emby'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: ListenableBuilder(
            listenable: app,
            builder: (_, __) => ServerCardGrid(
              appState: app,
              onSelectServer: (_) async {},
              onAddServer: () {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('在线 · 28 ms'), findsOneWidget);
    expect(find.text('电影 420'), findsOneWidget);
    expect(find.text('剧集 85'), findsOneWidget);
    expect(find.text('离线'), findsOneWidget);
  });

  testWidgets('Mobile Movie DetailScreen renders Poster Cover & solid Version/Audio/Subtitle Selector without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final app = VedroAppState(_MockVedroCore());
    final stub = MediaItemModel(id: 'm1', name: '沙丘2', type: 'Movie');
    await tester.pumpWidget(MaterialApp(
      home: DetailScreen(item: stub, appState: app),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('detail-backdrop-banner')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-poster-cover')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-version-selector')), findsOneWidget);
    expect(find.text('选择片源版本 (2)'), findsOneWidget);
    expect(find.text('4K · Dolby Vision · TrueHD Atmos · REMUX'), findsOneWidget);
    expect(find.text('1080p · BluRay · x264'), findsOneWidget);
    expect(find.text('English TrueHD Atmos'), findsOneWidget);
    expect(find.text('简体中文 ASS'), findsOneWidget);

    await tester.tap(find.text('1080p · BluRay · x264'));
    await tester.pumpAndSettle();
    expect(find.text('当前'), findsOneWidget);
  });

  testWidgets(
      'Download permission strictly hides download button on normal Emby and confines quota card strictly to Settings -> Downloads',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 1. Standard Emby user WITHOUT download permission (CanDownload: false, me/quota: null)
    final embyMock = _MockVedroCore(
      isAdmin: false,
      dialect: 'emby',
      canDownload: false,
      enableContentDownloading: false,
      meQuotaJson: null,
    );
    final embyApp = VedroAppState(embyMock)
      ..userId = 'u1'
      ..connectedUrl = 'https://emby.example.com'
      ..enableContentDownloading = false
      ..capabilities = ServerCapabilitiesModel(
        dialect: 'emby',
        serverId: 'emby-1',
        serverName: 'Standard Emby',
        advertisedVersion: '4.8.11.0',
        supportsTranscoding: true,
        supportsPopular: false,
        supportsSuggestions: true,
        supportsHideFromResume: true,
        usesStreamTickets: false,
      );

    await tester.pumpWidget(MaterialApp(
      home: DetailScreen(
        key: const ValueKey('emby-detail'),
        item: MediaItemModel(id: 'm1', name: '沙丘2', type: 'Movie', canDownload: false),
        appState: embyApp,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('detail-download-button')), findsNothing);
    expect(find.byKey(const ValueKey('detail-download-quota-pill')), findsNothing);
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    expect(find.text('离线下载到本地'), findsNothing);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    // 2. EmbyGo user WITH download permission & metered quota (30 GiB monthly + 500 GiB pack)
    const gib = 1024 * 1024 * 1024;
    final embygoMock = _MockVedroCore(
      isAdmin: false,
      dialect: 'embygo',
      canDownload: true,
      enableContentDownloading: false,
      meQuotaJson: <String, dynamic>{
        'limits': <String, dynamic>{
          'is_admin': false,
          'allow_downloads': true,
        },
        'download_quota': <String, dynamic>{
          'Enabled': true,
          'AdminExempt': false,
          'MonthlyQuotaBytes': 30 * gib,
          'MonthlyUsedBytes': 0,
          'MonthlyRemainingBytes': 30 * gib,
          'PackBytes': 500 * gib,
          'InFlightBytes': 0,
          'ActiveDownloads': 0,
          'MaxConcurrentDownloads': 2,
          'TotalRemainingBytes': 530 * gib,
          'CycleDownloadBytes': 0,
          'CycleStart': '2026-11-01',
          'CycleEnd': '2026-12-01',
        },
      },
    );
    final embygoApp = VedroAppState(embygoMock)
      ..userId = 'u1'
      ..connectedUrl = 'https://embygo.example.com'
      ..capabilities = ServerCapabilitiesModel(
        dialect: 'embygo',
        serverId: 'embygo-1',
        serverName: 'My EmbyGo',
        advertisedVersion: '4.8.11.0',
        supportsTranscoding: false,
        supportsPopular: true,
        supportsSuggestions: true,
        supportsHideFromResume: true,
        usesStreamTickets: true,
      );
    await embygoApp.refreshMeQuota();
    expect(embygoApp.meQuota?.downloadQuota?.totalRemainingBytes, equals(530 * gib));
    expect(fmtQuotaBytes(500 * gib), equals('500.00 GB'));

    await tester.pumpWidget(MaterialApp(
      home: DetailScreen(
        key: const ValueKey('embygo-detail'),
        item: MediaItemModel(id: 'm1', name: '沙丘2', type: 'Movie', canDownload: true),
        appState: embygoApp,
      ),
    ));
    await tester.pumpAndSettle();

    // DetailScreen shows clean download button, ZERO download quota clutter!
    expect(find.byKey(const ValueKey('detail-download-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-download-quota-pill')), findsNothing);
    expect(find.textContaining('下载流量包'), findsNothing);
    expect(find.textContaining('530.00 GB'), findsNothing);

    // 2b. Tapping download on multi-version movie opens Version Download Picker cleanly
    //     (still zero quota clutter & NEVER exposes raw direct download links!)
    await tester.tap(find.byKey(const ValueKey('detail-download-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail-version-download-sheet')), findsOneWidget);
    expect(find.text('选择下载版本 (2)'), findsOneWidget);
    expect(find.textContaining('下载流量包'), findsNothing);
    expect(find.byIcon(Icons.link_rounded), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // 2c. More sheet also NEVER exposes raw direct download links
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('下载直链'), findsNothing);
    expect(find.byIcon(Icons.link_rounded), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // 3. SettingsScreen -> 下载管理 is the ONLY place showing 下载流量包 card (sidebar subtitle also free of GB clutter)
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        appState: embygoApp,
        onOpenServerHub: () {},
        onOpenAddServer: ([_]) {},
      ),
    ));
    await tester.pumpAndSettle();
    // Before clicking 下载管理, sidebar shows clean "无任务" without quota balance text
    expect(find.byKey(const ValueKey('settings-download-quota-card')), findsNothing);
    await tester.tap(find.text('下载管理'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-download-quota-card')), findsOneWidget);
    expect(find.text('下载流量包'), findsOneWidget);
    expect(find.textContaining('530.00 GB'), findsOneWidget);
    expect(find.textContaining('一次性永久下载流量包'), findsOneWidget);

    // 4. Series multi-episode & multi-version Batch Download Picker
    await tester.pumpWidget(MaterialApp(
      home: DetailScreen(
        key: const ValueKey('embygo-series-batch-dl'),
        item: MediaItemModel(id: 'tv1', name: '三体', type: 'Series'),
        appState: embygoApp,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail-batch-download-btn')), findsOneWidget);
    expect(find.textContaining('下载流量包'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('detail-batch-download-btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail-batch-download-dialog')), findsOneWidget);
    expect(find.textContaining('选择下载剧集与版本'), findsOneWidget);
    expect(find.text('下载版本 (2)'), findsOneWidget);
    expect(find.text('全选本段'), findsOneWidget);
    await tester.tap(find.text('全选本段'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已选 50 集'), findsOneWidget);
    expect(find.textContaining('下载流量包'), findsNothing);

    // 5. Resumable DownloadTaskModel metadata roundtrip & concurrency capping
    final task = DownloadTaskModel(
      id: 't1',
      itemId: 'ep1',
      title: '三体',
      subtitle: 'S01E01 · 倒计时',
      mediaSourceId: 'ms-4k',
      versionLabel: '4K · DV',
      etag: '"abc123"',
      totalBytes: 8589934592,
      downloadedBytes: 4294967296,
      retryCount: 2,
      status: 'paused',
    );
    final roundtripped = DownloadTaskModel.fromJson(task.toJson());
    expect(roundtripped.mediaSourceId, equals('ms-4k'));
    expect(roundtripped.versionLabel, equals('4K · DV'));
    expect(roundtripped.etag, equals('"abc123"'));
    expect(roundtripped.retryCount, equals(2));
    expect(roundtripped.progress, closeTo(0.5, 0.001));
    expect(embygoApp.effectiveDownloadConcurrency, equals(2));
  });

  testWidgets(
      'VedroPrecisionSlider interactive ticks/reset, compact 360px DetailScreen action deck & multi-source Danmaku RPCs',
      (tester) async {
    // 1. Compact 360x780 portrait DetailScreen action deck never wraps awkwardly or overflows
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final app = VedroAppState(_MockVedroCore(enableContentDownloading: true))
      ..userId = 'u1'
      ..connectedUrl = 'https://embygo.example.com'
      ..enableContentDownloading = true;
    await tester.pumpWidget(MaterialApp(
      home: DetailScreen(
        key: const ValueKey('compact-360-movie'),
        item: MediaItemModel(id: 'm1', name: '沙丘2', type: 'Movie', canDownload: true),
        appState: app,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail-download-button')), findsOneWidget);
    expect(find.text('缓存'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('标已看'), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: DetailScreen(
        key: const ValueKey('compact-360-series'),
        item: MediaItemModel(id: 'tv1', name: '三体', type: 'Series', canDownload: true),
        appState: app,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail-batch-download-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-download-button')), findsOneWidget);
    expect(find.text('下载'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('标已看'), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);

    // 2. VedroPrecisionSlider tick selection & one-tap reset
    double speed = 1.0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF0B0B0D),
        body: Center(
          child: SizedBox(
            width: 340,
            child: StatefulBuilder(
              builder: (_, setSt) => VedroPrecisionSlider(
                label: '播放倍速',
                valueText: '${speed.toStringAsFixed(speed == speed.roundToDouble() ? 1 : 2)}×',
                value: speed,
                min: 0.25,
                max: 3.0,
                step: 0.05,
                defaultValue: 1.0,
                ticks: const [
                  (0.5, '0.5×'),
                  (1.0, '1.0×'),
                  (1.5, '1.5×'),
                  (2.0, '2.0×'),
                  (3.0, '3.0×'),
                ],
                onChanged: (v) => setSt(() => speed = v),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('播放倍速'), findsOneWidget);
    expect(find.text('复位'), findsNothing);
    await tester.tap(find.text('2.0×'));
    await tester.pumpAndSettle();
    expect(speed, closeTo(2.0, 0.01));
    expect(find.text('复位'), findsOneWidget);
    await tester.tap(find.text('复位'));
    await tester.pumpAndSettle();
    expect(speed, closeTo(1.0, 0.01));
    expect(find.text('复位'), findsNothing);

    // 3. Multi-source Danmaku auto-match, interactive search & explicit target loading
    final autoRes = await app.fetchDanmaku(
      '三体',
      altTitle: '3 Body Problem',
      season: 1,
      episode: 1,
    );
    expect(autoRes.title, contains('弹弹play'));
    expect(autoRes.comments.length, equals(2));

    final candidates = await app.searchDanmakuCandidates('三体');
    expect(candidates.length, equals(1));
    expect((candidates.first['episodes'] as List).isNotEmpty, isTrue);

    final targetRes = await app.loadDanmakuTarget(
      provider: 'bilibili_pgc',
      targetId: '998877',
      title: '哔哩哔哩 · 三体 第1话',
    );
    expect(targetRes.comments.length, equals(1));
    expect(targetRes.comments.first.text, equals('B站弹幕加载成功'));
  });

  testWidgets(
      '5-version Movie & Series enforce strict single-selection (never multi-select) and surface visible Audio/Subtitle panel even when unprobed',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final app = VedroAppState(_MockVedroCore(enableContentDownloading: true))
      ..userId = 'u1'
      ..connectedUrl = 'https://embygo.example.com'
      ..enableContentDownloading = true;

    // 1. 5-version Movie with colliding Name="MKV" & empty Id="" & empty MediaStreams=[]
    await tester.pumpWidget(MaterialApp(
      theme: VedroTheme.fromSkin(app.prefs.activeSkin),
      home: DetailScreen(
        key: const ValueKey('detail-5ver-movie'),
        item: MediaItemModel(id: 'm-5ver', name: '奥本海默', type: 'Movie', canDownload: true),
        appState: app,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('detail-version-selector')), findsOneWidget);
    expect(find.text('选择片源版本 (5)'), findsOneWidget);
    // Strictly ONE active version badge initially!
    expect(find.text('当前'), findsOneWidget);

    // Always-visible Audio & Subtitle control bar even when MediaStreams is empty (embygo unprobed)
    expect(find.byKey(const ValueKey('detail-audio-subtitle-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-mount-local-sub-btn')), findsOneWidget);
    expect(find.text('音轨与字幕'), findsOneWidget);
    expect(find.text('关闭字幕'), findsOneWidget);

    // Tap through versions #2, #3, #4, #5 — strictly ONE '当前' badge at every single step!
    for (final idx in [1, 2, 3, 4, 0]) {
      final card = find.byKey(ValueKey('movie-version-card-$idx'));
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.text('当前'), findsOneWidget);
    }

    // Tap '繁体中文' & '关闭字幕' on unprobed Movie DetailScreen -> follows EACH version independently!
    await tester.ensureVisible(find.text('繁体中文'));
    await tester.tap(find.text('繁体中文'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preplay-sub-zh-Hant-on')), findsOneWidget);

    // Switch to version #2 -> resets to version #2's independent default ('zh'), then switch back -> restores 'zh-Hant'!
    await tester.tap(find.byKey(const ValueKey('movie-version-card-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preplay-sub-zh-on')), findsOneWidget);
    expect(find.byKey(const ValueKey('preplay-sub-zh-Hant-on')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('movie-version-card-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preplay-sub-zh-Hant-on')), findsOneWidget);

    await tester.tap(find.text('关闭字幕'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preplay-sub-off-on')), findsOneWidget);

    // 2. 5-version Series with colliding Name="S01E01" & empty Id="" & empty MediaStreams=[]
    await tester.pumpWidget(MaterialApp(
      theme: VedroTheme.fromSkin(app.prefs.activeSkin),
      home: DetailScreen(
        key: const ValueKey('detail-5ver-series'),
        item: MediaItemModel(id: 'tv-5ver', name: '幕府将军', type: 'Series', canDownload: true),
        appState: app,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('detail-version-selector')), findsOneWidget);
    expect(find.text('选择剧集片源版本 (5)'), findsOneWidget);
    expect(find.text('当前'), findsOneWidget);
    // Series also surfaces Audio & Subtitle panel directly on DetailScreen!
    expect(find.byKey(const ValueKey('detail-audio-subtitle-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-mount-local-sub-btn')), findsOneWidget);

    for (final idx in [1, 2, 3, 4, 2]) {
      final card = find.byKey(ValueKey('series-version-card-$idx'));
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.text('当前'), findsOneWidget);
    }
  });

  testWidgets('VedroSkin 9 presets (Light & Dark), share code roundtrip & DIY Custom Skin Studio',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 1. Verify all 9 bold presets & CustomSkinSpec share code roundtrip
    expect(VedroSkin.presets.length, equals(9));
    expect(VedroSkin.byId('daylight').isLight, isTrue);
    expect(VedroSkin.byId('editorial_paper').isLight, isTrue);
    expect(VedroSkin.byId('editorial_paper').editorialSerif, isTrue);
    expect(VedroSkin.byId('cyber_neon').frameStyle, equals('neon'));
    expect(VedroSkin.byId('cyber_neon').ctaStyle, equals('gradient'));

    const diy = CustomSkinSpec(
      id: 'custom_test_1',
      name: '落日琥珀馆',
      isLight: false,
      canvasHex: '#140D08',
      surfaceHex: '#22160E',
      accentHex: '#F59E0B',
      accentSecondaryHex: '#EF4444',
      ctaStyle: 'gradient',
      frameStyle: 'hairline',
      cardRadius: 16,
      pillRadius: 999,
      ambientGlow: true,
      editorialSerif: true,
    );
    final code = diy.encodeShareCode();
    expect(code, startsWith('VEDRO-SKIN:'));
    final decoded = CustomSkinSpec.tryDecodeShareCode(code);
    expect(decoded, isNotNull);
    expect(decoded!.name, equals('落日琥珀馆'));
    expect(decoded.accentHex, equals('#F59E0B'));
    expect(decoded.editorialSerif, isTrue);

    // 2. SettingsScreen -> 应用风格 switches live between Light/Dark presets & creates a DIY skin
    final app = VedroAppState(_MockVedroCore());
    await tester.pumpWidget(
      AnimatedBuilder(
        animation: app,
        builder: (_, __) => MaterialApp(
          theme: VedroTheme.fromSkin(app.prefs.activeSkin),
          home: SettingsScreen(
            appState: app,
            onOpenServerHub: () {},
            onOpenAddServer: ([_]) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('应用风格'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('skin-preset-obsidian')), findsOneWidget);
    expect(find.byKey(const ValueKey('skin-preset-daylight')), findsOneWidget);
    expect(find.byKey(const ValueKey('skin-preset-cyber_neon')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('skin-preset-daylight')));
    await tester.tap(find.byKey(const ValueKey('skin-preset-daylight')));
    await tester.pumpAndSettle();
    expect(app.prefs.skinId, equals('daylight'));
    expect(app.prefs.activeSkin.isLight, isTrue);

    await tester.ensureVisible(find.byKey(const ValueKey('skin-preset-cyber_neon')));
    await tester.tap(find.byKey(const ValueKey('skin-preset-cyber_neon')));
    await tester.pumpAndSettle();
    expect(app.prefs.skinId, equals('cyber_neon'));
    expect(app.prefs.activeSkin.frameStyle, equals('neon'));

    // Open DIY Custom Skin Studio & save a new custom skin
    await tester.ensureVisible(find.byKey(const ValueKey('open-diy-skin-editor-btn')));
    await tester.tap(find.byKey(const ValueKey('open-diy-skin-editor-btn')));
    await tester.pumpAndSettle();
    expect(find.text('保存并启用皮肤'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('save-diy-skin-btn')));
    await tester.pumpAndSettle();
    expect(app.prefs.customSkins.length, equals(1));
    expect(app.prefs.skinId, equals(app.prefs.customSkins.first.id));

    // Live modular layout customizer inside full ShellScreen NEVER kicks user out of 应用风格!
    await tester.pumpWidget(
      AnimatedBuilder(
        animation: app,
        builder: (_, __) => MaterialApp(
          theme: VedroTheme.fromSkin(app.prefs.activeSkin),
          home: ShellScreen(appState: app),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('skin-studio-pane')), findsOneWidget);
    expect(find.byKey(const ValueKey('skin-live-preview-stage')), findsOneWidget);

    // Switch live preview tabs (Detail & Player HUD)
    await tester.tap(find.byKey(const ValueKey('skin-preview-tab-detail')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('skin-preview-tab-player')));
    await tester.pumpAndSettle();

    // Switch navLayout between left_rail & centered_capsule -> stays in 应用风格!
    await tester.ensureVisible(find.byKey(const ValueKey('skin-mod-left_rail')));
    await tester.tap(find.byKey(const ValueKey('skin-mod-left_rail')));
    await tester.pumpAndSettle();
    expect(app.prefs.activeSkin.navLayout, equals('left_rail'));
    expect(find.byKey(const ValueKey('skin-studio-pane')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('skin-mod-unified_glass')));
    await tester.tap(find.byKey(const ValueKey('skin-mod-unified_glass')));
    await tester.pumpAndSettle();
    expect(app.prefs.activeSkin.effectiveSurfaceMaterial, equals('unified_glass'));
    expect(find.byKey(const ValueKey('skin-studio-pane')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('skin-mod-overlay_poster')));
    await tester.tap(find.byKey(const ValueKey('skin-mod-overlay_poster')));
    await tester.pumpAndSettle();
    expect(app.prefs.activeSkin.cardStyle, equals('overlay_poster'));
    expect(find.byKey(const ValueKey('skin-studio-pane')), findsOneWidget);
  });

  testWidgets('Audio & Subtitle tracks follow selected video version passively with ZERO cloud-drive API probes',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final mock = _MockVedroCore();
    final app = VedroAppState(mock);
    await tester.pumpWidget(MaterialApp(
      theme: VedroTheme.fromSkin(app.prefs.activeSkin),
      home: DetailScreen(
        key: const ValueKey('detail-probe-ver'),
        item: MediaItemModel(id: 'm-probe-ver', name: '星际穿越', type: 'Movie'),
        appState: app,
      ),
    ));
    await tester.pumpAndSettle();

    // Version 0 (already played/cached) shows its exact Audio & Subtitle streams with 0 cloud probes!
    expect(mock.probeMediaSourceCalls, equals(0));
    expect(find.text('English TrueHD Atmos 7.1'), findsOneWidget);
    expect(find.text('简英双语特效 ASS'), findsOneWidget);
    expect(find.textContaining('跟随版本 1'), findsOneWidget);

    // Switch to Version 1 (unplayed on cloud drive) -> 0 cloud probes, shows Version 1 passive traits!
    await tester.tap(find.byKey(const ValueKey('movie-version-card-1')));
    await tester.pumpAndSettle();
    expect(mock.probeMediaSourceCalls, equals(0));
    expect(find.text('English TrueHD Atmos 7.1'), findsNothing);
    expect(find.textContaining('网盘尚未缓存该版本内封轨道'), findsOneWidget);
    expect(find.text('国粤双语'), findsOneWidget);
    expect(find.textContaining('跟随版本 2'), findsOneWidget);

    // Switch to Version 2 (played raw version) -> Shows Japanese AAC audio + "该版本无内封或服务端外挂字幕"
    await tester.tap(find.byKey(const ValueKey('movie-version-card-2')));
    await tester.pumpAndSettle();
    expect(mock.probeMediaSourceCalls, equals(0));
    expect(find.text('日语原声 AAC 2.0'), findsOneWidget);
    expect(find.text('该版本无内封或服务端外挂字幕'), findsOneWidget);
    expect(find.textContaining('跟随版本 3'), findsOneWidget);
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
      final savedTracks = await bridge.invoke('save_learned_tracks', {
        'item_id': 'item-1',
        'media_source_id': 'src-1',
        'streams': [
          {'Index': 1, 'Type': 'Audio', 'Codec': 'eac3', 'Language': 'chi', 'Title': '国语配音'},
        ],
      }) as Map<String, dynamic>;
      expect(savedTracks['saved'], isTrue);
    } finally {
      bridge.dispose();
    }
  });
}
