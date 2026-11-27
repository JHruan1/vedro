import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vedro/core/ffi/vedro_bridge.dart';
import 'package:vedro/core/models/models.dart';
import 'package:vedro/core/models/preferences.dart';
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
import 'package:vedro/widgets/app_lock_gate.dart';
import 'package:vedro/widgets/danmaku_engine.dart';
import 'package:vedro/widgets/media_card.dart';
import 'package:vedro/widgets/server_card_grid.dart';
import 'package:vedro/widgets/skin_studio_pane.dart';
import 'package:vedro/widgets/vedro_ui.dart';

class _MockVedroCore implements VedroCoreClient {
  _MockVedroCore({
    this.isAdmin = false,
    this.dialect = 'embygo',
    this.canDownload = true,
    this.enableContentDownloading = false,
    this.meQuotaJson,
    this.savedServersList = const [],
    this.lastActiveServerId,
  });
  final bool isAdmin;
  final String dialect;
  final bool canDownload;
  final bool enableContentDownloading;
  final Map<String, dynamic>? meQuotaJson;
  final List<Map<String, dynamic>> savedServersList;
  String? lastActiveServerId;
  int probeMediaSourceCalls = 0;
  Map<String, dynamic>? lastAiTranslateParams;
  Map<String, dynamic>? lastAiModelsParams;
  Map<String, dynamic>? lastProxyConfigParams;
  Map<String, dynamic>? lastActivatedNode;
  Map<String, dynamic>? lastRestoreParams;
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
        return <String, dynamic>{'version': '0.3.7-test'};
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
      case 'in_app_proxy_status':
        return <String, dynamic>{
          'active': lastProxyConfigParams != null && lastProxyConfigParams!['mode'] != 'off',
          'mode': lastProxyConfigParams?['mode'] ?? 'off',
          'proxy_url': lastProxyConfigParams?['proxy_url'],
          'managed_core': false,
        };
      case 'configure_in_app_proxy':
        lastProxyConfigParams = Map<String, dynamic>.from(params);
        return <String, dynamic>{
          'ok': true,
          'active': params['mode'] != 'off',
          'mode': params['mode'] ?? 'off',
          'proxy_url': params['proxy_url'],
          'managed_core': params['mode'] == 'singbox' || params['mode'] == 'mihomo',
        };
      case 'test_in_app_proxy':
        return <String, dynamic>{
          'ok': true,
          'status': 204,
          'latency_ms': 42,
          'proxy_url': lastProxyConfigParams?['proxy_url'] ?? 'socks5h://127.0.0.1:1080',
        };
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
      case 'fetch_proxy_subscription':
        final reqUrl = (params['url'] ?? '').toString();
        if (reqUrl.contains('sub2.example.com')) {
          return <String, dynamic>{
            'count': 2,
            'userinfo': <String, dynamic>{
              'used': 5368709120,
              'total': 53687091200,
            },
            'nodes': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'node_jp_01',
                'name': '🇯🇵 东京专线 01',
                'protocol': 'vless',
                'server': 'jp1.sub2.example.com',
                'port': 443,
                'native_supported': true,
              },
              <String, dynamic>{
                'id': 'node_tw_02',
                'name': '🇹🇼 台北 Hinet 02',
                'protocol': 'trojan',
                'server': 'tw2.sub2.example.com',
                'port': 443,
                'native_supported': true,
              },
            ],
          };
        }
        return <String, dynamic>{
          'count': 3,
          'userinfo': <String, dynamic>{
            'used': 10737418240,
            'total': 107374182400,
          },
          'nodes': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'node_us_slow',
              'name': '🇺🇸 洛杉矶 BGP 03',
              'protocol': 'trojan',
              'server': 'us3.example.com',
              'port': 443,
              'native_supported': true,
            },
            <String, dynamic>{
              'id': 'node_sg_02',
              'name': '🇸🇬 新加坡网关',
              'protocol': 'socks5',
              'server': '127.0.0.1',
              'port': 7890,
              'direct_proxy_url': 'socks5h://127.0.0.1:7890',
              'native_supported': true,
            },
            <String, dynamic>{
              'id': 'node_hk_01',
              'name': '🇭🇰 香港 IEPL 01',
              'protocol': 'vless',
              'server': 'hk1.example.com',
              'port': 443,
              'native_supported': true,
            },
          ],
        };
      case 'ping_proxy_nodes':
        return <String, dynamic>{
          'latencies': <String, dynamic>{
            'node_us_slow': 240,
            'node_hk_01': 26,
            'node_sg_02': 48,
            'node_jp_01': 32,
            'node_tw_02': 44,
          },
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
      case 'activate_proxy_node':
        final n = Map<String, dynamic>.from(params['node'] as Map);
        lastActivatedNode = n;
        return <String, dynamic>{
          'ok': true,
          'mode': 'node',
          'active': true,
          'proxy_url': 'socks5h://127.0.0.1:20801',
          'node_id': n['id'],
          'node_name': n['name'],
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

    // 5. Settings -> 网络代理 supports Subscription URL -> Node Grid -> Click to activate node (zero essay!)
    await tester.tap(find.text('网络代理'));
    await tester.pumpAndSettle();
    expect(find.textContaining('原理说明'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('proxy-mode-sub')));
    await tester.pumpAndSettle();
    expect(app.prefs.inAppProxyMode, equals('sub'));
    await tester.enterText(
      find.byKey(const ValueKey('proxy-sub-url-field')),
      'https://sub.example.com/api/v1/client/subscribe?token=abc',
    );
    await tester.tap(find.byKey(const ValueKey('proxy-sub-fetch-btn')));
    await tester.pumpAndSettle();
    expect(find.text('🇭🇰 香港 IEPL 01'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('proxy-node-node_hk_01')),
        matching: find.text('26 ms'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('proxy-node-auto')), findsOneWidget);

    // Default sort is 'latency': HK (26 ms) MUST appear before US (240 ms) even though US was index 0!
    final hkPos = tester.getTopLeft(find.byKey(const ValueKey('proxy-node-node_hk_01')));
    final usPos = tester.getTopLeft(find.byKey(const ValueKey('proxy-node-node_us_slow')));
    expect(hkPos.dy < usPos.dy || (hkPos.dy == usPos.dy && hkPos.dx < usPos.dx), isTrue);

    // Tapping '自动选择' auto-picks lowest-latency HK (26 ms) node!
    await tester.tap(find.byKey(const ValueKey('proxy-node-auto')));
    await tester.pumpAndSettle();
    expect(app.prefs.selectedProxyNodeId, equals('auto'));
    expect(app.autoProxyResolvedNodeId, equals('node_hk_01'));
    expect(mock.lastActivatedNode?['name'], equals('🇭🇰 香港 IEPL 01'));

    // Switching sort dropdown to '默认顺序' moves US (index 0) ahead of HK!
    await tester.tap(find.byKey(const ValueKey('proxy-node-sort-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('proxy-sort-default')));
    await tester.pumpAndSettle();
    expect(app.prefs.proxyNodeSort, equals('default'));
    final hkDefaultPos = tester.getTopLeft(find.byKey(const ValueKey('proxy-node-node_hk_01')));
    final usDefaultPos = tester.getTopLeft(find.byKey(const ValueKey('proxy-node-node_us_slow')));
    expect(
      usDefaultPos.dy < hkDefaultPos.dy ||
          (usDefaultPos.dy == hkDefaultPos.dy && usDefaultPos.dx < hkDefaultPos.dx),
      isTrue,
    );

    // Direct manual node selection also works cleanly
    await tester.tap(find.byKey(const ValueKey('proxy-node-node_hk_01')));
    await tester.pumpAndSettle();
    expect(app.prefs.selectedProxyNodeId, equals('node_hk_01'));
    expect(mock.lastActivatedNode?['name'], equals('🇭🇰 香港 IEPL 01'));

    // 6. Settings -> AI 翻译 fetches model list (`/models`) via Proxy IP & zero "100% 不经过" essay!
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
    expect(find.text('添加媒体服务器'), findsOneWidget);

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

    // Episode 1 headline is clearly visible ("1. 倒计时") alongside "2 版本" badge without collision!
    expect(find.text('1. 倒计时'), findsOneWidget);
    expect(find.text('2 版本'), findsOneWidget);
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

    // 1. Hero uses ShaderMask(BlendMode.dstIn) alpha fade (no bottom seam!) & renders Slide 0
    expect(find.byKey(const ValueKey('hero-page-view')), findsOneWidget);
    final mask = tester.widget<ShaderMask>(find.byKey(const ValueKey('hero-alpha-mask-0')));
    expect(mask.blendMode, equals(BlendMode.dstIn));
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
      'Multi-subscription proxy management, default rating ON / 2x OFF badges, and zero-overlap adaptive Library grid across PPI & TextScaler',
      (tester) async {
    // 1. Legacy single-subscription JSON migrates cleanly to ProxySubscriptionProfile
    final migrated = VedroPreferences.fromJson({
      'proxy_subscription_url': 'https://legacy-airport.example.com/api/v1/client/subscribe?token=xyz',
      'proxy_nodes': [
        {'id': 'n1', 'name': 'Legacy HK', 'protocol': 'vless', 'server': 'hk.example.com', 'port': 443},
      ],
    });
    expect(migrated.proxySubscriptions.length, equals(1));
    expect(migrated.proxySubscriptions.first.name, equals('legacy-airport.example.com'));
    expect(migrated.activeProxySubId, equals('sub_default'));
    expect(migrated.showRatings, isTrue);
    expect(migrated.showMultiVersionBadge, isFalse);
    for (final s in VedroSkin.presets) {
      expect(s.showCardRating, isTrue, reason: 'Preset ${s.id} must show card rating by default');
    }

    // 2. Default Poster Badges: Rating star badge ON ('8.6'), Multi-version '2×' OFF by default
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

    expect(find.text('8.6'), findsOneWidget);
    expect(find.textContaining('★'), findsNothing); // Not duplicated in subtitle text!
    expect(find.text('2×'), findsNothing); // Hidden by default!

    // Explicitly toggling showMultiVersionBadge ON displays '2×', and OFF hides it again
    await app.updatePrefs(app.prefs.copyWith(showMultiVersionBadge: true));
    await tester.pumpAndSettle();
    expect(find.text('2×'), findsOneWidget);
    await app.updatePrefs(app.prefs.copyWith(showMultiVersionBadge: false));
    await tester.pumpAndSettle();
    expect(find.text('2×'), findsNothing);

    // 3. Multi-Subscription Proxy Management: Save 2 named subscriptions, switch, refresh all, delete
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

    await tester.tap(find.text('网络代理'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('proxy-mode-sub')));
    await tester.pumpAndSettle();

    // Save Subscription #1 ("主力机场")
    await tester.enterText(find.byKey(const ValueKey('proxy-sub-name-field')), '主力机场');
    await tester.enterText(
      find.byKey(const ValueKey('proxy-sub-url-field')),
      'https://sub1.example.com/api/v1/client/subscribe?token=111',
    );
    await tester.tap(find.byKey(const ValueKey('proxy-sub-fetch-btn')));
    await tester.pumpAndSettle();
    expect(app.prefs.proxySubscriptions.length, equals(1));
    expect(find.text('主力机场'), findsOneWidget);
    expect(find.text('🇭🇰 香港 IEPL 01'), findsOneWidget);

    // Add Subscription #2 ("日本专线") via '添加订阅' button
    await tester.tap(find.byKey(const ValueKey('proxy-sub-show-add-btn')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('proxy-sub-name-field')), '日本专线');
    await tester.enterText(
      find.byKey(const ValueKey('proxy-sub-url-field')),
      'https://sub2.example.com/api/v1/client/subscribe?token=222',
    );
    await tester.tap(find.byKey(const ValueKey('proxy-sub-fetch-btn')));
    await tester.pumpAndSettle();

    expect(app.prefs.proxySubscriptions.length, equals(2));
    expect(find.text('已存订阅 (2)'), findsOneWidget);
    expect(find.text('🇯🇵 东京专线 01'), findsOneWidget);
    expect(find.text('🇭🇰 香港 IEPL 01'), findsNothing);

    final sub1Id = app.prefs.proxySubscriptions.first.id;
    final sub2Id = app.prefs.proxySubscriptions.last.id;

    // Tap Subscription #1 card -> switches active node list back to HK/SG/US live!
    await tester.tap(find.byKey(ValueKey('proxy-sub-card-$sub1Id')));
    await tester.pumpAndSettle();
    expect(app.prefs.activeProxySubId, equals(sub1Id));
    expect(find.text('🇭🇰 香港 IEPL 01'), findsOneWidget);
    expect(find.text('🇯🇵 东京专线 01'), findsNothing);

    // Refresh all subscriptions & delete Subscription #2
    await tester.tap(find.byKey(const ValueKey('proxy-sub-refresh-all-btn')));
    await tester.pumpAndSettle();
    expect(find.text('已刷新 2 个订阅'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('proxy-sub-delete-$sub2Id')));
    await tester.pumpAndSettle();
    expect(app.prefs.proxySubscriptions.length, equals(1));

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
      final proxyStatus = await bridge.invoke('in_app_proxy_status') as Map<String, dynamic>;
      expect(proxyStatus['active'], isFalse);
      final setCustomProxy = await bridge.invoke('configure_in_app_proxy', {
        'mode': 'custom',
        'proxy_url': 'socks5h://127.0.0.1:10808',
      }) as Map<String, dynamic>;
      expect(setCustomProxy['ok'], isTrue);
      expect(setCustomProxy['active'], isTrue);
      final subRes = await bridge.invoke('fetch_proxy_subscription', {
        'raw_content': 'socks5://127.0.0.1:1080#LocalNode\nvless://11111111-2222-3333-4444-555555555555@hk.example.com:443?security=tls#HK-VLESS',
      }) as Map<String, dynamic>;
      expect(subRes['count'], equals(2));
      final subNodes = (subRes['nodes'] as List).cast<Map<String, dynamic>>();
      expect(subNodes[1]['native_supported'], isTrue);
      // Activate VLESS node via real in-process Rust multi-protocol engine (ZERO external sing-box binary!)
      final actRes = await bridge.invoke('activate_proxy_node', {
        'node': subNodes[1],
      }) as Map<String, dynamic>;
      expect(actRes['ok'], isTrue);
      expect(actRes['engine'], equals('native_rust'));
      final nativeStatus = await bridge.invoke('in_app_proxy_status') as Map<String, dynamic>;
      expect(nativeStatus['active'], isTrue);
      expect(nativeStatus['managed_engine'], equals('native_rust'));
      final resetProxy = await bridge.invoke('configure_in_app_proxy', {
        'mode': 'off',
      }) as Map<String, dynamic>;
      expect(resetProxy['active'], isFalse);
    } finally {
      bridge.dispose();
    }
  });
}
