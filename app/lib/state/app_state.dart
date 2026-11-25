import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/ffi/vedro_bridge.dart';
import '../core/models/models.dart';
import '../core/platform/native_playback_channel.dart';

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

  ResolvedArt? wideArt(MediaItemModel item, {int width = 640}) {
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
