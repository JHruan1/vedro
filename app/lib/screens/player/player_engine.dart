part of '../player_screen.dart';

/// MPV engine lifecycle, hardware/filter/beauty pipeline, AI subtitle/ASR hooks & danmaku loader.
extension _PlayerEngineExt on _PlayerScreenState {
  Future<void> _applyMpvProperty(String key, String value) async {
    if (_disposed) return;
    final platform = _player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty(key, value);
      } catch (_) {}
    }
  }

  Future<String?> _readMpvProperty(String key) async {
    if (_disposed) return null;
    final platform = _player.platform;
    if (platform is NativePlayer) {
      try {
        return await platform.getProperty(key);
      } catch (_) {}
    }
    return null;
  }

  String? _matchVersionSourceForNextEpisode(MediaItemModel ep) {
    if (ep.mediaSources.length <= 1) return null;
    final prevSources = _prepared?.allSources ?? _currentItem.mediaSources;
    if (prevSources.isEmpty) return null;
    final prevId = _prepared?.mediaSourceId;
    final prevResolved = MediaSourceModel.resolveVersions(prevSources, stripEpisodePrefix: true);
    if (prevResolved.isEmpty) return null;
    final chosen = prevResolved.firstWhere(
      (v) => prevId != null && v.source.id == prevId,
      orElse: () => prevResolved.first,
    );
    final nextResolved = MediaSourceModel.resolveVersions(ep.mediaSources, stripEpisodePrefix: true);
    for (final nv in nextResolved) {
      if (nv.seriesMatchSignature == chosen.seriesMatchSignature) {
        return nv.source.id;
      }
    }
    return null;
  }

  Future<void> _switchEpisode(MediaItemModel ep, {double? overridePositionSecs}) async {
    _cancelUpNextCountdown();
    final matchedSourceId = _matchVersionSourceForNextEpisode(ep);
    await _reportStoppedAndCleanup(overridePositionSecs: overridePositionSecs);
    if (!mounted || _disposed) return;
    _completedTriggered = false;
    _hasEndedReplay = false;
    _customIntroSkipped = false;
    _customOutroSkipped = false;
    _quickSkipIntroDismissed = false;
    _quickSkipEligibleNotifier.value = false;
    _autoRetryCount = 0;
    _retryAnchorSecs = -1.0;
    _hwFallbackAttempted = false;
    _isInitialEpisode = false;
    _aiSubCtrl.resetForNewMedia(mediaTitle: ep.displayName);
    _activeSubLocalPath = null;
    _activeSubUrl = null;
    _activeSubFormat = null;
    _activeSubLabel = null;
    _secondarySubTrackId = null;
    unawaited(_applyMpvProperty('secondary-sid', 'no'));
    unawaited(_applyMpvProperty('sub-visibility', 'yes'));
    final localNext = _localPathById[ep.id];
    _setPlayerState(() {
      _currentItem = ep;
      if (localNext != null) {
        _activeLocalPath = localNext;
        _activeNetworkUrl = null;
      }
      _segments = const [];
      _chapters = const [];
      _showEpisodeDrawer = false;
      _positionSecs = 0;
      _bufferedSecs = 0;
      _positionNotifier.value = 0;
      _bufferedNotifier.value = 0;
      _activeSegmentNotifier.value = null;
      _durationSecs = 0;
      _danmakuComments = const [];
      _danmakuMatchTitle = null;
      _danmakuError = null;
    });
    if (localNext == null && !_isDirectNetwork) {
      unawaited(_fetchItemSegments(ep.id));
    }
    await _startPlayback(matchedSourceId);
    if (mounted && !_disposed && _danmakuEnabled) {
      unawaited(_loadDanmaku());
    }
  }

  Future<void> _fetchItemSegments(String itemId) async {
    try {
      final res = await widget.appState.core.invoke('get_item', {'item_id': itemId})
          as Map<String, dynamic>;
      final segs = ((res['segments'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MediaSegmentModel.fromJson)
          .toList();
      if (mounted && !_disposed && _currentItem.id == itemId && segs.isNotEmpty) {
        _setPlayerState(() => _segments = segs);
      }
    } catch (_) {}
  }

  Future<void> _applyVideoFilterChain() async {
    final filters = <String>[];
    if (_deinterlace) filters.add('yadif=mode=1');
    if (_hflip) filters.add('hflip');
    if (_vflip) filters.add('vflip');
    await _applyMpvProperty('vf', filters.join(','));
  }

  Future<void> _applyInitialPreferencesToMpv({
    Map<String, String> prepOptions = const {},
    bool applyInitialOverrides = false,
  }) async {
    if (_disposed) return;
    final p = widget.appState.prefs;
    const skipKeys = {'vo', 'ao', 'gpu-api', 'gpu-context'};
    final props = <String, String>{};
    for (final entry in prepOptions.entries) {
      if (!skipKeys.contains(entry.key)) {
        props[entry.key] = entry.value;
      }
    }

    final hwPref = (widget.appState.settings['hwdec'] ?? 'auto_zero_copy').toString();
    final hwVal = !_hwDecodeEnabled
        ? 'no'
        : (hwPref == 'auto_copy' ? 'auto-copy-safe' : 'auto-safe');
    props['hwdec'] = hwVal;
    props['hwdec-codecs'] = 'all';
    final preferNativeDv = widget.appState.settings['prefer_native_dolby_vision'] != false;
    props['target-colorspace-hint'] = preferNativeDv ? 'yes' : 'no';
    props['volume-max'] = '${_maxVolume.round()}';
    // Mobile thermal protection: avoid per-frame 4K compute-shader peak detection
    // and heavy display-resample / dithering on battery-powered phone SoCs.
    final effComputePeak = !_isMobile && p.hdrComputePeak;
    props['hdr-compute-peak'] = effComputePeak ? 'yes' : 'no';
    props['tone-mapping'] = _PlayerScreenState._normalizeToneMapping(_toneMapping);
    props['video-sync'] = _isMobile ? 'audio' : p.videoSync;
    final effBufMb = _isMobile ? p.bufferSizeMb.clamp(32, 96) : p.bufferSizeMb;
    props['demuxer-max-bytes'] = '${effBufMb}MiB';
    if (_isMobile && !_anime4kActive) {
      props['scale'] = 'bilinear';
      props['cscale'] = 'bilinear';
      props['dscale'] = 'bilinear';
      props['dither-depth'] = 'no';
    }

    // Apply preferred audio & subtitle language priorities:
    // Priority: Explicit initial override > per-series saved pref (`prepOptions`) > global preference.
    final hasExplicitAudioOverride =
        applyInitialOverrides && (widget.preferredAudioLangOverride?.isNotEmpty == true);
    final hasExplicitSubOverride = applyInitialOverrides &&
        (widget.initialSubtitleStreamIndex == -1 ||
            (widget.preferredSubLangOverride?.isNotEmpty == true));
    final effAudioPref =
        hasExplicitAudioOverride ? widget.preferredAudioLangOverride! : p.preferredAudioLang;
    final effSubPref =
        hasExplicitSubOverride ? (widget.preferredSubLangOverride ?? p.preferredSubLang) : p.preferredSubLang;
    final alang = switch (effAudioPref) {
      'zh' => 'cmn,zh,chi,zho,chs,cn,mandarin',
      'yue' => 'yue,cantonese,zh-hk,zho,chi',
      'ja' => 'ja,jpn,jp',
      'en' => 'en,eng',
      'ko' => 'ko,kor',
      _ => '',
    };
    if (alang.isNotEmpty) {
      if (hasExplicitAudioOverride || !props.containsKey('alang')) {
        props['alang'] = alang;
      }
    }
    if ((applyInitialOverrides && widget.initialSubtitleStreamIndex == -1) ||
        (effSubPref == 'off' && !props.containsKey('slang'))) {
      props['sid'] = 'no';
    } else if (props['sid'] != 'no') {
      final slang = switch (effSubPref) {
        'zh' => 'chs,sc,zh-cn,zh-hans,zh,chi,zho,cn',
        'zh-Hant' => 'cht,tc,zh-tw,zh-hk,zh-hant,zho,chi,zh',
        'en' => 'en,eng',
        'ja' => 'ja,jpn,jp',
        _ => '',
      };
      if (slang.isNotEmpty && (hasExplicitSubOverride || !props.containsKey('slang'))) {
        props['slang'] = slang;
      }
    }

    if (_audioDelaySecs.abs() > 0.001) {
      props['audio-delay'] = _audioDelaySecs.toStringAsFixed(3);
    }
    props['loop-file'] = _loopFile ? 'inf' : 'no';
    if (_eqBrightness != 0) props['brightness'] = '$_eqBrightness';
    if (_eqContrast != 0) props['contrast'] = '$_eqContrast';
    if (_eqSaturation != 0) props['saturation'] = '$_eqSaturation';
    if (_eqGamma != 0) props['gamma'] = '$_eqGamma';
    props['sub-fonts-dir'] = widget.appState.fontsDirectoryPath;
    if (_subFontFamily.trim().isNotEmpty) {
      props['sub-font'] = _subFontFamily.trim();
    }
    props['sub-ass-override'] = _forceAssOverride ? 'force' : 'no';
    props['sub-scale'] = _subScale.toStringAsFixed(2);
    props['sub-pos'] = '$_subPos';
    props['sub-color'] = p.subtitleColorHex;
    props['sub-border-size'] = p.subtitleOutlineWidth.toStringAsFixed(1);
    if (p.subtitleBgOpacity > 0.01) {
      props['sub-back-color'] = '0.0/0.0/0.0/${p.subtitleBgOpacity.toStringAsFixed(2)}';
    }
    if (_subDelaySecs != 0) {
      props['sub-delay'] = _subDelaySecs.toStringAsFixed(2);
    }
    props['video-autorotate'] = 'yes';
    if (_videoRotate != 0) {
      props['video-rotate'] = '$_videoRotate';
    }
    props['video-zoom'] = _videoZoom.toStringAsFixed(3);

    // Apply all deduplicated MPV properties in parallel to minimize startup latency
    await Future.wait(
      props.entries.map((e) => _applyMpvProperty(e.key, e.value)),
    );
    if (_disposed) return;
    await _applyAspectMode(_aspectMode);
    if (_disposed) return;
    await _applyAudioMode();
    if (_disposed) return;
    await _applyVideoFilterChain();
    if (_disposed) return;
    if (_anime4kActive) {
      await _applyAnime4k(true);
    }
    if (_disposed) return;
    if (_beautyParams.isActive) {
      await _applyBeautyParams(_beautyPreset, _beautyParams, persist: false, showHud: false);
    }
    if (_disposed) return;
    await _applyCustomMpvConf(p.customMpvConf);
    if (_disposed) return;
    await _applyVolumeToEngine(_muted ? 0.0 : _volume);
    if (_disposed) return;
    if ((_speed - 1.0).abs() > 0.01) {
      await _player.setRate(_speed);
    }
  }

  Future<void> _applyVolumeToEngine(double vol) async {
    final clamped = vol.clamp(0.0, _maxVolume);
    await _player.setVolume(clamped.clamp(0.0, 100.0));
    if (clamped > 100.0) {
      await _applyMpvProperty('volume', clamped.toStringAsFixed(1));
    }
  }

  Future<void> _applyAnime4k(bool enabled) async {
    if (!enabled) {
      await _applyMpvProperty('scale', _isMobile ? 'bilinear' : 'spline36');
      await _applyMpvProperty('cscale', _isMobile ? 'bilinear' : 'spline36');
      await _applyMpvProperty('sharpen', '0.0');
      await _applyMpvProperty('deband', widget.appState.settings['deband'] == true ? 'yes' : 'no');
      return;
    }
    final mode = widget.appState.prefs.anime4kMode;
    final sharp = switch (mode) {
      'A' || 'A+A' => '0.50',
      'B+B' => '0.42',
      'C' => '0.24',
      _ => '0.35',
    };
    await _applyMpvProperty('scale', 'ewa_lanczossharp');
    await _applyMpvProperty('cscale', 'ewa_lanczossharp');
    await _applyMpvProperty('deband', 'yes');
    await _applyMpvProperty('sharpen', sharp);
  }

  Future<void> _applyBeautyPreset(
    String presetId, {
    bool persist = true,
    bool showHud = true,
  }) async {
    final preset = BeautyFilterPreset.byId(presetId);
    await _applyBeautyParams(
      preset.id,
      preset.params,
      persist: persist,
      showHud: showHud,
      debounceShader: false,
    );
  }

  Future<void> _applyBeautyParams(
    String presetId,
    BeautyFilterParams rawParams, {
    bool persist = true,
    bool showHud = true,
    bool debounceShader = false,
  }) async {
    final params = rawParams.clamped();
    final effectivePreset = !params.isActive ? 'off' : presetId;
    if (mounted) {
      _setPlayerState(() {
        _beautyPreset = effectivePreset;
        _beautyParams = params;
      });
    } else {
      _beautyPreset = effectivePreset;
      _beautyParams = params;
    }

    Future<void> applyGpuShader() async {
      if (_disposed) return;
      if (!params.isActive) {
        await _applyMpvProperty('glsl-shaders', '');
        return;
      }
      try {
        final shaderPath = await BeautyFilterEngine.prepareShaderFileForParams(
          params,
          label: effectivePreset,
          mobileLean: _isMobile,
        );
        if (!_disposed && shaderPath != null && shaderPath.isNotEmpty) {
          await _applyMpvProperty('glsl-shaders', shaderPath.replaceAll('\\', '/'));
        }
      } catch (_) {
        if (!_disposed) await _applyMpvProperty('glsl-shaders', '');
      }
    }

    _beautyShaderDebounce?.cancel();
    if (debounceShader && params.isActive) {
      _beautyShaderDebounce = Timer(const Duration(milliseconds: 140), () {
        unawaited(applyGpuShader());
      });
    } else {
      await applyGpuShader();
    }

    if (persist) {
      unawaited(widget.appState.updatePrefs(
        widget.appState.prefs.copyWith(
          beautyFilterPreset: effectivePreset,
          beautyFilterStrength: _beautyStrength,
          beautySmooth: params.smooth,
          beautyWhiten: params.whiten,
          beautyRosy: params.rosy,
          beautyClarity: params.clarity,
        ),
      ));
    }
    if (showHud && mounted) {
      _flashGestureHud(
        'seek_feedback',
        text: !params.isActive
            ? '已关闭美颜'
            : '美颜：${BeautyFilterPreset.displayLabelFor(effectivePreset, params)}（${params.summaryLabel()}）',
      );
    }
  }

  ({String? localPath, String? url, String? format, String? label})
      _resolveBestSubtitleSourceForAi() {
    if (_activeSubLocalPath != null && _activeSubLocalPath!.isNotEmpty) {
      return (
        localPath: _activeSubLocalPath,
        url: null,
        format: null,
        label: _activeSubLabel ?? '本地字幕',
      );
    }
    if (_activeSubUrl != null && _activeSubUrl!.isNotEmpty) {
      return (
        localPath: null,
        url: _activeSubUrl,
        format: _activeSubFormat,
        label: _activeSubLabel ?? '外挂字幕',
      );
    }
    final textSubs = _prepared?.textSubtitles ?? const [];
    if (textSubs.isNotEmpty) {
      final curTrack = _player.state.track.subtitle;
      final curId = curTrack.id;
      final curTitle = (curTrack.title ?? '').toLowerCase();
      final curLang = (curTrack.language ?? '').toLowerCase();
      Map<String, dynamic>? matched;
      for (final s in textSubs) {
        final idx = s['index']?.toString() ?? '';
        final title = (s['title'] ?? '').toString().toLowerCase();
        final lang = (s['language'] ?? '').toString().toLowerCase();
        if ((curId != 'no' && curId != 'auto' && idx == curId) ||
            (curTitle.isNotEmpty && title == curTitle) ||
            (curLang.isNotEmpty && lang == curLang)) {
          matched = s;
          break;
        }
      }
      matched ??= textSubs.first;
      return (
        localPath: null,
        url: matched['url']?.toString(),
        format: matched['codec']?.toString(),
        label: matched['title']?.toString() ?? '字幕轨',
      );
    }
    return (localPath: null, url: null, format: null, label: null);
  }

  Future<void> _enableAiSubtitleTranslation({String? targetLangOverride}) async {
    if (!widget.appState.prefs.isAiReady) {
      _flashGestureHud('seek_feedback', text: '请先在「设置 → AI 翻译」开启并配置模型');
      return;
    }
    final src = _resolveBestSubtitleSourceForAi();
    await _applyMpvProperty('sub-visibility', 'no');
    if (!mounted || _disposed) return;
    await _aiSubCtrl.enable(
      subtitleUrl: src.url,
      localPath: src.localPath,
      format: src.format,
      sourceLabel: src.label,
      currentPositionSecs: _positionSecs,
      displayMode: widget.appState.prefs.aiSubtitleMode,
      targetLang: targetLangOverride ?? _aiSubCtrl.targetLang,
    );
    if (mounted && !_disposed) {
      _flashGestureHud(
        'seek_feedback',
        text: 'AI 双语字幕已开启 → ${_aiSubCtrl.targetLang}',
      );
    }
  }

  Future<void> _enableAiAsrSubtitle() async {
    if (widget.appState.prefs.asrEngine == 'local') {
      await LocalAsrManager.instance.refreshStatus();
    }
    if (!mounted || _disposed) return;
    if (!widget.appState.isAsrReadyForPlayback) {
      _flashGestureHud(
        'seek_feedback',
        text: widget.appState.prefs.asrEngine == 'local'
            ? '请先在「设置 → AI 翻译」下载本地离线语音模型 (~229 MB)'
            : '请先在「设置 → AI 翻译」配置云端语音识别 (ASR)',
      );
      return;
    }
    await _applyMpvProperty('sub-visibility', 'no');
    if (!mounted || _disposed) return;
    await _aiSubCtrl.enableAsr(
      sourceUrl: _prepared?.proxyUrl ?? _activeNetworkUrl,
      localPath: _activeLocalPath,
      currentPositionSecs: _positionSecs,
      durationSecs: _durationSecs,
      sourceLang: widget.appState.prefs.asrSourceLang,
      targetLang: _aiSubCtrl.targetLang,
      displayMode: widget.appState.prefs.aiSubtitleMode,
    );
    if (mounted && !_disposed) {
      _flashGestureHud(
        'seek_feedback',
        text: widget.appState.prefs.asrEngine == 'local'
            ? '本地离线 SenseVoice 听音识字已开启…'
            : 'AI 听音识字已开启，正在预读识别…',
      );
    }
  }

  Future<void> _disableAiSubtitle() async {
    _aiSubCtrl.disable();
    unawaited(LocalAsrManager.instance.unloadEngine());
    await _applyMpvProperty('sub-visibility', 'yes');
    if (mounted) {
      _flashGestureHud('seek_feedback', text: '已关闭 AI 字幕翻译');
    }
  }

  Future<void> _applyCustomMpvConf(String raw) async {
    if (raw.trim().isEmpty) return;
    // Strict allowlist of safe video/audio/subtitle/demuxer tuning keys (blocks IPC/script/file/dump injection)
    const allowed = {
      'interpolation',
      'tscale',
      'tscale-window',
      'tscale-clamp',
      'tscale-radius',
      'tscale-antiring',
      'scale',
      'cscale',
      'dscale',
      'scale-antiring',
      'cscale-antiring',
      'correct-downscaling',
      'linear-downscaling',
      'sigmoid-upscaling',
      'deband',
      'deband-iterations',
      'deband-threshold',
      'deband-range',
      'deband-grain',
      'dither',
      'dither-depth',
      'dither-size-fruit',
      'temporal-dither',
      'sharpen',
      'tone-mapping',
      'tone-mapping-param',
      'tone-mapping-max-boost',
      'hdr-compute-peak',
      'hdr-peak-percentile',
      'gamut-mapping-mode',
      'target-peak',
      'target-trc',
      'target-prim',
      'target-contrast',
      'video-sync',
      'video-sync-max-video-change',
      'video-sync-max-factor',
      'audio-pitch-correction',
      'audio-normalize-downmix',
      'audio-channels',
      'sub-fix-timing',
      'sub-gauss',
      'sub-gray',
      'sub-margin-y',
      'sub-margin-x',
      'sub-bold',
      'sub-italic',
      'sub-shadow-offset',
      'sub-shadow-color',
      'sub-spacing',
      'sub-line-height',
      'sub-ass-force-margins',
      'blend-subtitles',
      'demuxer-readahead-secs',
      'demuxer-max-back-bytes',
      'cache-secs',
      'hr-seek',
      'hr-seek-framedrop',
      'framedrop',
      'vd-lavc-threads',
      'ad-lavc-downmix',
    };
    for (final rawLine in raw.split('\n')) {
      final line = rawLine.split('#').first.trim();
      if (line.isEmpty) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final k = line.substring(0, eq).trim().toLowerCase();
      final v = line.substring(eq + 1).trim();
      if (k.isEmpty || !allowed.contains(k)) continue;
      await _applyMpvProperty(k, v);
    }
  }

  Future<void> _toggleHwDecode() async {
    final next = !_hwDecodeEnabled;
    _setPlayerState(() => _hwDecodeEnabled = next);
    await _applyMpvProperty('hwdec', next ? 'auto-safe' : 'no');
    _flashGestureHud('seek_feedback', text: next ? '硬件解码 (HW)' : '软件解码 (SW)');
  }

  Future<void> _rotateVideo([int? targetAngle]) async {
    final next = targetAngle ?? ((_videoRotate + 90) % 360);
    _setPlayerState(() => _videoRotate = next);
    await _applyMpvProperty('video-rotate', '$next');
    _flashGestureHud('seek_feedback', text: '旋转 $next°');
  }

  Future<void> _setVideoZoom(double zoom, {bool showHud = true}) async {
    final clamped = zoom.clamp(-0.5, 1.5);
    _setPlayerState(() => _videoZoom = clamped);
    await _applyMpvProperty('video-zoom', clamped.toStringAsFixed(3));
    if (showHud) {
      final pct = (100.0 * math.pow(2.0, clamped)).round();
      _flashGestureHud('seek_feedback', text: '缩放 $pct%');
    }
  }

  Future<void> _takeScreenshot() async {
    try {
      final bytes = await _player.screenshot(
        format: 'image/png',
        includeLibassSubtitles: true,
      );
      if (bytes == null || bytes.isEmpty) {
        _flashGestureHud('seek_feedback', text: '当前画面暂不支持截图');
        return;
      }
      final safeTitle = _currentItem.displayName
          .replaceAll(RegExp(r'[^\w\u4e00-\u9fff\-_. ]+'), '_')
          .trim();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${safeTitle.isEmpty ? 'vedro' : safeTitle}_$ts.png';
      final gallerySaved = await NativePlaybackChannel.saveScreenshotToGallery(
        bytes,
        fileName,
      );
      if (gallerySaved != null && gallerySaved.isNotEmpty) {
        _flashGestureHud(
          'seek_feedback',
          text: _isMobile ? '已保存截图到系统相册' : '已保存截图到图片目录',
        );
        return;
      }
      final dir = Directory('${widget.appState.downloadsDirectoryPath}/screenshots');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      _flashGestureHud('seek_feedback', text: '已保存截图');
    } catch (_) {
      _flashGestureHud('seek_feedback', text: '截图失败');
    }
  }

  String _fmtSpeed(double s) {
    final rounded2 = (s * 100).round() / 100.0;
    if ((rounded2 - rounded2.roundToDouble()).abs() < 0.005) {
      return '${rounded2.toStringAsFixed(1)}×';
    }
    if (((rounded2 * 10) - (rounded2 * 10).roundToDouble()).abs() < 0.005) {
      return '${rounded2.toStringAsFixed(1)}×';
    }
    return '${rounded2.toStringAsFixed(2)}×';
  }

  Future<void> _loadDanmaku({String? queryOverride}) async {
    final gen = ++_danmakuGen;
    final query = (queryOverride ?? (_currentItem.seriesName ?? _currentItem.displayName)).trim();
    if (query.isEmpty) return;
    _setPlayerState(() {
      _danmakuLoading = true;
      _danmakuError = null;
    });
    try {
      final res = await widget.appState.fetchDanmaku(
        query,
        altTitle: queryOverride == null ? _currentItem.originalTitle : null,
        season: _currentItem.parentIndexNumber,
        episode: _currentItem.indexNumber,
      );
      if (!mounted || gen != _danmakuGen) return;
      _setPlayerState(() {
        _danmakuComments = res.comments;
        _danmakuMatchTitle = res.title.isNotEmpty ? res.title : query;
        _danmakuLoading = false;
      });
      if (_danmakuEnabled) {
        _flashGestureHud(
          'seek_feedback',
          text: res.comments.isEmpty ? '未匹配到弹幕' : '已加载 ${res.comments.length} 条弹幕',
        );
      }
    } catch (e) {
      if (!mounted || gen != _danmakuGen) return;
      _setPlayerState(() {
        _danmakuLoading = false;
        _danmakuError = VedroErrorFormatter.friendly(e);
      });
    }
  }

  Future<void> _pickLocalDanmakuXml() async {
    final picked = await NativePlaybackChannel.pickFiles(
      extensions: const ['xml'],
      title: '选择本地 B 站格式 XML 弹幕文件',
    );
    if (picked.isEmpty) return;
    try {
      final raw = await File(picked.first).readAsString();
      final parsed = DanmakuComment.parseBilibiliXml(raw);
      if (!mounted) return;
      final fileName = picked.first.replaceAll('\\', '/').split('/').last;
      _setPlayerState(() {
        _danmakuComments = parsed;
        _danmakuMatchTitle = fileName;
        _danmakuError = parsed.isEmpty ? '该 XML 文件未解析出有效弹幕' : null;
        if (parsed.isNotEmpty) _danmakuEnabled = true;
      });
      if (parsed.isNotEmpty) {
        _flashGestureHud('seek_feedback', text: '已加载本地弹幕 ${parsed.length} 条');
      }
    } catch (e) {
      if (mounted) {
        _setPlayerState(() => _danmakuError = '读取本地弹幕失败：$e');
      }
    }
  }

  Future<void> _startPlayback(String? sourceId, {double? resumeFromSecs}) async {
    if (!mounted || _disposed) return;
    final gen = ++_playbackGen;
    final isReconnectOrSwitch = resumeFromSecs != null;
    final savedAudioId = isReconnectOrSwitch ? _player.state.track.audio.id : null;
    final savedSubId = isReconnectOrSwitch ? _player.state.track.subtitle.id : null;
    final savedLocalSub = isReconnectOrSwitch ? _activeSubLocalPath : null;
    final savedExtSubUrl = isReconnectOrSwitch ? _activeSubUrl : null;
    final savedExtSubLabel = isReconnectOrSwitch ? _activeSubLabel : null;
    final savedSecondarySub = isReconnectOrSwitch ? _secondarySubTrackId : null;

    _setPlayerState(() {
      _loading = true;
      _error = null;
      _hasEndedReplay = false;
    });
    final applyInitialOverrides = _isInitialEpisode;
    _isInitialEpisode = false;
    try {
      final p = widget.appState.prefs;

      // 1. Direct network stream URL (http/https/rtsp/rtmp/mms/udp/rtp)
      if (_isDirectNetwork) {
        final netUrl = _activeNetworkUrl!;
        await _applyInitialPreferencesToMpv(applyInitialOverrides: applyInitialOverrides);
        if (!mounted || _disposed || gen != _playbackGen) return;
        final startSecs = resumeFromSecs ?? 0.0;
        await _player.open(
          Media(
            netUrl,
            start: startSecs > 3.0 ? Duration(milliseconds: (startSecs * 1000).round()) : null,
          ),
          play: true,
        );
        if (!mounted || _disposed || gen != _playbackGen) return;
        if (!p.incognitoMode) {
          unawaited(widget.appState.recordLocalHistory(
            title: _currentItem.displayName,
            target: netUrl,
            isNetworkUrl: true,
            positionSecs: startSecs,
            durationSecs: _durationSecs,
          ));
        }
        if (applyInitialOverrides &&
            widget.initialExternalSubtitlePath != null &&
            widget.initialExternalSubtitlePath!.trim().isNotEmpty) {
          await _loadExternalSubtitleFile(widget.initialExternalSubtitlePath!);
        } else if (savedLocalSub != null && savedLocalSub.isNotEmpty) {
          await _loadExternalSubtitleFile(savedLocalSub);
        }
        if (_aiSubCtrl.enabled && _aiSubCtrl.asrMode) {
          _aiSubCtrl.updateAsrMediaSource(sourceUrl: netUrl, localPath: null);
        }
        if (!mounted || _disposed || gen != _playbackGen) return;
        _setPlayerState(() {
          _loading = false;
          _paused = false;
        });
        _syncNowPlaying(force: true);
        _scheduleHideControls();
        _startTimers();
        return;
      }

      // 2. Local offline downloaded / user-picked video file
      if (_isLocalFile) {
        final localPath = _activeLocalPath!;
        await _applyInitialPreferencesToMpv(applyInitialOverrides: applyInitialOverrides);
        if (!mounted || _disposed || gen != _playbackGen) return;
        double startSecs = resumeFromSecs ?? 0.0;
        if (resumeFromSecs == null && p.rememberPosition) {
          startSecs = await widget.appState.getLocalResumeSecs(localPath);
        }
        if (!mounted || _disposed || gen != _playbackGen) return;
        await _player.open(
          Media(
            localPath,
            start: startSecs > 3.0 ? Duration(milliseconds: (startSecs * 1000).round()) : null,
          ),
          play: true,
        );
        if (!mounted || _disposed || gen != _playbackGen) return;
        if (!p.incognitoMode) {
          unawaited(widget.appState.recordLocalHistory(
            title: _currentItem.displayName,
            target: localPath,
            isNetworkUrl: false,
            positionSecs: startSecs,
            durationSecs: _durationSecs,
          ));
        }
        if (applyInitialOverrides &&
            widget.initialExternalSubtitlePath != null &&
            widget.initialExternalSubtitlePath!.trim().isNotEmpty) {
          await _loadExternalSubtitleFile(widget.initialExternalSubtitlePath!);
        } else if (savedLocalSub != null && savedLocalSub.isNotEmpty) {
          await _loadExternalSubtitleFile(savedLocalSub);
        } else if (p.autoLoadExternalSubs &&
            (!applyInitialOverrides || widget.initialSubtitleStreamIndex != -1) &&
            p.preferredSubLang != 'off') {
          final sidecars = NativePlaybackChannel.findSidecarSubtitles(localPath);
          if (sidecars.isNotEmpty) {
            final subPath = sidecars.first;
            final title = subPath.replaceAll('\\', '/').split('/').last;
            _activeSubLocalPath = subPath;
            _activeSubUrl = null;
            _activeSubFormat = null;
            _activeSubLabel = title;
            await _player.setSubtitleTrack(
              SubtitleTrack.uri(Uri.file(subPath).toString(), title: title),
            );
          }
        }
        if (_aiSubCtrl.enabled && _aiSubCtrl.asrMode) {
          _aiSubCtrl.updateAsrMediaSource(sourceUrl: null, localPath: localPath);
        }
        if (!mounted || _disposed || gen != _playbackGen) return;
        _setPlayerState(() {
          _loading = false;
          _paused = false;
        });
        _syncNowPlaying(force: true);
        _scheduleHideControls();
        _startTimers();
        return;
      }

      // 3. Emby / Jellyfin / EmbyGo server stream
      if (_segments.isEmpty) {
        unawaited(_fetchItemSegments(_currentItem.id));
      }
      ({String? audioLang, String? subtitleLang, int? audioIndex, int? subtitleIndex})? savedTrackPref;
      final scopeId = _trackPrefScopeId;
      if (scopeId != null &&
          !isReconnectOrSwitch &&
          (!applyInitialOverrides ||
              (widget.initialAudioStreamIndex == null &&
                  widget.initialSubtitleStreamIndex == null))) {
        savedTrackPref = await widget.appState.getTrackPreference(scopeId);
        if (!mounted || _disposed || gen != _playbackGen) return;
      }

      final prepRaw = await widget.appState.core.invoke('prepare_playback', {
        'item_id': _currentItem.id,
        if (sourceId != null) 'media_source_id': sourceId,
        if (applyInitialOverrides && widget.initialAudioStreamIndex != null)
          'audio_stream_index': widget.initialAudioStreamIndex,
        if (applyInitialOverrides && widget.initialSubtitleStreamIndex != null)
          'subtitle_stream_index': widget.initialSubtitleStreamIndex,
        'inspect_header': true,
      }) as Map<String, dynamic>;
      if (!mounted || _disposed || gen != _playbackGen) return;

      final prep = PreparedPlaybackModel.fromJson(prepRaw);
      final prepOptions = Map<String, String>.from(prep.mpvOptions);
      if (savedTrackPref != null) {
        final prefAlang = savedTrackPref.audioLang?.trim() ?? '';
        final prefSlang = savedTrackPref.subtitleLang?.trim() ?? '';
        if (prefAlang.isNotEmpty) prepOptions['alang'] = prefAlang;
        if (prefSlang == 'off') {
          prepOptions['sid'] = 'no';
        } else if (prefSlang.isNotEmpty) {
          prepOptions['slang'] = prefSlang;
        }
      }
      await _applyInitialPreferencesToMpv(
        prepOptions: prepOptions,
        applyInitialOverrides: applyInitialOverrides,
      );
      if (!mounted || _disposed || gen != _playbackGen) return;

      final Duration? startDur;
      if (resumeFromSecs != null && resumeFromSecs > 1.0) {
        startDur = Duration(milliseconds: (resumeFromSecs * 1000).round());
      } else if (p.rememberPosition && _currentItem.playbackPositionTicks > 0) {
        startDur = Duration(microseconds: _currentItem.playbackPositionTicks ~/ 10);
      } else {
        startDur = null;
      }

      await _player.open(
        Media(prep.proxyUrl, start: startDur),
        play: true,
      );
      if (!mounted || _disposed || gen != _playbackGen) return;

      // Restore live tracks on reconnect / HW->SW fallback, or apply initial/preferred tracks
      if (isReconnectOrSwitch) {
        if (savedAudioId != null && savedAudioId != 'auto' && savedAudioId != 'no') {
          unawaited(_applyMpvProperty('aid', savedAudioId));
        }
        if (savedLocalSub != null && savedLocalSub.isNotEmpty) {
          await _loadExternalSubtitleFile(savedLocalSub);
        } else if (savedExtSubUrl != null && savedExtSubUrl.isNotEmpty) {
          await _player.setSubtitleTrack(
            SubtitleTrack.uri(savedExtSubUrl, title: savedExtSubLabel),
          );
        } else if (savedSubId == 'no') {
          await _player.setSubtitleTrack(SubtitleTrack.no());
        } else if (savedSubId != null && savedSubId != 'auto') {
          unawaited(_applyMpvProperty('sid', savedSubId));
        }
        if (savedSecondarySub != null && savedSecondarySub.isNotEmpty) {
          unawaited(_applyMpvProperty('secondary-sid', savedSecondarySub));
        }
      } else if (applyInitialOverrides &&
          widget.initialExternalSubtitlePath != null &&
          widget.initialExternalSubtitlePath!.trim().isNotEmpty) {
        await _loadExternalSubtitleFile(widget.initialExternalSubtitlePath!);
      } else if ((applyInitialOverrides && widget.initialSubtitleStreamIndex == -1) ||
          savedTrackPref?.subtitleLang == 'off' ||
          p.preferredSubLang == 'off') {
        await _player.setSubtitleTrack(SubtitleTrack.no());
      } else if (applyInitialOverrides && widget.initialSubtitleStreamIndex != null) {
        Map<String, dynamic>? chosenExt;
        for (final sub in prep.externalSubtitles) {
          if ((sub['index'] as num?)?.toInt() == widget.initialSubtitleStreamIndex &&
              sub['url'] != null) {
            chosenExt = sub;
            break;
          }
        }
        if (chosenExt != null) {
          _activeSubLocalPath = null;
          _activeSubUrl = chosenExt['url'].toString();
          _activeSubFormat = chosenExt['codec']?.toString();
          _activeSubLabel = chosenExt['title']?.toString();
          await _player.setSubtitleTrack(
            SubtitleTrack.uri(
              chosenExt['url'].toString(),
              title: chosenExt['title']?.toString(),
              language: chosenExt['language']?.toString(),
            ),
          );
        }
      } else if (p.autoLoadExternalSubs && prep.externalSubtitles.isNotEmpty) {
        Map<String, dynamic>? preferredExt;
        final prefLang =
            (savedTrackPref?.subtitleLang ?? p.preferredSubLang).toLowerCase();
        for (final sub in prep.externalSubtitles) {
          if (sub['url'] == null) continue;
          final lang = (sub['language'] ?? '').toString().toLowerCase();
          final title = (sub['title'] ?? '').toString().toLowerCase();
          if (prefLang == 'zh' &&
              (lang.contains('zh') || lang.contains('chi') || lang.contains('chs') || title.contains('简'))) {
            preferredExt = sub;
            break;
          }
          if (prefLang == 'zh-hant' &&
              (lang.contains('cht') || lang.contains('tw') || lang.contains('hk') || title.contains('繁'))) {
            preferredExt = sub;
            break;
          }
          if (prefLang == 'en' && (lang.contains('en') || title.contains('eng'))) {
            preferredExt = sub;
            break;
          }
          if (prefLang.isNotEmpty && lang.contains(prefLang)) {
            preferredExt = sub;
            break;
          }
        }
        preferredExt ??= prep.externalSubtitles.cast<Map<String, dynamic>?>().firstWhere(
              (s) => s?['is_default'] == true && s?['url'] != null,
              orElse: () => prep.externalSubtitles.first,
            );
        if (preferredExt != null && preferredExt['url'] != null) {
          _activeSubLocalPath = null;
          _activeSubUrl = preferredExt['url'].toString();
          _activeSubFormat = preferredExt['codec']?.toString();
          _activeSubLabel = preferredExt['title']?.toString();
          await _player.setSubtitleTrack(
            SubtitleTrack.uri(
              preferredExt['url'].toString(),
              title: preferredExt['title']?.toString(),
              language: preferredExt['language']?.toString(),
            ),
          );
        }
      }

      if (_aiSubCtrl.enabled && _aiSubCtrl.asrMode) {
        _aiSubCtrl.updateAsrMediaSource(sourceUrl: prep.proxyUrl, localPath: null);
      }

      if (!p.incognitoMode) {
        unawaited(
          widget.appState.core
              .invoke('report_playback_start', {
                'item_id': _currentItem.id,
                'media_source_id': prep.mediaSourceId,
                'play_session_id': prep.playSessionId,
                'position_ticks': startDur != null ? startDur.inMicroseconds * 10 : 0,
                if (_currentItem.runTimeTicks != null) 'run_time_ticks': _currentItem.runTimeTicks,
                'is_paused': false,
              })
              .catchError((_) => null),
        );
      }

      if (!mounted || _disposed || gen != _playbackGen) return;
      _setPlayerState(() {
        _prepared = prep;
        _loading = false;
        _paused = false;
      });
      _syncNowPlaying(force: true);
      _scheduleHideControls();
      _startTimers();
    } catch (e) {
      if (mounted && !_disposed && gen == _playbackGen) {
        _setPlayerState(() {
          _error = VedroErrorFormatter.friendly(e);
          _loading = false;
          _controlsVisible = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _error != null && _errorRetryFocusNode.canRequestFocus) {
            _errorRetryFocusNode.requestFocus();
          }
        });
      }
    }
  }

  void _startTimers() {
    if (!mounted || _disposed) return;

    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(milliseconds: 900), (_) async {
      if (!mounted || _disposed || !_showStats) return;
      try {
        final rustStats = await widget.appState.core.invoke('player_stats') as Map<String, dynamic>;
        final results = await Future.wait([
          _readMpvProperty('video-codec'),
          _readMpvProperty('hwdec-current'),
          _readMpvProperty('width'),
          _readMpvProperty('height'),
          _readMpvProperty('estimated-vf-fps'),
          _readMpvProperty('frame-drop-count'),
          _readMpvProperty('audio-codec-name'),
          _readMpvProperty('audio-params/channels'),
        ]);
        if (!mounted || _disposed) return;
        _statsNotifier.value = {
          'proxy': rustStats['proxy'],
          'playback': {
            'video_codec': results[0],
            'hwdec_current': results[1] ?? 'auto-safe',
            'width': int.tryParse(results[2] ?? '') ?? 0,
            'height': int.tryParse(results[3] ?? '') ?? 0,
            'fps': double.tryParse(results[4] ?? '') ?? 0.0,
            'dropped_frames': int.tryParse(results[5] ?? '') ?? 0,
            'audio_codec': results[6],
            'audio_channels': results[7],
            'hdr_decision': {'explanation': _prepared?.hdrExplanation ?? 'Direct Play'},
            'audio_decision': {'summary': _prepared?.audioSummary ?? 'Auto'},
          },
        };
      } catch (_) {}
    });

    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted || _disposed || widget.appState.prefs.incognitoMode) return;
      if (_isLocalFile) {
        if (!_paused && _positionSecs > 3.0) {
          await widget.appState.saveLocalResumeSecs(_activeLocalPath!, _positionSecs);
        }
        return;
      }
      if (_isDirectNetwork) return;
      try {
        await widget.appState.core.invoke('report_playback_progress', {
          'item_id': _currentItem.id,
          if (_prepared?.mediaSourceId != null) 'media_source_id': _prepared!.mediaSourceId,
          if (_prepared?.playSessionId != null) 'play_session_id': _prepared!.playSessionId,
          'position_ticks': (_positionSecs * 10000000).round(),
          if (_durationSecs > 0) 'run_time_ticks': (_durationSecs * 10000000).round(),
          'is_paused': _paused,
        });
        await widget.appState.core.invoke('report_playback_ping');
      } catch (_) {}
    });

    _ticketRefreshTimer?.cancel();
    if (_prepared?.usesStreamTicket == true) {
      _ticketRefreshTimer = Timer.periodic(const Duration(minutes: 7), (_) async {
        if (!mounted || _disposed) return;
        try {
          await widget.appState.core.invoke('refresh_stream_ticket');
        } catch (_) {}
      });
    }

    _speedTimer?.cancel();
    if (!_isLocalFile) {
      _speedTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (!mounted || _disposed) return;
        final showSpeed = widget.appState.prefs.showNetworkSpeed;
        if (!showSpeed && !_buffering && !_loading) return;
        try {
          // Lock-free atomic read from Rust StreamProxy for Emby/Jellyfin; mpv cache-speed for direct network URLs
          int bps = _isServerStream ? widget.appState.core.proxySpeedBps : 0;
          if (bps <= 0 && (_isDirectNetwork || _buffering || _loading)) {
            final mpvSpeed = await _readMpvProperty('cache-speed');
            bps = double.tryParse(mpvSpeed ?? '')?.round() ?? 0;
          }
          if (mounted && !_disposed) {
            final safeBps = bps < 0 ? 0 : bps;
            if (_networkSpeedBpsNotifier.value != safeBps) {
              _networkSpeedBpsNotifier.value = safeBps;
            }
          }
        } catch (_) {}
      });
    }
  }

  Future<void> _reportStoppedAndCleanup({double? overridePositionSecs}) async {
    if (!_isServerStream) return;
    final prep = _prepared;
    final reportSecs = overridePositionSecs ?? _positionSecs;
    try {
      if (!widget.appState.prefs.incognitoMode) {
        await widget.appState.core.invoke('report_playback_stopped', {
          'item_id': _currentItem.id,
          if (prep?.mediaSourceId != null) 'media_source_id': prep!.mediaSourceId,
          if (prep?.playSessionId != null) 'play_session_id': prep!.playSessionId,
          if (prep?.streamId != null) 'stream_id': prep!.streamId,
          'position_ticks': (reportSecs * 10000000).round(),
          if (_durationSecs > 0) 'run_time_ticks': (_durationSecs * 10000000).round(),
          'is_paused': true,
        });
      }
      await widget.appState.core.invoke('player_stop', {
        if (prep?.streamId != null) 'stream_id': prep!.streamId,
      });
    } catch (_) {}
  }


  Future<void> _applyAudioMode() async {
    await _applyMpvProperty('audio-channels', _audioMode == 'pcm_stereo' ? 'stereo' : 'auto-safe');
    if (_audioMode == 'passthrough_bitstream') {
      await _applyMpvProperty('audio-spdif', 'ac3,eac3,dts,dts-hd,truehd');
      await _applyMpvProperty('af', '');
    } else {
      await _applyMpvProperty('audio-spdif', '');
      final filters = <String>[];
      if (_audioMode == 'headphone_binaural') {
        filters.add('lavfi=[bs2b=fcut=700:feed=45]');
      }
      if (_dialogueBoost) {
        filters.add('lavfi=[equalizer=f=2200:t=q:w=1.2:g=4.0]');
      }
      if (_nightMode) {
        filters.add('lavfi=[acompressor=threshold=-20dB:ratio=4:attack=10:release=150:makeup=4dB]');
      }
      if (_loudnessNorm) {
        filters.add('lavfi=[dynaudnorm=f=150:g=15:p=0.95]');
      }
      await _applyMpvProperty('af', filters.join(','));
    }
  }
}
