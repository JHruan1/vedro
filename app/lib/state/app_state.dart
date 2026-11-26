import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/ffi/vedro_bridge.dart';
import '../core/models/models.dart';
import '../core/models/preferences.dart';
import '../core/platform/native_playback_channel.dart';
import '../widgets/danmaku_engine.dart';

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

  // Home collections
  List<MediaItemModel> views = [];
  List<MediaItemModel> popular = [];
  List<MediaItemModel> resume = [];
  List<MediaItemModel> nextUp = [];
  List<MediaItemModel> suggestions = [];
  List<MediaItemModel> favorites = [];
  List<Map<String, dynamic>> latestByLibrary = [];

  // Playlists
  List<MediaItemModel> playlists = [];

  // Remote control toast messages from WebSocket
  String? remoteBannerMessage;

  // Playback settings mirrored with Rust SQLite store
  Map<String, dynamic> settings = {};

  // Comprehensive user preferences persisted in SQLite KV (`vedro_prefs`)
  VedroPreferences prefs = const VedroPreferences();

  // Local offline downloads queue persisted in SQLite KV (`downloads_queue`)
  List<DownloadTaskModel> downloads = [];
  String? _supportDirPath;

  // Customizable Home layout (persisted in SQLite `settings` KV under `home_layout`)
  List<HomeSectionConfig> homeSections = List<HomeSectionConfig>.from(HomeSectionConfig.defaults);
  bool showHomeHero = true;

  // Network transport options (auto-detected OS/Android proxy or user override)
  String systemProxyUrl = '';
  String customProxyUrl = '';
  bool acceptInvalidCerts = false;

  // EmbyGo Admin dashboard snapshot
  Map<String, dynamic>? embygoAdminDashboard;

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
        }
      } catch (_) {}
      try {
        final kv = await core.invoke('get_kv', {'key': 'downloads_queue'});
        if (kv is Map<String, dynamic> && kv['value'] is List) {
          downloads = (kv['value'] as List)
              .whereType<Map<String, dynamic>>()
              .map(DownloadTaskModel.fromJson)
              .toList();
        }
      } catch (_) {}

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

      isInitialized = true;
      isBusy = false;
      notifyListeners();

      unawaited(() async {
        try {
          final dir = await getApplicationSupportDirectory();
          _supportDirPath = dir.path;
        } catch (_) {}
      }());

      // Seamless auto-restore for returning users; fresh users land directly on Home Server Hub
      final recent = savedServers.where((s) => s.accessToken != null && s.userId != null).toList();
      if (recent.isNotEmpty) {
        isAutoRestoring = true;
        notifyListeners();
        try {
          await restoreSavedServer(recent.first, silentError: true);
        } finally {
          isAutoRestoring = false;
          notifyListeners();
        }
      } else {
        unawaited(discoverLanServers());
      }
    } catch (e) {
      errorMessage = e.toString();
      isInitialized = true;
      isBusy = false;
      notifyListeners();
    }
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
      capabilities = ServerCapabilitiesModel.fromJson(
        res['capabilities'] as Map<String, dynamic>,
      );
      if (res['proxy_addr'] != null) proxyAddr = res['proxy_addr'].toString();
      connectedUrl = url.trim();
      return capabilities!;
    } catch (e) {
      errorMessage = _humanizeError(e.toString());
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
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
      loginStage = '正在验证身份…';
      isBusy = true;
      notifyListeners();

      final res = await core.invoke('login', {
        'username': user.trim(),
        'password': password,
      }) as Map<String, dynamic>;
      final auth = res['auth'] as Map<String, dynamic>;
      final userObj = auth['User'] as Map<String, dynamic>;
      username = userObj['Name']?.toString();
      userId = userObj['Id']?.toString();
      isAdmin = (userObj['Policy'] as Map<String, dynamic>?)?['IsAdministrator'] == true;
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

      _startEventPolling();
      await _reloadSavedServers();
      unawaited(refreshHome());
    } catch (e) {
      errorMessage = _humanizeError(e.toString());
      isBusy = false;
      loginStage = null;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> restoreSavedServer(
    SavedServerProfile profile, {
    bool silentError = false,
  }) async {
    if (profile.accessToken == null || profile.userId == null) {
      connectedUrl = profile.url;
      notifyListeners();
      return;
    }
    if (!silentError) errorMessage = null;
    homeError = null;
    loginStage = '正在连接 ${profile.name}…';
    isBusy = true;
    notifyListeners();
    try {
      final route = profile.activeRoute;
      final targetUrl = route?.url.isNotEmpty == true ? route!.url : profile.url;
      final routeProxy = (route?.proxyUrl?.trim().isNotEmpty == true)
          ? route!.proxyUrl!.trim()
          : effectiveProxyUrl;
      final routeTls = route?.acceptInvalidCerts ?? acceptInvalidCerts;

      final res = await core.invoke('restore_session', {
        'url': targetUrl,
        'access_token': profile.accessToken,
        'user_id': profile.userId,
        if (routeProxy.isNotEmpty) 'proxy_url': routeProxy,
        'accept_invalid_certs': routeTls,
      }) as Map<String, dynamic>;
      connectedUrl = targetUrl;
      activeServerId = profile.id;
      if (res['proxy_addr'] != null) proxyAddr = res['proxy_addr'].toString();
      capabilities = ServerCapabilitiesModel.fromJson(
        res['capabilities'] as Map<String, dynamic>,
      );
      final u = res['user'] as Map<String, dynamic>;
      username = u['Name']?.toString();
      userId = u['Id']?.toString();
      isAdmin = (u['Policy'] as Map<String, dynamic>?)?['IsAdministrator'] == true;

      _clearHomeCollections();
      isBusy = false;
      loginStage = null;
      isLoadingHome = true;
      notifyListeners();

      _startEventPolling();
      unawaited(refreshHome());
    } catch (e) {
      if (!silentError) {
        errorMessage = _humanizeError(e.toString());
      }
      isBusy = false;
      loginStage = null;
      notifyListeners();
      if (!silentError) rethrow;
    }
  }

  Future<bool> switchToServerById(String serverId) async {
    if (serverId == activeServerId && isSignedIn) return true;
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
        username = u['Name']?.toString();
        userId = u['Id']?.toString();
        isAdmin = (u['Policy'] as Map<String, dynamic>?)?['IsAdministrator'] == true;
      }
      await _reloadSavedServers();
      isBusy = false;
      loginStage = null;
      isLoadingHome = true;
      notifyListeners();
      _startEventPolling();
      unawaited(refreshHome());
    } catch (e) {
      errorMessage = _humanizeError(e.toString());
      isBusy = false;
      loginStage = null;
      notifyListeners();
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
    _wsPollTimer?.cancel();
    try {
      await core.invoke('logout');
    } catch (_) {}
    activeServerId = null;
    connectedUrl = null;
    capabilities = null;
    userId = null;
    username = null;
    isAdmin = false;
    isLoadingHome = false;
    homeError = null;
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
    latestByLibrary = [];
  }

  Future<void> refreshHome() async {
    if (!isSignedIn) return;
    if (!hasAnyHomeContent) {
      isLoadingHome = true;
      homeError = null;
      notifyListeners();
    }
    try {
      final res = await core.invoke('get_home') as Map<String, dynamic>;
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
      homeError = null;
    } catch (e) {
      homeError = _humanizeError(e.toString());
    } finally {
      isLoadingHome = false;
      notifyListeners();
    }
  }

  Future<void> refreshPlaylists() async {
    if (!isSignedIn) {
      playlists = [];
      notifyListeners();
      return;
    }
    final res = await core.invoke('list_playlists') as Map<String, dynamic>;
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

  Future<void> loadEmbyGoAdminDashboard() async {
    if (!isAdmin || !isSignedIn) return;
    final res = await core.invoke('get_embygo_admin_dashboard') as Map<String, dynamic>;
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

  Future<void> updatePrefs(VedroPreferences updated) async {
    prefs = updated;
    notifyListeners();
    try {
      await core.invoke('set_kv', {
        'key': 'vedro_prefs',
        'value': prefs.toJson(),
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

  Future<void> enqueueDownload(MediaItemModel item, {String? mediaSourceId}) async {
    final taskId = '${item.id}_${DateTime.now().millisecondsSinceEpoch}';
    final initial = DownloadTaskModel(
      id: taskId,
      itemId: item.id,
      title: item.cardTitle,
      subtitle: item.cardSubtitle,
      status: 'downloading',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    downloads.insert(0, initial);
    notifyListeners();
    await _persistDownloads();

    unawaited(() async {
      try {
        final prepRaw = await core.invoke('prepare_playback', {
          'item_id': item.id,
          if (mediaSourceId != null) 'media_source_id': mediaSourceId,
          'inspect_header': false,
        }) as Map<String, dynamic>;
        final prep = PreparedPlaybackModel.fromJson(prepRaw);
        final ext = (prep.allSources.isNotEmpty ? prep.allSources.first.container : null) ?? 'mkv';
        final safeName = item.cardTitle
            .replaceAll(RegExp(r'[^\w\u4e00-\u9fff\-_. ]+'), '_')
            .trim();
        final dir = Directory(downloadsDirectoryPath);
        if (!dir.existsSync()) dir.createSync(recursive: true);
        final outPath = '${dir.path}/${safeName.isEmpty ? item.id : safeName}.$ext';

        final client = HttpClient();
        try {
          final req = await client.getUrl(Uri.parse(prep.proxyUrl));
          final resp = await req.close();
          final total = resp.contentLength > 0 ? resp.contentLength : 0;
          final file = File(outPath);
          final sink = file.openWrite();
          var received = 0;
          var lastEmit = DateTime.now();

          await for (final chunk in resp) {
            sink.add(chunk);
            received += chunk.length;
            final now = DateTime.now();
            if (now.difference(lastEmit).inMilliseconds > 350) {
              lastEmit = now;
              _replaceDownload(
                taskId,
                (d) => d.copyWith(
                  filePath: outPath,
                  totalBytes: total,
                  downloadedBytes: received,
                  status: 'downloading',
                ),
              );
            }
          }
          await sink.flush();
          await sink.close();
          _replaceDownload(
            taskId,
            (d) => d.copyWith(
              filePath: outPath,
              totalBytes: total > 0 ? total : received,
              downloadedBytes: received,
              status: 'completed',
            ),
          );
          await _persistDownloads();
        } finally {
          client.close();
        }
      } catch (e) {
        _replaceDownload(
          taskId,
          (d) => d.copyWith(status: 'failed', error: e.toString()),
        );
        await _persistDownloads();
      }
    }());
  }

  void _replaceDownload(
    String id,
    DownloadTaskModel Function(DownloadTaskModel) transform,
  ) {
    final idx = downloads.indexWhere((d) => d.id == id);
    if (idx >= 0) {
      downloads[idx] = transform(downloads[idx]);
      notifyListeners();
    }
  }

  Future<void> deleteDownload(String taskId, {bool deleteFile = true}) async {
    final idx = downloads.indexWhere((d) => d.id == taskId);
    if (idx < 0) return;
    final task = downloads.removeAt(idx);
    if (deleteFile && task.filePath.isNotEmpty) {
      try {
        final f = File(task.filePath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    notifyListeners();
    await _persistDownloads();
  }

  Future<String> importSubtitleFont(String sourcePath) async {
    final src = File(sourcePath.trim());
    if (!src.existsSync()) {
      throw Exception('找不到字体文件：$sourcePath');
    }
    final dir = Directory(fontsDirectoryPath);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final fileName = src.uri.pathSegments.last;
    final dest = '${dir.path}/$fileName';
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
      final f = File(fontPath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    final next = prefs.customFontPaths.where((p) => p != fontPath).toList();
    await updatePrefs(prefs.copyWith(customFontPaths: next));
  }

  /// Translate text (movie overview / subtitle line) through Rust OpenAI-compatible proxy.
  Future<String> translateText(String text, {String? targetLang}) async {
    if (!prefs.isAiReady) {
      throw Exception('请先在「设置 → AI 服务（翻译）」中启用并配置接口');
    }
    final res = await core.invoke('ai_translate', {
      'base_url': prefs.aiBaseUrl.trim(),
      'api_key': prefs.aiApiKey.trim(),
      'model': prefs.aiModel.trim(),
      'text': text,
      'target_lang': targetLang ?? prefs.aiTargetLang,
    }) as Map<String, dynamic>;
    return (res['translated'] ?? '').toString();
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
    if (trimmed.isEmpty) return;
    try {
      if (!kIsWeb && Platform.isMacOS) {
        await Process.start('open', [trimmed]);
      } else if (!kIsWeb && Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', trimmed], runInShell: true);
      } else if (!kIsWeb && Platform.isLinux) {
        await Process.start('xdg-open', [trimmed]);
      }
    } catch (_) {}
  }

  DownloadTaskModel? findDownloadForItem(String itemId) {
    for (final d in downloads) {
      if (d.itemId == itemId) return d;
    }
    return null;
  }

  Future<void> deletePlaylist(String playlistId) async {
    await core.invoke('delete_playlist', {'playlist_id': playlistId});
    await refreshPlaylists();
  }

  /// Launch an item in an external player (IINA / Infuse / MPV / VLC / PotPlayer) using a direct URL.
  Future<String> launchExternalPlayer(
    MediaItemModel item, {
    String? mediaSourceId,
    String? playerOverride,
  }) async {
    final targetPlayer = (playerOverride ?? prefs.externalPlayer).toLowerCase();
    final res = await core.invoke('external_play_url', {
      'item_id': item.id,
      if (mediaSourceId != null) 'media_source_id': mediaSourceId,
      if (targetPlayer != 'builtin') 'player_id': targetPlayer,
    }) as Map<String, dynamic>;
    final streamUrl = (res['url'] ?? '').toString();
    if (streamUrl.isEmpty) throw Exception('无法获取外部播放直链');

    if (!kIsWeb && Platform.isMacOS) {
      switch (targetPlayer) {
        case 'iina':
          await Process.start('open', ['iina://weblink?url=${Uri.encodeComponent(streamUrl)}']);
          return '已通过 IINA 打开';
        case 'infuse':
          await Process.start('open', ['infuse://x-callback-url/play?url=${Uri.encodeComponent(streamUrl)}']);
          return '已通过 Infuse 打开';
        case 'vlc':
          await Process.start('open', ['-a', 'VLC', streamUrl]);
          return '已通过 VLC 打开';
        case 'mpv':
          await Process.start('open', ['-a', 'mpv', streamUrl]);
          return '已通过 MPV 打开';
        default:
          await Process.start('open', [streamUrl]);
          return '已交由系统播放器打开';
      }
    } else if (!kIsWeb && Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', streamUrl], runInShell: true);
      return '已调用外部播放器';
    } else if (!kIsWeb && Platform.isLinux) {
      await Process.start('xdg-open', [streamUrl]);
      return '已调用外部播放器';
    }
    return streamUrl;
  }

  /// Fetch real danmaku comments from DandanPlay-compatible API or custom XML/JSON URL via Rust.
  Future<({String title, List<DanmakuComment> comments})> fetchDanmaku(
    String title, {
    int? episode,
    String? apiOverride,
  }) async {
    final res = await core.invoke('danmaku_fetch', {
      'title': title,
      if (episode != null) 'episode': episode,
      if ((apiOverride ?? prefs.danmakuApiUrl).trim().isNotEmpty)
        'api_base': (apiOverride ?? prefs.danmakuApiUrl).trim(),
    }) as Map<String, dynamic>;
    if (res['raw'] is String) {
      return (
        title: title,
        comments: DanmakuComment.parseBilibiliXml(res['raw'].toString()),
      );
    }
    final list = (res['comments'] as List<dynamic>?) ?? const [];
    return (
      title: (res['episode_title'] ?? title).toString(),
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
    if (tag != null && tag.isNotEmpty) params.add('tag=$tag');
    if (maxWidth != null) params.add('maxWidth=$maxWidth');
    params.add('quality=88');
    final q = params.isEmpty ? '' : '?${params.join('&')}';

    if (proxyAddr != null && proxyAddr!.isNotEmpty) {
      return 'http://$proxyAddr/img/Items/${Uri.encodeComponent(itemId)}/Images/$type$q';
    }
    final base = connectedUrl!.endsWith('/')
        ? connectedUrl!.substring(0, connectedUrl!.length - 1)
        : connectedUrl!;
    return '$base/Items/${Uri.encodeComponent(itemId)}/Images/$type$q';
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
    if (tag != null && tag.isNotEmpty) params.add('tag=$tag');
    if (maxWidth != null) params.add('maxWidth=$maxWidth');
    params.add('quality=86');
    final q = params.isEmpty ? '' : '?${params.join('&')}';
    if (proxyAddr != null && proxyAddr!.isNotEmpty && serverId.isNotEmpty) {
      return 'http://$proxyAddr/img-srv/${Uri.encodeComponent(serverId)}/Items/${Uri.encodeComponent(itemId)}/Images/$type$q';
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
    return poster != null ? ResolvedArt(url: poster, isPoster: true) : null;
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
    return poster != null ? ResolvedArt(url: poster, isPoster: true) : null;
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

  void _startEventPolling() {
    _wsPollTimer?.cancel();
    _wsPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final events = core.pollEvents();
      for (final ev in events) {
        final payload = ev['event'];
        if (payload is Map<String, dynamic>) {
          final kind = payload['kind']?.toString();
          if (kind == 'display_message') {
            remoteBannerMessage = '${payload['header'] ?? ''}: ${payload['text'] ?? ''}'.trim();
            notifyListeners();
          } else if (kind == 'user_data_changed') {
            refreshHome();
          }
        }
      }
    });
  }

  static String _humanizeError(String raw) {
    final cleaned = raw.replaceFirst('VedroCoreException: ', '');
    if (cleaned.contains('unauthorized') || cleaned.contains('401')) {
      return '用户名或密码不正确';
    }
    return cleaned;
  }

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
    _wsPollTimer?.cancel();
    super.dispose();
  }
}
