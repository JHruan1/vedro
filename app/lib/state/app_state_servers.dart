part of 'app_state.dart';

/// Server discovery, authentication, multi-route probing, switching & aggregated search.
extension VedroAppStateServers on VedroAppState {
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
        'device_name': VedroAppState._platformDeviceName(),
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
      VedroArtworkSignal.notifyRefresh();
      return capabilities!;
    } catch (e) {
      if (epoch == _sessionEpoch) {
        errorMessage = VedroErrorFormatter.format(e.toString());
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
      errorMessage = VedroErrorFormatter.format(e.toString());
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
    VedroArtworkSignal.notifyRefresh();
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
    final route = profile.activeRoute;
    final targetUrl = route?.url.isNotEmpty == true ? route!.url : profile.url;
    final targetName = displayNameForServer(profile);
    final isSwitchingServer = !preserveCachedHome && prevServerId != profile.id;

    if (!silentError) errorMessage = null;
    homeError = null;
    if (!preserveCachedHome) {
      loginStage = '正在连接 $targetName…';
      isBusy = true;
      if (isSwitchingServer) {
        // 0ms immediate state transition so HomeScreen cross-fades out the old server
        // right away and shows a smooth switching state instead of hanging on stale cards.
        switchingToServerName = targetName;
        activeServerId = profile.id;
        connectedUrl = targetUrl;
        userId = profile.userId;
        username = profile.username;
        isAdmin = profile.isAdmin;
        _clearHomeCollections();
        isLoadingHome = true;
      }
      notifyListeners();
    }
    try {
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
      if (hasAnyHomeContent) switchingToServerName = null;
      notifyListeners();
      VedroArtworkSignal.notifyRefresh();

      _startEventPolling();
      unawaited(_reloadSavedServers());
      unawaited(refreshHome());
      unawaited(refreshMeQuota());
    } catch (e) {
      if (epoch != _sessionEpoch || _disposed) return;
      final humanized = VedroErrorFormatter.format(e.toString());
      if (silentError || isSwitchingServer) {
        // Keep target server selected and surface a clear retryable state on Home
        connectedUrl = targetUrl;
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
          homeError = '无法连接至 $targetName：$humanized';
        }
      }
      if (!silentError) {
        errorMessage = humanized;
      }
      isBusy = false;
      isLoadingHome = false;
      switchingToServerName = null;
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
      VedroArtworkSignal.notifyRefresh();
      _startEventPolling();
      unawaited(refreshHome());
      unawaited(refreshMeQuota());
    } catch (e) {
      if (epoch == _sessionEpoch) {
        errorMessage = VedroErrorFormatter.format(e.toString());
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
}
