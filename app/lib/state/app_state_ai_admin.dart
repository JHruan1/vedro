part of 'app_state.dart';

/// AI translation/ASR RPCs, EmbyGo admin console, devices, speed test & image cache.
extension VedroAppStateAiAdmin on VedroAppState {
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
}
