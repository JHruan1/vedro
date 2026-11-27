import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vedro/core/ffi/vedro_bridge.dart';
import 'package:vedro/core/models/models.dart';
import 'package:vedro/core/models/preferences.dart';
import 'package:vedro/core/platform/native_playback_channel.dart';
import 'package:vedro/core/platform/platform_perf.dart';
import 'package:vedro/core/theme/display_profile.dart';
import 'package:vedro/core/theme/dynamic_color_engine.dart';
import 'package:vedro/core/theme/vedro_skin.dart';
import 'package:vedro/core/theme/vedro_theme.dart';
import 'package:vedro/main.dart';
import 'package:vedro/screens/detail_screen.dart';
import 'package:vedro/screens/home_screen.dart';
import 'package:vedro/screens/library_screen.dart';
import 'package:vedro/screens/settings_screen.dart';
import 'package:vedro/screens/shell_screen.dart';
import 'package:vedro/state/app_state.dart';
import 'package:vedro/widgets/admin_console_pane.dart';
import 'package:vedro/widgets/ai_bilingual_subtitle.dart';
import 'package:vedro/widgets/app_lock_gate.dart';
import 'package:vedro/widgets/beauty_filter.dart';
import 'package:vedro/widgets/danmaku_engine.dart';
import 'package:vedro/core/services/local_asr_engine.dart';
import 'package:vedro/widgets/media_card.dart';
import 'package:vedro/widgets/server_card_grid.dart';
import 'package:vedro/widgets/skin_studio_pane.dart';
import 'package:vedro/widgets/update_checker.dart';
import 'package:vedro/widgets/vedro_artwork.dart';
import 'package:vedro/widgets/vedro_ui.dart';
import 'package:vedro/widgets/windows_immersive_frame.dart';

class _MockVedroCore implements VedroCoreClient {
  _MockVedroCore({
    this.isAdmin = false,
    this.dialect = 'embygo',
    this.canDownload = true,
    this.enableContentDownloading = false,
    this.meQuotaJson,
    this.savedServersList = const [],
    this.lastActiveServerId,
    this.cachedHomeForBootstrap,
  });
  final bool isAdmin;
  final String dialect;
  final bool canDownload;
  final bool enableContentDownloading;
  final Map<String, dynamic>? meQuotaJson;
  final List<Map<String, dynamic>> savedServersList;
  String? lastActiveServerId;
  final Map<String, dynamic>? cachedHomeForBootstrap;
  int probeMediaSourceCalls = 0;
  Map<String, dynamic>? lastAiTranslateParams;
  Map<String, dynamic>? lastAiModelsParams;
  Map<String, dynamic>? lastRestoreParams;
  int mockImageCacheFiles = 42;
  int mockImageCacheBytes = 12 * 1024 * 1024;
  int mockImageCacheMemEntries = 18;
  int subtitleBatchTranslateCalls = 0;
  int asrSliceCalls = 0;
  bool failAsrSlices = false;

  @override
  int get proxySpeedBps => 0;
  List<Map<String, dynamic>> mockDevices = [
    <String, dynamic>{
      'DeviceId': 'dev-current-win',
      'Name': 'Windows 11 Desktop',
      'AppName': 'Vedro',
      'AppVersion': '0.3.7',
      'LastUserId': 'u1',
      'LastUserName': 'alice',
      'DateLastActivity': '2026-11-27T08:30:00Z',
    },
    <String, dynamic>{
      'DeviceId': 'dev-old-ipad',
      'Name': 'iPad Pro',
      'AppName': 'SenPlayer',
      'AppVersion': '4.2.0',
      'LastUserId': 'u1',
      'LastUserName': 'alice',
      'DateLastActivity': '2026-11-20T12:15:00Z',
    },
  ];

  @override
  String get coreVersion => '0.3.7-test';

  @override
  Future<dynamic> invoke(String method, [Map<String, dynamic> params = const {}]) async {
    switch (method) {
      case 'version':
        return <String, dynamic>{'version': '0.3.8-test'};
      case 'bootstrap_state':
        if (cachedHomeForBootstrap != null) {
          return <String, dynamic>{
            'version': '0.3.8-test',
            'proxy_addr': '127.0.0.1:45678',
            'servers': savedServersList,
            'settings': <String, dynamic>{'hwdec': 'auto_zero_copy'},
            'last_active_server_id': lastActiveServerId,
            'cached_home': cachedHomeForBootstrap,
          };
        }
        return <String, dynamic>{};
      case 'get_me_quota':
        return meQuotaJson;
      case 'list_servers':
        return savedServersList;
      case 'get_settings':
        return <String, dynamic>{
          'hwdec': 'auto_zero_copy',
          'prefer_native_dolby_vision': true,
          'tone_mapping': 'bt2446a',
          'audio_mode': 'auto',
          'display': <String, dynamic>{'supports_hdr10': true},
        };
      case 'get_kv':
        if (params['key'] == 'last_active_server_id') {
          return <String, dynamic>{'value': lastActiveServerId};
        }
        return <String, dynamic>{'value': null};
      case 'set_kv':
        if (params['key'] == 'last_active_server_id') {
          lastActiveServerId = params['value']?.toString();
        }
        return <String, dynamic>{'saved': true};
      case 'restore_session':
        lastRestoreParams = Map<String, dynamic>.from(params);
        final sid = params['server_id']?.toString() ?? 'embygo-1';
        lastActiveServerId = sid;
        final matched = savedServersList
            .where((s) => s['id']?.toString() == sid)
            .firstOrNull;
        final srvName = matched?['name']?.toString() ?? 'My EmbyGo';
        return <String, dynamic>{
          'capabilities': <String, dynamic>{
            'dialect': dialect,
            'server_id': sid,
            'server_name': srvName,
            'advertised_version': '4.8.11.0',
            'supports_transcoding': dialect != 'embygo',
            'supports_popular': dialect == 'embygo',
            'supports_suggestions': true,
            'supports_hide_from_resume': true,
            'uses_stream_tickets': dialect == 'embygo',
          },
          'user': <String, dynamic>{
            'Id': params['user_id'] ?? 'u1',
            'Name': isAdmin ? 'admin' : 'viewer',
            'Policy': <String, dynamic>{
              'IsAdministrator': isAdmin,
              'EnableContentDownloading': enableContentDownloading,
            },
          },
          'proxy_addr': '127.0.0.1:28080',
        };
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
            },
            <String, dynamic>{
              'Id': 's-hot-1',
              'Name': '人生切割术',
              'Type': 'Series',
              'ProductionYear': 2025,
              'CommunityRating': 9.1,
              'Overview': '近期全服最热剧集轮播置顶测试。',
              'BackdropImageTags': <dynamic>['bd-sev-1'],
            },
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
      case 'ai_translate':
        lastAiTranslateParams = Map<String, dynamic>.from(params);
        return <String, dynamic>{
          'translated': '【客户端翻译】${params['text']}',
          'direct_ip': params['direct_ip'] == true,
        };
      case 'ai_list_models':
        lastAiModelsParams = Map<String, dynamic>.from(params);
        return <String, dynamic>{
          'models': <String>['gpt-4o-mini', 'deepseek-chat', 'qwen-plus'],
          'direct_ip': params['direct_ip'] == true,
        };
      case 'get_items':
        final items = List<Map<String, dynamic>>.generate(12, (i) {
          final n = i + 1;
          return <String, dynamic>{
            'Id': 'lib-movie-$n',
            'Name': '星际远航：超长测试片名第 $n 部典藏版',
            'Type': 'Movie',
            'ProductionYear': 2024,
            'CommunityRating': 8.6,
            'MediaSourceCount': 2,
          };
        });
        return <String, dynamic>{
          'Items': items,
          'TotalRecordCount': items.length,
        };
      case 'get_embygo_admin_dashboard':
        return <String, dynamic>{
          'status': <String, dynamic>{
            'version': '0.9.4',
            'items': 24800,
            'files': 21200,
            'subtitle_files': 18600,
            'postgres_catalog': true,
            'transcoding_enabled': false,
            'last_scan_attempt_at': '2026-11-27T01:30:00Z',
          },
          'counts': <String, dynamic>{
            'MovieCount': 1280,
            'SeriesCount': 460,
            'EpisodeCount': 23060,
          },
          'playing_sessions': <dynamic>[],
          'sessions': <dynamic>[
            <String, dynamic>{
              'Id': 'sess-1',
              'UserName': 'alice',
              'Client': 'Vedro iOS',
              'DeviceName': 'iPhone 16 Pro',
              'NowPlayingItem': <String, dynamic>{
                'Name': '沙丘2',
                'RunTimeTicks': 100000000,
              },
              'PlayState': <String, dynamic>{
                'PositionTicks': 42000000,
                'PlayMethod': 'DirectPlay',
                'IsPaused': false,
              },
            },
          ],
          'libraries': <dynamic>[
            <String, dynamic>{
              'Id': 'lib-1',
              'Name': '4K 电影臻藏',
              'CollectionType': 'movies',
              'Locations': <String>['/mnt/cloud/Movies_4K'],
              'GenerateCovers': true,
            },
          ],
          'users': <dynamic>[
            <String, dynamic>{
              'Id': 'u-admin',
              'Name': 'admin',
              'Policy': <String, dynamic>{'IsAdministrator': true, 'EnableContentDownloading': true},
            },
            <String, dynamic>{
              'Id': 'u-alice',
              'Name': 'alice_vip_member',
              'Policy': <String, dynamic>{'IsAdministrator': false, 'EnableContentDownloading': true},
            },
          ],
          'tasks': <dynamic>[
            <String, dynamic>{
              'Key': 'RefreshLibrary',
              'Name': '扫描媒体库增量更新',
              'State': 'Idle',
            },
          ],
          'activity': <dynamic>[
            <String, dynamic>{
              'Name': 'alice 开始播放 沙丘2',
              'Date': '2026-11-27T02:10:00Z',
              'Severity': 'Info',
            },
          ],
          'devices': <String, dynamic>{
            'Items': mockDevices,
          },
        };
      case 'get_user_devices':
        return <String, dynamic>{
          'items': List<Map<String, dynamic>>.from(mockDevices),
          'current_device_id': 'dev-current-win',
        };
      case 'delete_user_device':
        final targetDev = params['device_id']?.toString();
        mockDevices.removeWhere((d) => d['DeviceId'] == targetDev);
        return <String, dynamic>{'deleted': targetDev};
      case 'run_embygo_speedtest':
        return <String, dynamic>{
          'route': 'cdn',
          'latency_ms': 24.0,
          'client_ip': '203.0.113.88',
          'measured_mbps': 168.4,
          'account_limit_bps': 0,
          'effective_mbps': 168.4,
          'remaining_this_hour': 5,
          'remaining_today': 19,
        };
      case 'cancel_embygo_speedtest':
        return <String, dynamic>{'cancelled': true};
      case 'admin_user_detail':
        return <String, dynamic>{
          'Policy': <String, dynamic>{'EnableContentDownloading': true},
          'DownloadQuota': <String, dynamic>{
            'Enabled': true,
            'AdminExempt': false,
            'MonthlyQuotaBytes': 32212254720,
            'MonthlyUsedBytes': 0,
            'MonthlyRemainingBytes': 32212254720,
            'PackBytes': 536870912000,
            'TotalRemainingBytes': 569083166720,
            'ActiveDownloads': 1,
            'MaxConcurrentDownloads': 2,
          },
        };
      case 'admin_download_quota_events':
        return <dynamic>[];
      case 'get_image_cache_stats':
        return <String, dynamic>{
          'disk_files': mockImageCacheFiles,
          'disk_bytes': mockImageCacheBytes,
          'memory_entries': mockImageCacheMemEntries,
          'cache_dir': '/tmp/vedro-mock/img_cache',
        };
      case 'clear_image_cache':
        final removed = mockImageCacheFiles;
        final freed = mockImageCacheBytes;
        mockImageCacheFiles = 0;
        mockImageCacheBytes = 0;
        mockImageCacheMemEntries = 0;
        return <String, dynamic>{
          'removed_files': removed,
          'freed_bytes': freed,
        };
      case 'load_subtitle_cues':
        return <String, dynamic>{
          'format': 'srt',
          'total': 3,
          'cues': <Map<String, dynamic>>[
            {'idx': 0, 'start_ms': 1000, 'end_ms': 4000, 'text': 'Hello world.'},
            {'idx': 1, 'start_ms': 5000, 'end_ms': 8000, 'text': 'How are you?'},
            {'idx': 2, 'start_ms': 150000, 'end_ms': 154000, 'text': 'See you later.'},
          ],
        };
      case 'ai_translate_subtitle_batch':
        subtitleBatchTranslateCalls += 1;
        final lang = (params['target_lang'] ?? '简体中文').toString();
        final lines = (params['lines'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>();
        final out = <String, String>{};
        for (final l in lines) {
          final idx = l['idx'].toString();
          final txt = l['text'].toString();
          out[idx] = '[$lang] $txt';
        }
        return <String, dynamic>{'translations': out, 'model': 'mock-ai'};
      case 'ai_transcribe_audio_slice':
        asrSliceCalls += 1;
        if (failAsrSlices) {
          throw Exception('ASR service unavailable');
        }
        final startMs = (((params['start_secs'] as num?)?.toDouble() ?? 0.0) * 1000).round();
        return <String, dynamic>{
          'detected_language': 'ja',
          'cues': <Map<String, dynamic>>[
            {
              'start_ms': startMs + 500,
              'end_ms': startMs + 4500,
              'text': 'おはようございます',
            },
          ],
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

    expect(find.text('添加服务器'), findsOneWidget);
    expect(find.byIcon(Icons.tune_rounded), findsWidgets);

    await tester.tap(find.text('添加服务器'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(1), 'viewer');
    await tester.enterText(find.byType(TextField).at(2), 'secret');
    await tester.tap(find.text('连接并添加'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('人生切割术'), findsOneWidget);
    expect(find.text('近期热播'), findsOneWidget);
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
    expect(find.text('AI 翻译'), findsOneWidget);
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
    // Series multi-version selector MUST be a sleek iOS Pull-Down Dropdown and switchable!
    expect(find.byKey(const ValueKey('detail-version-selector')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-version-dropdown')), findsOneWidget);
    expect(find.text('4K · Dolby Vision · Atmos'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('detail-version-dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('1080p · BluRay · x265'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('series-version-item-1')));
    await tester.pumpAndSettle();
    expect(find.text('1080p · BluRay · x265'), findsOneWidget);

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

    // v0.3.10: redundant NFO metadata, technical specs, and file path footer blocks are removed
    expect(find.text('影片资料与 NFO 信息'), findsNothing);
    expect(find.text('技术规格'), findsNothing);
    expect(find.text('媒体路径'), findsNothing);
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

    // Visual-first server cards: latency as signal+ms, inventory as compact icon+number,
    // offline as cloud_off icon (no verbose "在线 · 电影 · 剧集" sentences).
    expect(find.text('28ms'), findsOneWidget);
    expect(find.text('420'), findsOneWidget);
    expect(find.text('85'), findsOneWidget);
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    expect(find.byIcon(Icons.tv_rounded), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
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
    expect(find.byKey(const ValueKey('detail-version-dropdown')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-audio-dropdown')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-subtitle-dropdown')), findsOneWidget);
    expect(find.text('4K · Dolby Vision · TrueHD Atmos · REMUX'), findsOneWidget);
    expect(find.text('English TrueHD Atmos'), findsOneWidget);
    expect(find.text('简体中文 ASS'), findsOneWidget);

    // Open iOS Glass Pull-Down Version Menu & switch to 1080p version
    await tester.ensureVisible(find.byKey(const ValueKey('detail-version-dropdown')));
    await tester.tap(find.byKey(const ValueKey('detail-version-dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('1080p · BluRay · x264'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('movie-version-item-1')));
    await tester.pumpAndSettle();
    expect(find.text('1080p · BluRay · x264'), findsOneWidget);

    // Open Subtitle Pull-Down Menu -> verify 关闭字幕 & 挂载本地字幕文件… are inside the dropdown
    await tester.ensureVisible(find.byKey(const ValueKey('detail-subtitle-dropdown')));
    await tester.tap(find.byKey(const ValueKey('detail-subtitle-dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('挂载本地字幕文件…'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('detail-subtitle-off-item')));
    await tester.pumpAndSettle();
    expect(find.text('关闭字幕'), findsOneWidget);
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
    // Before clicking 下载与缓存, sidebar shows clean "无任务" without quota balance text
    expect(find.byKey(const ValueKey('settings-download-quota-card')), findsNothing);
    await tester.tap(find.text('下载与缓存'));
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
      '5-version Movie & Series enforce strict single-selection and keep DetailScreen free of global preferred-language clutter',
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
    expect(find.byKey(const ValueKey('detail-version-dropdown')), findsOneWidget);

    // DetailScreen NEVER shows global preferred audio/subtitle rows OR wordy banners!
    expect(find.text('首选配音'), findsNothing);
    expect(find.text('首选字幕'), findsNothing);
    expect(find.textContaining('网盘尚未缓存'), findsNothing);
    expect(find.byKey(const ValueKey('detail-audio-subtitle-panel')), findsOneWidget);

    // Open Version Pull-Down Menu & cycle through versions #2, #3, #4, #5 — strictly ONE checkmark in menu!
    for (final idx in [1, 2, 3, 4, 0]) {
      final drop = find.byKey(const ValueKey('detail-version-dropdown'));
      await tester.ensureVisible(drop);
      await tester.tap(drop);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('vedro-pulldown-menu-list')),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      final item = find.byKey(ValueKey('movie-version-item-$idx'));
      await tester.ensureVisible(item);
      await tester.tap(item);
      await tester.pumpAndSettle();
    }

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
    expect(find.byKey(const ValueKey('detail-version-dropdown')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-audio-subtitle-panel')), findsNothing);
    expect(find.text('首选配音'), findsNothing);
    expect(find.text('首选字幕'), findsNothing);

    for (final idx in [1, 2, 3, 4, 2]) {
      final drop = find.byKey(const ValueKey('detail-version-dropdown'));
      await tester.ensureVisible(drop);
      await tester.tap(drop);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('vedro-pulldown-menu-list')),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      final item = find.byKey(ValueKey('series-version-item-$idx'));
      await tester.ensureVisible(item);
      await tester.tap(item);
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
      '4 Cohesive Master Themes (Cinema, Frosted, Liquid Glass, MD3), Monet Dynamic Color & Conditional Sub-Settings',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 1. Verify 4 Master Themes + Legacy share code roundtrip + Monet RGBA pixel extraction
    expect(VedroSkin.masterThemes.length, equals(4));
    expect(VedroSkin.byId('ios_liquid_glass').isLiquidGlass, isTrue);
    expect(VedroSkin.byId('ios_frosted').effectiveSurfaceMaterial, equals('unified_glass'));
    expect(VedroSkin.byId('material_design').themeFamily, equals('material_design'));

    // Synthetic fiery amber-orange poster pixels -> Monet extractor picks warm orange hue (~20°-40°)
    final amberPixels = List<int>.generate(16 * 16 * 4, (i) {
      final ch = i % 4;
      if (ch == 0) return 235; // R
      if (ch == 1) return 115; // G
      if (ch == 2) return 28; // B
      return 255; // A
    });
    final extractedAmber = DynamicColorEngine.extractDominantSeedFromRgba(
      amberPixels,
      width: 16,
      height: 16,
    );
    expect(extractedAmber, isNotNull);
    final amberHue = HSLColor.fromColor(extractedAmber!).hue;
    expect(amberHue, inInclusiveRange(15.0, 45.0));

    final liquidWithMonet = DynamicColorEngine.applySeedToSkin(
      VedroSkin.iosLiquidGlass,
      extractedAmber,
    );
    expect(liquidWithMonet.isLiquidGlass, isTrue);
    expect((HSLColor.fromColor(liquidWithMonet.accent).hue - amberHue).abs(), lessThan(12.0));

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
    expect(decoded?.name, equals('落日琥珀馆'));

    // 2. SettingsScreen -> 应用风格 switches between 4 Master Themes & shows ONLY matching sub-settings!
    final app = VedroAppState(_MockVedroCore());
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
    await tester.tap(find.text('应用风格'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('skin-studio-pane')), findsOneWidget);
    expect(find.byKey(const ValueKey('skin-live-preview-stage')), findsOneWidget);

    // Default `immersive_cinema`: NO glass translucency / blur sliders!
    expect(find.byKey(const ValueKey('skin-preset-immersive_cinema')), findsOneWidget);
    expect(find.byKey(const ValueKey('glass-translucency-slider-row')), findsNothing);
    expect(find.byKey(const ValueKey('glass-blur-radius-slider-row')), findsNothing);

    // Switch to `ios_liquid_glass` -> Translucency, Blur Radius & Liquid Specular appear!
    await tester.tap(find.byKey(const ValueKey('skin-preset-ios_liquid_glass')));
    await tester.pumpAndSettle();
    expect(app.prefs.skinId, equals('ios_liquid_glass'));
    expect(app.prefs.activeSkin.isLiquidGlass, isTrue);
    expect(find.byKey(const ValueKey('glass-translucency-slider-row')), findsOneWidget);
    expect(find.byKey(const ValueKey('glass-blur-radius-slider-row')), findsOneWidget);
    expect(find.byKey(const ValueKey('liquid-specular-dropdown')), findsOneWidget);

    // Switch to `ios_frosted` -> Translucency & Blur Radius stay visible, Liquid Specular hides!
    await tester.tap(find.byKey(const ValueKey('skin-preset-ios_frosted')));
    await tester.pumpAndSettle();
    expect(app.prefs.skinId, equals('ios_frosted'));
    expect(find.byKey(const ValueKey('glass-translucency-slider-row')), findsOneWidget);
    expect(find.byKey(const ValueKey('liquid-specular-dropdown')), findsNothing);

    // Switch to `material_design` -> Glass sliders hide, MD3 Tonal Chroma appears!
    await tester.tap(find.byKey(const ValueKey('skin-preset-material_design')));
    await tester.pumpAndSettle();
    expect(app.prefs.skinId, equals('material_design'));
    expect(find.byKey(const ValueKey('glass-translucency-slider-row')), findsNothing);
    expect(find.byKey(const ValueKey('md3-chroma-dropdown')), findsOneWidget);

    // Switch Appearance Mode to Light via iOS Pull-Down Menu (`theme-mode-dropdown`)
    await tester.ensureVisible(find.byKey(const ValueKey('theme-mode-dropdown')));
    await tester.tap(find.byKey(const ValueKey('theme-mode-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theme-mode-light')));
    await tester.pumpAndSettle();
    expect(app.prefs.themeMode, equals('light'));
    expect(app.prefs.activeSkin.isLight, isTrue);

    // Pick iOS Accent Color swatch (`purple`) & switch Desktop Nav Layout without losing Settings tab!
    await tester.ensureVisible(find.byKey(const ValueKey('accent-swatch-purple')));
    await tester.tap(find.byKey(const ValueKey('accent-swatch-purple')));
    await tester.pumpAndSettle();
    expect(app.prefs.accentId, equals('purple'));

    await tester.ensureVisible(find.byKey(const ValueKey('desktop-nav-layout-dropdown')));
    await tester.tap(find.byKey(const ValueKey('desktop-nav-layout-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('skin-mod-left_rail')));
    await tester.pumpAndSettle();
    expect(app.prefs.activeSkin.navLayout, equals('left_rail'));
    expect(find.byKey(const ValueKey('skin-studio-pane')), findsOneWidget);
  });

  testWidgets(
      'Settings hosts Global Audio/Subtitle, Font preview, AI Model Fetch + Proxy IP routing & Subscription Node Picker',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final mock = _MockVedroCore();
    final app = VedroAppState(mock);

    // 1. Default theme is Cohesive Immersive Cinema (`immersive_cinema` + `full_bleed` + `blurred_fanart` + Monet ON)!
    expect(app.prefs.activeSkin.id, equals('immersive_cinema'));
    expect(app.prefs.activeSkin.heroStyle, equals('full_bleed'));
    expect(app.prefs.activeSkin.backdropMode, equals('blurred_fanart'));
    expect(app.prefs.dynamicMonet, isTrue);

    // 2. AI translation supports both direct IP AND proxy IP (`direct_ip: false`) + model list fetching!
    await app.updatePrefs(app.prefs.copyWith(aiEnabled: true, aiDirectClientIp: false));
    final translated = await app.translateText('Do not go gentle into that good night.');
    expect(translated, contains('客户端翻译'));
    expect(mock.lastAiTranslateParams?['direct_ip'], isFalse);

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

    // 3. Settings -> 播放设置 prominently hosts Global Preferred Audio & Subtitle Languages
    await tester.tap(find.text('播放设置'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-global-audio-sub-card')), findsOneWidget);
    expect(find.text('首选音轨语言'), findsOneWidget);
    expect(find.text('首选字幕语言'), findsOneWidget);

    // 4. Settings -> 字体管理 shows live Font & Cinema Subtitle preview card
    await tester.tap(find.text('字体管理'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('font-live-preview-card')), findsOneWidget);
    expect(find.text('不要温顺地走进那个良夜'), findsOneWidget);

    // 5. Settings no longer includes in-app proxy ('网络代理') section
    expect(find.text('网络代理'), findsNothing);

    // 6. Settings -> AI 翻译 fetches model list (`/models`) cleanly!
    await tester.drag(find.byType(ListView).first, const Offset(0, -340));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI 翻译'));
    await tester.pumpAndSettle();
    expect(find.textContaining('100% 不经过'), findsNothing);
    expect(find.byKey(const ValueKey('ai-preset-bilibili')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-egress-false')));
    await tester.pumpAndSettle();
    expect(app.prefs.aiDirectClientIp, isFalse);
    await tester.tap(find.byKey(const ValueKey('ai-fetch-models-btn')));
    await tester.pumpAndSettle();
    expect(mock.lastAiModelsParams?['direct_ip'], isFalse);
    expect(find.byKey(const ValueKey('ai-model-chip-deepseek-chat')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-model-chip-deepseek-chat')));
    await tester.pumpAndSettle();
    expect(app.prefs.aiModel, equals('deepseek-chat'));
  });

  testWidgets('Android Double-Back Exit Confirmation & Mobile vs Desktop Differentiated SkinStudioPane',
      (tester) async {
    // 1. Verify DisplayMetricsProfile resolution & PPI adaptation across form factors
    const compactAndroid = DisplayMetricsProfile(
      platform: 'android',
      logicalSize: Size(360, 780),
      devicePixelRatio: 2.75,
    );
    const ultraWideMac = DisplayMetricsProfile(
      platform: 'macos',
      logicalSize: Size(2560, 1440),
      devicePixelRatio: 2.0,
    );
    expect(compactAndroid.formFactor, equals(VedroFormFactor.compactPhone));
    expect(compactAndroid.estimatedPpi, equals(440));
    expect(compactAndroid.recommendedSkinOverrides['mobile_nav_style'], equals('compact_icon_only'));
    expect(compactAndroid.recommendedSkinOverrides['hero_style'], equals('full_bleed'));
    expect(compactAndroid.recommendedBufferSizeMb, equals(96));
    expect(ultraWideMac.formFactor, equals(VedroFormFactor.desktopUltraWide));
    expect(ultraWideMac.recommendedBufferSizeMb, equals(384));

    // 2. Android Mobile viewport (390x844 @ 3x): Back on Settings returns to Home; first Back on Home shows toast!
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final app = VedroAppState(_MockVedroCore());
    await tester.pumpWidget(
      AnimatedBuilder(
        animation: app,
        builder: (_, __) => MaterialApp(
          theme: VedroTheme.fromSkin(app.prefs.activeSkinFor(isMobile: true)),
          home: ShellScreen(appState: app),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to 设置 tab, then press system Back -> returns to 首页 instead of exiting!
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('添加服务器'), findsOneWidget);

    // Press system Back on 首页 once -> shows concise '再按一次退出' toast!
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const ValueKey('double-back-exit-toast')), findsOneWidget);
    expect(find.text('再按一次退出'), findsOneWidget);

    // 3. Portrait Android Mobile SkinStudioPane (360px narrow screen!) renders cleanly with ZERO overflow!
    tester.view.physicalSize = const Size(1080, 2340); // 360x780 @ 3x portrait phone!
    tester.view.devicePixelRatio = 3.0;
    await tester.pumpWidget(
      AnimatedBuilder(
        animation: app,
        builder: (_, __) => MaterialApp(
          theme: VedroTheme.fromSkin(app.prefs.activeSkinFor(isMobile: true)),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SkinStudioPane(appState: app, platformOverride: 'android'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('skin-live-preview-stage')), findsOneWidget);
    expect(find.text('沉浸影院'), findsWidgets);
    expect(find.text('iOS 毛玻璃'), findsOneWidget);
    expect(find.text('iOS 液态玻璃'), findsOneWidget);
    expect(find.text('Material 设计'), findsOneWidget);
    expect(find.text('莫奈动态取色'), findsOneWidget);
    expect(find.text('底部导航样式'), findsOneWidget);
    expect(find.text('滑动时收缩导航栏'), findsOneWidget);
    expect(find.text('显示导航栏名称'), findsOneWidget);
    expect(find.text('导航栏位置'), findsNothing);

    // Tap preview scene chip on portrait phone -> zero overflow!
    await tester.tap(find.byKey(const ValueKey('preview-scene-sakura')));
    await tester.pumpAndSettle();
    expect(find.text('花束般的恋爱'), findsOneWidget);
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

    // Version 0 (already played/cached) shows its exact Audio & Subtitle streams on the Pull-Down buttons with 0 cloud probes!
    expect(mock.probeMediaSourceCalls, equals(0));
    expect(find.text('English TrueHD Atmos 7.1'), findsOneWidget);
    expect(find.text('简英双语特效 ASS'), findsOneWidget);

    // Switch Version Dropdown to Version 1 (unplayed on cloud drive) -> 0 cloud probes, shows Version 1 passive traits!
    await tester.tap(find.byKey(const ValueKey('detail-version-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('movie-version-item-1')));
    await tester.pumpAndSettle();
    expect(mock.probeMediaSourceCalls, equals(0));
    expect(find.text('English TrueHD Atmos 7.1'), findsNothing);
    expect(find.textContaining('网盘尚未缓存'), findsNothing);
    expect(find.text('国粤双语'), findsOneWidget);

    // Switch Version Dropdown to Version 2 (played raw version) -> Shows Japanese AAC audio + concise "无内封字幕"
    await tester.tap(find.byKey(const ValueKey('detail-version-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('movie-version-item-2')));
    await tester.pumpAndSettle();
    expect(mock.probeMediaSourceCalls, equals(0));
    expect(find.text('日语原声 AAC 2.0'), findsOneWidget);
    expect(find.text('无内封字幕'), findsOneWidget);
  });

  testWidgets(
      'Portrait 360px Series Episode List & AdminConsolePane stay crisp with clean version labels and zero overflow',
      (tester) async {
    // 1. Series version resolver strips S01E01 & Preferred clutter cleanly
    final cleaned = MediaSourceModel.resolveVersions(
      [
        MediaSourceModel(id: 's1', name: 'S01E01 · 动漫 · Local · Preferred', container: 'mkv'),
        MediaSourceModel(id: 's2', name: 'S01E01 · 1080p · 国粤双语 · Preferred', container: 'mkv'),
      ],
      stripEpisodePrefix: true,
    );
    expect(cleaned.first.displayTitle, equals('动漫 · Local'));
    expect(cleaned.last.displayTitle, equals('1080p · 国粤双语'));

    // 2. Portrait 360x780 Series Episode list mode: full episode headline + unclipped range pills + expandable search
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final mock = _MockVedroCore(isAdmin: true, dialect: 'embygo', canDownload: true);
    final app = VedroAppState(mock)
      ..userId = 'u-admin'
      ..isAdmin = true
      ..connectedUrl = 'https://embygo.example.com'
      ..capabilities = ServerCapabilitiesModel(
        dialect: 'embygo',
        serverId: 'srv-1',
        serverName: 'EmbyGo Pro',
        advertisedVersion: '4.8.11.0',
        supportsTranscoding: false,
        supportsPopular: true,
        supportsSuggestions: true,
        supportsHideFromResume: true,
        usesStreamTickets: true,
      );

    await tester.pumpWidget(MaterialApp(
      theme: VedroTheme.fromSkin(VedroSkin.iosLiquidGlass),
      home: DetailScreen(
        item: MediaItemModel(id: 'tv1', name: '三体', type: 'Series', canDownload: true),
        appState: app,
      ),
    ));
    await tester.pumpAndSettle();

    // Switch Episode view mode to 'list' via clean Pull-Down menu
    final viewDrop = find.byKey(const ValueKey('detail-episode-view-dropdown'));
    await tester.ensureVisible(viewDrop);
    await tester.tap(viewDrop);
    await tester.pumpAndSettle();
    await tester.tap(find.text('列表视图'));
    await tester.pumpAndSettle();

    // Episode 1 headline is clearly visible ("1. 倒计时") alongside visual icon+count version pill!
    expect(find.text('1. 倒计时'), findsOneWidget);
    expect(find.byIcon(Icons.layers_outlined), findsWidgets);
    expect(find.text('2'), findsWidgets);
    expect(find.text('1-50'), findsOneWidget);
    expect(find.text('51-100'), findsOneWidget);
    expect(find.text('101-120'), findsOneWidget);

    // Search toggle opens full-width search bar cleanly
    await tester.tap(find.byKey(const ValueKey('detail-episode-search-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('取消'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // 3. Portrait 360x780 AdminConsolePane: scrollable tabs, Liquid Glass cards & clean Quota dialog
    await tester.pumpWidget(MaterialApp(
      theme: VedroTheme.fromSkin(VedroSkin.iosLiquidGlass),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ListenableBuilder(
            listenable: app,
            builder: (_, __) => AdminConsolePane(appState: app),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('admin-console-pane')), findsOneWidget);
    expect(find.text('1280'), findsOneWidget);
    expect(find.text('4K 电影臻藏'), findsOneWidget);

    await tester.tap(find.text('用户'));
    await tester.pumpAndSettle();
    expect(find.text('alice_vip_member'), findsOneWidget);
    expect(find.textContaining('EnableContentDownloading'), findsNothing);

    await tester.tap(find.text('管理').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载权限与流量额度'));
    await tester.pumpAndSettle();
    expect(find.text('允许离线下载原文件'), findsOneWidget);
    expect(find.textContaining('User.Policy'), findsNothing);
  });

  testWidgets(
      'Mobile Home Hero supports horizontal swipe, ShaderMask zero-seam fade, compact category rails & live Settings card scale',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 2532); // 390x844 @ 3x iPhone portrait
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final mock = _MockVedroCore();
    final app = VedroAppState(mock)
      ..userId = 'u1'
      ..connectedUrl = 'https://embygo.example.com'
      ..popular = [
        MediaItemModel(
          id: 'hero-s1',
          name: '人生切割术',
          type: 'Series',
          backdropImageTag: 'bg1',
          overview: '宏观数据精检部门的记忆切割故事。',
        ),
        MediaItemModel(
          id: 'hero-s2',
          name: '幕府将军',
          type: 'Series',
          backdropImageTag: 'bg2',
          overview: '战国风云史诗剧集。',
        ),
      ]
      ..views = [
        MediaItemModel(id: 'lib-cn', name: '华语电影', type: 'CollectionFolder'),
        MediaItemModel(id: 'lib-en', name: '外语电影', type: 'CollectionFolder'),
      ]
      ..latestByLibrary = [
        <String, dynamic>{
          'library': <String, dynamic>{'Id': 'lib-cn', 'Name': '华语电影', 'Type': 'CollectionFolder'},
          'items': <Map<String, dynamic>>[
            <String, dynamic>{'Id': 'cn1', 'Name': '流浪地球2', 'Type': 'Movie', 'ProductionYear': 2023},
            <String, dynamic>{'Id': 'cn2', 'Name': '让子弹飞', 'Type': 'Movie', 'ProductionYear': 2010},
          ],
        },
        <String, dynamic>{
          'library': <String, dynamic>{'Id': 'lib-en', 'Name': '外语电影', 'Type': 'CollectionFolder'},
          'items': <Map<String, dynamic>>[
            <String, dynamic>{'Id': 'en1', 'Name': '星际穿越', 'Type': 'Movie', 'ProductionYear': 2014},
            <String, dynamic>{'Id': 'en2', 'Name': '盗梦空间', 'Type': 'Movie', 'ProductionYear': 2010},
          ],
        },
      ];

    await tester.pumpWidget(
      AnimatedBuilder(
        animation: app,
        builder: (_, __) => MaterialApp(
          theme: VedroTheme.fromSkin(app.prefs.activeSkinFor(isMobile: true)),
          home: Scaffold(
            body: VedroSkinCanvas(
              backdropImageUrl: 'https://embygo.example.com/Items/hero-s1/Images/Backdrop',
              child: HomeScreen(
                appState: app,
                onItemTap: (_, {heroPrefix}) {},
                onQuickPlay: (_) {},
                onLibraryTap: (_) {},
                onOpenServerHub: () {},
                onOpenAddServer: ([_]) {},
                onOpenSettings: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 1. Hero uses zero-saveLayer ClipRect + gradient dissolve (no offscreen ShaderMask!) & renders Slide 0
    expect(find.byKey(const ValueKey('hero-page-view')), findsOneWidget);
    expect(find.byKey(const ValueKey('hero-alpha-mask-0')), findsOneWidget);
    expect(tester.widget(find.byKey(const ValueKey('hero-alpha-mask-0'))), isA<ClipRect>());
    expect(find.text('人生切割术'), findsOneWidget);

    // 2. Horizontal swipe switches Hero slide from '人生切割术' -> '幕府将军'!
    await tester.fling(find.byKey(const ValueKey('hero-page-view')), const Offset(-280, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('幕府将军'), findsOneWidget);

    // 3. Compact mobile vertical & horizontal spacing: both 华语电影 and 外语电影 fit comfortably
    expect(app.prefs.horizontalMargin(false), equals(12.0));
    expect(app.prefs.posterCardWidth(false), closeTo(106.0, 0.1));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(find.text('最新加入 · 华语电影'), findsOneWidget);
    expect(find.text('最新加入 · 外语电影'), findsOneWidget);

    // 4. Settings -> 列表配置 adjusts posterScale (80%) & sectionSpacing live!
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
    // Switch to mobile sub-page or desktop pane: on 390px mobile SettingsScreen, tap '列表配置'
    await tester.tap(find.text('列表配置'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('poster-scale-slider')), findsOneWidget);
    await tester.tap(find.text('80%'));
    await tester.pumpAndSettle();
    expect(app.prefs.posterScale, closeTo(0.80, 0.01));
    expect(app.prefs.posterCardWidth(false), closeTo(84.8, 0.5));
  });

  testWidgets(
      'Default rating OFF / 2x OFF badges, toggleable ratings, and zero-overlap adaptive Library grid across PPI & TextScaler',
      (tester) async {
    final defaults = VedroPreferences.fromJson(const {});
    expect(defaults.showRatings, isFalse);
    expect(defaults.showMultiVersionBadge, isFalse);
    for (final s in VedroSkin.presets) {
      expect(s.showCardRating, isTrue, reason: 'Preset ${s.id} keeps rating badge support when enabled');
    }

    // 2. Default Poster Badges: clean poster with Rating star badge OFF & Multi-version '2×' OFF by default
    tester.view.physicalSize = const Size(1280, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final mock = _MockVedroCore();
    final app = VedroAppState(mock)
      ..userId = 'u1'
      ..connectedUrl = 'https://embygo.example.com'
      ..views = [
        MediaItemModel(id: 'lib1', name: '电影', type: 'CollectionFolder'),
      ];

    final sampleMovie = MediaItemModel(
      id: 'm1',
      name: '沙丘2',
      type: 'Movie',
      productionYear: 2024,
      communityRating: 8.6,
      mediaSourceCount: 2,
    );

    await tester.pumpWidget(
      AnimatedBuilder(
        animation: app,
        builder: (_, __) => MaterialApp(
          theme: VedroTheme.fromSkin(app.prefs.activeSkin),
          home: Scaffold(
            body: Center(
              child: MediaCard(
                item: sampleMovie,
                appState: app,
                width: 140,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('8.6'), findsNothing); // Clean poster by default!
    expect(find.textContaining('★'), findsNothing);
    expect(find.text('2×'), findsNothing); // Hidden by default!

    // Explicitly toggling showRatings ON displays '8.6' badge (without duplicating in subtitle)
    await app.updatePrefs(app.prefs.copyWith(showRatings: true));
    await tester.pumpAndSettle();
    expect(find.text('8.6'), findsOneWidget);
    expect(find.textContaining('★'), findsNothing);
    await app.updatePrefs(app.prefs.copyWith(showRatings: false));
    await tester.pumpAndSettle();
    expect(find.text('8.6'), findsNothing);

    // Design Language v2: version badges stay off poster art (version switching lives in Peek menu & Detail).
    await app.updatePrefs(app.prefs.copyWith(showMultiVersionBadge: true));
    await tester.pumpAndSettle();
    expect(find.text('2×'), findsNothing);
    await app.updatePrefs(app.prefs.copyWith(showMultiVersionBadge: false));
    await tester.pumpAndSettle();
    expect(find.text('2×'), findsNothing);

    // 4. Mathematical Zero-Overlap Proof for LibraryScreen across Extreme Resolutions, PPI & OS TextScaler
    Future<void> verifyZeroGridOverlap({
      required Size physicalSize,
      required double dpr,
      required String density,
      required double posterScale,
      required double textScale,
    }) async {
      tester.view.physicalSize = physicalSize;
      tester.view.devicePixelRatio = dpr;
      await app.updatePrefs(
        app.prefs.copyWith(listDensity: density, posterScale: posterScale),
      );
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: physicalSize / dpr,
            devicePixelRatio: dpr,
            textScaler: TextScaler.linear(textScale),
          ),
          child: MaterialApp(
            builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            ),
            theme: VedroTheme.fromSkin(app.prefs.activeSkinFor(isMobile: physicalSize.width / dpr < 600)),
            home: LibraryScreen(
              appState: app,
              onItemTap: (_) {},
              onQuickPlay: (_) {},
              onOpenAddServer: ([_]) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify zero Flutter overflow exceptions occurred
      expect(tester.takeException(), isNull);

      final cards = find.descendant(
        of: find.byKey(const ValueKey('library-poster-grid')),
        matching: find.byType(MediaCard),
      );
      final cardCount = cards.evaluate().length;
      expect(cardCount, greaterThanOrEqualTo(5));

      // Group visible MediaCards into rows by top Y coordinate
      final rects = List<Rect>.generate(cardCount, (i) => tester.getRect(cards.at(i)));
      final row0Top = rects.first.top;
      final row0Cards = rects.where((r) => (r.top - row0Top).abs() < 2.0).toList();
      final row1Cards = rects.where((r) => r.top > row0Top + 20.0).toList();
      expect(row0Cards.length, greaterThanOrEqualTo(2));
      expect(row1Cards, isNotEmpty);

      final row0Bottom = row0Cards.first.bottom;
      final row1Top = row1Cards.first.top;
      // Row 0's card (including title + '2024' year text) MUST end strictly above Row 1's poster with full spacing!
      expect(row0Bottom, lessThanOrEqualTo(row1Top - 6.0));

      // Also directly measure the '2024' year Text widget inside Row 0's first MediaCard!
      final row0YearFinder = find.descendant(
        of: cards.first,
        matching: find.text('2024'),
      );
      expect(row0YearFinder, findsOneWidget);
      final yearRect = tester.getRect(row0YearFinder);
      expect(yearRect.bottom, lessThanOrEqualTo(row0Bottom + 0.5));
      expect(yearRect.bottom, lessThanOrEqualTo(row1Top - 6.0));
    }

    // Case A: Ultra-compact 320x640 @ 2.0x phone + compact density + 75% card scale + 135% Large OS Font!
    await verifyZeroGridOverlap(
      physicalSize: const Size(640, 1280),
      dpr: 2.0,
      density: 'compact',
      posterScale: 0.75,
      textScale: 1.35,
    );

    // Case B: Standard 390x844 @ 3.0x phone + compact density + 80% card scale (4 columns!) + 115% OS Font!
    await verifyZeroGridOverlap(
      physicalSize: const Size(1170, 2532),
      dpr: 3.0,
      density: 'compact',
      posterScale: 0.80,
      textScale: 1.15,
    );

    // Case C: 2560x1440 @ 2.0x HiDPI Desktop + compact density + 85% card scale!
    await verifyZeroGridOverlap(
      physicalSize: const Size(2560, 1440),
      dpr: 2.0,
      density: 'compact',
      posterScale: 0.85,
      textScale: 1.0,
    );
  });

  testWidgets(
      'v0.3.7: Remembers last connected server, 媒体库 tab switches servers, zero double-fanart, zero DetailScreen CLS, no background blur, EmbyGo SpeedTest & Devices, and native window chrome sync',
      (tester) async {
    // Capture native window chrome calls (Windows DWM / macOS NSWindow / Android InsetsController)
    final chromeCalls = <Map<String, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.vedro.player/hardware'),
      (call) async {
        if (call.method == 'setWindowChrome' && call.arguments is Map) {
          chromeCalls.add(Map<String, dynamic>.from(call.arguments as Map));
          return null;
        }
        if (call.method == 'queryCapabilities') {
          return <String, dynamic>{'supports_hdr10': true, 'refresh_rate_hz': 120.0};
        }
        return null;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('com.vedro.player/hardware'), null);
    });

    // 1. Remembers last connected server (`srv-2`) even if `srv-1` has higher timestamp in list
    final mock = _MockVedroCore(
      isAdmin: true,
      lastActiveServerId: 'srv-2',
      savedServersList: [
        <String, dynamic>{
          'id': 'srv-1',
          'name': '一号主力服',
          'url': 'https://srv1.example.com',
          'dialect': 'embygo',
          'user_id': 'u1',
          'username': 'alice',
          'access_token': 'tok-1',
          'is_admin': true,
          'last_connected_at': 2000,
        },
        <String, dynamic>{
          'id': 'srv-2',
          'name': '二号动漫专线服',
          'url': 'https://srv2.example.com',
          'dialect': 'embygo',
          'user_id': 'u1',
          'username': 'alice',
          'access_token': 'tok-2',
          'is_admin': true,
          'last_connected_at': 1500,
        },
      ],
    );

    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final app = VedroAppState(mock);
    addTearDown(app.dispose);
    await app.initialize();
    expect(app.isSignedIn, isTrue);
    expect(app.activeServerId, equals('srv-2'));
    expect(app.activeServerDisplayName, equals('二号动漫专线服'));
    expect(mock.lastRestoreParams?['server_id'], equals('srv-2'));

    // 2. Legacy `blur_in_background: true` in saved JSON is forced OFF & AppLockGate NEVER blurs on background
    final migratedPrefs = VedroPreferences.fromJson({'blur_in_background': true});
    expect(migratedPrefs.blurInBackground, isFalse);

    await tester.pumpWidget(
      AnimatedBuilder(
        animation: app,
        builder: (_, __) {
          final skin = app.prefs.activeSkin;
          return MaterialApp(
            theme: VedroTheme.fromSkin(skin),
            home: AppLockGate(
              appState: app,
              child: ShellScreen(appState: app),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    // Simulate switching app to inactive/paused (e.g., Alt-Tab on Windows or backgrounding on mobile) -> ZERO blur shield!
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byType(BackdropFilter), findsWidgets); // Only glass nav, no full-screen privacy shield
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    // 3. Nav bar '媒体库' opens ServerHubScreen (multi-server switcher) and tapping '一号主力服' switches straight to Home!
    await tester.tap(find.text('媒体库').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('server-hub-screen')), findsOneWidget);
    expect(find.text('一号主力服'), findsOneWidget);
    expect(find.text('二号动漫专线服'), findsWidgets);

    await tester.tap(find.text('一号主力服'));
    await tester.pumpAndSettle();
    expect(app.activeServerId, equals('srv-1'));
    expect(find.byKey(const ValueKey('tab-home')), findsOneWidget);

    // 4. DetailScreen Frame-0 Stability (Zero button pop-in / CLS) & Zero Double-Stacked VedroSkinCanvas Fanart!
    await app.updatePrefs(app.prefs.copyWith(skinId: 'ios_frosted')); // usesBlurredFanart == true!
    await tester.pumpWidget(
      MaterialApp(
        theme: VedroTheme.fromSkin(app.prefs.activeSkin),
        home: DetailScreen(
          item: MediaItemModel(id: 'tv1', name: 'FX战士久留美', type: 'Series'),
          appState: app,
        ),
      ),
    );
    // Pump Frame 0 BEFORE async get_item / get_seasons / get_episodes complete!
    await tester.pump();
    final canvasOnDetail = tester.widget<VedroSkinCanvas>(find.byType(VedroSkinCanvas));
    expect(canvasOnDetail.backdropImageUrl, isNull); // NEVER double-stacked!
    expect(find.textContaining('播放'), findsOneWidget); // Play button ALREADY present on Frame 0!
    final frame0PlayTop = tester.getTopLeft(find.textContaining('播放').first).dy;

    await tester.pumpAndSettle();
    final settledPlayTop = tester.getTopLeft(find.textContaining('播放').first).dy;
    // Play CTA stays rock-steady instead of jumping down heavily!
    expect((settledPlayTop - frame0PlayTop).abs(), lessThanOrEqualTo(28.0));
    expect(chromeCalls, isNotEmpty);

    // 5. SettingsScreen exposes EmbyGo 播放测速 & 设备管理 (and Privacy has NO background-blur switch!)
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

    // Speedtest section runs EmbyGo route speedtest and renders tiers & IP
    await tester.tap(find.text('播放测速'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('speedtest-action-btn')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('speedtest-action-btn')));
    await tester.pumpAndSettle();
    expect(find.text('自建 CDN'), findsOneWidget);
    expect(find.text('203.0.113.88'), findsOneWidget);
    expect(find.text('168.4 Mbps'), findsWidgets);
    expect(find.text('4K 原盘 REMUX'), findsOneWidget);
    expect(find.text('可流畅播放'), findsWidgets);

    // Devices section lists current + old device and removes old iPad device cleanly
    await tester.tap(find.text('设备管理'));
    await tester.pumpAndSettle();
    expect(find.text('Windows 11 Desktop'), findsOneWidget);
    expect(find.text('当前设备'), findsOneWidget);
    expect(find.text('iPad Pro'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remove-device-dev-old-ipad')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '移除'));
    await tester.pumpAndSettle();
    expect(find.text('iPad Pro'), findsNothing);
    expect(app.userDevices.length, equals(1));

    // Scroll Settings sidebar down to Privacy & AdminConsolePane
    await tester.drag(find.byType(ListView).first, const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐私保护'));
    await tester.pumpAndSettle();
    expect(find.text('切至后台时模糊应用画面'), findsNothing);

    await tester.tap(find.text('服务器管理台'));
    await tester.pumpAndSettle();
    expect(find.text('设备'), findsOneWidget);
    await tester.tap(find.text('设备'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已登记设备'), findsOneWidget);
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
      final boot = await bridge.invoke('bootstrap_state') as Map<String, dynamic>;
      expect(boot['version'], isNotEmpty);
      expect(boot['proxy_addr']?.toString(), contains('127.0.0.1:'));
      expect(boot['servers'], isA<List<dynamic>>());
      expect(boot['settings'], isA<Map<String, dynamic>>());
      final imgStats = await bridge.invoke('get_image_cache_stats') as Map<String, dynamic>;
      expect(imgStats['disk_files'], isA<num>());
      expect(imgStats['disk_bytes'], isA<num>());
      final cleared = await bridge.invoke('clear_image_cache') as Map<String, dynamic>;
      expect(cleared['removed_files'], isA<num>());
      expect(cleared['freed_bytes'], isA<num>());
    } finally {
      bridge.dispose();
    }
  });

  testWidgets(
      'v0.3.8: Instant bootstrap_state SWR Home hydration, Series cover FramedPoster fallback for missing episode stills, and WindowsImmersiveFrame',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 1. Instant bootstrap_state + cached_home SWR cold-start hydration (zero splash block!)
    final swrMock = _MockVedroCore(
      lastActiveServerId: 'srv-swr',
      savedServersList: const [
        <String, dynamic>{
          'id': 'srv-swr',
          'name': '极速冷启动服',
          'url': 'https://swr.example.com',
          'dialect': 'embygo',
          'user_id': 'u1',
          'username': 'alice',
          'access_token': 'tok-swr',
          'is_admin': false,
          'last_connected_at': 3000,
        },
      ],
      cachedHomeForBootstrap: const <String, dynamic>{
        'views': <dynamic>[
          <String, dynamic>{'Id': 'lib-swr', 'Name': '秒开电影库', 'Type': 'CollectionFolder'},
        ],
        'resume': <dynamic>[],
        'next_up': <dynamic>[],
        'popular': <dynamic>[
          <String, dynamic>{'Id': 'm-swr', 'Name': '冷启动秒出大片', 'Type': 'Movie'},
        ],
        'suggestions': <dynamic>[],
        'latest': <String, dynamic>{},
      },
    );
    final swrApp = VedroAppState(swrMock);
    addTearDown(swrApp.dispose);
    await swrApp.initialize();
    expect(swrApp.isInitialized, isTrue);
    expect(swrApp.isAutoRestoring, isFalse);
    expect(swrApp.activeServerId, equals('srv-swr'));
    expect(swrApp.views.map((v) => v.name), contains('秒开电影库'));
    expect(swrApp.popular.map((p) => p.name), contains('冷启动秒出大片'));

    // 2. Series episode without Thumb/Primary still falls back to Series/Season portrait cover via FramedPoster (matching EmbyGo Web)
    final app = VedroAppState(_MockVedroCore())
      ..userId = 'u1'
      ..connectedUrl = 'https://embygo.example.com'
      ..proxyAddr = '127.0.0.1:45678';

    final seriesWithCover = MediaItemModel(
      id: 'series-cover-1',
      name: '繁花',
      type: 'Series',
      primaryImageTag: 'series_poster_tag',
    );
    final epWithoutStill = MediaItemModel(
      id: 'ep-no-still-1',
      name: '第一集',
      type: 'Episode',
      seriesId: 'series-cover-1',
      seriesName: '繁花',
      seriesPrimaryImageTag: 'series_poster_tag',
      parentIndexNumber: 1,
      indexNumber: 1,
    );

    final resolvedWide = app.wideArt(epWithoutStill);
    expect(resolvedWide, isNotNull);
    expect(resolvedWide!.isPoster, isTrue);
    expect(resolvedWide.url, contains('/Items/series-cover-1/Images/Primary'));
    expect(resolvedWide.tinyUrl, contains('maxWidth=140'));

    await tester.pumpWidget(
      MaterialApp(
        theme: VedroTheme.fromSkin(app.prefs.activeSkin),
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 135,
            child: VedroArtwork(
              item: epWithoutStill,
              fallbackItem: seriesWithCover,
              appState: app,
              landscape: true,
              width: 440,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(FramedPoster), findsOneWidget);

    // 2. WindowsImmersiveFrame renders borderless caption buttons & auto-hides during cinema playback
    NativePlaybackChannel.fullscreenNotifier.value = false;
    NativePlaybackChannel.maximizedNotifier.value = false;
    NativePlaybackChannel.playerHudAutoHideNotifier.value = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: VedroTheme.fromSkin(app.prefs.activeSkin),
        home: const WindowsImmersiveFrame(
          isLight: false,
          forceEnableForTest: true,
          child: Scaffold(body: Center(child: Text('Full-Bleed Windows Canvas'))),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('win-caption-minimize')), findsOneWidget);
    expect(find.byKey(const ValueKey('win-caption-maximize')), findsOneWidget);
    expect(find.byKey(const ValueKey('win-caption-close')), findsOneWidget);

    NativePlaybackChannel.playerHudAutoHideNotifier.value = true;
    await tester.pump(const Duration(milliseconds: 220));
    final animOpacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first);
    expect(animOpacity.opacity, equals(0.0));
    NativePlaybackChannel.playerHudAutoHideNotifier.value = false;

    // 3. WindowsWindowDragArea starts drag immediately on empty header area without stealing button taps
    var dragCount = 0;
    var zoomCount = 0;
    var menuCount = 0;
    var btnTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 58,
            child: Stack(
              children: [
                Positioned.fill(
                  child: WindowsWindowDragArea(
                    key: const ValueKey('test-win-drag-area'),
                    forceEnableForTest: true,
                    onStartDrag: () => dragCount++,
                    onToggleZoom: () => zoomCount++,
                    onSystemMenu: () => menuCount++,
                  ),
                ),
                Positioned(
                  left: 16,
                  top: 11,
                  child: ElevatedButton(
                    key: const ValueKey('test-header-btn'),
                    onPressed: () => btnTaps++,
                    child: const Text('Click'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Tapping a button above WindowsWindowDragArea must click the button, NOT drag the window
    await tester.tap(find.byKey(const ValueKey('test-header-btn')));
    await tester.pump();
    expect(btnTaps, equals(1));
    expect(dragCount, equals(0));

    // Clicking empty header space at y=29 (center of 58px titlebar) triggers instant drag; rapid 2nd click triggers zoom
    final emptySpot = const Offset(280, 29);
    final g1 = await tester.startGesture(emptySpot, kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
    await g1.up();
    await tester.pump(const Duration(milliseconds: 80));
    expect(dragCount, equals(1));
    expect(zoomCount, equals(0));

    final g2 = await tester.startGesture(emptySpot, kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
    await g2.up();
    await tester.pump();
    expect(dragCount, equals(1));
    expect(zoomCount, equals(1));

    // Right-clicking empty header space opens native system menu
    final sec = await tester.startGesture(emptySpot, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await sec.up();
    await tester.pump();
    expect(menuCount, equals(1));
  });

  testWidgets(
      'v0.3.9: Per-platform blur cap, image cacheWidth scaling, GlassSurface zero-blur bypass & cached DanmakuLayer',
      (tester) async {
    // 1. PlatformPerfProfile bounds live blur sigma and computes lean decode cacheWidth
    expect(PlatformPerfProfile.clampLiveBlur(44.0), lessThanOrEqualTo(20.0));
    expect(PlatformPerfProfile.clampLiveBlur(0.0), equals(0.0));
    final posterCacheW = PlatformPerfProfile.imageCacheWidthFor(120, 3.0);
    expect(posterCacheW, isNotNull);
    expect(posterCacheW!, inInclusiveRange(180, 320));

    // 2. GlassSurface(enableBlur: false) mounts ZERO BackdropFilter layers (used when player HUD hides)
    await tester.pumpWidget(
      MaterialApp(
        theme: VedroTheme.fromSkin(VedroSkin.immersiveCinema),
        home: const Scaffold(
          body: GlassSurface(
            enableBlur: false,
            blur: 32,
            child: Text('Hidden HUD'),
          ),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        theme: VedroTheme.fromSkin(VedroSkin.immersiveCinema),
        home: const Scaffold(
          body: GlassSurface(
            enableBlur: true,
            blur: 32,
            child: Text('Visible HUD'),
          ),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);

    // 3. Cached DanmakuLayer paints cleanly inside RepaintBoundary without Opacity saveLayer
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 450,
            child: DanmakuLayer(
              comments: [
                DanmakuComment(timeSecs: 1.0, mode: 1, color: Colors.white, text: '流畅弹幕测试'),
                DanmakuComment(timeSecs: 1.5, mode: 5, color: Colors.amber, text: '顶部弹幕测试'),
              ],
              positionSecs: 2.0,
              opacity: 0.85,
              fontSize: 18.0,
              speedSecs: 8.0,
              areaFraction: 0.5,
              hideTop: false,
              hideBottom: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(DanmakuLayer), findsOneWidget);
    expect(
      find.descendant(of: find.byType(DanmakuLayer), matching: find.byType(Opacity)),
      findsNothing,
    );
  });

  testWidgets(
      'v0.3.10: Network speed & player memory prefs, local image cache usage + clear button, and clean settings toggles',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 1. VedroPreferences defaults & JSON round-trip for v0.3.10 features
    const defaults = VedroPreferences();
    expect(defaults.showNetworkSpeed, isTrue);
    expect(defaults.rememberBrightness, isTrue);
    expect(defaults.rememberVolume, isTrue);
    expect(defaults.savedVolume, equals(100.0));
    expect(defaults.rememberSpeed, isTrue);
    expect(defaults.rememberAspect, isTrue);

    final customized = defaults.copyWith(
      showNetworkSpeed: false,
      rememberBrightness: false,
      savedBrightness: 0.65,
      rememberVolume: true,
      savedVolume: 72.0,
      rememberSpeed: false,
      rememberAspect: false,
    );
    final decoded = VedroPreferences.fromJson(customized.toJson());
    expect(decoded.showNetworkSpeed, isFalse);
    expect(decoded.rememberBrightness, isFalse);
    expect(decoded.savedBrightness, closeTo(0.65, 0.001));
    expect(decoded.rememberVolume, isTrue);
    expect(decoded.savedVolume, closeTo(72.0, 0.001));
    expect(decoded.rememberSpeed, isFalse);
    expect(decoded.rememberAspect, isFalse);

    // 2. Settings -> 下载与缓存 shows local image cache size/count and clears cleanly
    final mock = _MockVedroCore();
    final app = VedroAppState(mock);
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

    await tester.tap(find.text('下载与缓存'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-image-cache-card')), findsOneWidget);
    expect(find.textContaining('12 MB'), findsOneWidget);
    expect(find.textContaining('42 张本地图片'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('clear-image-cache-btn')));
    await tester.pumpAndSettle();
    expect(find.textContaining('0 张本地图片'), findsOneWidget);
    expect(find.textContaining('已清理 42 张缓存图片'), findsOneWidget);

    // 3. Settings -> 播放设置 exposes network speed & player memory toggles across all platforms
    await tester.tap(find.text('播放设置'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pref-show-network-speed')), findsOneWidget);
    expect(find.byKey(const ValueKey('pref-remember-brightness')), findsOneWidget);
    expect(find.byKey(const ValueKey('pref-remember-volume')), findsOneWidget);
    expect(find.byKey(const ValueKey('pref-remember-speed')), findsOneWidget);
    expect(find.byKey(const ValueKey('pref-remember-aspect')), findsOneWidget);
  });

  testWidgets(
      'v0.3.11: YouTube-style AI bilingual lookahead subtitles, ASR speech-to-subtitle, low-power GPU beauty filter & in-app update checker',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 1. Preferences round-trip for AI subtitle, ASR, and beauty filter settings
    const basePrefs = VedroPreferences();
    expect(basePrefs.aiSubtitleMode, equals('bilingual_trans_top'));
    expect(basePrefs.aiSubtitleBatchSize, equals(18));
    expect(basePrefs.beautyFilterPreset, equals('off'));
    expect(basePrefs.isAsrReady, isFalse);

    final updated = basePrefs.copyWith(
      aiEnabled: true,
      aiSubtitleMode: 'bilingual_orig_top',
      aiSubtitleFontScale: 1.35,
      aiSubtitleBatchSize: 24,
      asrEnabled: true,
      asrEngine: 'cloud',
      asrBaseUrl: 'https://api.siliconflow.cn/v1',
      asrModel: 'FunAudioLLM/SenseVoiceSmall',
      asrSourceLang: 'ja',
      beautyFilterPreset: 'natural',
      beautyFilterStrength: 0.70,
    );
    final roundTripped = VedroPreferences.fromJson(updated.toJson());
    expect(roundTripped.aiSubtitleMode, equals('bilingual_orig_top'));
    expect(roundTripped.aiSubtitleFontScale, closeTo(1.35, 0.001));
    expect(roundTripped.aiSubtitleBatchSize, equals(24));
    expect(roundTripped.isAsrReady, isTrue);
    expect(roundTripped.asrSourceLang, equals('ja'));
    expect(roundTripped.beautyFilterPreset, equals('natural'));
    expect(roundTripped.beautyFilterStrength, closeTo(0.70, 0.001));

    // 2. AI Bilingual Lookahead Controller prefetches upcoming cues, switches target lang like YouTube, and supports ASR
    final mock = _MockVedroCore();
    final app = VedroAppState(mock);
    app.prefs = updated.copyWith(aiSubtitleMode: 'bilingual_trans_top');
    addTearDown(app.dispose);

    final subCtrl = AiSubtitleTranslatorController(appState: app, mediaTitle: 'Test Cinema');
    addTearDown(subCtrl.dispose);

    await subCtrl.enable(
      subtitleUrl: 'https://example.com/sub.srt',
      currentPositionSecs: 2.0,
      targetLang: '简体中文',
    );
    await tester.pump();
    await tester.pump();
    expect(subCtrl.totalCues, equals(3));
    expect(subCtrl.translatedCount, greaterThanOrEqualTo(2));
    expect(subCtrl.activeCueNotifier.value?.original, equals('Hello world.'));
    expect(subCtrl.activeCueNotifier.value?.translated, equals('[简体中文] Hello world.'));

    // Switching target language in-place re-translates after respectful public-API pacing interval
    await subCtrl.setTargetLang('日本語');
    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pump();
    expect(subCtrl.activeCueNotifier.value?.translated, equals('[日本語] Hello world.'));

    // Render bilingual overlay and verify both translated & original lines appear
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              AiBilingualSubtitleOverlay(
                controller: subCtrl,
                subScale: 1.0,
                subPos: 96,
                colorHex: '#FFFFFF',
                outlineWidth: 2.0,
                bgOpacity: 0.4,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('ai-bilingual-subtitle-box')), findsOneWidget);
    expect(find.text('[日本語] Hello world.'), findsOneWidget);
    expect(find.text('Hello world.'), findsOneWidget);

    // ASR speech-to-subtitle lookahead mode extracts audio slice cues & auto-translates them
    await subCtrl.enableAsr(
      sourceUrl: 'http://127.0.0.1:45678/stream/1',
      currentPositionSecs: 1.0,
      durationSecs: 60.0,
      targetLang: '简体中文',
    );
    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pump();
    expect(mock.asrSliceCalls, greaterThanOrEqualTo(1));
    expect(subCtrl.totalCues, greaterThanOrEqualTo(1));
    expect(subCtrl.activeCueNotifier.value?.original, equals('おはようございます'));
    expect(subCtrl.activeCueNotifier.value?.translated, equals('[简体中文] おはようございます'));

    // 3. 2-Pass Portrait Beauty Camera GPU shader generator (stackable smooth/whiten/rosy/clarity)
    expect(BeautyFilterPreset.all.length, equals(6));
    expect(BeautyFilterEngine.buildGlslSource('off', 0.55), isNull);
    expect(BeautyFilterEngine.buildGlslSourceFromParams(BeautyFilterParams.off), isNull);
    for (final preset in BeautyFilterPreset.all.where((p) => p.id != 'off')) {
      for (final strength in const [0.15, 0.55, 1.0]) {
        final glsl = BeautyFilterEngine.buildGlslSource(preset.id, strength)!;
        expect(glsl, contains('//!HOOK MAIN'));
        expect(glsl, contains('//!SAVE VEDRO_SKIN_H'));
        expect(glsl, contains('//!BIND VEDRO_SKIN_H'));
        expect(glsl, contains('HOOKED_texOff(vec2(0.0, 0.0))'));
        expect(glsl, isNot(contains('HOOKED_texOff(0)')));
        expect(glsl, isNot(contains('--')), reason: '${preset.id} must never emit -- operator');
        expect(glsl, contains('vedro_skin_mask'));
        expect(glsl, contains('skinMask'));
      }
    }
    // Stackable custom portrait combination + mobile lean 7-tap shader
    const customStack = BeautyFilterParams(smooth: 0.70, whiten: 0.65, rosy: 0.45, clarity: 0.50);
    final desktopShader = BeautyFilterEngine.buildGlslSourceFromParams(customStack, mobileLean: false)!;
    final mobileShader = BeautyFilterEngine.buildGlslSourceFromParams(customStack, mobileLean: true)!;
    expect(desktopShader, contains('4.0 * stepX'));
    expect(mobileShader, isNot(contains('4.0 * stepX')));
    expect(mobileShader, contains('3.0 * stepX'));
    expect(customStack.summaryLabel(), contains('磨皮 70%'));
    expect(customStack.summaryLabel(), contains('美白 65%'));
    expect(customStack.summaryLabel(), contains('粉嫩 45%'));
    expect(customStack.summaryLabel(), contains('亮眼 50%'));
    final prefWithStack = VedroPreferences.fromJson(
      const VedroPreferences(
        beautyFilterPreset: 'custom',
        beautySmooth: 0.70,
        beautyWhiten: 0.65,
        beautyRosy: 0.45,
        beautyClarity: 0.50,
      ).toJson(),
    );
    expect(prefWithStack.beautySmooth, closeTo(0.70, 0.001));
    expect(prefWithStack.beautyWhiten, closeTo(0.65, 0.001));
    expect(prefWithStack.beautyRosy, closeTo(0.45, 0.001));
    expect(prefWithStack.beautyClarity, closeTo(0.50, 0.001));
    expect(BeautyFilterEngine.thermalNotice, contains('发热'));

    // 4. In-App Update Checker: semver comparison, per-platform asset selection, and update dialog
    expect(compareSemver('v0.3.11', '0.3.10+25'), greaterThan(0));
    expect(compareSemver('0.3.10', 'v0.3.10'), equals(0));
    expect(compareSemver('0.3.9', '0.3.10'), lessThan(0));

    final mockRelease = VedroReleaseInfo.fromGitHubJson({
      'tag_name': 'v0.3.12',
      'name': 'v0.3.12',
      'body': '- AI 双语字幕与语音识别\n- 低功耗美颜滤镜',
      'html_url': 'https://github.com/JHruan1/vedro/releases/tag/v0.3.12',
      'assets': [
        {
          'name': 'vedro-v0.3.12-windows-x64-setup.exe',
          'browser_download_url':
              'https://github.com/JHruan1/vedro/releases/download/v0.3.12/vedro-v0.3.12-windows-x64-setup.exe',
          'size': 28000000,
        },
        {
          'name': 'vedro-v0.3.12-macos-universal.dmg',
          'browser_download_url':
              'https://github.com/JHruan1/vedro/releases/download/v0.3.12/vedro-v0.3.12-macos-universal.dmg',
          'size': 50000000,
        },
        {
          'name': 'vedro-v0.3.12-android-arm64-v8a.apk',
          'browser_download_url':
              'https://github.com/JHruan1/vedro/releases/download/v0.3.12/vedro-v0.3.12-android-arm64-v8a.apk',
          'size': 40000000,
        },
        {
          'name': 'vedro-v0.3.12-ios-unsigned.ipa',
          'browser_download_url':
              'https://github.com/JHruan1/vedro/releases/download/v0.3.12/vedro-v0.3.12-ios-unsigned.ipa',
          'size': 16000000,
        },
      ],
    });
    expect(mockRelease.bestAssetForPlatform(osOverride: 'windows')?.name, endsWith('-setup.exe'));
    expect(mockRelease.bestAssetForPlatform(osOverride: 'macos')?.name, endsWith('.dmg'));
    expect(mockRelease.bestAssetForPlatform(osOverride: 'android')?.name, contains('arm64-v8a'));
    expect(mockRelease.bestAssetForPlatform(osOverride: 'ios')?.name, endsWith('.ipa'));

    final checker = VedroUpdateChecker(
      fetcher: (_) async => {
        'tag_name': 'v0.3.12',
        'name': 'v0.3.12',
        'body': '新版本包含双语字幕和美颜滤镜。',
        'html_url': 'https://github.com/JHruan1/vedro/releases/tag/v0.3.12',
        'assets': [
          {
            'name': 'vedro-v0.3.12-windows-x64-setup.exe',
            'browser_download_url':
                'https://github.com/JHruan1/vedro/releases/download/v0.3.12/vedro-v0.3.12-windows-x64-setup.exe',
            'size': 28000000,
          },
        ],
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: VedroTheme.fromSkin(app.prefs.activeSkin),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              key: const ValueKey('trigger-update-check'),
              onPressed: () => checker.checkAndPrompt(ctx, currentVersion: '0.3.11'),
              child: const Text('检查更新'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('trigger-update-check')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vedro-update-dialog')), findsOneWidget);
    expect(find.text('发现新版本 v0.3.12'), findsOneWidget);
    expect(find.byKey(const ValueKey('vedro-update-download-btn')), findsOneWidget);

    // 5. SettingsScreen -> AI 翻译 exposes bilingual subtitle & ASR cards, plus Check Update button
    app.activeSettingsSection = 'ai';
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
    expect(find.byKey(const ValueKey('settings-check-update-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-asr-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('asr-preset-groq')), findsOneWidget);
    expect(find.byKey(const ValueKey('asr-preset-siliconflow')), findsOneWidget);
  });

  testWidgets(
      'v0.3.12: Built-in local offline ASR (sherpa-onnx SenseVoice-Small INT8 + Silero VAD) panel, WAV PCM decoder & energy VAD splitter',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 1. Default ASR engine is built-in local offline model with China mirror acceleration
    const defaults = VedroPreferences();
    expect(defaults.asrEngine, equals('local'));
    expect(defaults.asrUseChinaMirror, isTrue);
    expect(
      LocalAsrModelSpec.modelUrls(preferChinaMirror: true).first,
      contains('hf-mirror.com'),
    );
    expect(
      LocalAsrModelSpec.modelUrls(preferChinaMirror: false).first,
      contains('huggingface.co'),
    );

    // 2. WAV PCM16 decoder, RMS energy VAD splitter & SenseVoice tag cleaner
    final wav = Uint8List(44 + 16000 * 2);
    wav.setRange(0, 4, 'RIFF'.codeUnits);
    wav.setRange(8, 12, 'WAVE'.codeUnits);
    wav.setRange(36, 40, 'data'.codeUnits);
    final bd = ByteData.sublistView(wav);
    bd.setUint32(40, 16000 * 2, Endian.little);
    // Write 0.5s of strong voiced signal in the middle (samples 4000..12000)
    for (var i = 4000; i < 12000; i++) {
      bd.setInt16(44 + i * 2, (i.isEven ? 12000 : -12000), Endian.little);
    }
    final pcm = decodePcm16WavToFloat32(wav);
    expect(pcm.length, equals(16000));
    final segments = splitSpeechByEnergy(pcm);
    expect(segments.length, equals(1));
    expect(segments.first.startSample, inInclusiveRange(3500, 4500));
    expect(
      cleanSenseVoiceText('<|ja|><|NEUTRAL|><|Speech|><|woitn|>おはようございます！'),
      equals('おはようございます！'),
    );

    // 3. Settings -> AI 翻译 defaults to built-in local offline model panel with download button
    final app = VedroAppState(_MockVedroCore());
    app.activeSettingsSection = 'ai';
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
    expect(find.byKey(const ValueKey('settings-local-asr-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('download-local-asr-btn')), findsOneWidget);

    // 4. Settings -> 视频设置 also directly surfaces Beauty Filter card with thermal reminder
    await tester.tap(find.text('视频设置'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-beauty-filter-card')), findsOneWidget);
    expect(find.text('综合美颜'), findsOneWidget);
    expect(find.text('清透美白'), findsOneWidget);
    expect(find.text('粉嫩元气'), findsOneWidget);
    expect(find.text('磨皮（肤质保边）'), findsOneWidget);
    expect(find.text('美白（仅提亮肤色）'), findsOneWidget);
    expect(find.text('粉嫩（气色与润唇）'), findsOneWidget);
    expect(find.text('亮眼清晰（五官立体）'), findsOneWidget);
  });

  testWidgets(
      'v0.4.0: TV D-Pad focus activation, ASR anti-flash circuit breaker, Bilibili public-API rate limit policy & security validators',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 1. Security URL validators
    expect(
      isTrustedReleaseUrl('https://github.com/JHruan1/vedro/releases/download/v0.4.0/app.apk'),
      isTrue,
    );
    expect(
      isTrustedReleaseUrl('https://objects.githubusercontent.com/github-production-release-asset/1'),
      isTrue,
    );
    expect(isTrustedReleaseUrl('http://github.com/JHruan1/vedro'), isFalse);
    expect(isTrustedReleaseUrl('https://evil.example.com/vedro.apk'), isFalse);
    expect(NativePlaybackChannel.isAllowedHttpUrl('https://stream.example.com/a.m3u8'), isTrue);
    expect(NativePlaybackChannel.isAllowedHttpUrl('http://192.168.1.10:8096/v.mkv'), isTrue);
    expect(NativePlaybackChannel.isAllowedHttpUrl('file:///etc/passwd'), isFalse);
    expect(NativePlaybackChannel.isAllowedHttpUrl('javascript:alert(1)'), isFalse);

    // 2. Respectful Bilibili public API rate limit policy vs custom OpenAI endpoint
    expect(
      AiSubtitleTranslatorController.isBilibiliPublicEndpoint('https://index-translate.bilibili.com/v1'),
      isTrue,
    );
    final biliPolicy = AiSubtitleTranslatorController.rateLimitPolicyFor(
      'https://index-translate.bilibili.com/v1',
    );
    expect(biliPolicy.isPublicSharedApi, isTrue);
    expect(biliPolicy.maxConcurrency, equals(1));
    expect(biliPolicy.minIntervalMs, greaterThanOrEqualTo(2400));
    expect(biliPolicy.maxLookaheadSecs, lessThanOrEqualTo(55));
    expect(biliPolicy.maxBatchSize, lessThanOrEqualTo(24));

    final customPolicy = AiSubtitleTranslatorController.rateLimitPolicyFor(
      'https://api.deepseek.com/v1',
    );
    expect(customPolicy.isPublicSharedApi, isFalse);
    expect(customPolicy.maxConcurrency, greaterThanOrEqualTo(2));

    // 3. TV D-Pad focus activation on PressableScale & Left/Right stepping on VedroPrecisionSlider
    var tapped = 0;
    var sliderVal = 1.0;
    final btnFocus = FocusNode();
    addTearDown(btnFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: VedroTheme.fromSkin(VedroSkin.obsidian),
        home: Scaffold(
          body: Column(
            children: [
              PressableScale(
                focusNode: btnFocus,
                autofocus: true,
                onTap: () => tapped += 1,
                child: const SizedBox(width: 120, height: 44, child: Text('TV 按钮')),
              ),
              StatefulBuilder(
                builder: (ctx, setLocal) => VedroPrecisionSlider(
                  label: '音量',
                  value: sliderVal,
                  min: 0.0,
                  max: 2.0,
                  step: 0.25,
                  valueText: sliderVal.toStringAsFixed(2),
                  onChanged: (v) => setLocal(() => sliderVal = v),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tapped, equals(1));

    // Move focus to slider track and step right via D-Pad arrowRight
    final sliderTrackFinder = find.descendant(
      of: find.byType(VedroPrecisionSlider),
      matching: find.byType(LayoutBuilder),
    );
    expect(sliderTrackFinder, findsWidgets);
    Focus.of(tester.element(sliderTrackFinder.first)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(sliderVal, greaterThan(1.0));

    // 4. ASR anti-flashing retry cap & circuit breaker
    final failingCore = _MockVedroCore()..failAsrSlices = true;
    final app = VedroAppState(failingCore);
    app.prefs = app.prefs.copyWith(
      asrEngine: 'cloud',
      asrEnabled: true,
      asrBaseUrl: 'https://api.groq.com/openai/v1',
      asrApiKey: 'gsk_test',
      asrModel: 'whisper-large-v3-turbo',
    );
    addTearDown(app.dispose);

    final ctrl = AiSubtitleTranslatorController(appState: app, mediaTitle: 'Test Video');
    addTearDown(ctrl.dispose);

    await ctrl.enableAsr(
      sourceUrl: 'http://127.0.0.1:28080/stream.mkv',
      currentPositionSecs: 0.0,
    );
    // Repeated position updates while ASR keeps failing must never loop endlessly or show "0 句"
    for (var t = 0; t < 5; t++) {
      ctrl.updatePosition(t * 1.0);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(failingCore.asrSliceCalls, lessThanOrEqualTo(4));
    expect(ctrl.activeCueNotifier.value?.statusHint ?? '', isNot(contains('已识别 0 句')));

    // 5. AppLockGate lockout after 5 wrong PIN attempts
    final lockPrefs = const VedroPreferences().copyWith(
      passcodeEnabled: true,
      passcodeHash: hashPasscode('1234'),
    );
    final lockApp = VedroAppState(_MockVedroCore())
      ..isInitialized = true
      ..prefs = lockPrefs;
    addTearDown(lockApp.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: VedroTheme.fromSkin(VedroSkin.obsidian),
        home: AppLockGate(
          appState: lockApp,
          child: const Text('UNLOCKED_HOME'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('UNLOCKED_HOME'), findsNothing);
    for (var attempt = 0; attempt < 5; attempt++) {
      for (final d in ['9', '9', '9', '9']) {
        await tester.tap(find.text(d));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('尝试次数过多'), findsOneWidget);
  });

  testWidgets(
      'v1.0.0: Salted PIN hashing, PinLockoutController, trusted release URLs, SemVer 2.0, VedroSkin equality, slider boundary D-Pad release, 0% subtitle bg & config backup',
      (tester) async {
    // 1. VedroSkin value equality & hashCode (critical for ThemeData caching)
    final skinA = const VedroPreferences(skinId: 'immersive_cinema', accentId: 'blue').activeSkin;
    final skinB = const VedroPreferences(skinId: 'immersive_cinema', accentId: 'blue').activeSkin;
    final skinC = const VedroPreferences(skinId: 'immersive_cinema', accentId: 'emerald').activeSkin;
    final skinLight = const VedroPreferences(skinId: 'immersive_cinema', themeMode: 'light').activeSkin;
    expect(skinA, equals(skinB));
    expect(skinA.hashCode, equals(skinB.hashCode));
    expect(skinA, isNot(equals(skinC)));
    expect(skinA, isNot(equals(skinLight)));

    // 2. Salted v2 PIN hashing + legacy v1 compatibility + PinLockoutController
    final salted1 = createSaltedPasscodeHash('2468');
    final salted2 = createSaltedPasscodeHash('2468');
    expect(salted1, startsWith('vedro.lock.v2:'));
    expect(salted2, startsWith('vedro.lock.v2:'));
    expect(salted1, isNot(equals(salted2)));
    expect(verifyPasscode('2468', salted1), isTrue);
    expect(verifyPasscode('2468', salted2), isTrue);
    expect(verifyPasscode('0000', salted1), isFalse);
    // Legacy v1 hashes still verify seamlessly
    final legacyHash = hashPasscode('1234');
    expect(verifyPasscode('1234', legacyHash), isTrue);
    expect(verifyPasscode('4321', legacyHash), isFalse);

    final pinApp = VedroAppState(_MockVedroCore());
    addTearDown(pinApp.dispose);
    final lockout = PinLockoutController.forState(pinApp);
    for (var i = 0; i < 4; i++) {
      final res = lockout.verify('9999', salted1);
      expect(res.ok, isFalse);
      expect(res.lockoutSecs, equals(0));
    }
    final fifth = lockout.verify('9999', salted1);
    expect(fifth.ok, isFalse);
    expect(fifth.lockoutSecs, greaterThan(0));
    expect(lockout.remainingLockoutSecs, greaterThan(0));
    // Even correct PIN is rejected while locked out
    expect(lockout.verify('2468', salted1).ok, isFalse);
    lockout.reset();
    expect(lockout.remainingLockoutSecs, equals(0));
    expect(lockout.verify('2468', salted1).ok, isTrue);

    // 3. Trusted release URL validation & SemVer 2.0 prerelease comparison
    expect(
      isTrustedReleaseUrl('https://github.com/JHruan1/vedro/releases/tag/v1.0.0'),
      isTrue,
    );
    expect(
      isTrustedReleaseUrl(
          'https://github.com/JHruan1/vedro/releases/download/v1.0.0/Vedro-1.0.0-arm64-v8a.apk'),
      isTrue,
    );
    expect(
      isTrustedReleaseUrl('https://objects.githubusercontent.com/github-production-release-asset/foo'),
      isTrue,
    );
    expect(isTrustedReleaseUrl('http://github.com/JHruan1/vedro/releases/tag/v1.0.0'), isFalse);
    expect(isTrustedReleaseUrl('https://github.com/evil/vedro/releases/tag/v1.0.0'), isFalse);
    expect(
      isTrustedReleaseUrl('https://user:pass@github.com/JHruan1/vedro/releases/tag/v1.0.0'),
      isFalse,
    );
    expect(
      isTrustedReleaseUrl('https://github.com:8443/JHruan1/vedro/releases/tag/v1.0.0'),
      isFalse,
    );
    expect(isTrustedReleaseUrl('javascript:alert(1)'), isFalse);

    expect(compareSemver('1.0.0', '1.0.0-rc.1'), greaterThan(0));
    expect(compareSemver('1.0.0-rc.1', '1.0.0'), lessThan(0));
    expect(compareSemver('1.0.0-beta.10', '1.0.0-beta.2'), greaterThan(0));
    expect(compareSemver('1.0.0-alpha.1', '1.0.0-alpha.beta'), lessThan(0));
    expect(compareSemver('v1.0.0+30', '1.0.0'), equals(0));

    // 4. Media stream URL validator
    expect(NativePlaybackChannel.isAllowedMediaUrl('https://cdn.example.com/movie.mkv'), isTrue);
    expect(NativePlaybackChannel.isAllowedMediaUrl('rtsp://192.168.1.5:554/live'), isTrue);
    expect(NativePlaybackChannel.isAllowedMediaUrl('rtmp://live.example.com/app/stream'), isTrue);
    expect(NativePlaybackChannel.isAllowedMediaUrl('file:///etc/passwd'), isFalse);
    expect(NativePlaybackChannel.isAllowedMediaUrl('javascript:alert(1)'), isFalse);
    expect(NativePlaybackChannel.isAllowedMediaUrl('smb://nas/video.mkv'), isFalse);
    expect(NativePlaybackChannel.isAllowedMediaUrl('https://example.com/bad url'), isFalse);

    // 5. VedroErrorFormatter Chinese humanization
    expect(VedroErrorFormatter.friendly('HTTP 401 Unauthorized'), contains('用户名或密码'));
    expect(VedroErrorFormatter.format('HTTP 403 Forbidden'), contains('403'));
    expect(VedroErrorFormatter.format('HTTP 404 Not Found'), contains('404'));
    expect(VedroErrorFormatter.format('HTTP 429 Too Many Requests'), contains('429'));
    expect(VedroErrorFormatter.format('TLS certificate unknownIssuer'), contains('证书'));
    expect(VedroErrorFormatter.format('failed to lookup address: nodename'), contains('域名解析'));
    expect(VedroErrorFormatter.format('Connection refused (os error 111)'), contains('连接被拒绝'));
    expect(VedroErrorFormatter.format('request timed out'), contains('超时'));
    expect(VedroErrorFormatter.format('<!DOCTYPE html><html>502</html>'), contains('非预期页面'));

    // 6. History URL sanitization & Config backup/import/reset security invariants
    final sanitized = VedroAppState.sanitizeUrlForHistory(
      'https://user:secret@media.example.com/stream.m3u8?api_key=abc&token=xyz&quality=4k',
    );
    expect(sanitized, isNot(contains('api_key')));
    expect(sanitized, isNot(contains('token')));
    expect(sanitized, isNot(contains('secret')));
    expect(sanitized, contains('quality=4k'));

    final cfgApp = VedroAppState(_MockVedroCore());
    addTearDown(cfgApp.dispose);
    await cfgApp.updatePrefs(
      const VedroPreferences().copyWith(
        skinId: 'liquid_glass',
        passcodeEnabled: true,
        passcodeHash: salted1,
        aiApiKey: 'sk-secret-ai-key',
        asrApiKey: 'sk-secret-asr-key',
        maxVolumePercent: 300,
      ),
      immediate: true,
    );
    // Max volume boost is strictly capped at 150% (never 300%)
    expect(cfgApp.prefs.maxVolumePercent, equals(150));
    expect(
      VedroPreferences.fromJson(const {'max_volume_percent': 300, 'saved_volume': 280.0})
          .maxVolumePercent,
      equals(150),
    );
    expect(
      VedroPreferences.fromJson(const {'max_volume_percent': 300, 'saved_volume': 280.0})
          .savedVolume,
      equals(150.0),
    );

    // Android SAF content:// URI local playlist support
    final safResolved = NativePlaybackChannel.resolveLocalPlaylist(
      'content://com.android.providers.downloads.documents/document/raw%3A%2Fmovie.mkv',
    );
    expect(safResolved.files.length, equals(1));
    expect(safResolved.startIndex, equals(0));

    final exportedStr = cfgApp.exportConfigJson();
    final exportedMap = jsonDecode(exportedStr) as Map<String, dynamic>;
    final exportedPrefs = exportedMap['preferences'] as Map<String, dynamic>;
    expect(exportedPrefs.containsKey('passcode_hash'), isFalse);
    expect(exportedPrefs.containsKey('passcode_enabled'), isFalse);
    expect(exportedPrefs.containsKey('ai_api_key'), isFalse);
    expect(exportedPrefs.containsKey('asr_api_key'), isFalse);
    expect(exportedPrefs['max_volume_percent'], equals(150));

    // Resetting defaults preserves passcode lock
    await cfgApp.resetPreferencesToDefaults();
    expect(cfgApp.prefs.skinId, equals('immersive_cinema'));
    expect(cfgApp.prefs.passcodeEnabled, isTrue);
    expect(cfgApp.prefs.passcodeHash, equals(salted1));

    // Importing backup restores non-secret prefs while keeping local passcode & keys intact
    await cfgApp.updatePrefs(
      cfgApp.prefs.copyWith(aiApiKey: 'sk-local-keep'),
      immediate: true,
    );
    await cfgApp.importConfigJson(exportedStr);
    expect(cfgApp.prefs.skinId, equals('liquid_glass'));
    expect(cfgApp.prefs.maxVolumePercent, equals(150));
    expect(cfgApp.prefs.passcodeHash, equals(salted1));
    expect(cfgApp.prefs.aiApiKey, equals('sk-local-keep'));

    // 7. AiBilingualSubtitleOverlay honors 0% bgOpacity (no dark pill) & live displayMode switch
    AiSubtitleTranslatorController.resetGlobalRateLimitState();
    final subApp = VedroAppState(_MockVedroCore());
    addTearDown(subApp.dispose);
    final subCtrl = AiSubtitleTranslatorController(appState: subApp, mediaTitle: 'ZeroBg');
    addTearDown(subCtrl.dispose);
    subCtrl.activeCueNotifier.value = const BilingualCueSnapshot(
      original: 'Original Line',
      translated: '译文行',
      displayMode: 'translated_only',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              AiBilingualSubtitleOverlay(
                controller: subCtrl,
                subScale: 1.0,
                subPos: 96,
                colorHex: '#FFFFFF',
                outlineWidth: 2.0,
                bgOpacity: 0.0,
                fontFamily: 'Noto Sans CJK SC',
              ),
            ],
          ),
        ),
      ),
    );
    final subBox = tester.widget<Container>(find.byKey(const ValueKey('ai-bilingual-subtitle-box')));
    expect(subBox.decoration, isNull);
    expect(find.text('译文行'), findsOneWidget);
    expect(find.text('Original Line'), findsNothing);

    // 8. VedroPrecisionSlider releases D-Pad Left at min so TV focus escapes cleanly to left sidebar
    final leftBtnFocus = FocusNode();
    addTearDown(leftBtnFocus.dispose);
    var sliderVal = 0.0;
    await tester.pumpWidget(
      MaterialApp(
        theme: VedroTheme.fromSkin(VedroSkin.obsidian),
        home: Scaffold(
          body: Row(
            children: [
              PressableScale(
                focusNode: leftBtnFocus,
                onTap: () {},
                child: const SizedBox(width: 100, height: 48, child: Text('左侧栏')),
              ),
              Expanded(
                child: StatefulBuilder(
                  builder: (_, setLocal) => VedroPrecisionSlider(
                    label: '亮度',
                    value: sliderVal,
                    min: 0.0,
                    max: 1.0,
                    step: 0.25,
                    valueText: '${(sliderVal * 100).round()}%',
                    onChanged: (v) => setLocal(() => sliderVal = v),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final trackFinder = find.descendant(
      of: find.byType(VedroPrecisionSlider),
      matching: find.byType(LayoutBuilder),
    );
    Focus.of(tester.element(trackFinder.first)).requestFocus();
    await tester.pump();
    // At min (0.0), arrowLeft is ignored by the slider and focus escapes to the left sidebar button!
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(leftBtnFocus.hasFocus, isTrue);
  });

  testWidgets(
      'v1.0.2 Regression: URL Sanitizer, Image Path Segments, ABI Auto-Updater, Mobile Cache Card & Zero-Crash Subtitle Stack',
      (tester) async {
    // 1. sanitizeUrlForHistory strips user:pass@ AND single-param ?api_key=SECRET cleanly
    expect(
      VedroAppState.sanitizeUrlForHistory('https://alice:topsecret@emby.example.com/v/1.mkv'),
      equals('https://emby.example.com/v/1.mkv'),
    );
    expect(
      VedroAppState.sanitizeUrlForHistory('https://emby.example.com/v/1.mkv?api_key=SECRET123'),
      equals('https://emby.example.com/v/1.mkv'),
    );
    expect(
      VedroAppState.sanitizeUrlForHistory(
          'https://user:pw@emby.example.com/v/1.mkv?Static=true&StreamTicket=tk999&token=abc'),
      equals('https://emby.example.com/v/1.mkv?Static=true'),
    );

    // 2. buildImageUrl keeps multi-segment image type (Backdrop/0) intact without %2F mangling
    final mock = _MockVedroCore();
    final app = VedroAppState(mock);
    addTearDown(app.dispose);
    app.connectedUrl = 'https://emby.example.com';
    app.proxyAddr = '127.0.0.1:45678';
    final bdUrl = app.buildImageUrl('item-42', type: 'Backdrop/0', tag: 't1', maxWidth: 1280);
    expect(bdUrl, contains('/img/Items/item-42/Images/Backdrop/0?'));
    expect(bdUrl, isNot(contains('%2F')));

    // 3. Auto-updater parses Rust check_app_update JSON with SHA-256 & matches exact Android ABI
    final rel = VedroReleaseInfo.fromGitHubJson({
      'tag_name': 'v1.0.2',
      'version': '1.0.2',
      'html_url': 'https://github.com/JHruan1/vedro/releases/tag/v1.0.2',
      'body': 'v1.0.2 fixes',
      'assets': [
        {
          'name': 'vedro-v1.0.2-android-arm64-v8a.apk',
          'url': 'https://github.com/JHruan1/vedro/releases/download/v1.0.2/vedro-v1.0.2-android-arm64-v8a.apk',
          'size': 28000000,
          'sha256': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        },
        {
          'name': 'vedro-v1.0.2-android-armeabi-v7a.apk',
          'url': 'https://github.com/JHruan1/vedro/releases/download/v1.0.2/vedro-v1.0.2-android-armeabi-v7a.apk',
          'size': 26000000,
          'sha256': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        },
        {
          'name': 'vedro-v1.0.2-windows-x64-setup.exe',
          'url': 'https://github.com/JHruan1/vedro/releases/download/v1.0.2/vedro-v1.0.2-windows-x64-setup.exe',
          'size': 32000000,
          'sha256': 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        },
      ],
    });
    final v7Asset = rel.bestAssetForPlatform(osOverride: 'android', abiOverride: 'armeabi-v7a');
    expect(v7Asset?.name, equals('vedro-v1.0.2-android-armeabi-v7a.apk'));
    expect(v7Asset?.sha256, equals('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'));
    final winAsset = rel.bestAssetForPlatform(osOverride: 'windows');
    expect(winAsset?.name, equals('vedro-v1.0.2-windows-x64-setup.exe'));

    // 4. autoCheckUpdates preference defaults to true and roundtrips false cleanly
    const defPrefs = VedroPreferences();
    expect(defPrefs.autoCheckUpdates, isTrue);
    final toggled = VedroPreferences.fromJson(defPrefs.copyWith(autoCheckUpdates: false).toJson());
    expect(toggled.autoCheckUpdates, isFalse);

    // 5. AiBilingualSubtitleOverlay mounts inside Stack cleanly (RepaintBoundary is INSIDE Positioned.fill)
    final subCtrl = AiSubtitleTranslatorController(appState: app, mediaTitle: 'StackSafe');
    addTearDown(subCtrl.dispose);
    subCtrl.activeCueNotifier.value = const BilingualCueSnapshot(
      original: 'Hello',
      translated: '你好',
      displayMode: 'bilingual_trans_top',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              const SizedBox.expand(),
              AiBilingualSubtitleOverlay(
                controller: subCtrl,
                subScale: 1.0,
                subPos: 96,
                colorHex: '#FFFFFF',
                outlineWidth: 2.0,
                bgOpacity: 0.4,
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('你好'), findsOneWidget);

    // 6. SettingsScreen -> 下载与缓存 renders on 360px portrait phone with ZERO RenderFlex overflow!
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: VedroTheme.fromSkin(app.prefs.activeSkinFor(isMobile: true)),
        home: SettingsScreen(
          appState: app,
          onOpenAddServer: ([_]) {},
          onOpenServerHub: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('下载与缓存'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('下载与缓存').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-image-cache-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Instant 0ms server-switch transition stage & iOS Peek & Pop contextual menu on MediaCard long-press',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final restoreGate = Completer<void>();
    final mock = _DelayedRestoreMockCore(restoreGate);
    final app = VedroAppState(mock)
      ..activeServerId = 'srv-a'
      ..connectedUrl = 'https://a.example.com'
      ..userId = 'u1'
      ..username = 'Alice'
      ..views = [MediaItemModel(id: 'v1', name: '电影', type: 'CollectionFolder')]
      ..popular = [
        MediaItemModel(id: 'm-old', name: '旧服务器电影', type: 'Movie', productionYear: 2024),
      ]
      ..savedServers = [
        SavedServerProfile(
          id: 'srv-a',
          name: '主服 A',
          url: 'https://a.example.com',
          dialect: 'embygo',
          accessToken: 'tok-a',
          userId: 'u1',
        ),
        SavedServerProfile(
          id: 'srv-b',
          name: '备用服 B',
          url: 'https://b.example.com',
          dialect: 'embygo',
          accessToken: 'tok-b',
          userId: 'u2',
        ),
      ];
    addTearDown(app.dispose);

    await tester.pumpWidget(
      AnimatedBuilder(
        animation: app,
        builder: (_, __) => MaterialApp(
          theme: VedroTheme.fromSkin(app.prefs.activeSkin),
          home: Scaffold(
            body: HomeScreen(
              appState: app,
              onItemTap: (item, {heroPrefix}) {},
              onQuickPlay: (_) {},
              onLibraryTap: (_) {},
              onOpenServerHub: () {},
              onOpenAddServer: ([_]) {},
              onOpenSettings: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Triggering server switch sets switchingToServerName & clears stale Home at t=0ms
    final switchFuture = app.restoreSavedServer(app.savedServers[1]);
    expect(app.switchingToServerName, '备用服 B');
    expect(app.activeServerId, 'srv-b');
    expect(app.hasAnyHomeContent, isFalse);
    expect(app.isLoadingHome, isTrue);

    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('home-server-switching-stage')), findsOneWidget);
    expect(find.text('正在切换至「备用服 B」'), findsOneWidget);

    // Release slow server network response -> switching stage smoothly transitions out
    restoreGate.complete();
    await switchFuture;
    await tester.pumpAndSettle();
    expect(app.switchingToServerName, isNull);
    expect(find.byKey(const ValueKey('home-server-switching-stage')), findsNothing);

    // 2. Long-pressing a MediaCard lifts it and pops the anchored iOS Peek & Pop menu
    var openedDetail = false;
    final sampleEp = MediaItemModel(
      id: 'ep-1',
      name: '权力的游戏 S01E01',
      type: 'Episode',
      indexNumber: 1,
      productionYear: 2011,
      communityRating: 9.2,
      mediaSourceCount: 2,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: VedroTheme.fromSkin(app.prefs.activeSkin),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: MediaCard(
                item: sampleEp,
                appState: app,
                width: 180,
                landscape: true,
                onTap: () {},
                onLongPressWithRect: (rect) => showMediaItemContextSheet(
                  context: ctx,
                  item: sampleEp,
                  appState: app,
                  anchorRect: rect,
                  landscapePreview: true,
                  onOpenDetail: () => openedDetail = true,
                  onQuickPlay: () {},
                  onPickVersion: () {},
                  versionCount: 2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(MediaCard));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vedro-peek-context-menu')), findsOneWidget);
    expect(find.text('切换版本'), findsOneWidget);
    expect(find.text('查看详情'), findsOneWidget);

    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    expect(openedDetail, isTrue);
    expect(find.byKey(const ValueKey('vedro-peek-context-menu')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _DelayedRestoreMockCore extends _MockVedroCore {
  _DelayedRestoreMockCore(this.gate);
  final Completer<void> gate;

  @override
  Future<dynamic> invoke(String method, [Map<String, dynamic> params = const {}]) async {
    if (method == 'restore_session') {
      await gate.future;
    }
    return super.invoke(method, params);
  }
}
