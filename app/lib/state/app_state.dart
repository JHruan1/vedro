import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/ffi/vedro_bridge.dart';
import '../core/models/models.dart';
import '../core/platform/native_playback_channel.dart';

/// Central reactive application state backed directly by the compiled Rust core (`VedroCoreClient`).
///
/// Key responsiveness guarantees:
/// - Login transitions into ShellScreen the instant authentication returns; home rails
///   populate asynchronously behind animated shimmer skeletons (never freezing the login card).
/// - Returning users with a saved session auto-restore silently on startup.
/// - Artwork resolution mirrors embygo Web's ancestor fallback chain (Thumb -> Episode Primary
///   -> Backdrop -> ParentThumb -> ParentBackdrop -> FramedPoster -> GeneratedArt).
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

      // Query native display HDR / Dolby Vision & Atmos capabilities + Android system proxy
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

      // Seamless auto-restore for returning users (only if a saved session with token exists)
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

      // Immediately enter ShellScreen with smooth shimmer skeletons instead of stalling on Login!
      isBusy = false;
      loginStage = null;
      isLoadingHome = true;
      notifyListeners();

      _startEventPolling();
      unawaited(refreshHome());
      unawaited(_reloadSavedServers());
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
    loginStage = '正在恢复会话…';
    isBusy = true;
    notifyListeners();
    try {
      final res = await core.invoke('restore_session', {
        'url': profile.url,
        'access_token': profile.accessToken,
        'user_id': profile.userId,
        if (effectiveProxyUrl.isNotEmpty) 'proxy_url': effectiveProxyUrl,
        'accept_invalid_certs': acceptInvalidCerts,
      }) as Map<String, dynamic>;
      connectedUrl = profile.url;
      if (res['proxy_addr'] != null) proxyAddr = res['proxy_addr'].toString();
      capabilities = ServerCapabilitiesModel.fromJson(
        res['capabilities'] as Map<String, dynamic>,
      );
      final u = res['user'] as Map<String, dynamic>;
      username = u['Name']?.toString();
      userId = u['Id']?.toString();
      isAdmin = (u['Policy'] as Map<String, dynamic>?)?['IsAdministrator'] == true;

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

  Future<void> logout() async {
    _wsPollTimer?.cancel();
    try {
      await core.invoke('logout');
    } catch (_) {}
    userId = null;
    username = null;
    isAdmin = false;
    isLoadingHome = false;
    homeError = null;
    views = [];
    popular = [];
    resume = [];
    nextUp = [];
    suggestions = [];
    favorites = [];
    latestByLibrary = [];
    embygoAdminDashboard = null;
    notifyListeners();
  }

  Future<void> refreshHome() async {
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
    if (!isAdmin) return;
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
  // Artwork resolution (exact embygo Web ancestor fallback chain)
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

    // Route artwork through the local Rust loopback proxy so every poster/backdrop/logo
    // inherits OS/Clash/SOCKS5 proxy, native TLS roots, self-signed certs, HTTP/2 pooling,
    // and instant 0.1ms RAM caching!
    if (proxyAddr != null && proxyAddr!.isNotEmpty) {
      return 'http://$proxyAddr/img/Items/${Uri.encodeComponent(itemId)}/Images/$type$q';
    }
    final base = connectedUrl!.endsWith('/')
        ? connectedUrl!.substring(0, connectedUrl!.length - 1)
        : connectedUrl!;
    return '$base/Items/${Uri.encodeComponent(itemId)}/Images/$type$q';
  }

  /// 2:3 key art: item's own Primary (non-episode), else parent/series Primary.
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

  /// 16:9 card art: Thumb -> Episode Primary -> Backdrop -> ParentThumb -> ParentBackdrop -> FramedPoster.
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

  /// Full-bleed hero art: Backdrop -> ParentBackdrop -> Thumb -> ParentThumb -> Episode Primary -> FramedPoster.
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

  /// Transparent title logo (TMDB ClearLogo) for cinematic Hero & Detail headers.
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
