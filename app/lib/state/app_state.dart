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
import '../core/theme/display_profile.dart';
import '../core/theme/dynamic_color_engine.dart';
import '../widgets/danmaku_engine.dart';
import '../widgets/local_asr_engine.dart';
import '../widgets/vedro_artwork.dart';

/// Centralized user-friendly Chinese error formatter translating raw transport, TLS,
/// DNS, HTTP status, and malformed HTML/JSON responses into actionable explanations.
class VedroErrorFormatter {
  static String friendly(Object error) => format(error);

  static String format(Object error) {
    final raw = error
        .toString()
        .replaceFirst('VedroCoreException: ', '')
        .replaceFirst('Exception: ', '')
        .trim();
    if (raw.isEmpty) return '操作失败，请稍后重试';
    final lower = raw.toLowerCase();

    if (lower.contains('unauthorized') ||
        lower.contains('http 401') ||
        lower.contains('status 401') ||
        lower.contains('invalid username') ||
        lower.contains('invalid password')) {
      return '用户名或密码不正确，或登录凭证已失效';
    }
    if (lower.contains('http 403') || lower.contains('status 403') || lower.contains('forbidden')) {
      return '服务器拒绝访问（403），请检查账号权限或是否被限制';
    }
    if (lower.contains('http 404') || lower.contains('status 404') || lower.contains('not found')) {
      return '接口或资源不存在（404），请确认服务器地址与路径（如 /emby）';
    }
    if (lower.contains('http 429') || lower.contains('status 429') || lower.contains('too many requests')) {
      return '请求过于频繁（429），请稍后再试';
    }
    if (lower.contains('http 502') || lower.contains('http 503') || lower.contains('http 504')) {
      return '服务器网关异常或维护中（502/503/504），请稍后重试';
    }
    if (lower.contains('certificate') ||
        lower.contains('tls') ||
        lower.contains('ssl') ||
        lower.contains('handshake') ||
        lower.contains('invalidpeer') ||
        lower.contains('unknownissuer')) {
      return 'HTTPS 证书校验失败：若使用自签名证书，请在「网络与代理」中开启允许自签名证书';
    }
    if (lower.contains('dns') ||
        lower.contains('failed to lookup') ||
        lower.contains('nodename nor servname') ||
        lower.contains('name or service not known') ||
        lower.contains('no such host')) {
      return '域名解析失败，请检查服务器地址拼写或网络连接';
    }
    if (lower.contains('connection refused') || lower.contains('os error 111') || lower.contains('econnrefused')) {
      return '连接被拒绝，请确认服务器已运行且端口正确';
    }
    if (lower.contains('timed out') || lower.contains('timeout') || lower.contains('deadline')) {
      return '连接超时，请检查网络状况、防火墙或代理设置';
    }
    if (lower.contains('expected value at line 1') ||
        lower.contains('<!doctype') ||
        lower.contains('<html') ||
        lower.contains('formatexception')) {
      return '服务器返回了非预期页面（可能被反向代理拦截或地址有误）';
    }
    return raw;
  }
}

/// Recent local file or direct network URL playback entry persisted in SQLite KV (`local_history_v1`).
class VedroLocalHistoryEntry {
  const VedroLocalHistoryEntry({
    required this.key,
    required this.title,
    required this.target,
    required this.isNetworkUrl,
    this.positionSecs = 0.0,
    this.durationSecs = 0.0,
    this.playedAtMs = 0,
  });

  final String key;
  final String title;
  final String target;
  final bool isNetworkUrl;
  final double positionSecs;
  final double durationSecs;
  final int playedAtMs;

  double get progress =>
      durationSecs > 0 ? (positionSecs / durationSecs).clamp(0.0, 1.0) : 0.0;

  Map<String, dynamic> toJson() => {
        'key': key,
        'title': title,
        'target': target,
        'is_network_url': isNetworkUrl,
        'position_secs': positionSecs,
        'duration_secs': durationSecs,
        'played_at_ms': playedAtMs,
      };

  factory VedroLocalHistoryEntry.fromJson(Map<String, dynamic> j) => VedroLocalHistoryEntry(
        key: (j['key'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        target: (j['target'] ?? '').toString(),
        isNetworkUrl: j['is_network_url'] == true,
        positionSecs: asJsonDouble(j['position_secs']) ?? 0.0,
        durationSecs: asJsonDouble(j['duration_secs']) ?? 0.0,
        playedAtMs: asJsonInt(j['played_at_ms']) ?? 0,
      );
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
            items: _parseItems(entry['items']),
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

  Future<void> discoverLanServers() async {
    try {
      final res = await core.invoke('discover_servers', {'timeout_ms': 1200});
      if (res is List) {
        discoveredServers = res.whereType<Map<String, dynamic>>().toList();
        notifyListeners();
      }
    } catch (_) {}
  }

  String get effectiveProxyUrl =>
      customProxyUrl.trim().isNotEmpty ? customProxyUrl.trim() : systemProxyUrl;

  Future<ServerCapabilitiesModel> connectServer(
    String url, {
    String? proxyUrl,
    bool? acceptInvalidTls,
  }) async {
    final epoch = ++_sessionEpoch;
    errorMessage = null;
    loginStage = '正在连接服务器…';
    isBusy = true;
    notifyListeners();
    try {
      if (proxyUrl != null) customProxyUrl = proxyUrl.trim();
      if (acceptInvalidTls != null) acceptInvalidCerts = acceptInvalidTls;
      final res = await core.invoke('connect_server', {
        'url': url.trim(),
        'device_name': _platformDeviceName(),
        if (effectiveProxyUrl.isNotEmpty) 'proxy_url': effectiveProxyUrl,
        'accept_invalid_certs': acceptInvalidCerts,
      }) as Map<String, dynamic>;
      if (epoch != _sessionEpoch || _disposed) {
        throw VedroCoreException('连接操作已被新的切换或退出操作取代');
      }
      capabilities = ServerCapabilitiesModel.fromJson(
        res['capabilities'] as Map<String, dynamic>,
      );
      if (res['proxy_addr'] != null) proxyAddr = res['proxy_addr'].toString();
      connectedUrl = url.trim();
      FadeNetworkImage.notifyGlobalRefresh();
      return capabilities!;
    } catch (e) {
      if (epoch == _sessionEpoch) {
        errorMessage = _humanizeError(e.toString());
      }
      rethrow;
    } finally {
      if (epoch == _sessionEpoch) {
        isBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> login(
    String url,
    String user,
    String password, {
    String? proxyUrl,
    bool? acceptInvalidTls,
  }) async {
    errorMessage = null;
    homeError = null;
    loginStage = '正在连接服务器…';
    isBusy = true;
    notifyListeners();
    try {
      await connectServer(
        url,
        proxyUrl: proxyUrl,
        acceptInvalidTls: acceptInvalidTls,
      );
      final epoch = _sessionEpoch;
      loginStage = '正在验证身份…';
      isBusy = true;
      notifyListeners();

      final res = await core.invoke('login', {
        'username': user.trim(),
        'password': password,
      }) as Map<String, dynamic>;
      if (epoch != _sessionEpoch || _disposed) return;
      _applyAuthLoginResult(res);
      await _reloadSavedServers();
      unawaited(refreshHome());
      unawaited(refreshMeQuota());
    } catch (e) {
      errorMessage = _humanizeError(e.toString());
      isBusy = false;
      loginStage = null;
      notifyListeners();
      rethrow;
    }
  }

  void _applyAuthLoginResult(Map<String, dynamic> res) {
    final auth = asJsonMap(res['auth']);
    final userObj = asJsonMap(auth['User']);
    final policyObj = asJsonMapOrNull(userObj['Policy']);
    username = userObj['Name']?.toString();
    userId = userObj['Id']?.toString();
    isAdmin = policyObj?['IsAdministrator'] == true;
    enableContentDownloading = policyObj?['EnableContentDownloading'] == true;
    meQuota = null;
    if (res['capabilities'] is Map<String, dynamic>) {
      capabilities = ServerCapabilitiesModel.fromJson(
        res['capabilities'] as Map<String, dynamic>,
      );
    }
    if (res['proxy_addr'] != null) proxyAddr = res['proxy_addr'].toString();
    activeServerId = capabilities?.serverId.isNotEmpty == true
        ? capabilities!.serverId
        : (auth['ServerId']?.toString() ?? connectedUrl);

    _clearHomeCollections();
    isBusy = false;
    loginStage = null;
    isLoadingHome = true;
    notifyListeners();
    FadeNetworkImage.notifyGlobalRefresh();
    _startEventPolling();
  }

  /// Initiate Jellyfin Quick Connect (returns `{code, secret}` to authorize from another device).
  Future<Map<String, dynamic>> initiateQuickConnect(
    String url, {
    String? proxyUrl,
    bool? acceptInvalidTls,
  }) async {
    await connectServer(url, proxyUrl: proxyUrl, acceptInvalidTls: acceptInvalidTls);
    final res = await core.invoke('quick_connect_initiate');
    return asJsonMap(res);
  }

  /// Poll Jellyfin Quick Connect status; when authorized, finishes sign-in and returns `true`.
  Future<bool> pollQuickConnect(String secret) async {
    final epoch = _sessionEpoch;
    final res = asJsonMap(await core.invoke('quick_connect_check', {'secret': secret}));
    if (epoch != _sessionEpoch || _disposed) return false;
    if (res['authenticated'] == true) {
      _applyAuthLoginResult(res);
      await _reloadSavedServers();
      unawaited(refreshHome());
      unawaited(refreshMeQuota());
      return true;
    }
    return false;
  }

  Future<void> restoreSavedServer(
    SavedServerProfile profile, {
    bool silentError = false,
    bool preserveCachedHome = false,
  }) async {
    if (profile.accessToken == null || profile.userId == null) {
      connectedUrl = profile.url;
      notifyListeners();
      return;
    }
    final epoch = ++_sessionEpoch;
    final prevServerId = activeServerId;
    if (!silentError) errorMessage = null;
    homeError = null;
    if (!preserveCachedHome) {
      loginStage = '正在连接 ${profile.name}…';
      isBusy = true;
      notifyListeners();
    }
    try {
      final route = profile.activeRoute;
      final targetUrl = route?.url.isNotEmpty == true ? route!.url : profile.url;
      final routeProxy = (route?.proxyUrl?.trim().isNotEmpty == true)
          ? route!.proxyUrl!.trim()
          : effectiveProxyUrl;
      final routeTls = route?.acceptInvalidCerts ?? acceptInvalidCerts;

      final res = await core.invoke('restore_session', {
        'server_id': profile.id,
        'url': targetUrl,
        'access_token': profile.accessToken,
        'user_id': profile.userId,
        if (routeProxy.isNotEmpty) 'proxy_url': routeProxy,
        'accept_invalid_certs': routeTls,
      }) as Map<String, dynamic>;
      if (epoch != _sessionEpoch || _disposed) return;

      connectedUrl = targetUrl;
      activeServerId = profile.id;
      if (res['proxy_addr'] != null) proxyAddr = res['proxy_addr'].toString();
      capabilities = ServerCapabilitiesModel.fromJson(
        res['capabilities'] as Map<String, dynamic>,
      );
      final u = res['user'] as Map<String, dynamic>;
      final uPolicy = u['Policy'] as Map<String, dynamic>?;
      username = u['Name']?.toString();
      userId = u['Id']?.toString();
      isAdmin = uPolicy?['IsAdministrator'] == true;
      enableContentDownloading = uPolicy?['EnableContentDownloading'] == true;
      meQuota = null;

      if (!preserveCachedHome || prevServerId != profile.id) {
        _clearHomeCollections();
      }
      isBusy = false;
      loginStage = null;
      isLoadingHome = !hasAnyHomeContent;
      notifyListeners();
      FadeNetworkImage.notifyGlobalRefresh();

      _startEventPolling();
      unawaited(_reloadSavedServers());
      unawaited(refreshHome());
      unawaited(refreshMeQuota());
    } catch (e) {
      if (epoch != _sessionEpoch || _disposed) return;
      final humanized = _humanizeError(e.toString());
      if (silentError) {
        // Keep the remembered server selected even if network/proxy is temporarily unreachable on cold start
        connectedUrl = profile.activeRoute?.url.isNotEmpty == true ? profile.activeRoute!.url : profile.url;
        activeServerId = profile.id;
        userId = profile.userId;
        username = profile.username;
        isAdmin = profile.isAdmin;
        capabilities ??= ServerCapabilitiesModel(
          dialect: profile.dialect,
          serverId: profile.id,
          serverName: profile.name,
          advertisedVersion: '',
          supportsTranscoding: profile.dialect != 'embygo',
          supportsPopular: profile.dialect == 'embygo',
          supportsSuggestions: true,
          supportsHideFromResume: true,
          usesStreamTickets: profile.dialect == 'embygo',
        );
        if (!hasAnyHomeContent) {
          homeError = '无法连接至 ${profile.name}：$humanized';
        }
      } else {
        errorMessage = humanized;
      }
      isBusy = false;
      isLoadingHome = false;
      loginStage = null;
      notifyListeners();
      if (!silentError) rethrow;
    }
  }

  Future<bool> switchToServerById(String serverId) async {
    if (serverId == activeServerId && isSignedIn && homeError == null && hasAnyHomeContent) {
      return true;
    }
    for (final s in savedServers) {
      if (s.id == serverId) {
        await restoreSavedServer(s);
        return true;
      }
    }
    return false;
  }

  Future<void> saveServerRoutes(
    String serverId,
    List<ServerRouteModel> routes, {
    String? activeRouteId,
  }) async {
    await core.invoke('save_server_routes', {
      'server_id': serverId,
      'routes': routes.map((r) => r.toJson()).toList(),
      if (activeRouteId != null) 'active_route_id': activeRouteId,
    });
    await _reloadSavedServers();
  }

  Future<List<Map<String, dynamic>>> testServerRoutes(String serverId) async {
    final res = await core.invoke('test_server_routes', {'server_id': serverId});
    if (res is List) {
      return res.whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  }

  /// Probe all saved servers (or one server) concurrently for online/offline status,
  /// latency, and Movie / Series / Episode inventory counts (`/Items/Counts`).
  Future<void> probeServersStatus({String? serverId, bool force = false}) async {
    if (savedServers.isEmpty) return;
    if (!force &&
        serverId == null &&
        _lastServerProbeAt != null &&
        DateTime.now().difference(_lastServerProbeAt!).inSeconds < 25) {
      return;
    }
    if (isProbingServers && serverId == null) return;
    isProbingServers = true;
    notifyListeners();
    try {
      final res = await core.invoke('probe_servers_status', {
        if (serverId != null) 'server_id': serverId,
      });
      if (res is Map) {
        final next = Map<String, ServerLiveStatus>.from(serverStatuses);
        res.forEach((k, v) {
          if (v is Map) {
            next[k.toString()] = ServerLiveStatus.fromJson(
              k.toString(),
              Map<String, dynamic>.from(v),
            );
          }
        });
        serverStatuses = next;
        if (serverId == null) _lastServerProbeAt = DateTime.now();
      }
    } catch (_) {
    } finally {
      isProbingServers = false;
      notifyListeners();
    }
  }

  Future<void> switchServerRoute(String serverId, String routeId) async {
    final epoch = ++_sessionEpoch;
    errorMessage = null;
    homeError = null;
    isBusy = true;
    loginStage = '正在切换线路…';
    notifyListeners();
    try {
      final res = await core.invoke('switch_server_route', {
        'server_id': serverId,
        'route_id': routeId,
      }) as Map<String, dynamic>;
      if (epoch != _sessionEpoch || _disposed) return;
      if (res['proxy_addr'] != null) proxyAddr = res['proxy_addr'].toString();
      if (res['capabilities'] is Map<String, dynamic>) {
        capabilities = ServerCapabilitiesModel.fromJson(
          res['capabilities'] as Map<String, dynamic>,
        );
      }
      if (res['profile'] is Map<String, dynamic>) {
        final p = SavedServerProfile.fromJson(res['profile'] as Map<String, dynamic>);
        connectedUrl = p.url;
        activeServerId = p.id;
      }
      if (res['user'] is Map<String, dynamic>) {
        final u = res['user'] as Map<String, dynamic>;
        final uPolicy = u['Policy'] as Map<String, dynamic>?;
        username = u['Name']?.toString();
        userId = u['Id']?.toString();
        isAdmin = uPolicy?['IsAdministrator'] == true;
        enableContentDownloading = uPolicy?['EnableContentDownloading'] == true;
      }
      meQuota = null;
      await _reloadSavedServers();
      if (epoch != _sessionEpoch || _disposed) return;
      isBusy = false;
      loginStage = null;
      isLoadingHome = true;
      notifyListeners();
      FadeNetworkImage.notifyGlobalRefresh();
      _startEventPolling();
      unawaited(refreshHome());
      unawaited(refreshMeQuota());
    } catch (e) {
      if (epoch == _sessionEpoch) {
        errorMessage = _humanizeError(e.toString());
        isBusy = false;
        loginStage = null;
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> deleteServer(String serverId) async {
    await core.invoke('delete_server', {'id': serverId});
    if (activeServerId == serverId) {
      await logout();
    }
    await _reloadSavedServers();
  }

  Future<({List<AggregatedSearchHit> hits, List<Map<String, dynamic>> servers})>
      aggregatedSearch(String term, {int limit = 24}) async {
    final res = await core.invoke('aggregated_search', {
      'term': term,
      'limit': limit,
    }) as Map<String, dynamic>;
    if (res['proxy_addr'] != null) {
      proxyAddr = res['proxy_addr'].toString();
    }
    final hits = ((res['items'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AggregatedSearchHit.fromJson)
        .toList();
    final servers = ((res['servers'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    return (hits: hits, servers: servers);
  }

  Future<void> logout() async {
    ++_sessionEpoch;
    ++_speedTestGen;
    _wsPollTimer?.cancel();
    _wsPollTimer = null;
    _speedTestPollTimer?.cancel();
    _speedTestPollTimer = null;
    try {
      await core.invoke('logout');
    } catch (_) {}
    activeServerId = null;
    connectedUrl = null;
    capabilities = null;
    userId = null;
    username = null;
    isAdmin = false;
    enableContentDownloading = false;
    isBusy = false;
    loginStage = null;
    isSpeedTesting = false;
    meQuota = null;
    isLoadingQuota = false;
    isLoadingHome = false;
    homeError = null;
    playlists = [];
    _clearHomeCollections();
    embygoAdminDashboard = null;
    notifyListeners();
  }

  void _clearHomeCollections() {
    views = [];
    popular = [];
    resume = [];
    nextUp = [];
    suggestions = [];
    favorites = [];
    latestByLibrary = const [];
  }

  void _applyHomePayload(Map<String, dynamic> res) {
    if (res['capabilities'] is Map<String, dynamic>) {
      capabilities = ServerCapabilitiesModel.fromJson(
        res['capabilities'] as Map<String, dynamic>,
      );
    }
    views = _parseItems(res['views']);
    popular = _parseItems(res['popular']);
    resume = _parseItems(res['resume']);
    nextUp = _parseItems(res['next_up']);
    suggestions = _parseItems(res['suggestions']);
    favorites = _parseItems(res['favorites']);
    latestByLibrary = ((res['latest_by_library'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<void> refreshHome() async {
    if (!isSignedIn) return;
    final epoch = _sessionEpoch;
    if (!hasAnyHomeContent) {
      isLoadingHome = true;
      homeError = null;
      notifyListeners();
    }
    try {
      final wantSuggestions = homeSections.any((s) => s.id == 'suggestions' && s.visible);
      final wantFavorites = homeSections.any((s) => s.id == 'favorites' && s.visible);
      Map<String, dynamic> res;
      try {
        res = await core.invoke('get_home', {
          'include_suggestions': wantSuggestions,
          'include_favorites': wantFavorites,
        }) as Map<String, dynamic>;
      } catch (firstErr) {
        // Automatic self-healing if Rust core had not yet finished attaching the active server
        final msg = firstErr.toString().toLowerCase();
        if (msg.contains('no server connected') && activeServerId != null) {
          final match = savedServers.where((s) => s.id == activeServerId).firstOrNull;
          if (match != null && match.accessToken != null && match.userId != null) {
            final route = match.activeRoute;
            final targetUrl = route?.url.isNotEmpty == true ? route!.url : match.url;
            final routeProxy = (route?.proxyUrl?.trim().isNotEmpty == true)
                ? route!.proxyUrl!.trim()
                : effectiveProxyUrl;
            await core.invoke('restore_session', {
              'server_id': match.id,
              'url': targetUrl,
              'access_token': match.accessToken,
              'user_id': match.userId,
              if (routeProxy.isNotEmpty) 'proxy_url': routeProxy,
              'accept_invalid_certs': route?.acceptInvalidCerts ?? acceptInvalidCerts,
            });
            res = await core.invoke('get_home', {
              'include_suggestions': wantSuggestions,
              'include_favorites': wantFavorites,
            }) as Map<String, dynamic>;
          } else {
            rethrow;
          }
        } else {
          rethrow;
        }
      }
      if (epoch != _sessionEpoch || _disposed) return;
      _applyHomePayload(res);
      homeError = null;
      FadeNetworkImage.notifyGlobalRefresh();
    } catch (e) {
      if (epoch == _sessionEpoch && !hasAnyHomeContent) {
        homeError = _humanizeError(e.toString());
      }
    } finally {
      if (epoch == _sessionEpoch) {
        isLoadingHome = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshPlaylists() async {
    if (!isSignedIn) {
      playlists = [];
      notifyListeners();
      return;
    }
    final epoch = _sessionEpoch;
    final res = await core.invoke('list_playlists') as Map<String, dynamic>;
    if (epoch != _sessionEpoch || _disposed) return;
    playlists = _parseItems(res['Items']);
    notifyListeners();
  }

  Future<void> hideFromResume(String itemId) async {
    await core.invoke('hide_from_resume', {'item_id': itemId, 'hide': true});
    resume.removeWhere((i) => i.id == itemId);
    notifyListeners();
  }

  Future<void> toggleFavorite(MediaItemModel item) async {
    await core.invoke('set_favorite', {'item_id': item.id, 'favorite': !item.isFavorite});
    unawaited(refreshHome());
  }

  Future<void> togglePlayed(MediaItemModel item) async {
    await core.invoke('set_played', {'item_id': item.id, 'played': !item.played});
    unawaited(refreshHome());
  }

  /// Fetch Next Up episode(s) for a specific Series so DetailScreen auto-selects the right season.
  Future<MediaItemModel?> getNextUpForSeries(String seriesId) async {
    if (!isSignedIn || seriesId.isEmpty) return null;
    try {
      final res = await core.invoke('get_next_up_for_series', {'series_id': seriesId});
      if (res is Map<String, dynamic>) {
        final items = _parseItems(res['Items']);
        if (items.isNotEmpty) return items.first;
      }
    } catch (_) {}
    return null;
  }

  /// Per-series / per-item remembered audio & subtitle track selection (`track_preferences` table).
  Future<({String? audioLang, String? subtitleLang, int? audioIndex, int? subtitleIndex})?>
      getTrackPreference(String seriesOrItemId) async {
    if (seriesOrItemId.isEmpty) return null;
    try {
      final res = await core.invoke('get_track_preference', {
        'scope_id': seriesOrItemId,
        'series_or_item_id': seriesOrItemId,
      });
      if (res is Map<String, dynamic>) {
        final rawPref = res['preference'];
        final data = rawPref is Map
            ? Map<String, dynamic>.from(rawPref)
            : (res.containsKey('audio_lang') || res.containsKey('subtitle_lang') ? res : null);
        if (data == null) return null;
        final subDisabled = data['subtitle_disabled'] == true;
        return (
          audioLang: data['audio_lang']?.toString(),
          subtitleLang: subDisabled ? 'off' : data['subtitle_lang']?.toString(),
          audioIndex: asJsonInt(data['audio_index']),
          subtitleIndex: asJsonInt(data['subtitle_index']),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<void> setTrackPreference(
    String seriesOrItemId, {
    String? audioLang,
    String? subtitleLang,
    int? audioIndex,
    int? subtitleIndex,
  }) async {
    if (seriesOrItemId.isEmpty || prefs.incognitoMode) return;
    try {
      await core.invoke('set_track_preference', {
        'scope_id': seriesOrItemId,
        'series_or_item_id': seriesOrItemId,
        if (audioLang != null) 'audio_lang': audioLang,
        if (subtitleLang != null) 'subtitle_lang': subtitleLang == 'off' ? '' : subtitleLang,
        if (subtitleLang != null) 'subtitle_disabled': subtitleLang == 'off',
        if (audioIndex != null) 'audio_index': audioIndex,
        if (subtitleIndex != null) 'subtitle_index': subtitleIndex,
      });
    } catch (_) {}
  }

  Future<void> loadEmbyGoAdminDashboard() async {
    if (!isAdmin || !isSignedIn) return;
    final epoch = _sessionEpoch;
    final res = await core.invoke('get_embygo_admin_dashboard') as Map<String, dynamic>;
    if (epoch != _sessionEpoch || _disposed) return;
    embygoAdminDashboard = res;
    notifyListeners();
  }

  Future<void> triggerLibraryRefresh() async {
    await core.invoke('trigger_library_refresh');
    await loadEmbyGoAdminDashboard();
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

  /// Persistent local SQLite cache for AI subtitle translations so rewatching or resuming
  /// never re-queries public translation endpoints.
  Future<Map<int, String>> loadAiTranslationCache(String cacheKey) async {
    if (cacheKey.isEmpty) return const {};
    try {
      final kv = await core.invoke('get_kv', {'key': 'ai_sub_cache_v1:$cacheKey'});
      if (kv is Map<String, dynamic> && kv['value'] is Map) {
        final out = <int, String>{};
        (kv['value'] as Map).forEach((k, v) {
          final idx = int.tryParse(k.toString());
          final txt = v?.toString() ?? '';
          if (idx != null && txt.isNotEmpty) {
            out[idx] = txt;
          }
        });
        return out;
      }
    } catch (_) {}
    return const {};
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

  Future<void> saveAiTranslationCache(String cacheKey, Map<int, String> translations) async {
    if (cacheKey.isEmpty || translations.isEmpty) return;
    try {
      final serialized = <String, String>{};
      var count = 0;
      for (final entry in translations.entries) {
        if (count >= 10000) break;
        if (entry.value.isNotEmpty) {
          serialized['${entry.key}'] = entry.value;
          count++;
        }
      }
      await core.invoke('set_kv', {
        'key': 'ai_sub_cache_v1:$cacheKey',
        'value': serialized,
      });
    } catch (_) {}
  }

  Future<void> _persistDownloads() async {
    try {
      await core.invoke('set_kv', {
        'key': 'downloads_queue',
        'value': downloads.map((d) => d.toJson()).toList(),
      });
    } catch (_) {}
  }

  String get downloadsDirectoryPath {
    if (prefs.downloadCustomDir.trim().isNotEmpty) {
      return prefs.downloadCustomDir.trim();
    }
    return '${_supportDirPath ?? Directory.systemTemp.path}/vedro_downloads';
  }

  String get fontsDirectoryPath =>
      '${_supportDirPath ?? Directory.systemTemp.path}/vedro_fonts';

  /// Account-level download eligibility.
  /// On EmbyGo, honors `meQuota.limits.allowDownloads` (which accounts for admin, server download-quota,
  /// and `EnableContentDownloading`). On standard Emby/Jellyfin, honors `User.Policy.EnableContentDownloading`.
  bool get canDownloadAccount {
    if (!isSignedIn) return false;
    if (meQuota != null) return meQuota!.limits.allowDownloads;
    return enableContentDownloading || (capabilities?.isEmbyGo == true && isAdmin);
  }

  /// Strict item-level download permission check.
  /// Always hides download controls when the user lacks permission on Emby, Jellyfin, or EmbyGo.
  bool canDownloadItem(MediaItemModel? item) {
    if (!isSignedIn || item == null) return false;
    if (item.canDownload != null) return item.canDownload!;
    if (!item.isPlayable) return false;
    return canDownloadAccount;
  }

  Future<void> refreshMeQuota() async {
    if (!isSignedIn) {
      meQuota = null;
      isLoadingQuota = false;
      notifyListeners();
      return;
    }
    final epoch = _sessionEpoch;
    isLoadingQuota = true;
    notifyListeners();
    try {
      final res = await core.invoke('get_me_quota');
      if (epoch != _sessionEpoch || _disposed) return;
      if (res is Map<String, dynamic> && res.containsKey('limits')) {
        meQuota = MeQuotaModel.fromJson(res);
      } else {
        meQuota = null;
      }
    } catch (_) {
      // Standard Emby / Jellyfin servers do not expose `/emby-compat/me/quota`.
    } finally {
      if (epoch == _sessionEpoch) {
        isLoadingQuota = false;
        notifyListeners();
      }
    }
  }

  int get effectiveDownloadConcurrency {
    final localMax = prefs.downloadMaxConcurrent.clamp(1, 5);
    final dq = meQuota?.downloadQuota;
    if (dq != null && dq.enabled && !dq.adminExempt && dq.maxConcurrentDownloads > 0) {
      return localMax < dq.maxConcurrentDownloads ? localMax : dq.maxConcurrentDownloads;
    }
    return localMax;
  }

  Future<void> enqueueDownload(
    MediaItemModel item, {
    String? mediaSourceId,
    String? versionLabel,
    int? expectedBytes,
  }) async {
    await enqueueBatchDownloads([
      (
        item: item,
        mediaSourceId: mediaSourceId,
        versionLabel: versionLabel,
        expectedBytes: expectedBytes,
      ),
    ]);
  }

  /// Enqueue one or more episodes/versions cleanly into the resumable, concurrency-bounded download queue.
  Future<int> enqueueBatchDownloads(
    List<({MediaItemModel item, String? mediaSourceId, String? versionLabel, int? expectedBytes})>
        requests,
  ) async {
    if (requests.isEmpty) return 0;
    for (final req in requests) {
      if (!canDownloadItem(req.item)) {
        throw Exception('当前账号未开放下载权限，请联系管理员');
      }
    }

    final dq = meQuota?.downloadQuota;
    if (dq != null && dq.enabled && !dq.adminExempt) {
      final totalNeeded = requests.fold<int>(0, (sum, r) => sum + (r.expectedBytes ?? 0));
      if (totalNeeded > 0 && !dq.canFitBytes(totalNeeded)) {
        throw Exception(
          '下载流量包余额不足：当前剩余 ${fmtQuotaBytes(dq.totalRemainingBytes)}，所选文件共需 ${fmtQuotaBytes(totalNeeded)}（仅限原文件下载，在线播放不限流量）',
        );
      }
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    var added = 0;
    for (var i = 0; i < requests.length; i++) {
      final req = requests[i];
      final dupIdx = downloads.indexWhere((d) =>
          d.itemId == req.item.id &&
          (req.mediaSourceId == null ||
              d.mediaSourceId == null ||
              d.mediaSourceId == req.mediaSourceId) &&
          (d.status == 'downloading' || d.status == 'queued' || d.status == 'completed'));
      if (dupIdx >= 0) continue;

      final taskId = '${req.item.id}_${nowMs}_$i';
      downloads.insert(
        added,
        DownloadTaskModel(
          id: taskId,
          itemId: req.item.id,
          title: req.item.cardTitle,
          subtitle: req.item.cardSubtitle,
          mediaSourceId: req.mediaSourceId,
          versionLabel: req.versionLabel ?? '',
          totalBytes: req.expectedBytes ?? 0,
          status: 'queued',
          createdAt: nowMs + i,
        ),
      );
      added++;
    }
    if (added == 0) return 0;
    notifyListeners();
    await _persistDownloads();
    _pumpDownloadQueue();
    return added;
  }

  void pauseDownload(String taskId) {
    final handle = _activeDownloadHandles[taskId];
    if (handle != null) {
      handle.paused = true;
      handle.abort();
    }
    _replaceDownload(
      taskId,
      (d) => d.copyWith(status: 'paused', speedBytesPerSec: 0, clearError: true),
    );
    unawaited(_persistDownloads());
    _pumpDownloadQueue();
  }

  void resumeDownload(String taskId) {
    final idx = downloads.indexWhere((d) => d.id == taskId);
    if (idx < 0) return;
    final task = downloads[idx];
    if (task.status == 'downloading' || task.status == 'completed') return;
    downloads[idx] = task.copyWith(
      status: 'queued',
      speedBytesPerSec: 0,
      retryCount: 0,
      clearError: true,
    );
    notifyListeners();
    unawaited(_persistDownloads());
    _pumpDownloadQueue();
  }

  void pauseAllDownloads() {
    for (final d in List<DownloadTaskModel>.from(downloads)) {
      if (d.status == 'downloading' || d.status == 'queued') {
        pauseDownload(d.id);
      }
    }
  }

  void resumeAllDownloads() {
    var changed = false;
    for (var i = 0; i < downloads.length; i++) {
      final d = downloads[i];
      if (d.status == 'paused' || d.status == 'failed') {
        downloads[i] = d.copyWith(
          status: 'queued',
          speedBytesPerSec: 0,
          retryCount: 0,
          clearError: true,
        );
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      unawaited(_persistDownloads());
      _pumpDownloadQueue();
    }
  }

  void _pumpDownloadQueue() {
    final maxConcurrent = effectiveDownloadConcurrency;
    while (_activeDownloadHandles.length < maxConcurrent) {
      // Pick oldest queued task (so multi-episode downloads progress E01 -> E02 -> E03 in order)
      DownloadTaskModel? nextTask;
      for (final d in downloads.reversed) {
        if (d.status == 'queued' && !_activeDownloadHandles.containsKey(d.id)) {
          nextTask = d;
          break;
        }
      }
      if (nextTask == null) break;
      final handle = _ActiveDownloadHandle();
      _activeDownloadHandles[nextTask.id] = handle;
      unawaited(_runResumableDownload(nextTask.id, handle));
    }
  }

  Future<void> _runResumableDownload(String taskId, _ActiveDownloadHandle handle) async {
    const maxAttempts = 8;
    Timer? inFlightRefreshTimer;

    try {
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        if (handle.paused || handle.cancelled) return;
        final currentIdx = downloads.indexWhere((d) => d.id == taskId);
        if (currentIdx < 0) return;
        final task = downloads[currentIdx];

        if (prefs.downloadWifiOnly) {
          final wifi = await NativePlaybackChannel.isWifiConnected();
          if (!wifi) {
            _replaceDownload(
              taskId,
              (d) => d.copyWith(
                status: 'paused',
                speedBytesPerSec: 0,
                error: '等待 Wi-Fi 连接（可在设置中关闭仅 Wi-Fi 下载）',
              ),
            );
            await _persistDownloads();
            return;
          }
        }

        _replaceDownload(
          taskId,
          (d) => d.copyWith(
            status: 'downloading',
            retryCount: attempt,
            error: attempt > 0 ? '断流自动断点续传中（第 $attempt 次重试）…' : null,
            clearError: attempt == 0,
          ),
        );

        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 20);
        handle.client = client;

        try {
          final prep = await core.invoke('prepare_download', {
            'item_id': task.itemId,
            if (task.mediaSourceId != null && task.mediaSourceId!.isNotEmpty)
              'media_source_id': task.mediaSourceId,
          }) as Map<String, dynamic>;

          if (handle.paused || handle.cancelled) return;

          final initialUrlStr = (prep['url'] ?? '').toString();
          if (initialUrlStr.isEmpty) {
            throw const _PermanentDownloadError('无法获取原文件下载地址');
          }
          final rawHeaders = (prep['headers'] as Map?)?.map(
                (k, v) => MapEntry(k.toString(), v.toString()),
              ) ??
              const <String, String>{};
          final rawExt = (prep['container']?.toString().trim().isNotEmpty == true)
              ? prep['container'].toString().trim().replaceFirst(RegExp(r'^\.'), '')
              : 'mkv';
          final ext = rawExt.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '').toLowerCase();
          final safeExt = ext.isEmpty ? 'mkv' : ext;
          final safeItemId = task.itemId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]+'), '_');
          final rawFilename = prep['filename']?.toString().trim() ?? '';
          final fallbackSize = (prep['size'] as num?)?.toInt() ?? task.totalBytes;
          final proxyUrl = prep['proxy_url']?.toString().trim() ?? '';
          final acceptInvalid = prep['accept_invalid_certs'] == true;

          final initialUri = Uri.parse(initialUrlStr);
          if (!NativePlaybackChannel.isAllowedHttpUrl(initialUrlStr)) {
            throw const _PermanentDownloadError('下载地址协议不安全，已拒绝');
          }
          final initialHost = initialUri.host.toLowerCase();
          if (acceptInvalid && initialHost.isNotEmpty) {
            client.badCertificateCallback =
                (_, host, __) => host.toLowerCase() == initialHost;
          }
          if (proxyUrl.isNotEmpty) {
            final parsedProxy = Uri.tryParse(proxyUrl);
            if (parsedProxy != null && parsedProxy.host.isNotEmpty && parsedProxy.port > 0) {
              final proxySpec = 'PROXY ${parsedProxy.host}:${parsedProxy.port}';
              client.findProxy = (_) => proxySpec;
            }
          }

          // Determine stable final path & `.part` resume path BEFORE issuing HTTP request
          final dir = Directory(downloadsDirectoryPath);
          if (!await dir.exists()) await dir.create(recursive: true);

          String outPath = task.filePath;
          if (outPath.isEmpty || !_isPathInsideDirectory(outPath, dir.path)) {
            final baseName = rawFilename.isNotEmpty
                ? rawFilename
                : '${task.title}${task.subtitle.isNotEmpty ? ' - ${task.subtitle}' : ''}${task.versionLabel.isNotEmpty ? ' [${task.versionLabel}]' : ''}.$safeExt';
            final safeName = _sanitizeDownloadFileName(
              baseName,
              fallback: '${safeItemId.isEmpty ? 'media' : safeItemId}.$safeExt',
            );
            outPath = '${dir.path}/$safeName';
            _replaceDownload(taskId, (d) => d.copyWith(filePath: outPath));
          }

          final partFile = File('$outPath.part');
          var offset = partFile.existsSync() ? partFile.lengthSync() : 0;
          if (fallbackSize > 0 && offset == fallbackSize) {
            // Already completely on disk from previous interrupted rename
            if (File(outPath).existsSync()) File(outPath).deleteSync();
            partFile.renameSync(outPath);
            _replaceDownload(
              taskId,
              (d) => d.copyWith(
                filePath: outPath,
                totalBytes: fallbackSize,
                downloadedBytes: fallbackSize,
                speedBytesPerSec: 0,
                status: 'completed',
                clearError: true,
              ),
            );
            await _persistDownloads();
            return;
          }

          var currentUri = initialUri;
          final initialOrigin = '${currentUri.scheme}://${currentUri.authority}';
          final initialIsPrivate = _isPrivateOrLoopbackHost(initialUri.host);
          HttpClientResponse? resp;

          for (var hop = 0; hop < 6; hop++) {
            if (handle.paused || handle.cancelled) return;
            final req = await client.getUrl(currentUri);
            req.followRedirects = false;
            final sameOrigin = '${currentUri.scheme}://${currentUri.authority}' == initialOrigin;
            rawHeaders.forEach((k, v) {
              final lower = k.toLowerCase();
              final isAuthHeader = lower == 'authorization' ||
                  lower == 'x-emby-authorization' ||
                  lower == 'x-emby-token' ||
                  lower == 'x-mediabrowser-token';
              if (sameOrigin || !isAuthHeader) {
                req.headers.set(k, v);
              }
            });
            if (offset > 0) {
              req.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
              if (task.etag != null && task.etag!.isNotEmpty) {
                req.headers.set('If-Range', task.etag!);
              }
            }
            final r = await req.close().timeout(const Duration(seconds: 25));
            if (r.statusCode == 301 ||
                r.statusCode == 302 ||
                r.statusCode == 303 ||
                r.statusCode == 307 ||
                r.statusCode == 308) {
              final loc = r.headers.value(HttpHeaders.locationHeader);
              await r.drain<void>();
              if (loc == null || loc.isEmpty) {
                throw const _PermanentDownloadError('下载重定向地址无效');
              }
              final nextUri = currentUri.resolve(loc);
              final nextScheme = nextUri.scheme.toLowerCase();
              if (nextScheme != 'http' && nextScheme != 'https') {
                throw const _PermanentDownloadError('下载重定向协议不安全，已拦截');
              }
              if (!initialIsPrivate && _isPrivateOrLoopbackHost(nextUri.host)) {
                throw const _PermanentDownloadError('下载重定向至内网地址，已拦截');
              }
              currentUri = nextUri;
              continue;
            }
            resp = r;
            break;
          }

          if (resp == null) {
            throw const _PermanentDownloadError('下载重定向次数过多');
          }

          if (resp.statusCode == 416) {
            await resp.drain<void>();
            if (fallbackSize > 0 && offset >= fallbackSize) {
              if (File(outPath).existsSync()) File(outPath).deleteSync();
              partFile.renameSync(outPath);
              _replaceDownload(
                taskId,
                (d) => d.copyWith(
                  filePath: outPath,
                  totalBytes: offset,
                  downloadedBytes: offset,
                  speedBytesPerSec: 0,
                  status: 'completed',
                  clearError: true,
                ),
              );
              await _persistDownloads();
              return;
            }
            if (partFile.existsSync()) partFile.deleteSync();
            throw const _TransientDownloadError('断点偏移失效，正在重新下载');
          }

          if (resp.statusCode < 200 || resp.statusCode >= 300) {
            final quotaErr = resp.headers.value('x-embygo-quota-error')?.trim() ?? '';
            final bodyBytes = <int>[];
            await for (final chunk in resp.timeout(const Duration(seconds: 10))) {
              if (bodyBytes.length < 64 * 1024) {
                final take = (64 * 1024) - bodyBytes.length;
                bodyBytes.addAll(chunk.length <= take ? chunk : chunk.sublist(0, take));
              } else {
                break;
              }
            }
            final bodyStr = utf8.decode(bodyBytes, allowMalformed: true).trim();
            String serverMsg = '';
            if (bodyStr.startsWith('{')) {
              try {
                final parsed = jsonDecode(bodyStr);
                if (parsed is Map && parsed['Message'] != null) {
                  serverMsg = parsed['Message'].toString().trim();
                }
              } catch (_) {}
            }
            final msg = _formatDownloadHttpError(resp.statusCode, quotaErr, serverMsg);
            // 401/403/404 are non-retryable permission/quota errors; 429/5xx are transient
            if (resp.statusCode == 429 || resp.statusCode >= 500) {
              final retryAfter = int.tryParse(resp.headers.value('retry-after') ?? '');
              throw _TransientDownloadError(msg, retryAfterSecs: retryAfter);
            }
            throw _PermanentDownloadError(msg);
          }

          // Refine filename from Content-Disposition only when starting fresh at offset 0
          if (offset == 0 && task.filePath.isEmpty) {
            final cdFilename = _parseContentDispositionFilename(
              resp.headers.value('content-disposition'),
            );
            if (cdFilename.isNotEmpty) {
              final safeCd = _sanitizeDownloadFileName(cdFilename, fallback: '');
              if (safeCd.isNotEmpty) {
                final candidate = '${dir.path}/$safeCd';
                if (_isPathInsideDirectory(candidate, dir.path)) {
                  outPath = candidate;
                  _replaceDownload(taskId, (d) => d.copyWith(filePath: outPath));
                }
              }
            }
          }

          final activePartFile = File('$outPath.part');
          final respEtag = resp.headers.value(HttpHeaders.etagHeader)?.trim();
          final contentRange = resp.headers.value(HttpHeaders.contentRangeHeader);
          final isPartial = resp.statusCode == 206 && offset > 0;

          int expectedTotal = fallbackSize;
          FileMode writeMode = FileMode.write;
          var received = 0;

          if (isPartial) {
            final parsedRange = _parseContentRange(contentRange);
            if (parsedRange != null && parsedRange.start == offset) {
              writeMode = FileMode.append;
              received = offset;
              if (parsedRange.total > 0) expectedTotal = parsedRange.total;
            } else if (resp.contentLength > 0) {
              writeMode = FileMode.append;
              received = offset;
              expectedTotal = offset + resp.contentLength;
            } else {
              offset = 0;
              received = 0;
              writeMode = FileMode.write;
            }
          } else {
            offset = 0;
            received = 0;
            writeMode = FileMode.write;
            if (resp.contentLength > 0) expectedTotal = resp.contentLength;
          }

          _replaceDownload(
            taskId,
            (d) => d.copyWith(
              filePath: outPath,
              etag: respEtag ?? d.etag,
              totalBytes: expectedTotal,
              downloadedBytes: received,
              status: 'downloading',
              clearError: true,
            ),
          );

          inFlightRefreshTimer?.cancel();
          inFlightRefreshTimer = Timer(const Duration(milliseconds: 650), () {
            if (!_disposed) unawaited(refreshMeQuota());
          });

          final sink = activePartFile.openWrite(mode: writeMode);
          var lastEmit = DateTime.now();
          var lastEmitBytes = received;
          var bytesSinceFlush = 0;

          try {
            await for (final chunk in resp.timeout(const Duration(seconds: 25))) {
              if (handle.paused || handle.cancelled) break;
              sink.add(chunk);
              received += chunk.length;
              bytesSinceFlush += chunk.length;
              // Periodic flush applies backpressure so gigabit downloads never balloon RAM
              if (bytesSinceFlush >= 1024 * 1024) {
                bytesSinceFlush = 0;
                await sink.flush();
              }
              final now = DateTime.now();
              final elapsedMs = now.difference(lastEmit).inMilliseconds;
              if (elapsedMs >= 400) {
                final deltaBytes = received - lastEmitBytes;
                final speed = elapsedMs > 0 ? ((deltaBytes * 1000) ~/ elapsedMs) : 0;
                lastEmit = now;
                lastEmitBytes = received;
                _replaceDownload(
                  taskId,
                  (d) => d.copyWith(
                    filePath: outPath,
                    totalBytes: expectedTotal,
                    downloadedBytes: received,
                    speedBytesPerSec: speed,
                    status: 'downloading',
                    clearError: true,
                  ),
                  tickOnly: true,
                );
              }
            }
            await sink.flush();
            await sink.close();
          } catch (streamErr) {
            try {
              await sink.flush();
              await sink.close();
            } catch (_) {}
            if (handle.paused || handle.cancelled) return;
            _replaceDownload(
              taskId,
              (d) => d.copyWith(downloadedBytes: received, speedBytesPerSec: 0),
            );
            throw _TransientDownloadError('连接中断，准备断点续传：$streamErr');
          }

          if (handle.paused || handle.cancelled) {
            _replaceDownload(
              taskId,
              (d) => d.copyWith(
                downloadedBytes: received,
                speedBytesPerSec: 0,
                // Don't clobber `'queued'` if user paused and immediately clicked resume while worker exited!
                status: handle.paused && d.status == 'downloading' ? 'paused' : d.status,
              ),
            );
            await _persistDownloads();
            return;
          }

          // Strict integrity verification: NEVER mark a truncated half-downloaded file as completed!
          if (expectedTotal > 0 && received < expectedTotal) {
            _replaceDownload(
              taskId,
              (d) => d.copyWith(downloadedBytes: received, speedBytesPerSec: 0),
            );
            throw _TransientDownloadError(
              '连接提前断开（已传 ${fmtFileSize(received)} / ${fmtFileSize(expectedTotal)}），正在断点续传…',
            );
          }

          if (File(outPath).existsSync()) {
            try {
              File(outPath).deleteSync();
            } catch (_) {}
          }
          if (activePartFile.existsSync()) {
            activePartFile.renameSync(outPath);
          }

          _replaceDownload(
            taskId,
            (d) => d.copyWith(
              filePath: outPath,
              totalBytes: expectedTotal > 0 ? expectedTotal : received,
              downloadedBytes: received,
              speedBytesPerSec: 0,
              status: 'completed',
              clearError: true,
            ),
          );
          await _persistDownloads();
          return;
        } on _PermanentDownloadError catch (e) {
          _replaceDownload(
            taskId,
            (d) => d.copyWith(
              status: 'failed',
              speedBytesPerSec: 0,
              error: e.message,
            ),
          );
          await _persistDownloads();
          return;
        } catch (e) {
          if (handle.paused || handle.cancelled) return;
          final msg = e is _TransientDownloadError
              ? e.message
              : e.toString().replaceFirst('Exception: ', '');
          if (attempt + 1 >= maxAttempts) {
            _replaceDownload(
              taskId,
              (d) => d.copyWith(
                status: 'failed',
                speedBytesPerSec: 0,
                error: '已自动续传 $maxAttempts 次仍中断：$msg（已保留进度，可点击继续）',
              ),
            );
            await _persistDownloads();
            return;
          }
          final waitSecs = e is _TransientDownloadError && e.retryAfterSecs != null
              ? e.retryAfterSecs!.clamp(2, 30)
              : [2, 4, 6, 10, 15, 20, 25][attempt.clamp(0, 6)];
          _replaceDownload(
            taskId,
            (d) => d.copyWith(
              status: 'downloading',
              speedBytesPerSec: 0,
              retryCount: attempt + 1,
              error: '连接中断，${waitSecs}s 后断点续传（第 ${attempt + 1}/$maxAttempts 次）',
            ),
          );
          await _persistDownloads();
          await Future.any<void>([
            Future<void>.delayed(Duration(seconds: waitSecs)),
            handle.cancelSignal.future,
          ]);
        } finally {
          inFlightRefreshTimer?.cancel();
          handle.client = null;
          client.close(force: true);
        }
      }
    } finally {
      inFlightRefreshTimer?.cancel();
      if (_activeDownloadHandles[taskId] == handle) {
        _activeDownloadHandles.remove(taskId);
      }
      if (!handle.done.isCompleted) {
        handle.done.complete();
      }
      if (!_disposed) {
        unawaited(refreshMeQuota());
        _quotaRefreshTimer?.cancel();
        _quotaRefreshTimer = Timer(const Duration(seconds: 2), () {
          if (!_disposed) unawaited(refreshMeQuota());
        });
        _pumpDownloadQueue();
      }
    }
  }

  static String _sanitizeDownloadFileName(String raw, {required String fallback}) {
    final base = raw
        .replaceAll('\\', '/')
        .split('/')
        .last
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fff\-_. ()\[\]]+'), '_')
        .replaceAll('..', '_')
        .replaceAll(RegExp(r'^\.+'), '')
        .trim();
    if (base.isEmpty || base == '.' || base == '..') return fallback;
    return base.length > 180 ? base.substring(0, 180) : base;
  }

  static bool _isPathInsideDirectory(String targetPath, String baseDir) {
    try {
      final normBase = Directory(baseDir).absolute.path.replaceAll('\\', '/');
      final cleanBase = normBase.endsWith('/') ? normBase : '$normBase/';
      final normTarget = File(targetPath).absolute.path.replaceAll('\\', '/');
      if (normTarget.contains('/../') || normTarget.endsWith('/..')) return false;
      return normTarget.startsWith(cleanBase);
    } catch (_) {
      return false;
    }
  }

  static bool _isPrivateOrLoopbackHost(String host) {
    final h = host.trim().toLowerCase().replaceAll(RegExp(r'^\[|\]$'), '');
    if (h.isEmpty || h == 'localhost' || h.endsWith('.local')) return true;
    final ip = InternetAddress.tryParse(h);
    if (ip == null) return false;
    if (ip.isLoopback || ip.isLinkLocal || ip.isMulticast) return true;
    final b = ip.rawAddress;
    if (ip.type == InternetAddressType.IPv4 && b.length == 4) {
      if (b[0] == 10 || b[0] == 0 || b[0] == 127) return true;
      if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true;
      if (b[0] == 192 && b[1] == 168) return true;
      if (b[0] == 169 && b[1] == 254) return true;
      if (b[0] == 100 && b[1] >= 64 && b[1] <= 127) return true;
    }
    if (ip.type == InternetAddressType.IPv6 && b.length == 16) {
      if ((b[0] & 0xFE) == 0xFC) return true; // fc00::/7 ULA
    }
    return false;
  }

  static ({int start, int end, int total})? _parseContentRange(String? header) {
    if (header == null || header.isEmpty) return null;
    final m = RegExp(r'bytes\s+(\d+)-(\d+)/(\d+|\*)', caseSensitive: false).firstMatch(header);
    if (m == null) return null;
    final start = int.tryParse(m.group(1)!) ?? -1;
    final end = int.tryParse(m.group(2)!) ?? -1;
    final total = m.group(3) == '*' ? 0 : (int.tryParse(m.group(3)!) ?? 0);
    if (start < 0 || end < start) return null;
    return (start: start, end: end, total: total);
  }

  static String _formatDownloadHttpError(int status, String quotaErr, String serverMsg) {
    switch (quotaErr) {
      case 'insufficient_download_quota':
        return serverMsg.isNotEmpty
            ? serverMsg
            : '下载流量包余额不足（仅限原文件下载，在线播放不限流量）';
      case 'too_many_concurrent_downloads':
        return serverMsg.isNotEmpty
            ? serverMsg
            : '同时下载任务数已达上限，请等待当前下载完成后再试';
      case 'telegram_binding_required':
        return serverMsg.isNotEmpty
            ? serverMsg
            : '请先绑定 Telegram 账号后再使用共享下载流量包';
    }
    if (serverMsg.isNotEmpty) return serverMsg;
    if (status == 403) return '当前账号无下载权限，请联系管理员';
    if (status == 429) return '下载并发数已达上限，请稍后再试';
    if (status == 503) return '无法核验下载流量额度，请稍后重试';
    return '下载失败 (HTTP $status)';
  }

  static String _parseContentDispositionFilename(String? header) {
    if (header == null || header.isEmpty) return '';
    final star = RegExp(r"filename\*=UTF-8''([^;\r\n]+)", caseSensitive: false).firstMatch(header);
    if (star != null) {
      try {
        return Uri.decodeComponent(star.group(1)!.trim());
      } catch (_) {}
    }
    final quoted = RegExp(r'filename="([^"]+)"', caseSensitive: false).firstMatch(header);
    if (quoted != null) return quoted.group(1)!.trim();
    final plain = RegExp(r'filename=([^;\r\n]+)', caseSensitive: false).firstMatch(header);
    if (plain != null) return plain.group(1)!.trim();
    return '';
  }

  void _replaceDownload(
    String id,
    DownloadTaskModel Function(DownloadTaskModel) transform, {
    bool tickOnly = false,
  }) {
    final idx = downloads.indexWhere((d) => d.id == id);
    if (idx >= 0) {
      downloads[idx] = transform(downloads[idx]);
      if (!_disposed) {
        downloadsTickNotifier.value = downloadsTickNotifier.value + 1;
        if (!tickOnly) {
          notifyListeners();
        }
      }
    }
  }

  Future<void> deleteDownload(String taskId, {bool deleteFile = true}) async {
    final handle = _activeDownloadHandles.remove(taskId);
    if (handle != null) {
      handle.cancelled = true;
      handle.abort();
      try {
        await handle.done.future.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    final idx = downloads.indexWhere((d) => d.id == taskId);
    if (idx < 0) return;
    final task = downloads.removeAt(idx);
    if (deleteFile && task.filePath.isNotEmpty) {
      for (final p in [task.filePath, '${task.filePath}.part']) {
        if (!_isPathInsideDirectory(p, downloadsDirectoryPath)) continue;
        try {
          final f = File(p);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }
    notifyListeners();
    await _persistDownloads();
    _pumpDownloadQueue();
  }

  Future<String> importSubtitleFont(String sourcePath) async {
    final src = File(sourcePath.trim());
    if (!src.existsSync()) {
      throw Exception('找不到字体文件：$sourcePath');
    }
    final dir = Directory(fontsDirectoryPath);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final rawName = src.uri.pathSegments.isNotEmpty ? src.uri.pathSegments.last : 'font.ttf';
    final fileName = _sanitizeDownloadFileName(rawName, fallback: 'font_${DateTime.now().millisecondsSinceEpoch}.ttf');
    final dest = '${dir.path}/$fileName';
    if (!_isPathInsideDirectory(dest, dir.path)) {
      throw Exception('字体文件名非法');
    }
    await src.copy(dest);
    final next = <String>{...prefs.customFontPaths, dest}.toList();
    final stem = fileName.replaceAll(RegExp(r'\.(ttf|otf|ttc)$', caseSensitive: false), '');
    await updatePrefs(prefs.copyWith(
      customFontPaths: next,
      subtitleFontFamily: stem,
    ));
    return stem;
  }

  Future<void> removeSubtitleFont(String fontPath) async {
    try {
      final fontsDir = Directory(fontsDirectoryPath).absolute.path;
      final targetAbs = File(fontPath).absolute.path;
      final normDir = fontsDir.replaceAll('\\', '/');
      final normTarget = targetAbs.replaceAll('\\', '/');
      if (normTarget.startsWith('$normDir/')) {
        final f = File(targetAbs);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
    final next = prefs.customFontPaths.where((p) => p != fontPath).toList();
    await updatePrefs(prefs.copyWith(customFontPaths: next));
  }

  /// Translate text (movie overview / subtitle line) through client-side Rust engine.
  Future<String> translateText(String text, {String? targetLang}) async {
    if (!prefs.isAiReady) {
      throw Exception('请先开启 AI 翻译');
    }
    final baseUrl = prefs.aiBaseUrl.trim();
    final res = await core.invoke('ai_translate', {
      'base_url': baseUrl,
      'api_key': prefs.aiApiKey.trim(),
      'model': prefs.aiModel.trim(),
      'text': text,
      'target_lang': targetLang ?? prefs.aiTargetLang,
      'direct_ip': prefs.aiDirectClientIp,
    }) as Map<String, dynamic>;
    return (res['translated'] ?? '').toString();
  }

  /// Load and parse SRT/VTT/ASS subtitle cues from a remote server URL or local file path.
  Future<List<Map<String, dynamic>>> loadSubtitleCues({
    String? url,
    String? localPath,
    String? format,
  }) async {
    final res = await core.invoke('load_subtitle_cues', {
      if (url != null && url.trim().isNotEmpty) 'url': url.trim(),
      if (localPath != null && localPath.trim().isNotEmpty) 'local_path': localPath.trim(),
      if (format != null && format.trim().isNotEmpty) 'format': format.trim(),
    }) as Map<String, dynamic>;
    return ((res['cues'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// Context-aware numbered batch subtitle translation via Rust FFI.
  Future<Map<int, String>> aiTranslateSubtitleBatch({
    required List<Map<String, dynamic>> lines,
    List<String> context = const [],
    String? mediaTitle,
    String? targetLang,
  }) async {
    if (!prefs.isAiReady) {
      throw Exception('请先在「设置 → AI 翻译」开启并配置模型');
    }
    if (lines.isEmpty) return const {};
    final res = await core.invoke('ai_translate_subtitle_batch', {
      'base_url': prefs.aiBaseUrl.trim(),
      'api_key': prefs.aiApiKey.trim(),
      'model': prefs.aiModel.trim(),
      'target_lang': (targetLang != null && targetLang.trim().isNotEmpty)
          ? targetLang.trim()
          : prefs.aiTargetLang,
      'direct_ip': prefs.aiDirectClientIp,
      if (mediaTitle != null && mediaTitle.trim().isNotEmpty) 'media_title': mediaTitle.trim(),
      if (context.isNotEmpty) 'context': context,
      'lines': lines,
    }) as Map<String, dynamic>;
    final rawMap = res['translations'];
    final out = <int, String>{};
    if (rawMap is Map) {
      rawMap.forEach((k, v) {
        final idx = int.tryParse(k.toString());
        final text = v?.toString().trim() ?? '';
        if (idx != null && text.isNotEmpty) {
          out[idx] = text;
        }
      });
    }
    return out;
  }

  /// True when either the built-in local offline SenseVoice model is downloaded
  /// (when `prefs.asrEngine == 'local'`) OR a cloud/self-hosted ASR API is configured.
  bool get isAsrReadyForPlayback {
    if (prefs.asrEngine == 'local') {
      return LocalAsrManager.instance.isModelDownloaded;
    }
    return prefs.isAsrReady;
  }

  /// Extract a `[startSecs, startSecs + durationSecs]` audio slice in pure Rust and transcribe
  /// it either locally on-device (`sherpa_onnx` SenseVoice-Small INT8 + Silero VAD) or via
  /// an OpenAI-compatible Whisper / SenseVoice `/audio/transcriptions` endpoint.
  Future<List<Map<String, dynamic>>> transcribeAudioSlice({
    String? sourceUrl,
    String? localPath,
    required double startSecs,
    double durationSecs = 20.0,
    String? sourceLang,
    String? prompt,
  }) async {
    final effectiveLang = (sourceLang != null && sourceLang.trim().isNotEmpty)
        ? sourceLang.trim()
        : prefs.asrSourceLang;

    if (prefs.asrEngine == 'local') {
      final extracted = await core.invoke('extract_audio_slice_file', {
        if (sourceUrl != null && sourceUrl.trim().isNotEmpty) 'source_url': sourceUrl.trim(),
        if (localPath != null && localPath.trim().isNotEmpty) 'local_path': localPath.trim(),
        'start_secs': startSecs,
        'duration_secs': durationSecs,
      }) as Map<String, dynamic>;
      final wavPath = (extracted['wav_path'] ?? '').toString();
      if (wavPath.isEmpty) {
        throw Exception('未能提取到有效音频切片');
      }
      return LocalAsrManager.instance.transcribeWavSlice(
        wavPath: wavPath,
        sliceStartSecs: startSecs,
        language: effectiveLang,
      );
    }

    if (!prefs.isAsrReady) {
      throw Exception('请先在「设置 → AI 翻译」开启并配置 AI 语音识别 (ASR)');
    }
    final res = await core.invoke('ai_transcribe_audio_slice', {
      if (sourceUrl != null && sourceUrl.trim().isNotEmpty) 'source_url': sourceUrl.trim(),
      if (localPath != null && localPath.trim().isNotEmpty) 'local_path': localPath.trim(),
      'start_secs': startSecs,
      'duration_secs': durationSecs,
      'asr_base_url': prefs.asrBaseUrl.trim(),
      'asr_api_key': prefs.asrApiKey.trim(),
      'asr_model': prefs.asrModel.trim(),
      'asr_language': effectiveLang,
      'direct_ip': prefs.asrDirectClientIp,
      if (prompt != null && prompt.trim().isNotEmpty) 'prompt': prompt.trim(),
    }) as Map<String, dynamic>;
    return ((res['cues'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// Fetch available model IDs from `{base_url}/models`.
  Future<List<String>> fetchAiModels({
    String? baseUrl,
    String? apiKey,
    bool? directIp,
  }) async {
    final url = (baseUrl ?? prefs.aiBaseUrl).trim();
    if (url.isEmpty) throw Exception('请先填写接口地址');
    final res = await core.invoke('ai_list_models', {
      'base_url': url,
      'api_key': (apiKey ?? prefs.aiApiKey).trim(),
      'direct_ip': directIp ?? prefs.aiDirectClientIp,
    }) as Map<String, dynamic>;
    final models = ((res['models'] as List<dynamic>?) ?? const [])
        .map((e) => e.toString())
        .where((s) => s.isNotEmpty)
        .toList();
    if (models.isNotEmpty) {
      await updatePrefs(prefs.copyWith(
        aiCachedModels: models,
        aiModel: models.contains(prefs.aiModel) ? prefs.aiModel : models.first,
      ));
    }
    return models;
  }

  Future<void> resetToHardwareRecommendedDefaults(DisplayMetricsProfile profile) async {
    await updatePrefs(prefs.applyHardwareDefaults(profile));
  }

  Future<void> adminEndSession(String sessionId) async {
    if (!isAdmin) return;
    await core.invoke('admin_end_session', {'session_id': sessionId});
    await loadEmbyGoAdminDashboard();
  }

  Future<void> adminCreateUser(String name, String password) async {
    if (!isAdmin) return;
    await core.invoke('admin_create_user', {'name': name, 'password': password});
    await loadEmbyGoAdminDashboard();
  }

  Future<void> adminSetUserPolicy(String userId, Map<String, dynamic> policy) async {
    if (!isAdmin) return;
    await core.invoke('admin_set_user_policy', {'user_id': userId, 'policy': policy});
    await loadEmbyGoAdminDashboard();
  }

  Future<void> adminDeleteUser(String userId) async {
    if (!isAdmin) return;
    await core.invoke('admin_delete_user', {'user_id': userId});
    await loadEmbyGoAdminDashboard();
  }

  Future<void> adminRunTask(String key) async {
    if (!isAdmin) return;
    await core.invoke('admin_run_task', {'key': key});
    await loadEmbyGoAdminDashboard();
  }

  Future<void> adminSetLibraryCovers(String id, bool enabled) async {
    if (!isAdmin) return;
    await core.invoke('admin_set_library_covers', {'id': id, 'enabled': enabled});
    await loadEmbyGoAdminDashboard();
  }

  Future<Map<String, dynamic>> adminGetUserDetail(String uid) async {
    final res = await core.invoke('admin_user_detail', {'user_id': uid});
    return res is Map<String, dynamic> ? res : const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> adminAdjustDownloadPack(
    String uid,
    int bytes, {
    String? note,
  }) async {
    final res = await core.invoke('admin_adjust_download_pack', {
      'user_id': uid,
      'bytes': bytes,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    if (uid == userId) unawaited(refreshMeQuota());
    return res is Map<String, dynamic> ? res : const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> adminSetMonthlyDownloadQuota(
    String uid,
    int? monthlyBytes,
  ) async {
    final res = await core.invoke('admin_set_monthly_download_quota', {
      'user_id': uid,
      'monthly_bytes': monthlyBytes,
    });
    if (uid == userId) unawaited(refreshMeQuota());
    return res is Map<String, dynamic> ? res : const <String, dynamic>{};
  }

  Future<List<DownloadQuotaEventModel>> adminGetDownloadQuotaEvents(
    String uid, {
    int limit = 20,
  }) async {
    final res = await core.invoke('admin_download_quota_events', {
      'user_id': uid,
      'limit': limit,
    });
    if (res is Map<String, dynamic> && res['Events'] is List) {
      return (res['Events'] as List)
          .whereType<Map<String, dynamic>>()
          .map(DownloadQuotaEventModel.fromJson)
          .toList();
    }
    return const [];
  }

  Future<void> addSearchHistory(String term) async {
    final cleaned = term.trim();
    if (cleaned.isEmpty) return;
    final next = [
      cleaned,
      ...prefs.searchHistory.where((t) => t != cleaned),
    ].take(12).toList();
    await updatePrefs(prefs.copyWith(searchHistory: next));
  }

  Future<void> clearSearchHistory() async {
    await updatePrefs(prefs.copyWith(searchHistory: const []));
  }

  ServerCardStyle serverCardStyleFor(String serverId) =>
      prefs.serverCardStyles[serverId] ?? const ServerCardStyle();

  String displayNameForServer(SavedServerProfile srv) {
    final custom = serverCardStyleFor(srv.id).customName.trim();
    return custom.isNotEmpty ? custom : srv.name;
  }

  Future<void> updateServerCardStyle(String serverId, ServerCardStyle style) async {
    final next = Map<String, ServerCardStyle>.from(prefs.serverCardStyles);
    next[serverId] = style;
    await updatePrefs(prefs.copyWith(serverCardStyles: next));
  }

  Future<void> openExternalUrl(String url) async {
    final trimmed = url.trim();
    if (!NativePlaybackChannel.isAllowedHttpUrl(trimmed)) return;
    await NativePlaybackChannel.openUrl(trimmed);
  }

  DownloadTaskModel? findDownloadForItem(String itemId, {String? mediaSourceId}) {
    if (mediaSourceId != null && mediaSourceId.isNotEmpty) {
      for (final d in downloads) {
        if (d.itemId == itemId && d.mediaSourceId == mediaSourceId) return d;
      }
    }
    for (final d in downloads) {
      if (d.itemId == itemId) return d;
    }
    return null;
  }

  Future<void> deletePlaylist(String playlistId) async {
    await core.invoke('delete_playlist', {'playlist_id': playlistId});
    await refreshPlaylists();
  }

  /// Launch an item in an external player (IINA / Infuse / MPV / VLC / PotPlayer / MX Player / Outplayer) across all 5 OSes.
  Future<String> launchExternalPlayer(
    MediaItemModel item, {
    String? mediaSourceId,
    String? playerOverride,
  }) async {
    final targetPlayer = (playerOverride ?? prefs.externalPlayer).toLowerCase();
    final isDesktop = !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    final res = await core.invoke('external_play_url', {
      'item_id': item.id,
      if (mediaSourceId != null) 'media_source_id': mediaSourceId,
      if (targetPlayer != 'builtin') 'player_id': targetPlayer,
      // Keep upstream server tokens off OS process argv on desktop by routing through local loopback proxy!
      'use_local_proxy': isDesktop,
    }) as Map<String, dynamic>;
    final streamUrl = (res['url'] ?? '').toString().trim();
    if (!NativePlaybackChannel.isAllowedHttpUrl(streamUrl)) {
      throw Exception('无法获取有效的外部播放直链');
    }

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final ok = await NativePlaybackChannel.launchExternalPlayer(
        streamUrl,
        player: targetPlayer,
        title: item.name,
      );
      if (!ok) {
        throw Exception('未检测到可用的外部播放器应用');
      }
      return '已调用外部播放器';
    }

    if (!kIsWeb && Platform.isMacOS) {
      switch (targetPlayer) {
        case 'iina':
          await Process.start('open', ['iina://weblink?url=${Uri.encodeComponent(streamUrl)}']);
          return '已通过 IINA 打开';
        case 'infuse':
          await Process.start('open', ['infuse://x-callback-url/play?url=${Uri.encodeComponent(streamUrl)}']);
          return '已通过 Infuse 打开';
        case 'vlc':
          await Process.start('open', ['-a', 'VLC', '--', streamUrl]);
          return '已通过 VLC 打开';
        case 'mpv':
          await Process.start('open', ['-a', 'mpv', '--', streamUrl]);
          return '已通过 MPV 打开';
        default:
          await Process.start('open', ['--', streamUrl]);
          return '已交由系统播放器打开';
      }
    } else if (!kIsWeb && Platform.isWindows) {
      final ok = await NativePlaybackChannel.launchExternalPlayer(
        streamUrl,
        player: targetPlayer,
        title: item.name,
      );
      if (!ok) {
        await NativePlaybackChannel.openUrl(streamUrl);
      }
      return '已调用外部播放器';
    } else if (!kIsWeb && Platform.isLinux) {
      if (targetPlayer == 'mpv') {
        await Process.start('mpv', ['--', streamUrl]);
      } else if (targetPlayer == 'vlc') {
        await Process.start('vlc', ['--', streamUrl]);
      } else {
        await Process.start('xdg-open', ['--', streamUrl]);
      }
      return '已调用外部播放器';
    }
    return streamUrl;
  }

  /// Fetch real danmaku comments from multi-source engine (DandanPlay + Bilibili PGC/Video + custom XML).
  Future<({String title, List<DanmakuComment> comments})> fetchDanmaku(
    String title, {
    String? altTitle,
    int? season,
    int? episode,
    String? apiOverride,
  }) async {
    final res = await core.invoke('danmaku_fetch', {
      'title': title,
      if (altTitle != null && altTitle.trim().isNotEmpty) 'alt_title': altTitle.trim(),
      if (season != null && season > 0) 'season': season,
      if (episode != null && episode > 0) 'episode': episode,
      if ((apiOverride ?? prefs.danmakuApiUrl).trim().isNotEmpty)
        'api_base': (apiOverride ?? prefs.danmakuApiUrl).trim(),
    }) as Map<String, dynamic>;
    return _parseDanmakuPayload(res, fallbackTitle: title);
  }

  Future<List<Map<String, dynamic>>> searchDanmakuCandidates(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return const [];
    final res = await core.invoke('danmaku_search', {
      'keyword': trimmed,
      if (prefs.danmakuApiUrl.trim().isNotEmpty) 'api_base': prefs.danmakuApiUrl.trim(),
    }) as Map<String, dynamic>;
    return ((res['candidates'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<({String title, List<DanmakuComment> comments})> loadDanmakuTarget({
    required String provider,
    required String targetId,
    required String title,
  }) async {
    final res = await core.invoke('danmaku_load_target', {
      'provider': provider,
      'target_id': targetId,
      'title': title,
      if (prefs.danmakuApiUrl.trim().isNotEmpty) 'api_base': prefs.danmakuApiUrl.trim(),
    }) as Map<String, dynamic>;
    return _parseDanmakuPayload(res, fallbackTitle: title);
  }

  static ({String title, List<DanmakuComment> comments}) _parseDanmakuPayload(
    Map<String, dynamic> res, {
    required String fallbackTitle,
  }) {
    final epTitle = (res['episode_title'] ?? fallbackTitle).toString();
    if (res['raw'] is String) {
      return (
        title: epTitle,
        comments: DanmakuComment.parseBilibiliXml(res['raw'].toString()),
      );
    }
    final list = (res['comments'] as List<dynamic>?) ?? const [];
    return (
      title: epTitle,
      comments: DanmakuComment.parseDandanComments(list),
    );
  }

  // ---------------------------------------------------------------------------
  // Artwork resolution (exact embygo Web ancestor fallback chain + RAM proxy)
  // ---------------------------------------------------------------------------

  String buildImageUrl(
    String itemId, {
    String type = 'Primary',
    String? tag,
    int? maxWidth,
  }) {
    if (connectedUrl == null || itemId.isEmpty) return '';
    final params = <String>[];
    if (tag != null && tag.isNotEmpty) params.add('tag=${Uri.encodeComponent(tag)}');
    if (maxWidth != null) params.add('maxWidth=$maxWidth');
    params.add('quality=88');
    final q = params.isEmpty ? '' : '?${params.join('&')}';
    final encType = type.split('/').where((s) => s.isNotEmpty).map(Uri.encodeComponent).join('/');

    if (proxyAddr != null && proxyAddr!.isNotEmpty) {
      return 'http://$proxyAddr/img/Items/${Uri.encodeComponent(itemId)}/Images/$encType$q';
    }
    final base = connectedUrl!.endsWith('/')
        ? connectedUrl!.substring(0, connectedUrl!.length - 1)
        : connectedUrl!;
    return '$base/Items/${Uri.encodeComponent(itemId)}/Images/$encType$q';
  }

  /// Build artwork URL for a specific server (used in multi-server aggregated search).
  String buildServerImageUrl(
    String serverId,
    String itemId, {
    String type = 'Primary',
    String? tag,
    int? maxWidth,
  }) {
    if (itemId.isEmpty) return '';
    final params = <String>[];
    if (tag != null && tag.isNotEmpty) params.add('tag=${Uri.encodeComponent(tag)}');
    if (maxWidth != null) params.add('maxWidth=$maxWidth');
    params.add('quality=86');
    final q = params.isEmpty ? '' : '?${params.join('&')}';
    final encType = type.split('/').where((s) => s.isNotEmpty).map(Uri.encodeComponent).join('/');
    if (proxyAddr != null && proxyAddr!.isNotEmpty && serverId.isNotEmpty) {
      return 'http://$proxyAddr/img-srv/${Uri.encodeComponent(serverId)}/Items/${Uri.encodeComponent(itemId)}/Images/$encType$q';
    }
    return buildImageUrl(itemId, type: type, tag: tag, maxWidth: maxWidth);
  }

  String? posterArtUrl(MediaItemModel item, {int width = 420}) {
    if (item.primaryImageTag != null && item.type != 'Episode') {
      return buildImageUrl(item.id, type: 'Primary', tag: item.primaryImageTag, maxWidth: width);
    }
    if (item.parentPrimaryImageItemId != null && item.parentPrimaryImageTag != null) {
      return buildImageUrl(
        item.parentPrimaryImageItemId!,
        type: 'Primary',
        tag: item.parentPrimaryImageTag,
        maxWidth: width,
      );
    }
    if (item.seriesId != null && item.seriesPrimaryImageTag != null) {
      return buildImageUrl(
        item.seriesId!,
        type: 'Primary',
        tag: item.seriesPrimaryImageTag,
        maxWidth: width,
      );
    }
    if (item.primaryImageTag != null) {
      return buildImageUrl(item.id, type: 'Primary', tag: item.primaryImageTag, maxWidth: width);
    }
    return null;
  }

  /// Direct server-side library cover for `CollectionFolder` / `UserView` items.
  /// Emby / Jellyfin / embygo store generated or custom 16:9 library covers in `Primary`,
  /// `Backdrop`, or `Thumb` on the view item itself.
  String? libraryCoverUrl(MediaItemModel view, {int width = 720}) {
    if (view.primaryImageTag != null && view.primaryImageTag!.isNotEmpty) {
      return buildImageUrl(view.id, type: 'Primary', tag: view.primaryImageTag, maxWidth: width);
    }
    if (view.backdropImageTag != null && view.backdropImageTag!.isNotEmpty) {
      return buildImageUrl(view.id, type: 'Backdrop', tag: view.backdropImageTag, maxWidth: width);
    }
    if (view.thumbImageTag != null && view.thumbImageTag!.isNotEmpty) {
      return buildImageUrl(view.id, type: 'Thumb', tag: view.thumbImageTag, maxWidth: width);
    }
    return null;
  }

  ResolvedArt? wideArt(MediaItemModel item, {int width = 640}) {
    if ((item.type == 'CollectionFolder' || item.type == 'UserView') &&
        item.primaryImageTag != null) {
      return ResolvedArt(
        url: buildImageUrl(item.id, type: 'Primary', tag: item.primaryImageTag, maxWidth: width),
        isPoster: false,
      );
    }
    if (item.thumbImageTag != null) {
      return ResolvedArt(
        url: buildImageUrl(item.id, type: 'Thumb', tag: item.thumbImageTag, maxWidth: width),
        isPoster: false,
      );
    }
    if (item.type == 'Episode' && item.primaryImageTag != null) {
      return ResolvedArt(
        url: buildImageUrl(item.id, type: 'Primary', tag: item.primaryImageTag, maxWidth: width),
        isPoster: false,
      );
    }
    if (item.backdropImageTag != null) {
      return ResolvedArt(
        url: buildImageUrl(item.id, type: 'Backdrop', tag: item.backdropImageTag, maxWidth: width),
        isPoster: false,
      );
    }
    if (item.parentThumbItemId != null && item.parentThumbImageTag != null) {
      return ResolvedArt(
        url: buildImageUrl(
          item.parentThumbItemId!,
          type: 'Thumb',
          tag: item.parentThumbImageTag,
          maxWidth: width,
        ),
        isPoster: false,
      );
    }
    if (item.parentBackdropItemId != null && item.parentBackdropImageTag != null) {
      return ResolvedArt(
        url: buildImageUrl(
          item.parentBackdropItemId!,
          type: 'Backdrop',
          tag: item.parentBackdropImageTag,
          maxWidth: width,
        ),
        isPoster: false,
      );
    }
    final poster = posterArtUrl(item, width: (width * 0.6).round());
    return poster != null
        ? ResolvedArt(
            url: poster,
            isPoster: true,
            tinyUrl: posterArtUrl(item, width: 140),
          )
        : null;
  }

  ResolvedArt? backdropArt(MediaItemModel item, {int width = 1920}) {
    if (item.backdropImageTag != null) {
      return ResolvedArt(
        url: buildImageUrl(item.id, type: 'Backdrop', tag: item.backdropImageTag, maxWidth: width),
        isPoster: false,
      );
    }
    if (item.parentBackdropItemId != null && item.parentBackdropImageTag != null) {
      return ResolvedArt(
        url: buildImageUrl(
          item.parentBackdropItemId!,
          type: 'Backdrop',
          tag: item.parentBackdropImageTag,
          maxWidth: width,
        ),
        isPoster: false,
      );
    }
    if (item.thumbImageTag != null) {
      return ResolvedArt(
        url: buildImageUrl(item.id, type: 'Thumb', tag: item.thumbImageTag, maxWidth: width),
        isPoster: false,
      );
    }
    if (item.parentThumbItemId != null && item.parentThumbImageTag != null) {
      return ResolvedArt(
        url: buildImageUrl(
          item.parentThumbItemId!,
          type: 'Thumb',
          tag: item.parentThumbImageTag,
          maxWidth: width,
        ),
        isPoster: false,
      );
    }
    if (item.type == 'Episode' && item.primaryImageTag != null) {
      return ResolvedArt(
        url: buildImageUrl(item.id, type: 'Primary', tag: item.primaryImageTag, maxWidth: width),
        isPoster: false,
      );
    }
    final poster = posterArtUrl(item, width: 800);
    return poster != null
        ? ResolvedArt(
            url: poster,
            isPoster: true,
            tinyUrl: posterArtUrl(item, width: 140),
          )
        : null;
  }

  String? logoArtUrl(MediaItemModel item, {int width = 640}) {
    if (item.logoImageTag != null) {
      return buildImageUrl(item.id, type: 'Logo', tag: item.logoImageTag, maxWidth: width);
    }
    if (item.parentLogoItemId != null && item.parentLogoImageTag != null) {
      return buildImageUrl(
        item.parentLogoItemId!,
        type: 'Logo',
        tag: item.parentLogoImageTag,
        maxWidth: width,
      );
    }
    return null;
  }

  Future<void> _reloadSavedServers() async {
    try {
      final list = await core.invoke('list_servers');
      if (list is List) {
        savedServers = list
            .whereType<Map<String, dynamic>>()
            .map(SavedServerProfile.fromJson)
            .toList()
          ..sort((a, b) => b.lastConnectedAt.compareTo(a.lastConnectedAt));
        notifyListeners();
      }
    } catch (_) {}
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

  /// Fetch registered login devices (`GET /emby-compat/devices` or `/Devices`).
  Future<List<Map<String, dynamic>>> loadUserDevices({String? targetUserId}) async {
    if (!isSignedIn) return const [];
    final epoch = _sessionEpoch;
    final isSelf = targetUserId == null || targetUserId == userId;
    if (isSelf) {
      isLoadingDevices = true;
      notifyListeners();
    }
    try {
      final res = await core.invoke('get_user_devices', {
        'user_id': targetUserId ?? userId,
      }) as Map<String, dynamic>;
      if (epoch != _sessionEpoch || _disposed) return const [];
      final list = ((res['items'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (res['current_device_id'] != null) {
        currentClientDeviceId = res['current_device_id'].toString();
      }
      if (isSelf) {
        userDevices = list;
      }
      return list;
    } finally {
      if (isSelf && epoch == _sessionEpoch) {
        isLoadingDevices = false;
        notifyListeners();
      }
    }
  }

  /// Remove a registered device slot (`DELETE /emby-compat/devices`).
  /// If removing the current device of the signed-in user, signs out locally as well.
  Future<void> removeUserDevice({
    String? targetUserId,
    required String deviceId,
  }) async {
    final effectiveUid = targetUserId ?? userId;
    await core.invoke('delete_user_device', {
      if (effectiveUid != null) 'user_id': effectiveUid,
      'device_id': deviceId,
    });
    final removingSelf = (effectiveUid == null || effectiveUid == userId) &&
        currentClientDeviceId != null &&
        deviceId == currentClientDeviceId;
    if (removingSelf) {
      await logout();
      return;
    }
    if (effectiveUid == null || effectiveUid == userId) {
      await loadUserDevices();
      unawaited(refreshMeQuota());
    }
  }

  /// Run an EmbyGo playback route speedtest (`POST /emby-compat/speedtest` + ping + download).
  Future<Map<String, dynamic>?> runEmbyGoSpeedTest() async {
    if (isSpeedTesting) return null;
    final gen = ++_speedTestGen;
    isSpeedTesting = true;
    liveSpeedTestMbps = null;
    speedTestLatencyMs = null;
    speedTestClientIp = null;
    speedTestError = null;
    notifyListeners();

    _speedTestPollTimer?.cancel();
    _speedTestPollTimer = Timer.periodic(
      const Duration(milliseconds: 220),
      (_) {
        if (gen == _speedTestGen) _consumeCoreEvents();
      },
    );
    try {
      final res = await core.invoke('run_embygo_speedtest') as Map<String, dynamic>;
      if (gen != _speedTestGen || _disposed) return null;
      _consumeCoreEvents();
      lastSpeedTestResult = res;
      speedTestLatencyMs = (res['latency_ms'] as num?)?.toDouble();
      speedTestClientIp = res['client_ip']?.toString();
      liveSpeedTestMbps = (res['effective_mbps'] as num?)?.toDouble() ??
          (res['measured_mbps'] as num?)?.toDouble();
      return res;
    } catch (e) {
      if (gen == _speedTestGen && !_disposed) {
        final msg = VedroErrorFormatter.format(e);
        if (!msg.contains('已取消')) {
          speedTestError = msg;
        }
      }
      return null;
    } finally {
      if (gen == _speedTestGen) {
        _speedTestPollTimer?.cancel();
        _speedTestPollTimer = null;
        isSpeedTesting = false;
        notifyListeners();
      }
    }
  }

  Future<void> cancelEmbyGoSpeedTest() async {
    ++_speedTestGen;
    _speedTestPollTimer?.cancel();
    _speedTestPollTimer = null;
    try {
      await core.invoke('cancel_embygo_speedtest');
    } catch (_) {}
    if (!_disposed) {
      isSpeedTesting = false;
      notifyListeners();
    }
  }

  /// Query local persistent disk + memory image cache usage from the Rust core.
  Future<Map<String, dynamic>> loadImageCacheStats() async {
    isLoadingImageCacheStats = true;
    notifyListeners();
    try {
      final raw = await core.invoke('get_image_cache_stats');
      if (raw is Map<String, dynamic>) {
        imageCacheStats = raw;
        return raw;
      }
      imageCacheStats = const <String, dynamic>{
        'disk_files': 0,
        'disk_bytes': 0,
        'memory_entries': 0,
      };
      return imageCacheStats!;
    } catch (_) {
      return imageCacheStats ??
          const <String, dynamic>{
            'disk_files': 0,
            'disk_bytes': 0,
            'memory_entries': 0,
          };
    } finally {
      isLoadingImageCacheStats = false;
      notifyListeners();
    }
  }

  /// Clear both the Rust persistent disk/RAM image cache and Flutter's decoded image cache.
  Future<Map<String, dynamic>> clearImageCache() async {
    isClearingImageCache = true;
    notifyListeners();
    try {
      final raw = await core.invoke('clear_image_cache');
      try {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      } catch (_) {}
      imageCacheStats = <String, dynamic>{
        'disk_files': 0,
        'disk_bytes': 0,
        'memory_entries': 0,
        if (imageCacheStats?['cache_dir'] != null)
          'cache_dir': imageCacheStats!['cache_dir'],
      };
      return raw is Map<String, dynamic>
          ? raw
          : const <String, dynamic>{'removed_files': 0, 'freed_bytes': 0};
    } finally {
      isClearingImageCache = false;
      notifyListeners();
    }
  }

  static String _humanizeError(String raw) => VedroErrorFormatter.format(raw);

  static List<MediaItemModel> _parseItems(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map(MediaItemModel.fromJson).toList();
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

class _ActiveDownloadHandle {
  HttpClient? client;
  bool paused = false;
  bool cancelled = false;
  final Completer<void> cancelSignal = Completer<void>();
  final Completer<void> done = Completer<void>();

  void abort() {
    if (!cancelSignal.isCompleted) {
      cancelSignal.complete();
    }
    try {
      client?.close(force: true);
    } catch (_) {}
  }
}

class _PermanentDownloadError implements Exception {
  const _PermanentDownloadError(this.message);
  final String message;
  @override
  String toString() => message;
}

class _TransientDownloadError implements Exception {
  const _TransientDownloadError(this.message, {this.retryAfterSecs});
  final String message;
  final int? retryAfterSecs;
  @override
  String toString() => message;
}
