part of 'app_state.dart';

/// Home collections, playlists, track preferences, fonts, external players & danmaku.
extension VedroAppStateMedia on VedroAppState {
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
    views = _parseMediaItems(res['views']);
    popular = _parseMediaItems(res['popular']);
    resume = _parseMediaItems(res['resume']);
    nextUp = _parseMediaItems(res['next_up']);
    suggestions = _parseMediaItems(res['suggestions']);
    favorites = _parseMediaItems(res['favorites']);
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
      VedroArtworkSignal.notifyRefresh();
    } catch (e) {
      if (epoch == _sessionEpoch && !hasAnyHomeContent) {
        homeError = VedroErrorFormatter.format(e.toString());
      }
    } finally {
      if (epoch == _sessionEpoch) {
        isLoadingHome = false;
        switchingToServerName = null;
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
    playlists = _parseMediaItems(res['Items']);
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
        final items = _parseMediaItems(res['Items']);
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

  Future<String> importSubtitleFont(String sourcePath) async {
    final src = File(sourcePath.trim());
    if (!src.existsSync()) {
      throw Exception('找不到字体文件：$sourcePath');
    }
    final dir = Directory(fontsDirectoryPath);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final rawName = src.uri.pathSegments.isNotEmpty ? src.uri.pathSegments.last : 'font.ttf';
    final fileName = VedroAppStateDownloads._sanitizeDownloadFileName(
      rawName,
      fallback: 'font_${DateTime.now().millisecondsSinceEpoch}.ttf',
    );
    final dest = '${dir.path}/$fileName';
    if (!VedroAppStateDownloads._isPathInsideDirectory(dest, dir.path)) {
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
    final isDesktop = PlatformPerfProfile.isDesktop;
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

    if (PlatformPerfProfile.isMobileOs) {
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
}
