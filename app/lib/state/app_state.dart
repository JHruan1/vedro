import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show PaintingBinding;
import 'package:path_provider/path_provider.dart';

import '../core/ffi/vedro_bridge.dart';
import '../core/models/models.dart';
import '../core/models/preferences.dart';
import '../core/platform/native_playback_channel.dart';
import '../core/platform/platform_perf.dart';
import '../core/services/danmaku_parser.dart';
import '../core/services/local_asr_engine.dart';
import '../core/theme/display_profile.dart';
import '../core/theme/dynamic_color_engine.dart';
import '../core/utils/artwork_signal.dart';
import '../core/utils/error_formatter.dart';

export '../core/utils/error_formatter.dart';
export '../core/models/local_history_model.dart';

part 'app_state_ai_admin.dart';
part 'app_state_artwork.dart';
part 'app_state_downloads.dart';
part 'app_state_media.dart';
part 'app_state_servers.dart';

List<MediaItemModel> _parseMediaItems(dynamic raw) {
  if (raw is! List) return const [];
  return raw.whereType<Map<String, dynamic>>().map(MediaItemModel.fromJson).toList();
}

/// Central reactive application state backed directly by the compiled Rust core (`VedroCoreClient`).
///
/// Architecture aligned with SenPlayer / Forward:
/// - Never forces a blocking login gate; launches directly into the main workspace.
/// - First-class multi-server management + per-server multi-route lines with live latency ping.
/// - Real parallel multi-server aggregated search (`aggregated_search`).
/// - RAM-cached local Rust loopback image proxy inheriting OS/Clash/SOCKS5 proxy & TLS roots.
class VedroAppState extends ChangeNotifier {
  VedroAppState(this.core);

  final VedroCoreClient core;

  bool isInitialized = false;
  bool isAutoRestoring = false;
  bool isBusy = false;
  bool isLoadingHome = false;
  String? loginStage;
  String? errorMessage;
  String? homeError;

  List<SavedServerProfile> savedServers = [];
  List<Map<String, dynamic>> discoveredServers = [];
  Map<String, ServerLiveStatus> serverStatuses = {};
  bool isProbingServers = false;
  DateTime? _lastServerProbeAt;

  ServerCapabilitiesModel? capabilities;
  String? activeServerId;
  String? connectedUrl;
  String? proxyAddr;
  String? username;
  String? userId;
  bool isAdmin = false;
  bool enableContentDownloading = false;
  MeQuotaModel? meQuota;
  bool isLoadingQuota = false;

  // Home collections
  List<MediaItemModel> views = [];
  List<MediaItemModel> popular = [];
  List<MediaItemModel> resume = [];
  List<MediaItemModel> nextUp = [];
  List<MediaItemModel> suggestions = [];
  List<MediaItemModel> favorites = [];
  List<Map<String, dynamic>> _latestByLibrary = const [];
  List<({MediaItemModel library, List<MediaItemModel> items})> _parsedLatestByLibrary = const [];

  List<Map<String, dynamic>> get latestByLibrary => _latestByLibrary;
  set latestByLibrary(List<Map<String, dynamic>> value) {
    _latestByLibrary = value;
    _parsedLatestByLibrary = [
      for (final entry in value)
        if (entry['library'] is Map<String, dynamic>)
          (
            library: MediaItemModel.fromJson(entry['library'] as Map<String, dynamic>),
            items: _parseMediaItems(entry['items']),
          ),
    ];
  }

  List<({MediaItemModel library, List<MediaItemModel> items})> get parsedLatestByLibrary =>
      _parsedLatestByLibrary;

  // Playlists
  List<MediaItemModel> playlists = [];

  // Remote control toast messages from WebSocket
  String? remoteBannerMessage;

  void dismissRemoteBanner() {
    if (remoteBannerMessage == null) return;
    remoteBannerMessage = null;
    notifyListeners();
  }

  // Scoped high-frequency notifiers so 400ms download ticks & 220ms speedtest ticks
  // NEVER trigger root `MaterialApp` rebuilds.
  final ValueNotifier<int> downloadsTickNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> speedtestTickNotifier = ValueNotifier<int>(0);

  bool _disposed = false;
  int _sessionEpoch = 0;
  int _speedTestGen = 0;
  Timer? _prefsDebounceTimer;
  Timer? _quotaRefreshTimer;
  bool _prefsDirty = false;
  List<VedroLocalHistoryEntry> localHistory = [];

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  // Playback settings mirrored with Rust SQLite store
  Map<String, dynamic> settings = {};

  // Comprehensive user preferences persisted in SQLite KV (`vedro_prefs`)
  VedroPreferences prefs = const VedroPreferences();
  Color? dynamicPageSeedColor;
  String? _dynamicSeedSourceKey;

  /// Update the global Monet page-adaptive seed color from the currently featured media item.
  void updateDynamicSeedFromItem(MediaItemModel? item) {
    if (item == null) {
      if (dynamicPageSeedColor != null) {
        dynamicPageSeedColor = null;
        _dynamicSeedSourceKey = null;
        notifyListeners();
      }
      return;
    }
    final key = '${item.id}:${item.primaryImageTag ?? ''}:${item.backdropImageTag ?? item.parentBackdropImageTag ?? ''}';
    if (_dynamicSeedSourceKey == key && dynamicPageSeedColor != null) return;
    _dynamicSeedSourceKey = key;

    final artUrl = backdropArt(item, width: 320)?.url ?? posterArtUrl(item, width: 320);
    final cached = DynamicColorEngine.cachedForUrl(artUrl);
    dynamicPageSeedColor = cached ?? DynamicColorEngine.seedForIdentity(item.id, item.name);
    notifyListeners();

    if (cached == null && artUrl != null && artUrl.isNotEmpty) {
      DynamicColorEngine.extractFromImageUrl(artUrl).then((extracted) {
        if (extracted != null && _dynamicSeedSourceKey == key) {
          dynamicPageSeedColor = extracted;
          notifyListeners();
        }
      });
    }
  }

  // Local offline downloads queue persisted in SQLite KV (`downloads_queue`)
  List<DownloadTaskModel> downloads = [];
  final Map<String, _ActiveDownloadHandle> _activeDownloadHandles = {};
  String? _supportDirPath;

  // Customizable Home layout (persisted in SQLite `settings` KV under `home_layout`)
  List<HomeSectionConfig> homeSections = List<HomeSectionConfig>.from(HomeSectionConfig.defaults);
  bool showHomeHero = true;

  // Preserves active Settings section across skin layout switches & window resizes
  String activeSettingsSection = 'servers';

  // Network transport options (auto-detected OS/Android proxy or user override)
  String systemProxyUrl = '';
  String customProxyUrl = '';
  bool acceptInvalidCerts = false;

  // EmbyGo Admin dashboard snapshot
  Map<String, dynamic>? embygoAdminDashboard;

  // EmbyGo Account Devices & Playback Speedtest state
  List<Map<String, dynamic>> userDevices = [];
  String? currentClientDeviceId;
  bool isLoadingDevices = false;
  bool isSpeedTesting = false;
  double? liveSpeedTestMbps;
  double? speedTestLatencyMs;
  String? speedTestClientIp;
  Map<String, dynamic>? lastSpeedTestResult;
  String? speedTestError;
  Timer? _speedTestPollTimer;

  // Local persistent image cache stats (`<db_dir>/img_cache` + Rust RAM cache)
  Map<String, dynamic>? imageCacheStats;
  bool isLoadingImageCacheStats = false;
  bool isClearingImageCache = false;

  Timer? _wsPollTimer;

  bool get isSignedIn => userId != null && connectedUrl != null;

  SavedServerProfile? get activeServer {
    if (activeServerId != null) {
      for (final s in savedServers) {
        if (s.id == activeServerId) return s;
      }
    }
    if (connectedUrl != null) {
      for (final s in savedServers) {
        if (s.url == connectedUrl) return s;
      }
    }
    return null;
  }

  String get activeServerDisplayName {
    if (activeServerId != null) {
      final custom = serverCardStyleFor(activeServerId!).customName.trim();
      if (custom.isNotEmpty) return custom;
    }
    if (capabilities?.serverName.isNotEmpty == true) return capabilities!.serverName;
    if (activeServer?.name.isNotEmpty == true) return activeServer!.name;
    return 'Vedro';
  }

  String? get activeRouteDisplayName => activeServer?.activeRoute?.name;

  bool get hasAnyHomeContent =>
      views.isNotEmpty ||
      popular.isNotEmpty ||
      resume.isNotEmpty ||
      nextUp.isNotEmpty ||
      favorites.isNotEmpty ||
      latestByLibrary.isNotEmpty;

  Future<void> initialize() async {
    isBusy = true;
    notifyListeners();
    try {
      String? rememberedId;
      Map<String, dynamic>? cachedHomeSnapshot;

      // Fast path: 1 single FFI round-trip reads version, proxyAddr, servers, settings, prefs,
      // home_layout, downloads_queue, last_active_server_id, AND cached_home from SQLite in <5ms!
      Map<String, dynamic>? boot;
      try {
        final rawBoot = await core.invoke('bootstrap_state');
        if (rawBoot is Map<String, dynamic> && rawBoot.containsKey('servers')) {
          boot = rawBoot;
        }
      } catch (_) {
        boot = null;
      }

      // On Android, probe Leanback / TV capability BEFORE applying first-run hardware defaults
      // so Android TV devices don't get stuck with phone defaults on cold start!
      if (!kIsWeb && Platform.isAndroid) {
        try {
          await NativePlaybackChannel.queryDisplayAndAudioCapabilities()
              .timeout(const Duration(milliseconds: 250));
        } catch (_) {}
      }

      if (boot != null) {
        if (boot['proxy_addr'] != null) {
          proxyAddr = boot['proxy_addr'].toString();
        }
        if (boot['servers'] is List) {
          savedServers = (boot['servers'] as List)
              .whereType<Map<String, dynamic>>()
              .map(SavedServerProfile.fromJson)
              .toList()
            ..sort((a, b) => b.lastConnectedAt.compareTo(a.lastConnectedAt));
        }
        if (boot['settings'] is Map<String, dynamic>) {
          settings = Map<String, dynamic>.from(boot['settings'] as Map);
        }
        if (boot['home_layout'] is Map<String, dynamic>) {
          final layout = boot['home_layout'] as Map<String, dynamic>;
          homeSections = HomeSectionConfig.normalize(layout['sections'] as List<dynamic>?);
          if (layout['show_hero'] is bool) {
            showHomeHero = layout['show_hero'] as bool;
          }
        }
        if (boot['vedro_prefs'] is Map<String, dynamic>) {
          prefs = VedroPreferences.fromJson(boot['vedro_prefs'] as Map<String, dynamic>);
        } else {
          final hwProfile = DisplayMetricsProfile.fromPlatformDispatcher();
          prefs = const VedroPreferences().applyHardwareDefaults(hwProfile);
          unawaited(
            core.invoke('set_kv', {'key': 'vedro_prefs', 'value': prefs.toJson()}),
          );
        }
        if (boot['downloads_queue'] is List) {
          downloads = _hydrateDownloadsList(boot['downloads_queue'] as List);
        }
        if (boot['last_active_server_id'] is String) {
          final v = (boot['last_active_server_id'] as String).trim();
          if (v.isNotEmpty) rememberedId = v;
        }
        if (boot['cached_home'] is Map<String, dynamic>) {
          cachedHomeSnapshot = boot['cached_home'] as Map<String, dynamic>;
        }
      } else {
        // Fallback path for mock test clients that do not implement `bootstrap_state`
        final ver = await core.invoke('version');
        if (ver is Map<String, dynamic> && ver['proxy_addr'] != null) {
          proxyAddr = ver['proxy_addr'].toString();
        }
        final list = await core.invoke('list_servers');
        if (list is List) {
          savedServers = list
              .whereType<Map<String, dynamic>>()
              .map(SavedServerProfile.fromJson)
              .toList()
            ..sort((a, b) => b.lastConnectedAt.compareTo(a.lastConnectedAt));
        }
        final cfg = await core.invoke('get_settings');
        if (cfg is Map<String, dynamic>) {
          settings = Map<String, dynamic>.from(cfg);
        }
        try {
          final kv = await core.invoke('get_kv', {'key': 'home_layout'});
          if (kv is Map<String, dynamic> && kv['value'] is Map<String, dynamic>) {
            final layout = kv['value'] as Map<String, dynamic>;
            homeSections = HomeSectionConfig.normalize(layout['sections'] as List<dynamic>?);
            if (layout['show_hero'] is bool) {
              showHomeHero = layout['show_hero'] as bool;
            }
          }
        } catch (_) {}
        try {
          final kv = await core.invoke('get_kv', {'key': 'vedro_prefs'});
          if (kv is Map<String, dynamic> && kv['value'] is Map<String, dynamic>) {
            prefs = VedroPreferences.fromJson(kv['value'] as Map<String, dynamic>);
          } else {
            final hwProfile = DisplayMetricsProfile.fromPlatformDispatcher();
            prefs = const VedroPreferences().applyHardwareDefaults(hwProfile);
            unawaited(
              core.invoke('set_kv', {'key': 'vedro_prefs', 'value': prefs.toJson()}),
            );
          }
        } catch (_) {}
        try {
          final kv = await core.invoke('get_kv', {'key': 'downloads_queue'});
          if (kv is Map<String, dynamic> && kv['value'] is List) {
            downloads = _hydrateDownloadsList(kv['value'] as List);
          }
        } catch (_) {}
        try {
          final lastKv = await core.invoke('get_kv', {'key': 'last_active_server_id'});
          if (lastKv is Map<String, dynamic> && lastKv['value'] is String) {
            final v = (lastKv['value'] as String).trim();
            if (v.isNotEmpty) rememberedId = v;
          }
        } catch (_) {}
      }

      PlatformPerfProfile.tvModeManualOverride = prefs.tvModeOverride;
      final recent = savedServers.where((s) => s.accessToken != null && s.userId != null).toList();
      final target = recent.isNotEmpty
          ? ((rememberedId != null
                  ? recent.where((s) => s.id == rememberedId).firstOrNull
                  : null) ??
              recent.first)
          : null;

      // Instant Stale-While-Revalidate (SWR) Home hydration:
      // Render the remembered server + cached Home rails on Frame 0 (<50ms) with ZERO splash block!
      if (target != null) {
        final route = target.activeRoute;
        connectedUrl = route?.url.isNotEmpty == true ? route!.url : target.url;
        activeServerId = target.id;
        userId = target.userId;
        username = target.username;
        isAdmin = target.isAdmin;
        capabilities = ServerCapabilitiesModel(
          dialect: target.dialect,
          serverId: target.id,
          serverName: target.name,
          advertisedVersion: '',
          supportsTranscoding: target.dialect != 'embygo',
          supportsPopular: target.dialect == 'embygo',
          supportsSuggestions: true,
          supportsHideFromResume: true,
          usesStreamTickets: target.dialect == 'embygo',
        );
        if (cachedHomeSnapshot != null) {
          _applyHomePayload(cachedHomeSnapshot);
        }
        isLoadingHome = !hasAnyHomeContent;
      }

      isInitialized = true;
      isAutoRestoring = false;
      isBusy = false;
      notifyListeners();

      unawaited(() async {
        try {
          final dir = await getApplicationSupportDirectory();
          _supportDirPath = dir.path;
        } catch (_) {}
      }());
      unawaited(_loadLocalHistory());

      // Background hardware probe + proxy activation + live session revalidation (never blocks UI entry!)
      final bgFuture = () async {
        try {
          final prevTv = NativePlaybackChannel.detectedAndroidTv;
          final hwCaps = await NativePlaybackChannel.queryDisplayAndAudioCapabilities();
          final detectedProxy = hwCaps['system_proxy_url']?.toString().trim() ?? '';
          if (detectedProxy.isNotEmpty) {
            systemProxyUrl = detectedProxy;
          }
          if (settings['display'] is Map<String, dynamic>) {
            final d = Map<String, dynamic>.from(settings['display'] as Map);
            d['supports_hdr10'] = hwCaps['supports_hdr10'] ?? d['supports_hdr10'];
            d['supports_hlg'] = hwCaps['supports_hlg'] ?? d['supports_hlg'];
            d['supports_native_dolby_vision'] =
                hwCaps['supports_native_dolby_vision'] ?? d['supports_native_dolby_vision'];
            d['max_luminance_nits'] = hwCaps['max_luminance_nits'] ?? d['max_luminance_nits'];
            settings['display'] = d;
          }
          if (prevTv != NativePlaybackChannel.detectedAndroidTv) {
            notifyListeners();
          }
        } catch (_) {}

        if (target != null) {
          await restoreSavedServer(
            target,
            silentError: true,
            preserveCachedHome: hasAnyHomeContent,
          );
        } else {
          unawaited(discoverLanServers());
        }
      }();

      // In unit tests (`boot == null`), await deterministically so assertions immediately see restored state.
      if (boot == null) {
        await bgFuture;
      } else {
        unawaited(bgFuture);
      }
    } catch (e) {
      errorMessage = e.toString();
      isInitialized = true;
      isAutoRestoring = false;
      isBusy = false;
      notifyListeners();
    }
  }

  List<DownloadTaskModel> _hydrateDownloadsList(List<dynamic> rawList) {
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(DownloadTaskModel.fromJson)
        .map((d) {
          if (d.status == 'downloading' || d.status == 'queued') {
            var syncedBytes = d.downloadedBytes;
            if (d.filePath.isNotEmpty) {
              final part = File('${d.filePath}.part');
              if (part.existsSync()) {
                syncedBytes = part.lengthSync();
              }
            }
            return d.copyWith(
              status: 'paused',
              downloadedBytes: syncedBytes,
              speedBytesPerSec: 0,
              error: '上次下载中断，可点击继续断点续传',
            );
          }
          return d;
        })
        .toList();
  }

  Future<void> saveSettings(Map<String, dynamic> updated) async {
    final saved = await core.invoke('save_settings', updated) as Map<String, dynamic>;
    settings = Map<String, dynamic>.from(saved);
    notifyListeners();
  }

  Future<void> saveHomeLayout(
    List<HomeSectionConfig> sections, {
    bool? showHero,
  }) async {
    homeSections = List<HomeSectionConfig>.from(sections);
    if (showHero != null) showHomeHero = showHero;
    notifyListeners();
    try {
      await core.invoke('set_kv', {
        'key': 'home_layout',
        'value': {
          'show_hero': showHomeHero,
          'sections': homeSections.map((s) => s.toJson()).toList(),
        },
      });
    } catch (_) {}
  }

  Future<void> resetHomeLayout() => saveHomeLayout(
        HomeSectionConfig.defaults,
        showHero: true,
      );

  Future<void> updatePrefs(VedroPreferences updated, {bool immediate = false}) async {
    prefs = updated;
    PlatformPerfProfile.tvModeManualOverride = prefs.tvModeOverride;
    _prefsDirty = true;
    notifyListeners();
    if (immediate) {
      await flushPrefsNow();
      return;
    }
    _prefsDebounceTimer?.cancel();
    _prefsDebounceTimer = Timer(const Duration(milliseconds: 240), () {
      unawaited(flushPrefsNow());
    });
  }

  Future<void> flushPrefsNow() async {
    _prefsDebounceTimer?.cancel();
    _prefsDebounceTimer = null;
    if (!_prefsDirty) return;
    _prefsDirty = false;
    try {
      await core.invoke('set_kv', {
        'key': 'vedro_prefs',
        'value': prefs.toJson(),
      });
    } catch (_) {}
  }

  /// Persistent resume position (in seconds) for local offline files / direct URLs.
  Future<double> getLocalResumeSecs(String pathKey) async {
    if (pathKey.trim().isEmpty) return 0.0;
    try {
      final kv = await core.invoke('get_kv', {'key': 'local_resume_v1'});
      if (kv is Map<String, dynamic> && kv['value'] is Map) {
        final v = (kv['value'] as Map)[pathKey];
        if (v is num) return v.toDouble().clamp(0.0, 86400.0);
      }
    } catch (_) {}
    return 0.0;
  }

  Future<void> saveLocalResumeSecs(String pathKey, double secs) async {
    if (pathKey.trim().isEmpty || prefs.incognitoMode) return;
    try {
      final map = <String, dynamic>{};
      final kv = await core.invoke('get_kv', {'key': 'local_resume_v1'});
      if (kv is Map<String, dynamic> && kv['value'] is Map) {
        (kv['value'] as Map).forEach((k, v) {
          if (v is num) map[k.toString()] = v.toDouble();
        });
      }
      if (secs <= 3.0) {
        map.remove(pathKey);
      } else {
        map[pathKey] = secs;
        while (map.length > 200) {
          map.remove(map.keys.first);
        }
      }
      await core.invoke('set_kv', {'key': 'local_resume_v1', 'value': map});
    } catch (_) {}
  }

  Future<void> _loadLocalHistory() async {
    try {
      final kv = await core.invoke('get_kv', {'key': 'local_history_v1'});
      if (_disposed) return;
      if (kv is Map<String, dynamic> && kv['value'] is List) {
        localHistory = (kv['value'] as List)
            .map(asJsonMapOrNull)
            .whereType<Map<String, dynamic>>()
            .map(VedroLocalHistoryEntry.fromJson)
            .where((e) => e.target.isNotEmpty)
            .take(30)
            .toList();
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Strip userinfo credentials (`user:pass@`) and sensitive query parameters
  /// (`api_key`, `token`, `password`, `auth`, `sig`, `StreamTicket`) before persisting history.
  static String sanitizeUrlForHistory(String raw) {
    final trimmed = raw.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return trimmed;
    const sensitive = {
      'api_key',
      'apikey',
      'token',
      'access_token',
      'streamticket',
      'password',
      'pass',
      'auth',
      'sig',
      'signature',
    };
    final cleaned = <String, List<String>>{};
    if (uri.hasQuery) {
      uri.queryParametersAll.forEach((k, values) {
        if (!sensitive.contains(k.toLowerCase())) {
          cleaned[k] = values;
        }
      });
    }
    // Note: In Dart `Uri.replace(queryParameters: null)` preserves the old query string!
    // Rebuild explicitly when all query params were stripped so secrets are guaranteed gone.
    final rebuilt = Uri(
      scheme: uri.scheme,
      userInfo: '',
      host: uri.hasAuthority ? uri.host : null,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      queryParameters: cleaned.isEmpty ? null : cleaned,
      fragment: uri.hasFragment ? uri.fragment : null,
    );
    return rebuilt.toString();
  }

  Future<void> recordLocalHistory({
    required String title,
    required String target,
    required bool isNetworkUrl,
    double positionSecs = 0.0,
    double durationSecs = 0.0,
  }) async {
    if (target.trim().isEmpty || prefs.incognitoMode) return;
    final safeTarget = isNetworkUrl ? sanitizeUrlForHistory(target) : target.trim();
    final key = '${isNetworkUrl ? 'url' : 'file'}::$safeTarget';
    final entry = VedroLocalHistoryEntry(
      key: key,
      title: title.trim().isEmpty ? safeTarget : title.trim(),
      target: safeTarget,
      isNetworkUrl: isNetworkUrl,
      positionSecs: positionSecs.isFinite ? positionSecs.clamp(0.0, 86400.0) : 0.0,
      durationSecs: durationSecs.isFinite ? durationSecs.clamp(0.0, 86400.0) : 0.0,
      playedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    localHistory = [
      entry,
      ...localHistory.where((e) => e.key != key),
    ].take(30).toList();
    notifyListeners();
    try {
      await core.invoke('set_kv', {
        'key': 'local_history_v1',
        'value': localHistory.map((e) => e.toJson()).toList(),
      });
    } catch (_) {}
  }

  Future<void> removeLocalHistoryEntry(String key) async {
    localHistory = localHistory.where((e) => e.key != key).toList();
    notifyListeners();
    try {
      await core.invoke('set_kv', {
        'key': 'local_history_v1',
        'value': localHistory.map((e) => e.toJson()).toList(),
      });
    } catch (_) {}
  }

  Future<void> clearLocalHistory() async {
    localHistory = [];
    notifyListeners();
    try {
      await core.invoke('set_kv', {'key': 'local_history_v1', 'value': const <dynamic>[]});
    } catch (_) {}
  }

  /// Export portable JSON configuration (preferences + home layout; NEVER exports PIN hashes or API keys).
  String exportConfigJson() {
    final p = prefs.toJson()
      ..remove('passcode_hash')
      ..remove('passcode_enabled')
      ..remove('ai_api_key')
      ..remove('asr_api_key');
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'vedro-config',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'preferences': p,
      'home_layout': {
        'show_hero': showHomeHero,
        'sections': homeSections.map((s) => s.toJson()).toList(),
      },
    });
  }

  /// Import a portable Vedro JSON config (preserves local passcode lock and API keys).
  Future<void> importConfigJson(String rawJson) async {
    final parsed = jsonDecode(rawJson.trim());
    if (parsed is! Map) {
      throw Exception('配置格式无效，请粘贴完整的 JSON 内容');
    }
    final prefMap = asJsonMapOrNull(parsed['preferences']);
    if (prefMap == null) {
      throw Exception('配置中缺少 preferences 字段');
    }
    final imported = VedroPreferences.fromJson(prefMap).copyWith(
      passcodeEnabled: prefs.passcodeEnabled,
      passcodeHash: prefs.passcodeHash,
      aiApiKey: prefs.aiApiKey,
      asrApiKey: prefs.asrApiKey,
    );
    await updatePrefs(imported, immediate: true);
    final layout = asJsonMapOrNull(parsed['home_layout']);
    if (layout != null) {
      await saveHomeLayout(
        HomeSectionConfig.normalize(layout['sections'] as List<dynamic>?),
        showHero: layout['show_hero'] is bool ? layout['show_hero'] as bool : showHomeHero,
      );
    }
  }

  /// Reset all user preferences back to factory defaults (preserving passcode lock).
  Future<void> resetPreferencesToDefaults() async {
    await updatePrefs(
      const VedroPreferences().copyWith(
        passcodeEnabled: prefs.passcodeEnabled,
        passcodeHash: prefs.passcodeHash,
      ),
      immediate: true,
    );
    await resetHomeLayout();
  }

  Future<void> resetToHardwareRecommendedDefaults(DisplayMetricsProfile profile) async {
    await updatePrefs(prefs.applyHardwareDefaults(profile));
  }

  void _consumeCoreEvents() {
    if (_disposed) return;
    final events = core.pollEvents();
    var changed = false;
    var speedTick = false;
    for (final ev in events) {
      if (ev['source'] == 'speedtest') {
        final phase = ev['phase']?.toString();
        if (phase == 'ping') {
          speedTestLatencyMs = (ev['latency_ms'] as num?)?.toDouble();
          speedTestClientIp = ev['client_ip']?.toString();
          speedTick = true;
        } else if (phase == 'download') {
          liveSpeedTestMbps = (ev['live_mbps'] as num?)?.toDouble();
          speedTick = true;
        }
        continue;
      }
      final payload = ev['event'];
      if (payload is Map<String, dynamic>) {
        final kind = payload['kind']?.toString();
        if (kind == 'display_message') {
          remoteBannerMessage = '${payload['header'] ?? ''}: ${payload['text'] ?? ''}'.trim();
          changed = true;
        } else if (kind == 'user_data_changed') {
          refreshHome();
        }
      }
    }
    if (speedTick && !_disposed) {
      speedtestTickNotifier.value = speedtestTickNotifier.value + 1;
    }
    if (changed) notifyListeners();
  }

  bool _appResumed = true;

  void setAppResumed(bool resumed) {
    if (_disposed || _appResumed == resumed) return;
    _appResumed = resumed;
    if (!resumed) {
      _wsPollTimer?.cancel();
      _wsPollTimer = null;
      unawaited(flushPrefsNow());
    } else if (isSignedIn) {
      _startEventPolling();
    }
  }

  void _startEventPolling() {
    _wsPollTimer?.cancel();
    if (_disposed || !_appResumed) return;
    final pollSecs = (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) ? 4 : 3;
    _wsPollTimer = Timer.periodic(Duration(seconds: pollSecs), (_) => _consumeCoreEvents());
  }

  static String _platformDeviceName() {
    if (kIsWeb) return 'Web';
    if (Platform.isIOS) return 'iPhone / iPad';
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isWindows) return 'Windows PC';
    return 'Linux Desktop';
  }

  @override
  void dispose() {
    _disposed = true;
    ++_sessionEpoch;
    ++_speedTestGen;
    _wsPollTimer?.cancel();
    _speedTestPollTimer?.cancel();
    _prefsDebounceTimer?.cancel();
    _quotaRefreshTimer?.cancel();
    if (_prefsDirty) {
      _prefsDirty = false;
      try {
        unawaited(
          core
              .invoke('set_kv', {
                'key': 'vedro_prefs',
                'value': prefs.toJson(),
              })
              .catchError((_) => null),
        );
      } catch (_) {}
    }
    for (final h in _activeDownloadHandles.values) {
      h.cancelled = true;
      h.abort();
    }
    _activeDownloadHandles.clear();
    downloadsTickNotifier.dispose();
    speedtestTickNotifier.dispose();
    super.dispose();
  }
}
