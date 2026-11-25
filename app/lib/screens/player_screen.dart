import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/models/models.dart';
import '../core/platform/native_playback_channel.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/danmaku_engine.dart';
import '../widgets/nerd_stats_hud.dart';
import '../widgets/vedro_artwork.dart';
import '../widgets/vedro_ui.dart';

/// IINA / Infuse / SenPlayer caliber native GPU cinema player:
/// - Zero-transcode DirectPlay of 4K Remux, Dolby Vision, Dolby Atmos, PGS/ASS subtitles
/// - Custom precision scrub bar (hover expand, buffered bar, segment markers, hover time tooltip)
/// - Auto-hiding cursor + hover-kept chrome + centered transport + inline desktop volume slider
/// - Full touch gestures (scrub HUD, left brightness, right volume, double-tap ±N s, long-press 2×)
/// - Skip Intro/Outro button (+ optional auto-skip), Episode Drawer, Aspect, Subtitle Style, Danmaku
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.item,
    required this.appState,
    this.mediaSourceId,
    this.playlistEpisodes,
    this.segments,
    this.initialAudioStreamIndex,
    this.initialSubtitleStreamIndex,
    this.localFilePath,
  });

  final MediaItemModel item;
  final VedroAppState appState;
  final String? mediaSourceId;
  final List<MediaItemModel>? playlistEpisodes;
  final List<MediaSegmentModel>? segments;
  final int? initialAudioStreamIndex;
  final int? initialSubtitleStreamIndex;
  final String? localFilePath;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;

  late MediaItemModel _currentItem;
  late List<MediaSegmentModel> _segments;

  PreparedPlaybackModel? _prepared;
  Map<String, dynamic> _stats = {};
  bool _loading = true;
  String? _error;

  bool _controlsVisible = true;
  bool _hoveringChrome = false;
  bool _showStats = false;
  bool _showEpisodeDrawer = false;
  bool _showRemaining = false;
  bool _paused = false;
  bool _muted = false;
  double _preMuteVolume = 100.0;
  double _positionSecs = 0;
  double _bufferedSecs = 0;
  double _durationSecs = 0;
  double _speed = 1.0;
  double _preBoostSpeed = 1.0;
  bool _isSpeedBoost = false;
  double _volume = 100.0;
  double _brightness = 1.0;

  // Live synced with preferences
  bool _hwDecodeEnabled = true;
  int _videoRotate = 0;
  double _videoZoom = 0.0;
  double _pinchBaseZoom = 0.0;
  bool _anime4kActive = false;
  double _subDelaySecs = 0.0;
  double _subScale = 1.0;
  int _subPos = 96;
  String _subFontFamily = '';
  bool _forceAssOverride = false;
  String _aspectMode = 'fit';
  String _toneMapping = 'bt.2446a';
  String _audioMode = 'auto';
  bool _nightMode = false;
  bool _dialogueBoost = false;
  bool _danmakuEnabled = false;
  List<DanmakuComment> _danmakuComments = const [];
  bool _danmakuLoading = false;
  String? _danmakuMatchTitle;
  String? _danmakuError;
  double _danmakuOpacity = 0.82;
  double _danmakuFontSize = 18.0;
  double _danmakuSpeedSecs = 9.0;
  double _danmakuArea = 0.5;
  bool _danmakuHideTop = false;
  bool _danmakuHideBottom = false;
  final Set<String> _autoSkippedSegKeys = {};
  bool _customIntroSkipped = false;
  bool _customOutroSkipped = false;
  bool _completedTriggered = false;

  // Gesture HUD state
  bool _scrubbing = false;
  double _scrubStartSecs = 0;
  double _scrubTargetSecs = 0;
  String? _scaleAxis; // 'h' | 'v' | 'pinch'
  Offset _scaleAnchor = Offset.zero;
  String? _gestureMode;
  String _seekFeedbackText = '';
  Offset _lastTapDownPos = Offset.zero;

  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _hideControlsTimer;
  Timer? _gestureHudTimer;
  Timer? _statsTimer;
  Timer? _progressTimer;
  Timer? _ticketRefreshTimer;
  final _focusNode = FocusNode();

  List<MediaItemModel> get _episodes => widget.playlistEpisodes ?? const [];

  int get _currentEpisodeIndex => _episodes.indexWhere((e) => e.id == _currentItem.id);

  MediaItemModel? get _nextEpisode {
    final idx = _currentEpisodeIndex;
    if (idx >= 0 && idx + 1 < _episodes.length) return _episodes[idx + 1];
    return null;
  }

  MediaSegmentModel? get _activeSegment {
    for (final seg in _segments) {
      if (_positionSecs >= seg.startSecs && _positionSecs < seg.endSecs - 1.0) {
        return seg;
      }
    }
    final p = widget.appState.prefs;
    if (p.customSkipIntroSecs > 0 &&
        _positionSecs >= 1.0 &&
        _positionSecs < p.customSkipIntroSecs - 1.0) {
      return MediaSegmentModel(
        type: 'Intro',
        startTicks: 0,
        endTicks: p.customSkipIntroSecs * 10000000,
      );
    }
    if (p.customSkipOutroSecs > 0 &&
        _durationSecs > p.customSkipOutroSecs + 30 &&
        _positionSecs >= _durationSecs - p.customSkipOutroSecs &&
        _positionSecs < _durationSecs - 1.5) {
      return MediaSegmentModel(
        type: 'Outro',
        startTicks: ((_durationSecs - p.customSkipOutroSecs) * 10000000).round(),
        endTicks: (_durationSecs * 10000000).round(),
      );
    }
    return null;
  }

  double get _maxVolume => widget.appState.prefs.maxVolumePercent.toDouble().clamp(100.0, 200.0);

  bool _isLikelyAnime(MediaItemModel item) {
    final text = [
      ...item.genres,
      item.displayName,
      item.seriesName ?? '',
    ].join(' ').toLowerCase();
    return text.contains('动画') ||
        text.contains('动漫') ||
        text.contains('番剧') ||
        text.contains('animation') ||
        text.contains('anime');
  }

  @override
  void initState() {
    super.initState();
    final p = widget.appState.prefs;
    _currentItem = widget.item;
    _segments = widget.segments ?? const [];
    _speed = p.defaultSpeed;
    _aspectMode = p.defaultAspect;
    _subScale = p.subtitleFontScale;
    _subPos = p.subtitlePos;
    _subDelaySecs = p.subtitleDelaySecs;
    _subFontFamily = p.subtitleFontFamily;
    _forceAssOverride = p.forceAssOverride;
    _showRemaining = p.showRemainingTime;
    _danmakuEnabled = p.danmakuEnabled;
    _danmakuOpacity = p.danmakuOpacity;
    _danmakuFontSize = p.danmakuFontSize;
    _danmakuSpeedSecs = p.danmakuSpeedSecs;
    _danmakuArea = p.danmakuArea;
    _danmakuHideTop = p.danmakuHideTop;
    _danmakuHideBottom = p.danmakuHideBottom;
    if (p.rememberBrightness) {
      _brightness = p.savedBrightness.clamp(0.15, 1.0);
    }
    _hwDecodeEnabled = (widget.appState.settings['hwdec'] ?? 'auto_zero_copy') != 'software';
    _anime4kActive = p.anime4kEnabled && (!p.anime4kOnlyAnime || _isLikelyAnime(_currentItem));
    _audioMode = (widget.appState.settings['audio_mode'] ?? 'auto').toString();
    _nightMode = widget.appState.settings['night_mode'] == true;
    _dialogueBoost = widget.appState.settings['dialogue_boost'] == true;

    NativePlaybackChannel.setKeepScreenOn(true);

    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: p.bufferSizeMb * 1024 * 1024,
        vo: 'gpu',
      ),
    );
    _videoController = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );

    _subs.add(_player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() => _paused = !playing);
        if (playing) {
          _scheduleHideControls();
        } else {
          _hideControlsTimer?.cancel();
        }
      }
    }));
    _subs.add(_player.stream.position.listen((pos) {
      if (mounted && !_scrubbing) {
        final secs = pos.inMilliseconds / 1000.0;
        setState(() => _positionSecs = secs);
        _checkAutoSkipSegments(secs);
      }
    }));
    _subs.add(_player.stream.buffer.listen((buf) {
      if (mounted) {
        setState(() => _bufferedSecs = buf.inMilliseconds / 1000.0);
      }
    }));
    _subs.add(_player.stream.duration.listen((dur) {
      if (mounted && dur.inMilliseconds > 0) {
        setState(() => _durationSecs = dur.inMilliseconds / 1000.0);
      }
    }));
    _subs.add(_player.stream.completed.listen((done) {
      if (done && !_completedTriggered && widget.appState.prefs.autoPlayNext && _nextEpisode != null) {
        _completedTriggered = true;
        _switchEpisode(_nextEpisode!);
      }
    }));
    _subs.add(_player.stream.error.listen((err) {
      if (mounted && err.isNotEmpty) {
        setState(() => _error = err);
      }
    }));

    _startPlayback(widget.mediaSourceId);
    if (_danmakuEnabled) {
      unawaited(_loadDanmaku());
    }
  }

  void _checkAutoSkipSegments(double secs) {
    final p = widget.appState.prefs;
    if (p.autoSkipIntro || p.autoSkipOutro) {
      for (final seg in _segments) {
        final t = seg.type.toLowerCase();
        final shouldSkip = (t == 'intro' && p.autoSkipIntro) || (t == 'outro' && p.autoSkipOutro);
        final key = '${_currentItem.id}:${seg.type}:${seg.startTicks}';
        if (shouldSkip &&
            secs >= seg.startSecs &&
            secs < seg.endSecs - 1.5 &&
            _autoSkippedSegKeys.add(key)) {
          _seekTo(seg.endSecs);
          _flashGestureHud('seek_feedback', text: '已自动${seg.buttonLabel}');
          return;
        }
      }
    }
    if (p.autoSkipIntro &&
        p.customSkipIntroSecs > 0 &&
        !_customIntroSkipped &&
        secs >= 1.0 &&
        secs < p.customSkipIntroSecs - 1.5) {
      _customIntroSkipped = true;
      _seekTo(p.customSkipIntroSecs.toDouble());
      _flashGestureHud('seek_feedback', text: '已自动跳过片头 (${p.customSkipIntroSecs}s)');
    } else if (p.autoSkipOutro &&
        p.customSkipOutroSecs > 0 &&
        !_customOutroSkipped &&
        _durationSecs > p.customSkipOutroSecs + 30 &&
        secs >= _durationSecs - p.customSkipOutroSecs) {
      _customOutroSkipped = true;
      if (p.autoPlayNext && _nextEpisode != null) {
        _switchEpisode(_nextEpisode!);
      } else {
        _seekTo(_durationSecs - 0.5);
      }
      _flashGestureHud('seek_feedback', text: '已自动跳过片尾');
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _hideControlsTimer?.cancel();
    _gestureHudTimer?.cancel();
    _statsTimer?.cancel();
    _progressTimer?.cancel();
    _ticketRefreshTimer?.cancel();
    _focusNode.dispose();
    if (widget.appState.prefs.rememberBrightness) {
      unawaited(widget.appState.updatePrefs(
        widget.appState.prefs.copyWith(savedBrightness: _brightness),
      ));
    }
    NativePlaybackChannel.setKeepScreenOn(false);
    _reportStoppedAndCleanup();
    _player.dispose();
    super.dispose();
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    if (_paused || _loading || _showEpisodeDrawer || _hoveringChrome) return;
    _hideControlsTimer = Timer(const Duration(milliseconds: 3200), () {
      if (mounted && !_paused && !_scrubbing && !_showEpisodeDrawer && !_hoveringChrome) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _revealControls() {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    _scheduleHideControls();
  }

  void _flashGestureHud(String mode, {String text = ''}) {
    _gestureHudTimer?.cancel();
    setState(() {
      _gestureMode = mode;
      if (text.isNotEmpty) _seekFeedbackText = text;
    });
    _gestureHudTimer = Timer(const Duration(milliseconds: 950), () {
      if (mounted) setState(() => _gestureMode = null);
    });
  }

  Future<void> _applyMpvProperty(String key, String value) async {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty(key, value);
      } catch (_) {}
    }
  }

  Future<String?> _readMpvProperty(String key) async {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      try {
        return await platform.getProperty(key);
      } catch (_) {}
    }
    return null;
  }

  Future<void> _switchEpisode(MediaItemModel ep) async {
    await _reportStoppedAndCleanup();
    _completedTriggered = false;
    _customIntroSkipped = false;
    _customOutroSkipped = false;
    setState(() {
      _currentItem = ep;
      _segments = const [];
      _showEpisodeDrawer = false;
      _positionSecs = 0;
      _bufferedSecs = 0;
      _durationSecs = 0;
      _danmakuComments = const [];
      _danmakuMatchTitle = null;
      _danmakuError = null;
    });
    unawaited(() async {
      try {
        final res = await widget.appState.core.invoke('get_item', {'item_id': ep.id})
            as Map<String, dynamic>;
        final segs = ((res['segments'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MediaSegmentModel.fromJson)
            .toList();
        if (mounted && _currentItem.id == ep.id) {
          setState(() => _segments = segs);
        }
      } catch (_) {}
    }());
    await _startPlayback(null);
    if (_danmakuEnabled) {
      unawaited(_loadDanmaku());
    }
  }

  Future<void> _applyInitialPreferencesToMpv() async {
    final p = widget.appState.prefs;
    final hwPref = (widget.appState.settings['hwdec'] ?? 'auto_zero_copy').toString();
    final hwVal = !_hwDecodeEnabled
        ? 'no'
        : (hwPref == 'auto_copy' ? 'auto-copy-safe' : 'auto-safe');
    await _applyMpvProperty('hwdec', hwVal);
    await _applyMpvProperty('hwdec-codecs', 'all');
    await _applyMpvProperty('target-colorspace-hint', 'yes');
    await _applyMpvProperty('hdr-compute-peak', p.hdrComputePeak ? 'yes' : 'no');
    await _applyMpvProperty('tone-mapping', _toneMapping);
    await _applyMpvProperty('video-sync', p.videoSync);
    await _applyMpvProperty('demuxer-max-bytes', '${p.bufferSizeMb}MiB');
    if (p.audioDelayMs != 0) {
      await _applyMpvProperty('audio-delay', (p.audioDelayMs / 1000.0).toStringAsFixed(3));
    }
    await _applyMpvProperty('sub-fonts-dir', widget.appState.fontsDirectoryPath);
    if (_subFontFamily.trim().isNotEmpty) {
      await _applyMpvProperty('sub-font', _subFontFamily.trim());
    }
    await _applyMpvProperty('sub-ass-override', _forceAssOverride ? 'force' : 'no');
    await _applyMpvProperty('sub-scale', _subScale.toStringAsFixed(2));
    await _applyMpvProperty('sub-pos', '$_subPos');
    await _applyMpvProperty('sub-color', p.subtitleColorHex);
    await _applyMpvProperty('sub-border-size', p.subtitleOutlineWidth.toStringAsFixed(1));
    if (p.subtitleBgOpacity > 0.01) {
      await _applyMpvProperty(
        'sub-back-color',
        '0.0/0.0/0.0/${p.subtitleBgOpacity.toStringAsFixed(2)}',
      );
    }
    if (_subDelaySecs != 0) {
      await _applyMpvProperty('sub-delay', _subDelaySecs.toStringAsFixed(2));
    }
    await _applyAspectMode(_aspectMode);
    await _applyMpvProperty('video-rotate', '$_videoRotate');
    await _applyMpvProperty('video-zoom', _videoZoom.toStringAsFixed(3));
    await _applyAnime4k(_anime4kActive);
    await _applyCustomMpvConf(p.customMpvConf);
    if ((_speed - 1.0).abs() > 0.01) {
      await _player.setRate(_speed);
    }
  }

  Future<void> _applyAnime4k(bool enabled) async {
    if (!enabled) {
      await _applyMpvProperty('scale', 'bilinear');
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

  Future<void> _applyCustomMpvConf(String raw) async {
    if (raw.trim().isEmpty) return;
    const blocked = {'vo', 'ao', 'gpu-context', 'gpu-api'};
    for (final rawLine in raw.split('\n')) {
      final line = rawLine.split('#').first.trim();
      if (line.isEmpty) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final k = line.substring(0, eq).trim();
      final v = line.substring(eq + 1).trim();
      if (k.isEmpty || blocked.contains(k)) continue;
      await _applyMpvProperty(k, v);
    }
  }

  Future<void> _toggleHwDecode() async {
    final next = !_hwDecodeEnabled;
    setState(() => _hwDecodeEnabled = next);
    await _applyMpvProperty('hwdec', next ? 'auto-safe' : 'no');
    _flashGestureHud('seek_feedback', text: next ? '硬件解码 (HW)' : '软件解码 (SW)');
  }

  Future<void> _rotateVideo([int? targetAngle]) async {
    final next = targetAngle ?? ((_videoRotate + 90) % 360);
    setState(() => _videoRotate = next);
    await _applyMpvProperty('video-rotate', '$next');
    _flashGestureHud('seek_feedback', text: '旋转 $next°');
  }

  Future<void> _setVideoZoom(double zoom, {bool showHud = true}) async {
    final clamped = zoom.clamp(-0.5, 1.5);
    setState(() => _videoZoom = clamped);
    await _applyMpvProperty('video-zoom', clamped.toStringAsFixed(3));
    if (showHud) {
      _flashGestureHud('seek_feedback', text: '缩放 ${(100 * (1 + clamped)).round()}%');
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
      final dir = Directory('${widget.appState.downloadsDirectoryPath}/screenshots');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final safeTitle = _currentItem.displayName
          .replaceAll(RegExp(r'[^\w\u4e00-\u9fff\-_. ]+'), '_')
          .trim();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/${safeTitle.isEmpty ? 'vedro' : safeTitle}_$ts.png');
      await file.writeAsBytes(bytes);
      _flashGestureHud('seek_feedback', text: '已保存截图');
    } catch (_) {
      _flashGestureHud('seek_feedback', text: '截图失败');
    }
  }

  Future<void> _loadDanmaku({String? queryOverride}) async {
    if (_danmakuLoading) return;
    final query = (queryOverride ?? (_currentItem.seriesName ?? _currentItem.displayName)).trim();
    if (query.isEmpty) return;
    setState(() {
      _danmakuLoading = true;
      _danmakuError = null;
    });
    try {
      final res = await widget.appState.fetchDanmaku(
        query,
        episode: _currentItem.indexNumber,
      );
      if (!mounted) return;
      setState(() {
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
      if (!mounted) return;
      setState(() {
        _danmakuLoading = false;
        _danmakuError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _startPlayback(String? sourceId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = widget.appState.prefs;

      // Support playing local offline downloaded file directly!
      if (widget.localFilePath != null && widget.localFilePath!.isNotEmpty) {
        await _applyInitialPreferencesToMpv();
        await _player.open(Media(widget.localFilePath!), play: true);
        if (mounted) {
          setState(() {
            _loading = false;
            _paused = false;
          });
          _scheduleHideControls();
        }
        return;
      }

      final prepRaw = await widget.appState.core.invoke('prepare_playback', {
        'item_id': _currentItem.id,
        if (sourceId != null) 'media_source_id': sourceId,
        if (widget.initialAudioStreamIndex != null)
          'audio_stream_index': widget.initialAudioStreamIndex,
        if (widget.initialSubtitleStreamIndex != null)
          'subtitle_stream_index': widget.initialSubtitleStreamIndex,
        'inspect_header': true,
      }) as Map<String, dynamic>;

      final prep = PreparedPlaybackModel.fromJson(prepRaw);

      const skipKeys = {'vo', 'ao', 'gpu-api', 'gpu-context'};
      for (final entry in prep.mpvOptions.entries) {
        if (skipKeys.contains(entry.key)) continue;
        await _applyMpvProperty(entry.key, entry.value);
      }
      await _applyInitialPreferencesToMpv();

      final startDur = (p.rememberPosition && _currentItem.playbackPositionTicks > 0)
          ? Duration(microseconds: _currentItem.playbackPositionTicks ~/ 10)
          : null;

      await _player.open(
        Media(prep.proxyUrl, start: startDur),
        play: true,
      );

      if (p.autoLoadExternalSubs) {
        for (final sub in prep.externalSubtitles) {
          if (sub['is_default'] == true && sub['url'] != null) {
            await _player.setSubtitleTrack(
              SubtitleTrack.uri(
                sub['url'].toString(),
                title: sub['title']?.toString(),
                language: sub['language']?.toString(),
              ),
            );
            break;
          }
        }
      }

      if (!p.incognitoMode) {
        await widget.appState.core.invoke('report_playback_start', {
          'position_ticks': _currentItem.playbackPositionTicks,
          if (_currentItem.runTimeTicks != null) 'run_time_ticks': _currentItem.runTimeTicks,
          'is_paused': false,
        });
      }

      if (mounted) {
        setState(() {
          _prepared = prep;
          _loading = false;
          _paused = false;
        });
        _scheduleHideControls();
      }
      _startTimers();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _startTimers() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(milliseconds: 800), (_) async {
      if (!_showStats) return;
      try {
        final rustStats = await widget.appState.core.invoke('player_stats') as Map<String, dynamic>;
        final vCodec = await _readMpvProperty('video-codec');
        final hwdec = await _readMpvProperty('hwdec-current');
        final w = int.tryParse(await _readMpvProperty('width') ?? '');
        final h = int.tryParse(await _readMpvProperty('height') ?? '');
        final fps = double.tryParse(await _readMpvProperty('estimated-vf-fps') ?? '');
        final drop = int.tryParse(await _readMpvProperty('frame-drop-count') ?? '') ?? 0;
        final aCodec = await _readMpvProperty('audio-codec-name');
        final aCh = await _readMpvProperty('audio-params/channels');

        if (mounted) {
          setState(() {
            _stats = {
              'proxy': rustStats['proxy'],
              'playback': {
                'video_codec': vCodec,
                'hwdec_current': hwdec ?? 'auto-safe',
                'width': w ?? 0,
                'height': h ?? 0,
                'fps': fps ?? 0.0,
                'dropped_frames': drop,
                'audio_codec': aCodec,
                'audio_channels': aCh,
                'hdr_decision': {'explanation': _prepared?.hdrExplanation ?? 'Direct Play'},
                'audio_decision': {'summary': _prepared?.audioSummary ?? 'Auto'},
              },
            };
          });
        }
      } catch (_) {}
    });

    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (widget.appState.prefs.incognitoMode || widget.localFilePath != null) return;
      try {
        await widget.appState.core.invoke('report_playback_progress', {
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
        try {
          await widget.appState.core.invoke('refresh_stream_ticket');
        } catch (_) {}
      });
    }
  }

  Future<void> _reportStoppedAndCleanup() async {
    if (widget.localFilePath != null) return;
    try {
      if (!widget.appState.prefs.incognitoMode) {
        await widget.appState.core.invoke('report_playback_stopped', {
          'position_ticks': (_positionSecs * 10000000).round(),
          if (_durationSecs > 0) 'run_time_ticks': (_durationSecs * 10000000).round(),
          'is_paused': true,
        });
      }
      await widget.appState.core.invoke('player_stop');
    } catch (_) {}
  }

  Future<void> _requestExit() async {
    if (widget.appState.prefs.confirmExitPlayer && !_paused && _error == null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('退出播放？'),
          content: const Text('当前播放进度会自动保存。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('继续观看')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _togglePause() async {
    await _player.playOrPause();
    _revealControls();
  }

  void _toggleMute() {
    if (_muted || _volume <= 0.1) {
      final restored = _preMuteVolume > 5 ? _preMuteVolume : 80.0;
      setState(() {
        _muted = false;
        _volume = restored;
      });
      _player.setVolume(restored);
    } else {
      _preMuteVolume = _volume;
      setState(() {
        _muted = true;
        _volume = 0;
      });
      _player.setVolume(0);
    }
    _flashGestureHud('volume');
  }

  void _setVolume(double v) {
    final clamped = v.clamp(0.0, _maxVolume);
    setState(() {
      _volume = clamped;
      _muted = clamped <= 0.1;
    });
    _player.setVolume(clamped);
  }

  Future<void> _seekTo(double secs) async {
    final target = secs.clamp(0.0, _durationSecs > 0 ? _durationSecs : 86400.0);
    await _player.seek(Duration(milliseconds: (target * 1000).round()));
    if (mounted) setState(() => _positionSecs = target);
  }

  Future<void> _seekBy(double delta, {bool showHud = false}) async {
    await _seekTo(_positionSecs + delta);
    if (showHud) {
      HapticFeedback.selectionClick();
      final sign = delta >= 0 ? '+' : '';
      _flashGestureHud('seek_feedback', text: '$sign${delta.round()}s');
    }
  }

  Future<void> _setSpeed(double s) async {
    final clamped = s.clamp(0.25, 4.0);
    await _player.setRate(clamped);
    if (mounted) setState(() => _speed = clamped);
  }

  Future<void> _applyAspectMode(String mode) async {
    setState(() => _aspectMode = mode);
    switch (mode) {
      case 'fill':
        await _applyMpvProperty('video-aspect-override', '-1');
        await _applyMpvProperty('panscan', '1.0');
        break;
      case '16:9':
        await _applyMpvProperty('panscan', '0.0');
        await _applyMpvProperty('video-aspect-override', '16:9');
        break;
      case '21:9':
        await _applyMpvProperty('panscan', '0.0');
        await _applyMpvProperty('video-aspect-override', '21:9');
        break;
      case '4:3':
        await _applyMpvProperty('panscan', '0.0');
        await _applyMpvProperty('video-aspect-override', '4:3');
        break;
      default:
        await _applyMpvProperty('panscan', '0.0');
        await _applyMpvProperty('video-aspect-override', '-1');
        break;
    }
  }

  void _handleDoubleTap(double width) {
    final step = widget.appState.prefs.seekStepSecs.toDouble();
    final ratio = width > 0 ? _lastTapDownPos.dx / width : 0.5;
    if (ratio < 0.35) {
      _seekBy(-step, showHud: true);
    } else if (ratio > 0.65) {
      _seekBy(step, showHud: true);
    } else {
      _togglePause();
    }
  }

  void _handleKey(KeyEvent ev) {
    if (ev is! KeyDownEvent) return;
    final key = ev.logicalKey;
    final step = widget.appState.prefs.seekStepSecs.toDouble();
    if (key == LogicalKeyboardKey.space) {
      _togglePause();
    } else if (key == LogicalKeyboardKey.escape) {
      if (_showEpisodeDrawer) {
        setState(() => _showEpisodeDrawer = false);
      } else {
        _requestExit();
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(step, showHud: true);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-step, showHud: true);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _setVolume(_volume + 5);
      _flashGestureHud('volume');
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _setVolume(_volume - 5);
      _flashGestureHud('volume');
    } else if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
    } else if (key == LogicalKeyboardKey.keyI) {
      setState(() => _showStats = !_showStats);
    } else if (key == LogicalKeyboardKey.keyS) {
      _takeScreenshot();
    } else if (key == LogicalKeyboardKey.keyD) {
      final next = !_danmakuEnabled;
      setState(() => _danmakuEnabled = next);
      if (next && _danmakuComments.isEmpty) unawaited(_loadDanmaku());
      _flashGestureHud('seek_feedback', text: next ? '弹幕已开启' : '弹幕已关闭');
    } else if (key == LogicalKeyboardKey.keyR) {
      _rotateVideo();
    } else if (key == LogicalKeyboardKey.keyN && _nextEpisode != null) {
      _switchEpisode(_nextEpisode!);
    } else if (key == LogicalKeyboardKey.bracketRight) {
      _setSpeed(_speed + 0.25);
    } else if (key == LogicalKeyboardKey.bracketLeft) {
      _setSpeed(_speed - 0.25);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 760;
    final isMac = !kIsWeb && Platform.isMacOS;
    final topPad = MediaQuery.paddingOf(context).top;
    final seg = _activeSegment;
    final step = widget.appState.prefs.seekStepSecs;
    final showSpecs = widget.appState.prefs.showSpecBadges;
    final specs = showSpecs
        ? <String>[
            if (_prepared?.dolbyVisionLabel != null) _prepared!.dolbyVisionLabel!,
            if (_prepared?.spatialAudioLabel != null) _prepared!.spatialAudioLabel!,
          ]
        : const <String>[];

    final hideCursor = !_controlsVisible && !_showEpisodeDrawer && !_paused && !_loading;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent && !_showEpisodeDrawer) {
              final delta = event.scrollDelta.dy > 0 ? -4.0 : 4.0;
              _setVolume(_volume + delta);
              _flashGestureHud('volume');
            }
          },
          child: MouseRegion(
            cursor: hideCursor ? SystemMouseCursors.none : SystemMouseCursors.basic,
            onHover: (_) => _revealControls(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _lastTapDownPos = d.localPosition,
              onTap: () {
                if (_showEpisodeDrawer) {
                  setState(() => _showEpisodeDrawer = false);
                  _scheduleHideControls();
                  return;
                }
                if (_controlsVisible) {
                  _hideControlsTimer?.cancel();
                  setState(() => _controlsVisible = false);
                } else {
                  _revealControls();
                }
              },
              onDoubleTap: () => _handleDoubleTap(size.width),
              onLongPressStart: (_) {
                HapticFeedback.mediumImpact();
                _preBoostSpeed = _speed;
                setState(() => _isSpeedBoost = true);
                _setSpeed(widget.appState.prefs.longPressSpeed);
              },
              onLongPressEnd: (_) {
                setState(() => _isSpeedBoost = false);
                _setSpeed(_preBoostSpeed);
              },
              onScaleStart: (d) {
                if (_showEpisodeDrawer) return;
                _scaleAxis = null;
                _scaleAnchor = d.localFocalPoint;
                _pinchBaseZoom = _videoZoom;
                if (d.pointerCount >= 2 && widget.appState.prefs.pinchToZoom) {
                  _scaleAxis = 'pinch';
                  _hideControlsTimer?.cancel();
                }
              },
              onScaleUpdate: (d) {
                if (_showEpisodeDrawer) return;
                if ((d.pointerCount >= 2 || _scaleAxis == 'pinch') &&
                    widget.appState.prefs.pinchToZoom) {
                  _scaleAxis = 'pinch';
                  final nextZoom = (_pinchBaseZoom + (d.scale - 1.0) * 0.85).clamp(-0.5, 1.5);
                  if ((nextZoom - _videoZoom).abs() > 0.015) {
                    _setVideoZoom(nextZoom);
                  }
                  return;
                }
                final delta = d.focalPointDelta;
                if (_scaleAxis == null) {
                  final totalDx = (d.localFocalPoint.dx - _scaleAnchor.dx).abs();
                  final totalDy = (d.localFocalPoint.dy - _scaleAnchor.dy).abs();
                  if (totalDx < 8 && totalDy < 8) return;
                  if (totalDx >= totalDy) {
                    if (_durationSecs <= 0) return;
                    _scaleAxis = 'h';
                    _hideControlsTimer?.cancel();
                    setState(() {
                      _scrubbing = true;
                      _scrubStartSecs = _positionSecs;
                      _scrubTargetSecs = _positionSecs;
                    });
                  } else {
                    _scaleAxis = 'v';
                  }
                }
                if (_scaleAxis == 'h' && _scrubbing) {
                  final deltaSecs = (delta.dx / size.width) * 180.0;
                  setState(() {
                    _scrubTargetSecs = (_scrubTargetSecs + deltaSecs).clamp(0.0, _durationSecs);
                  });
                } else if (_scaleAxis == 'v') {
                  final vDelta = -delta.dy / (size.height * 0.55);
                  if (_scaleAnchor.dx < size.width * 0.5) {
                    setState(() => _brightness = (_brightness + vDelta).clamp(0.15, 1.0));
                    _flashGestureHud('brightness');
                  } else {
                    _setVolume(_volume + vDelta * 100);
                    _flashGestureHud('volume');
                  }
                }
              },
              onScaleEnd: (_) {
                if (_scrubbing) {
                  final target = _scrubTargetSecs;
                  setState(() => _scrubbing = false);
                  _seekTo(target);
                  _scheduleHideControls();
                }
                _scaleAxis = null;
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Video(
                    controller: _videoController,
                    controls: NoVideoControls,
                    fill: Colors.black,
                  ),

                  if (_brightness < 0.99)
                    IgnorePointer(
                      child: Container(
                        color: Colors.black.withValues(alpha: (1.0 - _brightness).clamp(0.0, 0.85)),
                      ),
                    ),

                  // Real 60fps Canvas Danmaku overlay (DandanPlay JSON & Bilibili XML)
                  if (_danmakuEnabled)
                    DanmakuLayer(
                      comments: _danmakuComments,
                      positionSecs: _positionSecs,
                      opacity: _danmakuOpacity,
                      fontSize: _danmakuFontSize,
                      speedSecs: _danmakuSpeedSecs,
                      areaFraction: _danmakuArea,
                      hideTop: _danmakuHideTop,
                      hideBottom: _danmakuHideBottom,
                    ),

                  if (_loading)
                    const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: VedroTheme.fg),
                      ),
                    ),

                  if (_error != null)
                    Positioned(
                      bottom: 130,
                      left: 24,
                      right: 24,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: GlassSurface(
                            borderRadius: 12,
                            color: const Color(0xDC241214),
                            borderColor: const Color(0x55FF6B6F),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: VedroTheme.danger, fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Skip Intro / Outro floating frosted button
                  if (seg != null && !_showEpisodeDrawer)
                    Positioned(
                      right: 28,
                      bottom: _controlsVisible ? 142 : 34,
                      child: PressableScale(
                        onTap: () => _seekTo(seg.endSecs),
                        hoverScale: 1.04,
                        pressScale: 0.94,
                        child: GlassSurface(
                          borderRadius: 12,
                          blur: 24,
                          color: const Color(0xCC181920),
                          borderColor: const Color(0x45FFFFFF),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                seg.buttonLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.skip_next_rounded, size: 18, color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                    ),

                  if (_isSpeedBoost)
                    Positioned(
                      top: topPad + 48,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: GlassSurface(
                          borderRadius: 20,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.fast_forward_rounded, size: 15, color: VedroTheme.fg),
                              const SizedBox(width: 6),
                              Text(
                                '${widget.appState.prefs.longPressSpeed.toStringAsFixed(1)}×',
                                style: const TextStyle(
                                  color: VedroTheme.fg,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  if (_scrubbing)
                    Center(
                      child: GlassSurface(
                        borderRadius: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${_fmtTime(_scrubTargetSecs)} / ${_fmtTime(_durationSecs)}',
                              style: const TextStyle(
                                color: VedroTheme.fg,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _fmtDelta(_scrubTargetSecs - _scrubStartSecs),
                              style: const TextStyle(
                                color: VedroTheme.fg2,
                                fontSize: 12.5,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (!_scrubbing && _gestureMode != null)
                    Center(
                      child: GlassSurface(
                        borderRadius: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        child: _buildGestureHudContent(),
                      ),
                    ),

                  if (_showStats)
                    Positioned(
                      top: topPad + 72,
                      left: 24,
                      child: NerdStatsHud(stats: _stats),
                    ),

                  // Auto-hiding IINA / Infuse frosted chrome
                  IgnorePointer(
                    ignoring: !_controlsVisible || _showEpisodeDrawer,
                    child: AnimatedOpacity(
                      opacity: (_controlsVisible && !_showEpisodeDrawer) ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 210),
                      curve: Curves.easeOutCubic,
                      child: Stack(
                        children: [
                          // Top Bar
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: MouseRegion(
                              onEnter: (_) {
                                _hoveringChrome = true;
                                _hideControlsTimer?.cancel();
                              },
                              onExit: (_) {
                                _hoveringChrome = false;
                                _scheduleHideControls();
                              },
                              child: Container(
                                padding: EdgeInsets.fromLTRB(
                                  isMac ? 82 : 20,
                                  topPad + 12,
                                  20,
                                  28,
                                ),
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Color(0xC4000000), Colors.transparent],
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    _CircleHudButton(
                                      icon: Icons.arrow_back_ios_new_rounded,
                                      iconSize: 15,
                                      tooltip: '返回 (Esc)',
                                      onTap: _requestExit,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              _currentItem.seriesName != null
                                                  ? '${_currentItem.seriesName} ${_currentItem.episodeCode ?? ''} · ${_currentItem.displayName}'
                                                  : _currentItem.displayName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: -0.2,
                                              ),
                                            ),
                                          ),
                                          if (specs.isNotEmpty) ...[
                                            const SizedBox(width: 10),
                                            SpecGlyphRow(specs: specs),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Tooltip(
                                      message: _hwDecodeEnabled ? '当前硬件解码，点击切至软解' : '当前软件解码，点击切至硬解',
                                      child: _DeckPillButton(
                                        label: _hwDecodeEnabled ? 'HW' : 'SW',
                                        active: _hwDecodeEnabled,
                                        onTap: _toggleHwDecode,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    _CircleHudButton(
                                      icon: Icons.camera_alt_outlined,
                                      tooltip: '截图 (S)',
                                      onTap: _takeScreenshot,
                                    ),
                                    const SizedBox(width: 6),
                                    if (_episodes.length > 1) ...[
                                      _CircleHudButton(
                                        icon: Icons.video_library_outlined,
                                        tooltip: '选集',
                                        onTap: () => setState(() => _showEpisodeDrawer = true),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    _CircleHudButton(
                                      icon: Icons.aspect_ratio_rounded,
                                      tooltip: '画面比例 / 旋转 / 缩放',
                                      onTap: _openAspectSheet,
                                    ),
                                    const SizedBox(width: 6),
                                    _CircleHudButton(
                                      icon: Icons.info_outline_rounded,
                                      active: _showStats,
                                      tooltip: '硬件信息 (I)',
                                      onTap: () => setState(() => _showStats = !_showStats),
                                    ),
                                    if (widget.appState.prefs.enablePip) ...[
                                      const SizedBox(width: 6),
                                      _CircleHudButton(
                                        icon: Icons.picture_in_picture_alt_rounded,
                                        tooltip: '画中画',
                                        onTap: NativePlaybackChannel.enterPictureInPicture,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Bottom Frosted Cinema Control Deck
                          Positioned(
                            left: wide ? 28 : 14,
                            right: wide ? 28 : 14,
                            bottom: MediaQuery.paddingOf(context).bottom + (wide ? 22 : 14),
                            child: MouseRegion(
                              onEnter: (_) {
                                _hoveringChrome = true;
                                _hideControlsTimer?.cancel();
                              },
                              onExit: (_) {
                                _hoveringChrome = false;
                                _scheduleHideControls();
                              },
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 920),
                                  child: GlassSurface(
                                    borderRadius: 18,
                                    blur: 28,
                                    color: const Color(0xC8121317),
                                    borderColor: const Color(0x26FFFFFF),
                                    padding: EdgeInsets.fromLTRB(
                                      wide ? 18 : 14,
                                      12,
                                      wide ? 18 : 14,
                                      12,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Row 1: Custom precision Cinema Scrub Bar
                                        _CinemaScrubBar(
                                          positionSecs: _scrubbing ? _scrubTargetSecs : _positionSecs,
                                          bufferedSecs: _bufferedSecs,
                                          durationSecs: _durationSecs,
                                          segments: _segments,
                                          showRemaining: _showRemaining,
                                          fmtTime: _fmtTime,
                                          onToggleRemaining: () =>
                                              setState(() => _showRemaining = !_showRemaining),
                                          onScrubStart: () => _hideControlsTimer?.cancel(),
                                          onScrubUpdate: (secs) =>
                                              setState(() => _positionSecs = secs),
                                          onScrubEnd: (secs) {
                                            _seekTo(secs);
                                            _scheduleHideControls();
                                          },
                                        ),
                                        const SizedBox(height: 10),
                                        // Row 2: Left volume | Center transport | Right clean pills
                                        Row(
                                          children: [
                                            // Left: Volume controls (inline slider on desktop)
                                            if (wide) ...[
                                              _DeckIconButton(
                                                icon: _muted || _volume <= 0.1
                                                    ? Icons.volume_off_rounded
                                                    : (_volume < 50
                                                        ? Icons.volume_down_rounded
                                                        : Icons.volume_up_rounded),
                                                tooltip: '静音 (M)',
                                                onTap: _toggleMute,
                                              ),
                                              const SizedBox(width: 4),
                                              SizedBox(
                                                width: 82,
                                                child: _MiniVolumeBar(
                                                  value: (_volume / _maxVolume).clamp(0.0, 1.0),
                                                  onChanged: (ratio) =>
                                                      _setVolume(ratio * _maxVolume),
                                                ),
                                              ),
                                              const Spacer(),
                                            ],

                                            // Center Transport Cluster
                                            _DeckIconButton(
                                              icon: Icons.replay_10_rounded,
                                              tooltip: '后退 ${step}s',
                                              onTap: () => _seekBy(-step.toDouble(), showHud: true),
                                            ),
                                            const SizedBox(width: 8),
                                            PressableScale(
                                              onTap: _togglePause,
                                              hoverScale: 1.06,
                                              pressScale: 0.92,
                                              child: Container(
                                                width: 42,
                                                height: 42,
                                                decoration: const BoxDecoration(
                                                  color: Colors.white,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  _paused
                                                      ? Icons.play_arrow_rounded
                                                      : Icons.pause_rounded,
                                                  size: 25,
                                                  color: VedroTheme.canvas,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            _DeckIconButton(
                                              icon: Icons.forward_10_rounded,
                                              tooltip: '前进 ${step}s',
                                              onTap: () => _seekBy(step.toDouble(), showHud: true),
                                            ),
                                            if (_nextEpisode != null) ...[
                                              const SizedBox(width: 4),
                                              _DeckIconButton(
                                                icon: Icons.skip_next_rounded,
                                                tooltip: '下一集 (N)',
                                                onTap: () => _switchEpisode(_nextEpisode!),
                                              ),
                                            ],

                                            const Spacer(),

                                            // Right cohesive labeled pills
                                            _DeckPillButton(
                                              label:
                                                  '${_speed.toStringAsFixed(_speed == _speed.roundToDouble() ? 1 : 2)}×',
                                              onTap: _openSpeedSheet,
                                            ),
                                            const SizedBox(width: 6),
                                            _DeckPillButton(
                                              label: _danmakuEnabled && _danmakuComments.isNotEmpty
                                                  ? '弹幕 ${_danmakuComments.length}'
                                                  : '弹幕',
                                              active: _danmakuEnabled,
                                              onTap: _openDanmakuSheet,
                                            ),
                                            const SizedBox(width: 6),
                                            _DeckPillButton(
                                              label: '字幕',
                                              onTap: _openSubtitleSheet,
                                            ),
                                            const SizedBox(width: 6),
                                            _DeckPillButton(
                                              label: '音轨',
                                              onTap: _openAudioSheet,
                                            ),
                                            const SizedBox(width: 6),
                                            _DeckPillButton(
                                              label: '画面',
                                              onTap: _openHdrSheet,
                                            ),
                                            if ((_prepared?.allSources.length ?? 0) > 1) ...[
                                              const SizedBox(width: 6),
                                              _DeckPillButton(
                                                label: '版本',
                                                onTap: _openVersionSheet,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Click-outside scrim when Episode Drawer is open
                  if (_showEpisodeDrawer)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _showEpisodeDrawer = false);
                          _scheduleHideControls();
                        },
                        child: Container(color: const Color(0x66000000)),
                      ),
                    ),

                  // Slide-out frosted Episode Drawer
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    top: topPad + (isMac ? 42 : 16),
                    bottom: 16,
                    right: _showEpisodeDrawer ? 16 : -360,
                    width: 336,
                    child: GlassSurface(
                      borderRadius: 18,
                      blur: 30,
                      color: VedroTheme.glassStrong,
                      borderColor: const Color(0x28FFFFFF),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 12, 10, 10),
                            child: Row(
                              children: [
                                Text(
                                  '剧集 (${_episodes.length})',
                                  style: const TextStyle(
                                    color: VedroTheme.fg,
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 18, color: VedroTheme.fg2),
                                  onPressed: () {
                                    setState(() => _showEpisodeDrawer = false);
                                    _scheduleHideControls();
                                  },
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _episodes.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, idx) {
                                final ep = _episodes[idx];
                                final playing = ep.id == _currentItem.id;
                                final accent = Theme.of(context).colorScheme.secondary;
                                return PressableScale(
                                  onTap: () => _switchEpisode(ep),
                                  hoverScale: 1.015,
                                  pressScale: 0.97,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: playing
                                          ? accent.withValues(alpha: 0.16)
                                          : const Color(0x0FFFFFFF),
                                      borderRadius: BorderRadius.circular(11),
                                      border: Border.all(
                                        color: playing
                                            ? accent.withValues(alpha: 0.55)
                                            : VedroTheme.line,
                                        width: 0.7,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 84,
                                          child: AspectRatio(
                                            aspectRatio: 16 / 9,
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(6),
                                              child: VedroArtwork(
                                                item: ep,
                                                appState: widget.appState,
                                                landscape: true,
                                                width: 240,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${ep.indexNumber ?? idx + 1}. ${ep.displayName}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: playing ? Colors.white : VedroTheme.fg,
                                                  fontSize: 13,
                                                  fontWeight:
                                                      playing ? FontWeight.w600 : FontWeight.w500,
                                                ),
                                              ),
                                              if (fmtDurationTicks(ep.runTimeTicks).isNotEmpty)
                                                Text(
                                                  fmtDurationTicks(ep.runTimeTicks),
                                                  style: const TextStyle(
                                                    color: VedroTheme.fg3,
                                                    fontSize: 11.5,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGestureHudContent() {
    if (_gestureMode == 'seek_feedback') {
      return Text(
        _seekFeedbackText,
        style: const TextStyle(
          color: VedroTheme.fg,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      );
    }
    final isBrightness = _gestureMode == 'brightness';
    final progress = isBrightness ? _brightness : (_volume / _maxVolume).clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isBrightness
              ? Icons.brightness_6_rounded
              : (_volume <= 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded),
          size: 18,
          color: VedroTheme.fg,
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 112,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: const Color(0x33FFFFFF),
              color: VedroTheme.fg,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 38,
          child: Text(
            isBrightness ? '${(_brightness * 100).round()}%' : '${_volume.round()}%',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: VedroTheme.fg2,
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  void _openAspectSheet() {
    const modes = {
      'fit': '原始比例（适应屏幕）',
      'fill': '铺满屏幕（等比裁切黑边）',
      '16:9': '强制 16:9',
      '21:9': '宽银幕 21:9',
      '4:3': '经典 4:3',
    };
    const angles = [0, 90, 180, 270];
    showGlassSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text('画面比例、旋转与缩放', style: TextStyle(color: VedroTheme.fg, fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            ...modes.entries.map((e) => _SheetOptionRow(
                  label: e.value,
                  selected: e.key == _aspectMode,
                  onTap: () {
                    setModal(() => _aspectMode = e.key);
                    _applyAspectMode(e.key);
                  },
                )),
            const Divider(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  const Text('画面旋转', style: TextStyle(color: VedroTheme.fg2, fontSize: 13.5)),
                  const Spacer(),
                  for (final angle in angles) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _DeckPillButton(
                        label: '$angle°',
                        active: _videoRotate == angle,
                        onTap: () {
                          setModal(() => _videoRotate = angle);
                          _rotateVideo(angle);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _StepperRow(
              label: '画面缩放',
              valueText: '${(100 * (1 + _videoZoom)).round()}%',
              onMinus: () {
                final next = (_videoZoom - 0.1).clamp(-0.5, 1.5);
                setModal(() => _videoZoom = next);
                _setVideoZoom(next, showHud: false);
              },
              onPlus: () {
                final next = (_videoZoom + 0.1).clamp(-0.5, 1.5);
                setModal(() => _videoZoom = next);
                _setVideoZoom(next, showHud: false);
              },
            ),
            if (_videoZoom.abs() > 0.01 || _videoRotate != 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      setModal(() {
                        _videoZoom = 0.0;
                        _videoRotate = 0;
                      });
                      _setVideoZoom(0.0, showHud: false);
                      _rotateVideo(0);
                    },
                    child: const Text('重置旋转与缩放', style: TextStyle(fontSize: 12.5)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openDanmakuSheet() {
    final queryCtrl = TextEditingController(
      text: _danmakuMatchTitle ?? _currentItem.seriesName ?? _currentItem.displayName,
    );
    showGlassSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
          children: [
            Row(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('弹幕设置与匹配', style: TextStyle(color: VedroTheme.fg, fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                Switch(
                  value: _danmakuEnabled,
                  onChanged: (v) {
                    setModal(() => _danmakuEnabled = v);
                    setState(() => _danmakuEnabled = v);
                    if (v && _danmakuComments.isEmpty && !_danmakuLoading) {
                      unawaited(_loadDanmaku().then((_) {
                        if (ctx.mounted) setModal(() {});
                      }));
                    }
                  },
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 12),
              child: Text(
                _danmakuLoading
                    ? '正在从弹幕源匹配…'
                    : (_danmakuError != null
                        ? '匹配失败：$_danmakuError'
                        : (_danmakuComments.isNotEmpty
                            ? '已匹配：${_danmakuMatchTitle ?? ''}（${_danmakuComments.length} 条弹幕）'
                            : '输入番剧或电影名手动匹配弹幕（支持弹弹play / B站 XML 接口）')),
                style: TextStyle(
                  color: _danmakuError != null ? VedroTheme.danger : VedroTheme.fg3,
                  fontSize: 12,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: queryCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '搜索弹幕关键词',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _danmakuLoading
                        ? null
                        : () async {
                            setModal(() => _danmakuEnabled = true);
                            setState(() => _danmakuEnabled = true);
                            await _loadDanmaku(queryOverride: queryCtrl.text.trim());
                            if (ctx.mounted) setModal(() {});
                          },
                    child: Text(_danmakuLoading ? '匹配中…' : '匹配弹幕', style: const TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
            ),
            const Divider(height: 22),
            _StepperRow(
              label: '不透明度',
              valueText: '${(_danmakuOpacity * 100).round()}%',
              onMinus: () {
                final v = (_danmakuOpacity - 0.1).clamp(0.2, 1.0);
                setModal(() => _danmakuOpacity = v);
                setState(() => _danmakuOpacity = v);
                widget.appState.updatePrefs(widget.appState.prefs.copyWith(danmakuOpacity: v));
              },
              onPlus: () {
                final v = (_danmakuOpacity + 0.1).clamp(0.2, 1.0);
                setModal(() => _danmakuOpacity = v);
                setState(() => _danmakuOpacity = v);
                widget.appState.updatePrefs(widget.appState.prefs.copyWith(danmakuOpacity: v));
              },
            ),
            _StepperRow(
              label: '弹幕字号',
              valueText: '${_danmakuFontSize.round()} pt',
              onMinus: () {
                final v = (_danmakuFontSize - 2).clamp(12.0, 30.0);
                setModal(() => _danmakuFontSize = v);
                setState(() => _danmakuFontSize = v);
                widget.appState.updatePrefs(widget.appState.prefs.copyWith(danmakuFontSize: v));
              },
              onPlus: () {
                final v = (_danmakuFontSize + 2).clamp(12.0, 30.0);
                setModal(() => _danmakuFontSize = v);
                setState(() => _danmakuFontSize = v);
                widget.appState.updatePrefs(widget.appState.prefs.copyWith(danmakuFontSize: v));
              },
            ),
            _StepperRow(
              label: '滚动时长',
              valueText: '${_danmakuSpeedSecs.round()}s',
              onMinus: () {
                final v = (_danmakuSpeedSecs - 1).clamp(5.0, 15.0);
                setModal(() => _danmakuSpeedSecs = v);
                setState(() => _danmakuSpeedSecs = v);
                widget.appState.updatePrefs(widget.appState.prefs.copyWith(danmakuSpeedSecs: v));
              },
              onPlus: () {
                final v = (_danmakuSpeedSecs + 1).clamp(5.0, 15.0);
                setModal(() => _danmakuSpeedSecs = v);
                setState(() => _danmakuSpeedSecs = v);
                widget.appState.updatePrefs(widget.appState.prefs.copyWith(danmakuSpeedSecs: v));
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  const Text('显示区域', style: TextStyle(color: VedroTheme.fg2, fontSize: 13.5)),
                  const Spacer(),
                  for (final (frac, lbl) in [(0.25, '1/4'), (0.5, '半屏'), (0.75, '3/4'), (1.0, '全屏')])
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _DeckPillButton(
                        label: lbl,
                        active: (_danmakuArea - frac).abs() < 0.05,
                        onTap: () {
                          setModal(() => _danmakuArea = frac);
                          setState(() => _danmakuArea = frac);
                          widget.appState.updatePrefs(widget.appState.prefs.copyWith(danmakuArea: frac));
                        },
                      ),
                    ),
                ],
              ),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('屏蔽顶部固定弹幕', style: TextStyle(color: VedroTheme.fg, fontSize: 13.5)),
              value: _danmakuHideTop,
              onChanged: (v) {
                setModal(() => _danmakuHideTop = v);
                setState(() => _danmakuHideTop = v);
                widget.appState.updatePrefs(widget.appState.prefs.copyWith(danmakuHideTop: v));
              },
            ),
            SwitchListTile(
              dense: true,
              title: const Text('屏蔽底部固定弹幕', style: TextStyle(color: VedroTheme.fg, fontSize: 13.5)),
              value: _danmakuHideBottom,
              onChanged: (v) {
                setModal(() => _danmakuHideBottom = v);
                setState(() => _danmakuHideBottom = v);
                widget.appState.updatePrefs(widget.appState.prefs.copyWith(danmakuHideBottom: v));
              },
            ),
          ],
        ),
      ),
    ).whenComplete(queryCtrl.dispose);
  }

  void _openSpeedSheet() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0];
    showGlassSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('播放倍速', style: TextStyle(color: VedroTheme.fg, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: speeds.map((s) {
                final active = (_speed - s).abs() < 0.01;
                return PressableScale(
                  onTap: () {
                    Navigator.pop(ctx);
                    _setSpeed(s);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: active ? VedroTheme.fg : VedroTheme.surface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: active ? VedroTheme.fg : VedroTheme.line, width: 0.7),
                    ),
                    child: Text(
                      '$s×',
                      style: TextStyle(
                        color: active ? VedroTheme.canvas : VedroTheme.fg,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _openHdrSheet() {
    const algos = {
      'bt.2446a': 'BT.2446a（自然高光保留）',
      'spline': 'Spline（曲线动态映射）',
      'st2094-40': 'ST.2094-40（动态元数据）',
      'reinhard': 'Reinhard（高亮温和压缩）',
      'hable': 'Hable（电影感曲线）',
      'clip': 'Clip（直通无压缩）',
    };
    showGlassSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('画面增强与 HDR 色调映射', style: TextStyle(color: VedroTheme.fg, fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            if (_prepared != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                child: Text(_prepared!.hdrExplanation, style: const TextStyle(color: VedroTheme.fg3, fontSize: 12.5)),
              ),
            SwitchListTile(
              dense: true,
              title: Text(
                'Anime4K 动漫超分锐化 (${widget.appState.prefs.anime4kMode})',
                style: const TextStyle(color: VedroTheme.fg, fontSize: 13.5),
              ),
              subtitle: const Text(
                '启用 LanczosSharp 升频、暗场去色带与线条锐化',
                style: TextStyle(color: VedroTheme.fg3, fontSize: 11.5),
              ),
              value: _anime4kActive,
              onChanged: (v) async {
                setModal(() => _anime4kActive = v);
                setState(() => _anime4kActive = v);
                await _applyAnime4k(v);
              },
            ),
            const Divider(height: 16),
            ...algos.entries.map((e) => _SheetOptionRow(
                  label: e.value,
                  selected: e.key == _toneMapping,
                  onTap: () async {
                    Navigator.pop(ctx);
                    setState(() => _toneMapping = e.key);
                    await _applyMpvProperty('tone-mapping', e.key);
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _openAudioSheet() {
    const modes = {
      'auto': '自动（优先硬件直通 / 空间音频）',
      'passthrough_bitstream': 'HDMI 源码直通（TrueHD Atmos / DTS:X）',
      'spatial_audio': '系统空间音频',
      'headphone_binaural': '耳机双耳空间化',
      'pcm_stereo': '32-bit 立体声 PCM',
    };
    final audioTracks = _player.state.tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();

    showGlassSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          children: [
            if (audioTracks.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('音轨', style: TextStyle(color: VedroTheme.fg, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              ...audioTracks.map((t) => _SheetOptionRow(
                    label: t.title ?? t.language ?? '音轨 #${t.id}',
                    subtitle: [t.codec, t.language, t.channels].whereType<String>().join(' · '),
                    selected: _player.state.track.audio.id == t.id,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _player.setAudioTrack(t);
                    },
                  )),
              const Divider(height: 22),
            ],
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text('音频输出', style: TextStyle(color: VedroTheme.fg, fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            ...modes.entries.map((e) => _SheetOptionRow(
                  label: e.value,
                  selected: e.key == _audioMode,
                  onTap: () async {
                    setModal(() => _audioMode = e.key);
                    setState(() => _audioMode = e.key);
                    await _applyAudioMode();
                  },
                )),
            const Divider(height: 18),
            SwitchListTile(
              dense: true,
              title: const Text('夜间模式 (DRC)', style: TextStyle(color: VedroTheme.fg, fontSize: 13.5)),
              value: _nightMode,
              onChanged: (v) async {
                setModal(() => _nightMode = v);
                setState(() => _nightMode = v);
                await _applyAudioMode();
              },
            ),
            SwitchListTile(
              dense: true,
              title: const Text('人声对白增强', style: TextStyle(color: VedroTheme.fg, fontSize: 13.5)),
              value: _dialogueBoost,
              onChanged: (v) async {
                setModal(() => _dialogueBoost = v);
                setState(() => _dialogueBoost = v);
                await _applyAudioMode();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyAudioMode() async {
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
      await _applyMpvProperty('af', filters.join(','));
    }
  }

  void _openSubtitleSheet() {
    final extSubs = _prepared?.externalSubtitles ?? const [];
    final embeddedSubs = _player.state.tracks.subtitle
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();

    showGlassSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text('字幕与样式', style: TextStyle(color: VedroTheme.fg, fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            _SheetOptionRow(
              label: '关闭字幕',
              selected: _player.state.track.subtitle.id == 'no',
              onTap: () async {
                Navigator.pop(ctx);
                await _player.setSubtitleTrack(SubtitleTrack.no());
              },
            ),
            ...embeddedSubs.map((t) => _SheetOptionRow(
                  label: t.title ?? t.language ?? '字幕 #${t.id}',
                  subtitle: [t.codec, t.language].whereType<String>().join(' · '),
                  selected: _player.state.track.subtitle.id == t.id,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _player.setSubtitleTrack(t);
                  },
                )),
            ...extSubs.map((s) => _SheetOptionRow(
                  label: s['title']?.toString() ?? '外挂字幕',
                  subtitle: '${s['codec'] ?? 'srt'} · ${s['language'] ?? '外挂'}',
                  selected: false,
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (s['url'] != null) {
                      await _player.setSubtitleTrack(
                        SubtitleTrack.uri(
                          s['url'].toString(),
                          title: s['title']?.toString(),
                          language: s['language']?.toString(),
                        ),
                      );
                    }
                  },
                )),
            const Divider(height: 22),
            _StepperRow(
              label: '字号缩放',
              valueText: '${(_subScale * 100).round()}%',
              onMinus: () async {
                setModal(() => _subScale = (_subScale - 0.1).clamp(0.5, 2.0));
                await _applyMpvProperty('sub-scale', _subScale.toStringAsFixed(2));
              },
              onPlus: () async {
                setModal(() => _subScale = (_subScale + 0.1).clamp(0.5, 2.0));
                await _applyMpvProperty('sub-scale', _subScale.toStringAsFixed(2));
              },
            ),
            _StepperRow(
              label: '垂直位置',
              valueText: '$_subPos%',
              onMinus: () async {
                setModal(() => _subPos = (_subPos - 4).clamp(60, 100));
                await _applyMpvProperty('sub-pos', '$_subPos');
              },
              onPlus: () async {
                setModal(() => _subPos = (_subPos + 4).clamp(60, 100));
                await _applyMpvProperty('sub-pos', '$_subPos');
              },
            ),
            _StepperRow(
              label: '时间偏移',
              valueText: '${_subDelaySecs >= 0 ? '+' : ''}${_subDelaySecs.toStringAsFixed(1)}s',
              onMinus: () async {
                setModal(() => _subDelaySecs -= 0.2);
                await _applyMpvProperty('sub-delay', _subDelaySecs.toStringAsFixed(2));
              },
              onPlus: () async {
                setModal(() => _subDelaySecs += 0.2);
                await _applyMpvProperty('sub-delay', _subDelaySecs.toStringAsFixed(2));
              },
            ),
            SwitchListTile(
              dense: true,
              title: const Text('强制覆盖 ASS 字幕样式', style: TextStyle(color: VedroTheme.fg, fontSize: 13.5)),
              value: _forceAssOverride,
              onChanged: (v) async {
                setModal(() => _forceAssOverride = v);
                setState(() => _forceAssOverride = v);
                await _applyMpvProperty('sub-ass-override', v ? 'force' : 'no');
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('字幕字体', style: TextStyle(color: VedroTheme.fg2, fontSize: 13)),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (family, lbl) in [
                          ('', '系统默认'),
                          ('PingFang SC', '苹方'),
                          ('Hiragino Sans GB', '冬青黑'),
                          ('Noto Sans CJK SC', '思源黑体'),
                          ...widget.appState.prefs.customFontPaths.map((fp) {
                            final stem = fp
                                .split('/')
                                .last
                                .replaceAll(RegExp(r'\.(ttf|otf|ttc)$', caseSensitive: false), '');
                            return (stem, stem);
                          }),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _DeckPillButton(
                              label: lbl,
                              active: _subFontFamily == family,
                              onTap: () async {
                                setModal(() => _subFontFamily = family);
                                setState(() => _subFontFamily = family);
                                await _applyMpvProperty('sub-fonts-dir', widget.appState.fontsDirectoryPath);
                                await _applyMpvProperty('sub-font', family.isEmpty ? 'sans-serif' : family);
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openVersionSheet() {
    final sources = _prepared?.allSources ?? const [];
    showGlassSheet<void>(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('切换版本', style: TextStyle(color: VedroTheme.fg, fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          ...sources.map((src) => _SheetOptionRow(
                label: src.displayLabel,
                selected: src.id == _prepared?.mediaSourceId,
                onTap: () {
                  Navigator.pop(ctx);
                  _startPlayback(src.id);
                },
              )),
        ],
      ),
    );
  }

  String _fmtTime(double secs) {
    final total = secs.isFinite && secs > 0 ? secs.floor() : 0;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    return h > 0
        ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _fmtDelta(double delta) {
    final sign = delta >= 0 ? '+' : '-';
    return '$sign${_fmtTime(delta.abs())}';
  }
}

/// Custom IINA / Infuse precision scrub bar:
/// - Smoothly expands track height on hover/drag (4px -> 7px)
/// - Displays buffered track + Intro/Outro segment markers
/// - Floating hover timestamp preview pill above cursor
/// - Clickable right timestamp toggles Total vs Remaining time
class _CinemaScrubBar extends StatefulWidget {
  const _CinemaScrubBar({
    required this.positionSecs,
    required this.bufferedSecs,
    required this.durationSecs,
    required this.segments,
    required this.showRemaining,
    required this.fmtTime,
    required this.onToggleRemaining,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
  });

  final double positionSecs;
  final double bufferedSecs;
  final double durationSecs;
  final List<MediaSegmentModel> segments;
  final bool showRemaining;
  final String Function(double) fmtTime;
  final VoidCallback onToggleRemaining;
  final VoidCallback onScrubStart;
  final ValueChanged<double> onScrubUpdate;
  final ValueChanged<double> onScrubEnd;

  @override
  State<_CinemaScrubBar> createState() => _CinemaScrubBarState();
}

class _CinemaScrubBarState extends State<_CinemaScrubBar> {
  bool _hovering = false;
  bool _dragging = false;
  double? _hoverRatio;

  double _ratioFromDx(double dx, double width) =>
      width <= 0 ? 0.0 : (dx / width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final dur = widget.durationSecs > 0 ? widget.durationSecs : 1.0;
    final posRatio = (widget.positionSecs / dur).clamp(0.0, 1.0);
    final bufRatio = (widget.bufferedSecs / dur).clamp(0.0, 1.0);
    final active = _hovering || _dragging;
    final trackH = active ? 6.5 : 4.0;
    final accent = Theme.of(context).colorScheme.secondary;

    final rightTimeText = widget.showRemaining && widget.durationSecs > 0
        ? '-${widget.fmtTime((widget.durationSecs - widget.positionSecs).clamp(0, widget.durationSecs))}'
        : widget.fmtTime(widget.durationSecs);

    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            widget.fmtTime(widget.positionSecs),
            style: const TextStyle(
              color: Color(0xE0FFFFFF),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hovering = true),
                onHover: (e) => setState(() => _hoverRatio = _ratioFromDx(e.localPosition.dx, w)),
                onExit: (_) => setState(() {
                  _hovering = false;
                  _hoverRatio = null;
                }),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) {
                    final secs = _ratioFromDx(d.localPosition.dx, w) * dur;
                    widget.onScrubEnd(secs);
                  },
                  onHorizontalDragStart: (d) {
                    setState(() => _dragging = true);
                    widget.onScrubStart();
                    widget.onScrubUpdate(_ratioFromDx(d.localPosition.dx, w) * dur);
                  },
                  onHorizontalDragUpdate: (d) {
                    final ratio = _ratioFromDx(d.localPosition.dx, w);
                    setState(() => _hoverRatio = ratio);
                    widget.onScrubUpdate(ratio * dur);
                  },
                  onHorizontalDragEnd: (_) {
                    final ratio = _hoverRatio ?? posRatio;
                    setState(() => _dragging = false);
                    widget.onScrubEnd(ratio * dur);
                  },
                  child: SizedBox(
                    height: 24,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.centerLeft,
                      children: [
                        // Base track
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          height: trackH,
                          decoration: BoxDecoration(
                            color: const Color(0x30FFFFFF),
                            borderRadius: BorderRadius.circular(trackH / 2),
                          ),
                        ),
                        // Buffered track
                        if (bufRatio > 0)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            height: trackH,
                            width: w * bufRatio,
                            decoration: BoxDecoration(
                              color: const Color(0x38FFFFFF),
                              borderRadius: BorderRadius.circular(trackH / 2),
                            ),
                          ),
                        // Intro/Outro markers
                        for (final seg in widget.segments)
                          if (widget.durationSecs > 0)
                            Positioned(
                              left: (seg.startSecs / dur).clamp(0.0, 1.0) * w,
                              width: ((seg.endSecs - seg.startSecs) / dur).clamp(0.0, 1.0) * w,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 140),
                                height: trackH,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.72),
                                  borderRadius: BorderRadius.circular(trackH / 2),
                                ),
                              ),
                            ),
                        // Played progress bar
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 80),
                          height: trackH,
                          width: w * posRatio,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(trackH / 2),
                          ),
                        ),
                        // Hover-revealed sleek thumb
                        Positioned(
                          left: (w * posRatio - 6).clamp(0.0, (w - 12).clamp(0.0, w)),
                          child: AnimatedScale(
                            scale: active ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 140),
                            curve: Curves.easeOutCubic,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: Color(0x99000000), blurRadius: 8),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Hover timestamp tooltip pill
                        if (_hoverRatio != null && widget.durationSecs > 0)
                          Positioned(
                            left: (_hoverRatio! * w - 28).clamp(0.0, (w - 56).clamp(0.0, w)),
                            top: -28,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xE8141417),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0x28FFFFFF), width: 0.6),
                              ),
                              child: Text(
                                widget.fmtTime(_hoverRatio! * dur),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: widget.onToggleRemaining,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: SizedBox(
              width: 64,
              child: Text(
                rightTimeText,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Color(0xA6FFFFFF),
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniVolumeBar extends StatelessWidget {
  const _MiniVolumeBar({required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        void update(double dx) => onChanged((dx / w).clamp(0.0, 1.0));
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => update(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => update(d.localPosition.dx),
            child: SizedBox(
              height: 22,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 3.5,
                    decoration: BoxDecoration(
                      color: const Color(0x32FFFFFF),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Container(
                    height: 3.5,
                    width: w * value.clamp(0.0, 1.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Positioned(
                    left: (w * value.clamp(0.0, 1.0) - 5).clamp(0.0, (w - 10).clamp(0.0, w)),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CircleHudButton extends StatefulWidget {
  const _CircleHudButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.active = false,
    this.iconSize = 18,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool active;
  final double iconSize;

  @override
  State<_CircleHudButton> createState() => _CircleHudButtonState();
}

class _CircleHudButtonState extends State<_CircleHudButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    final btn = PressableScale(
      onTap: widget.onTap,
      onHoverChanged: (v) => setState(() => _hovered = v),
      hoverScale: 1.06,
      pressScale: 0.9,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.active
              ? accent.withValues(alpha: 0.25)
              : (_hovered ? const Color(0x32FFFFFF) : const Color(0x20000000)),
          border: Border.all(
            color: widget.active
                ? accent.withValues(alpha: 0.7)
                : const Color(0x24FFFFFF),
            width: 0.7,
          ),
        ),
        child: Icon(
          widget.icon,
          size: widget.iconSize,
          color: widget.active ? accent : Colors.white,
        ),
      ),
    );
    return widget.tooltip != null ? Tooltip(message: widget.tooltip!, child: btn) : btn;
  }
}

class _DeckIconButton extends StatefulWidget {
  const _DeckIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  State<_DeckIconButton> createState() => _DeckIconButtonState();
}

class _DeckIconButtonState extends State<_DeckIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final btn = PressableScale(
      onTap: widget.onTap,
      onHoverChanged: (v) => setState(() => _hovered = v),
      hoverScale: 1.06,
      pressScale: 0.9,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _hovered ? const Color(0x22FFFFFF) : Colors.transparent,
        ),
        child: Icon(widget.icon, size: 21, color: Colors.white),
      ),
    );
    return widget.tooltip != null ? Tooltip(message: widget.tooltip!, child: btn) : btn;
  }
}

class _DeckPillButton extends StatefulWidget {
  const _DeckPillButton({
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  State<_DeckPillButton> createState() => _DeckPillButtonState();
}

class _DeckPillButtonState extends State<_DeckPillButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return PressableScale(
      onTap: widget.onTap,
      onHoverChanged: (v) => setState(() => _hovered = v),
      hoverScale: 1.04,
      pressScale: 0.94,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.active
              ? accent.withValues(alpha: 0.24)
              : (_hovered ? const Color(0x28FFFFFF) : const Color(0x16FFFFFF)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.active ? accent.withValues(alpha: 0.65) : const Color(0x1CFFFFFF),
            width: 0.7,
          ),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            color: widget.active ? accent : const Color(0xEBFFFFFF),
            fontSize: 12,
            fontWeight: FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.valueText,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final String valueText;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: VedroTheme.fg2, fontSize: 13.5)),
          const SizedBox(width: 10),
          Text(
            valueText,
            style: const TextStyle(
              color: VedroTheme.fg,
              fontSize: 13,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          _DeckIconButton(icon: Icons.remove_rounded, onTap: onMinus),
          const SizedBox(width: 4),
          _DeckIconButton(icon: Icons.add_rounded, onTap: onPlus),
        ],
      ),
    );
  }
}

class _SheetOptionRow extends StatelessWidget {
  const _SheetOptionRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? const Color(0x16FFFFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? Colors.white : VedroTheme.fg,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: const TextStyle(color: VedroTheme.fg3, fontSize: 12)),
                  ],
                ],
              ),
            ),
            if (selected) Icon(Icons.check_rounded, size: 18, color: accent),
          ],
        ),
      ),
    );
  }
}
