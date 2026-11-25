import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/ffi/prism_bridge.dart';
import '../core/models/models.dart';
import '../core/platform/native_playback_channel.dart';

/// Central reactive application state backed directly by the compiled Rust core (`PrismCoreClient`).
class PrismAppState extends ChangeNotifier {
  PrismAppState(this.core);

  final PrismCoreClient core;

  bool isInitialized = false;
  bool isBusy = false;
  String? errorMessage;

  List<SavedServerProfile> savedServers = [];
  List<Map<String, dynamic>> discoveredServers = [];

  ServerCapabilitiesModel? capabilities;
  String? connectedUrl;
  String? username;
  String? userId;
  bool isAdmin = false;

  // Home collections
  List<MediaItemModel> views = [];
  List<MediaItemModel> popular = [];
  List<MediaItemModel> resume = [];
  List<MediaItemModel> nextUp = [];
  List<MediaItemModel> suggestions = [];
  List<Map<String, dynamic>> latestByLibrary = [];

  // Playlists
  List<MediaItemModel> playlists = [];

  // Remote control toast messages from WebSocket
  String? remoteBannerMessage;

  // Playback settings mirrored with Rust SQLite store
  Map<String, dynamic> settings = {};

  // EmbyGo Admin dashboard snapshot
  Map<String, dynamic>? embygoAdminDashboard;

  Timer? _wsPollTimer;

  bool get isSignedIn => userId != null && connectedUrl != null;

  Future<void> initialize() async {
    isBusy = true;
    notifyListeners();
    try {
      final list = await core.invoke('list_servers');
      if (list is List) {
        savedServers = list
            .whereType<Map<String, dynamic>>()
            .map(SavedServerProfile.fromJson)
            .toList();
      }
      final cfg = await core.invoke('get_settings');
      if (cfg is Map<String, dynamic>) {
        settings = Map<String, dynamic>.from(cfg);
      }

      // Query native display HDR / Dolby Vision & Atmos hardware capabilities
      final hwCaps = await NativePlaybackChannel.queryDisplayAndAudioCapabilities();
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
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> discoverLanServers() async {
    try {
      final res = await core.invoke('discover_servers', {'timeout_ms': 1500});
      if (res is List) {
        discoveredServers = res.whereType<Map<String, dynamic>>().toList();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<ServerCapabilitiesModel> connectServer(String url) async {
    errorMessage = null;
    isBusy = true;
    notifyListeners();
    try {
      final res = await core.invoke('connect_server', {
        'url': url.trim(),
        'device_name': _platformDeviceName(),
      }) as Map<String, dynamic>;
      capabilities = ServerCapabilitiesModel.fromJson(
        res['capabilities'] as Map<String, dynamic>,
      );
      connectedUrl = url.trim();
      return capabilities!;
    } catch (e) {
      errorMessage = e.toString();
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> login(String url, String user, String password) async {
    errorMessage = null;
    isBusy = true;
    notifyListeners();
    try {
      await connectServer(url);
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
      _startEventPolling();
      await refreshHome();
      await _reloadSavedServers();
    } catch (e) {
      errorMessage = e.toString();
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> restoreSavedServer(SavedServerProfile profile) async {
    if (profile.accessToken == null || profile.userId == null) {
      connectedUrl = profile.url;
      notifyListeners();
      return;
    }
    errorMessage = null;
    isBusy = true;
    notifyListeners();
    try {
      final res = await core.invoke('restore_session', {
        'url': profile.url,
        'access_token': profile.accessToken,
        'user_id': profile.userId,
      }) as Map<String, dynamic>;
      connectedUrl = profile.url;
      capabilities = ServerCapabilitiesModel.fromJson(
        res['capabilities'] as Map<String, dynamic>,
      );
      final u = res['user'] as Map<String, dynamic>;
      username = u['Name']?.toString();
      userId = u['Id']?.toString();
      isAdmin = (u['Policy'] as Map<String, dynamic>?)?['IsAdministrator'] == true;
      _startEventPolling();
      await refreshHome();
    } catch (e) {
      errorMessage = e.toString();
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
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
    views = [];
    popular = [];
    resume = [];
    nextUp = [];
    suggestions = [];
    latestByLibrary = [];
    embygoAdminDashboard = null;
    notifyListeners();
  }

  Future<void> refreshHome() async {
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
    latestByLibrary = ((res['latest_by_library'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    notifyListeners();
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
    await refreshHome();
  }

  Future<void> togglePlayed(MediaItemModel item) async {
    await core.invoke('set_played', {'item_id': item.id, 'played': !item.played});
    await refreshHome();
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

  String buildImageUrl(
    String itemId, {
    String type = 'Primary',
    String? tag,
    int? maxWidth,
  }) {
    if (connectedUrl == null) return '';
    final base = connectedUrl!.endsWith('/')
        ? connectedUrl!.substring(0, connectedUrl!.length - 1)
        : connectedUrl!;
    final params = <String>[];
    if (tag != null && tag.isNotEmpty) params.add('tag=$tag');
    if (maxWidth != null) params.add('maxWidth=$maxWidth');
    params.add('quality=88');
    final q = params.isEmpty ? '' : '?${params.join('&')}';
    return '$base/Items/$itemId/Images/$type$q';
  }

  Future<void> _reloadSavedServers() async {
    final list = await core.invoke('list_servers');
    if (list is List) {
      savedServers = list
          .whereType<Map<String, dynamic>>()
          .map(SavedServerProfile.fromJson)
          .toList();
    }
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
