import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/models/models.dart';
import '../core/platform/native_playback_channel.dart';
import '../core/platform/platform_perf.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/ai_bilingual_subtitle.dart';
import '../widgets/beauty_filter.dart';
import '../widgets/danmaku_engine.dart';
import '../widgets/local_asr_engine.dart';
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
    this.initialExternalSubtitlePath,
    this.preferredAudioLangOverride,
    this.preferredSubLangOverride,
    this.localFilePath,
    this.localPlaylistPaths,
  });

  final MediaItemModel item;
  final VedroAppState appState;
  final String? mediaSourceId;
  final List<MediaItemModel>? playlistEpisodes;
  final List<MediaSegmentModel>? segments;
  final int? initialAudioStreamIndex;
  final int? initialSubtitleStreamIndex;
  final String? initialExternalSubtitlePath;
  final String? preferredAudioLangOverride;
  final String? preferredSubLangOverride;
  final String? localFilePath;
  final List<String>? localPlaylistPaths;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _videoController;

  late MediaItemModel _currentItem;
  late List<MediaSegmentModel> _segments;
  String? _activeLocalPath;
  List<MediaItemModel> _localEpisodes = const [];
  final Map<String, String> _localPathById = {};
  final List<({String title, String path})> _loadedLocalSubtitles = [];

  PreparedPlaybackModel? _prepared;
  final ValueNotifier<Map<String, dynamic>> _statsNotifier =
      ValueNotifier<Map<String, dynamic>>(const {});
  bool _loading = true;
  bool _buffering = false;
  String? _error;
  bool _disposed = false;
  bool _isInitialEpisode = true;
  int _autoRetryCount = 0;
  bool _hwFallbackAttempted = false;
  bool _inPipMode = false;
  int _lastAudioInterruptCount = 0;
  bool _usingNativeBrightness = false;
  int _videoWidth = 16;
  int _videoHeight = 9;
  int _lastHoverRevealMs = 0;

  // End-of-video Replay & Up-Next 6s Countdown state
  bool _hasEndedReplay = false;
  int _upNextCountdown = 0;
  Timer? _upNextTimer;
  Timer? _pauseWakeLockTimer;
  bool _quickSkipIntroDismissed = false;

  // Mobile fullscreen live clock & battery indicator (isolated ValueNotifier)
  final ValueNotifier<({String clock, int batteryPct, bool charging})> _statusBarNotifier =
      ValueNotifier<({String clock, int batteryPct, bool charging})>(
    (clock: '', batteryPct: -1, charging: false),
  );
  Timer? _statusBarTimer;

  // Gesture HUD isolated ValueNotifier (zero full-screen setState on drag/key ticks)
  final ValueNotifier<({String? mode, String text})> _gestureHudNotifier =
      ValueNotifier<({String? mode, String text})>((mode: null, text: ''));

  // Rapid D-Pad seek accumulator
  double _accumulatedKeySeekDelta = 0.0;
  Timer? _keySeekFlushTimer;

  bool _controlsVisible = true;
  bool _hoveringChrome = false;
  bool _showStats = false;
  bool _showEpisodeDrawer = false;
  bool _epDrawerGrid = false;
  bool _epDrawerDescending = false;
  int _epDrawerRangeIdx = 0;
  bool _showRemaining = false;
  bool _isFullscreen = false;
  bool _enteredFullscreenHere = false;
  bool _isLandscapeOrientation = true;
  bool _userLockedOrientation = false;
  bool _alwaysOnTop = false;
  bool _screenLocked = false;
  bool _lockIconVisible = false;
  bool _loopFile = false;
  bool _paused = false;
  bool _muted = false;
  double _preMuteVolume = 100.0;
  double _positionSecs = 0;
  double _bufferedSecs = 0;
  double _durationSecs = 0;
  final ValueNotifier<double> _positionNotifier = ValueNotifier<double>(0);
  final ValueNotifier<double> _bufferedNotifier = ValueNotifier<double>(0);
  final ValueNotifier<MediaSegmentModel?> _activeSegmentNotifier =
      ValueNotifier<MediaSegmentModel?>(null);
  final ValueNotifier<int> _networkSpeedBpsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _sleepRemainingNotifier = ValueNotifier<int>(0);
  int _lastPosNotifyMs = 0;
  int _lastBufNotifyMs = 0;
  Timer? _speedTimer;
  Timer? _persistPrefsTimer;
  double _speed = 1.0;
  double _preBoostSpeed = 1.0;
  bool _isSpeedBoost = false;
  double _volume = 100.0;
  double _brightness = 1.0;

  // Color equalizer & beauty filter & audio delay & A-B loop & chapters & sleep timer
  int _eqBrightness = 0;
  int _eqContrast = 0;
  int _eqSaturation = 0;
  int _eqGamma = 0;
  String _beautyPreset = 'off';
  double _beautyStrength = 0.55;
  double _audioDelaySecs = 0.0;

  // AI bilingual subtitle + ASR lookahead controller
  late final AiSubtitleTranslatorController _aiSubCtrl;
  double _aiSubFontScale = 1.0;
  String? _activeSubLocalPath;
  String? _activeSubUrl;
  String? _activeSubFormat;
  String? _activeSubLabel;
  int _lastAiPosTickMs = 0;
  double? _loopPointA;
  double? _loopPointB;
  List<({String title, double timeSecs})> _chapters = const [];
  bool _sleepAfterEpisode = false;
  int _sleepRemainingSecs = 0;
  Timer? _sleepTimer;
  Timer? _lockIconTimer;

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
  List<Map<String, dynamic>> _danmakuCandidates = const [];
  bool _danmakuLoading = false;
  bool _danmakuSearching = false;
  String? _danmakuMatchTitle;
  String? _danmakuError;
  double _danmakuOpacity = 0.82;
  double _danmakuFontSize = 18.0;
  double _danmakuSpeedSecs = 9.0;
  double _danmakuArea = 0.5;
  bool _danmakuHideTop = false;
  bool _danmakuHideBottom = false;
  final Set<String> _autoSkippedSegKeys = {};
  final Set<String> _savedLearnedTrackKeys = {};
  bool _customIntroSkipped = false;
  bool _customOutroSkipped = false;
  bool _completedTriggered = false;

  // Gesture HUD state
  bool _scrubbing = false;
  double _scrubStartSecs = 0;
  double _scrubTargetSecs = 0;
  String? _scaleAxis; // 'h' | 'v' | 'pinch'
  Offset _scaleAnchor = Offset.zero;
  Offset _lastTapDownPos = Offset.zero;

  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _hideControlsTimer;
  Timer? _gestureHudTimer;
  Timer? _statsTimer;
  Timer? _progressTimer;
  Timer? _ticketRefreshTimer;
  final _focusNode = FocusNode(debugLabel: 'player-root');
  final _playPauseFocusNode = FocusNode(debugLabel: 'player-play-pause');
  final _unlockFocusNode = FocusNode(debugLabel: 'player-unlock');
  final _drawerCloseFocusNode = FocusNode(debugLabel: 'player-drawer-close');

  List<MediaItemModel> get _episodes =>
      _localEpisodes.isNotEmpty ? _localEpisodes : (widget.playlistEpisodes ?? const []);

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
    _activeLocalPath = widget.localFilePath;
    if (widget.localPlaylistPaths != null && widget.localPlaylistPaths!.isNotEmpty) {
      _buildLocalPlaylist(widget.localPlaylistPaths!);
    } else if (_activeLocalPath != null && _activeLocalPath!.isNotEmpty) {
      final resolved = NativePlaybackChannel.resolveLocalPlaylist(_activeLocalPath!);
      if (resolved.files.length > 1) {
        _buildLocalPlaylist(resolved.files);
      }
    }
    _speed = p.rememberSpeed ? p.defaultSpeed.clamp(0.25, 4.0) : 1.0;
    _aspectMode = p.rememberAspect ? p.defaultAspect : 'fit';
    _subScale = p.subtitleFontScale;
    _subPos = p.subtitlePos;
    _subDelaySecs = p.subtitleDelaySecs;
    _subFontFamily = p.subtitleFontFamily;
    _forceAssOverride = p.forceAssOverride;
    _audioDelaySecs = p.audioDelayMs / 1000.0;
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
    if (p.rememberVolume) {
      _volume = p.savedVolume.clamp(0.0, _maxVolume);
      _muted = _volume <= 0.1;
      if (_volume > 5) _preMuteVolume = _volume;
    }
    _hwDecodeEnabled = (widget.appState.settings['hwdec'] ?? 'auto_zero_copy') != 'software';
    _anime4kActive = p.anime4kEnabled && (!p.anime4kOnlyAnime || _isLikelyAnime(_currentItem));
    _toneMapping = (widget.appState.settings['tone_mapping'] ?? 'bt.2446a').toString();
    _audioMode = (widget.appState.settings['audio_mode'] ?? 'auto').toString();
    _nightMode = widget.appState.settings['night_mode'] == true;
    _dialogueBoost = widget.appState.settings['dialogue_boost'] == true;
    _beautyPreset = p.beautyFilterPreset;
    _beautyStrength = p.beautyFilterStrength;
    _aiSubFontScale = p.aiSubtitleFontScale;
    _aiSubCtrl = AiSubtitleTranslatorController(
      appState: widget.appState,
      mediaTitle: _currentItem.displayName,
    );

    WidgetsBinding.instance.addObserver(this);
    _lastAudioInterruptCount = NativePlaybackChannel.audioInterruptCountNotifier.value;
    NativePlaybackChannel.audioInterruptCountNotifier.addListener(_onAudioInterrupted);
    NativePlaybackChannel.pipModeNotifier.addListener(_onPipModeChanged);
    unawaited(NativePlaybackChannel.setAudioPlaybackActive(true));
    NativePlaybackChannel.setKeepScreenOn(true);
    NativePlaybackChannel.syncWindowChrome(
      isLight: false,
      canvasArgb: 0xFF000000,
      fgArgb: 0xFFF4F4F6,
    );
    if (_isMobile) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      NativePlaybackChannel.setPreferredFrameRate(60.0);
      final initialPortrait = _inferInitialPortraitVideo(_currentItem);
      _applyMobileOrientation(landscape: !initialPortrait);
      unawaited(_initMobileBrightnessAndStatus());
    }
    if (_isDesktop) {
      NativePlaybackChannel.ensureWindowListener();
      NativePlaybackChannel.fullscreenNotifier.addListener(_onNativeFullscreenChanged);
      NativePlaybackChannel.droppedFilesNotifier.addListener(_onFilesDropped);
      unawaited(NativePlaybackChannel.isFullscreen().then((fs) {
        if (mounted) setState(() => _isFullscreen = fs);
      }));
    }

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
        setState(() {
          _paused = !playing;
          if (playing) {
            _hasEndedReplay = false;
            _cancelUpNextCountdown();
          }
        });
        if (playing) {
          _pauseWakeLockTimer?.cancel();
          NativePlaybackChannel.setKeepScreenOn(true);
          _scheduleHideControls();
        } else {
          _hideControlsTimer?.cancel();
          _pauseWakeLockTimer?.cancel();
          _pauseWakeLockTimer = Timer(const Duration(seconds: 30), () {
            if (mounted && _paused) {
              NativePlaybackChannel.setKeepScreenOn(false);
            }
          });
        }
      }
    }));
    _subs.add(_player.stream.buffering.listen((buffering) {
      if (mounted && _buffering != buffering) {
        setState(() => _buffering = buffering);
      }
    }));
    _subs.add(_player.stream.position.listen((pos) {
      if (!mounted || _scrubbing) return;
      final secs = pos.inMilliseconds / 1000.0;
      _positionSecs = secs;
      _checkAutoSkipSegments(secs);
      if (_loopPointA != null && _loopPointB != null && secs >= _loopPointB!) {
        _seekTo(_loopPointA!);
      }
      final nextSeg = _activeSegment;
      final curSeg = _activeSegmentNotifier.value;
      if (nextSeg?.type != curSeg?.type || nextSeg?.endTicks != curSeg?.endTicks) {
        _activeSegmentNotifier.value = nextSeg;
      }
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (_aiSubCtrl.enabled && nowMs - _lastAiPosTickMs >= 120) {
        _lastAiPosTickMs = nowMs;
        _aiSubCtrl.updatePosition(
          secs,
          delaySecs: _subDelaySecs,
          durationSecs: _durationSecs,
        );
      }
      final danmakuActive = _danmakuEnabled && _danmakuComments.isNotEmpty;
      if (danmakuActive) {
        final interval = _isMobile ? 33 : 20;
        if (nowMs - _lastPosNotifyMs >= interval) {
          _lastPosNotifyMs = nowMs;
          _positionNotifier.value = secs;
        }
      } else if (_controlsVisible) {
        if (nowMs - _lastPosNotifyMs >= 250) {
          _lastPosNotifyMs = nowMs;
          _positionNotifier.value = secs;
        }
      }
    }));
    _subs.add(_player.stream.buffer.listen((buf) {
      if (!mounted) return;
      final secs = buf.inMilliseconds / 1000.0;
      _bufferedSecs = secs;
      if (_controlsVisible) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs - _lastBufNotifyMs >= 500) {
          _lastBufNotifyMs = nowMs;
          _bufferedNotifier.value = secs;
        }
      }
    }));
    _subs.add(_player.stream.duration.listen((dur) {
      if (mounted && dur.inMilliseconds > 0) {
        setState(() => _durationSecs = dur.inMilliseconds / 1000.0);
        if (_chapters.isEmpty) {
          unawaited(_loadChapters());
        }
      }
    }));
    _subs.add(_player.stream.completed.listen((done) {
      if (!done || !mounted) return;
      if (_activeLocalPath != null && _activeLocalPath!.isNotEmpty) {
        unawaited(widget.appState.saveLocalResumeSecs(_activeLocalPath!, 0.0));
      }
      if (_sleepAfterEpisode) {
        _sleepAfterEpisode = false;
        Navigator.of(context).pop();
        return;
      }
      if (!_completedTriggered &&
          !_loopFile &&
          widget.appState.prefs.autoPlayNext &&
          _nextEpisode != null) {
        _completedTriggered = true;
        _startUpNextCountdown();
      } else if (!_loopFile) {
        setState(() {
          _hasEndedReplay = true;
          _controlsVisible = true;
        });
      }
    }));
    _subs.add(_player.stream.videoParams.listen(_onVideoParamsChanged));
    _subs.add(_player.stream.tracks.listen(_onTracksChanged));
    _subs.add(_player.stream.subtitle.listen((lines) {
      if (!mounted || !_aiSubCtrl.enabled || !_aiSubCtrl.isLiveFallbackMode) return;
      _aiSubCtrl.onLiveSubtitleText(
        lines.where((l) => l.trim().isNotEmpty).join('\n'),
      );
    }));
    _subs.add(_player.stream.error.listen(_onPlayerStreamError));

    _startPlayback(widget.mediaSourceId);
    if (_danmakuEnabled) {
      unawaited(_loadDanmaku());
    }
  }

  Future<void> _initMobileBrightnessAndStatus() async {
    try {
      final cur = await NativePlaybackChannel.getScreenBrightness();
      if (!mounted) return;
      if (cur != null) {
        _usingNativeBrightness = true;
        if (widget.appState.prefs.rememberBrightness) {
          await NativePlaybackChannel.setScreenBrightness(_brightness);
        } else {
          setState(() => _brightness = cur.clamp(0.15, 1.0));
        }
      }
    } catch (_) {}
    await _refreshMobileStatusBar();
    _statusBarTimer?.cancel();
    _statusBarTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) unawaited(_refreshMobileStatusBar());
    });
  }

  Future<void> _refreshMobileStatusBar() async {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final bat = await NativePlaybackChannel.getBatteryInfo();
    if (!mounted) return;
    _statusBarNotifier.value = (
      clock: '$hh:$mm',
      batteryPct: bat?.level ?? -1,
      charging: bat?.charging ?? false,
    );
  }

  void _onAudioInterrupted() {
    if (!mounted) return;
    final cur = NativePlaybackChannel.audioInterruptCountNotifier.value;
    if (cur == _lastAudioInterruptCount) return;
    _lastAudioInterruptCount = cur;
    if (!_paused) {
      unawaited(_player.pause());
      _flashGestureHud('seek_feedback', text: '音频设备变化，已暂停播放');
    }
  }

  void _onPipModeChanged() {
    if (!mounted) return;
    final inPip = NativePlaybackChannel.pipModeNotifier.value;
    if (_inPipMode != inPip) {
      setState(() {
        _inPipMode = inPip;
        if (inPip) {
          _controlsVisible = false;
          _showEpisodeDrawer = false;
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      unawaited(_flushCurrentProgress());
      if (!widget.appState.prefs.backgroundAudio && !_inPipMode && !_paused) {
        unawaited(_player.pause());
      }
    } else if (state == AppLifecycleState.resumed) {
      if (!_paused) {
        NativePlaybackChannel.setKeepScreenOn(true);
      }
    }
  }

  Future<void> _flushCurrentProgress() async {
    if (widget.appState.prefs.incognitoMode) return;
    if (_activeLocalPath != null && _activeLocalPath!.isNotEmpty) {
      if (_positionSecs > 3.0) {
        await widget.appState.saveLocalResumeSecs(_activeLocalPath!, _positionSecs);
      }
      return;
    }
    if (_prepared == null) return;
    try {
      await widget.appState.core.invoke('report_playback_progress', {
        'position_ticks': (_positionSecs * 10000000).round(),
        if (_durationSecs > 0) 'run_time_ticks': (_durationSecs * 10000000).round(),
        'is_paused': _paused,
      });
    } catch (_) {}
  }

  void _onPlayerStreamError(String err) {
    if (!mounted || err.isEmpty) return;
    final lower = err.toLowerCase();
    // Ignore non-fatal subtitle/metadata probing noise
    if (lower.contains('subtitle') && !lower.contains('fatal')) return;

    // 1. Automatic 1x HW -> SW fallback on decoder failures
    if (_hwDecodeEnabled &&
        !_hwFallbackAttempted &&
        (lower.contains('hwdec') ||
            lower.contains('codec') ||
            lower.contains('videotoolbox') ||
            lower.contains('mediacodec') ||
            lower.contains('d3d11') ||
            lower.contains('vaapi'))) {
      _hwFallbackAttempted = true;
      _hwDecodeEnabled = false;
      _flashGestureHud('seek_feedback', text: '硬件解码异常，已自动切换软件解码重试…');
      unawaited(_startPlayback(_prepared?.mediaSourceId, resumeFromSecs: _positionSecs));
      return;
    }

    // 2. Automatic transient network / stream-ticket retry (up to 2x)
    if (_activeLocalPath == null &&
        _autoRetryCount < 2 &&
        (lower.contains('http') ||
            lower.contains('tcp') ||
            lower.contains('eof') ||
            lower.contains('timeout') ||
            lower.contains('network') ||
            lower.contains('connection') ||
            lower.contains('failed to open'))) {
      _autoRetryCount += 1;
      final attempt = _autoRetryCount;
      _flashGestureHud('seek_feedback', text: '网络波动，正在自动重连（第 $attempt/2 次）…');
      unawaited(() async {
        try {
          if (_prepared?.usesStreamTicket == true) {
            await widget.appState.core.invoke('refresh_stream_ticket');
          }
        } catch (_) {}
        await Future<void>.delayed(Duration(milliseconds: 800 * attempt));
        if (!mounted || _disposed) return;
        await _startPlayback(_prepared?.mediaSourceId, resumeFromSecs: _positionSecs);
      }());
      return;
    }

    setState(() {
      _error = err;
      _loading = false;
      _controlsVisible = true;
    });
  }

  void _startUpNextCountdown() {
    _upNextTimer?.cancel();
    setState(() {
      _upNextCountdown = 6;
      _controlsVisible = true;
    });
    _upNextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_upNextCountdown <= 1) {
        t.cancel();
        setState(() => _upNextCountdown = 0);
        final next = _nextEpisode;
        if (next != null) {
          unawaited(_switchEpisode(next));
        }
      } else {
        setState(() => _upNextCountdown -= 1);
      }
    });
  }

  void _cancelUpNextCountdown() {
    _upNextTimer?.cancel();
    _upNextTimer = null;
    if (_upNextCountdown != 0) {
      _upNextCountdown = 0;
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

  bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  bool get _isTv => PlatformPerfProfile.isTv;

  bool get _isMobile => !kIsWeb && ((Platform.isAndroid && !_isTv) || Platform.isIOS);

  bool _inferInitialPortraitVideo(MediaItemModel item) {
    if (item.mediaSources.isNotEmpty) {
      final vs = item.mediaSources.first.videoStreams;
      if (vs.isNotEmpty) {
        final w = vs.first.width ?? 0;
        final h = vs.first.height ?? 0;
        if (w > 0 && h > 0) return h > w;
      }
    }
    return false;
  }

  void _applyMobileOrientation({required bool landscape}) {
    if (!_isMobile) return;
    _isLandscapeOrientation = landscape;
    if (landscape) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  void _toggleMobileOrientation() {
    if (!_isMobile) return;
    final nextLandscape = !_isLandscapeOrientation;
    setState(() {
      _userLockedOrientation = true;
      _isLandscapeOrientation = nextLandscape;
    });
    _applyMobileOrientation(landscape: nextLandscape);
    _flashGestureHud('seek_feedback', text: nextLandscape ? '已切换横屏播放' : '已切换竖屏播放');
  }

  void _onTracksChanged(Tracks tracks) {
    if (!mounted || (_activeLocalPath != null && _activeLocalPath!.isNotEmpty)) return;
    final realAudios = tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final realSubs = tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
    if (realAudios.isEmpty && realSubs.isEmpty) return;

    final srcId = (widget.mediaSourceId != null && widget.mediaSourceId!.isNotEmpty)
        ? widget.mediaSourceId!
        : (_prepared?.allSources.isNotEmpty == true ? _prepared!.allSources.first.id : 'default');
    final cacheKey = '${_currentItem.id}::$srcId::${realAudios.length}::${realSubs.length}';
    if (!_savedLearnedTrackKeys.add(cacheKey)) return;

    final streams = <Map<String, dynamic>>[];
    var nextIdx = 0;
    for (final v in tracks.video.where((t) => t.id != 'auto' && t.id != 'no')) {
      streams.add({
        'Index': nextIdx++,
        'Type': 'Video',
        if (v.codec != null && v.codec!.isNotEmpty) 'Codec': v.codec,
        if (v.w != null && v.w! > 0) 'Width': v.w,
        if (v.h != null && v.h! > 0) 'Height': v.h,
      });
    }
    for (final a in realAudios) {
      streams.add({
        'Index': int.tryParse(a.id) ?? nextIdx,
        'Type': 'Audio',
        if (a.codec != null && a.codec!.isNotEmpty) 'Codec': a.codec,
        if (a.language != null && a.language!.isNotEmpty) 'Language': a.language,
        if (a.title != null && a.title!.isNotEmpty) 'Title': a.title,
        if (a.channelscount != null && a.channelscount! > 0) 'Channels': a.channelscount,
      });
      nextIdx++;
    }
    for (final s in realSubs) {
      // Skip external URLs already tracked separately as external sidecars
      if ((s.uri == true) || (s.id.startsWith('http'))) continue;
      streams.add({
        'Index': int.tryParse(s.id) ?? nextIdx,
        'Type': 'Subtitle',
        if (s.codec != null && s.codec!.isNotEmpty) 'Codec': s.codec,
        if (s.language != null && s.language!.isNotEmpty) 'Language': s.language,
        if (s.title != null && s.title!.isNotEmpty) 'Title': s.title,
        'IsExternal': false,
      });
      nextIdx++;
    }
    if (streams.isNotEmpty) {
      unawaited(
        widget.appState.core
            .invoke('save_learned_tracks', {
              'item_id': _currentItem.id,
              'media_source_id': srcId,
              'streams': streams,
            })
            .catchError((_) => null),
      );
    }
  }

  void _onVideoParamsChanged(VideoParams vp) {
    if (!mounted) return;
    final rawW = vp.dw ?? vp.w ?? 0;
    final rawH = vp.dh ?? vp.h ?? 0;
    if (rawW <= 0 || rawH <= 0) return;
    final rot = ((vp.rotate ?? 0) + _videoRotate) % 360;
    final swapped = rot == 90 || rot == 270;
    final effW = swapped ? rawH : rawW;
    final effH = swapped ? rawW : rawH;
    _videoWidth = effW;
    _videoHeight = effH;
    if (!_isMobile || _userLockedOrientation) return;
    final wantLandscape = effW >= effH;
    if (wantLandscape != _isLandscapeOrientation) {
      setState(() => _isLandscapeOrientation = wantLandscape);
      _applyMobileOrientation(landscape: wantLandscape);
    }
  }

  void _buildLocalPlaylist(List<String> files) {
    _localPathById.clear();
    final eps = <MediaItemModel>[];
    for (var i = 0; i < files.length; i++) {
      final path = files[i];
      final id = 'local_$i';
      final fileName = path.split(Platform.pathSeparator).last;
      final dot = fileName.lastIndexOf('.');
      final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
      _localPathById[id] = path;
      eps.add(MediaItemModel(
        id: id,
        name: stem,
        type: 'Video',
        indexNumber: i + 1,
      ));
      if (path == _activeLocalPath) {
        _currentItem = eps.last;
      }
    }
    _localEpisodes = eps;
  }

  void _onFilesDropped() {
    if (!mounted) return;
    final paths = NativePlaybackChannel.droppedFilesNotifier.value;
    if (paths.isEmpty) return;
    // Clear immediately so ShellScreen doesn't re-handle the same drop
    NativePlaybackChannel.droppedFilesNotifier.value = const [];

    // 1. Check for subtitle files first -> load live without interrupting playback!
    final subPaths = paths.where(NativePlaybackChannel.isSubtitleFile).toList();
    if (subPaths.isNotEmpty) {
      for (final sp in subPaths) {
        unawaited(_loadExternalSubtitleFile(sp));
      }
      return;
    }

    // 2. Otherwise check for video files or directory -> switch local playback!
    for (final p in paths) {
      final resolved = NativePlaybackChannel.resolveLocalPlaylist(p);
      if (resolved.files.isNotEmpty) {
        setState(() {
          _activeLocalPath = resolved.files[resolved.startIndex];
          _buildLocalPlaylist(resolved.files);
          _segments = const [];
          _chapters = const [];
          _danmakuComments = const [];
        });
        unawaited(_startPlayback(null));
        return;
      }
    }
  }

  Future<void> _loadExternalSubtitleFile(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    final fileName = trimmed.split(Platform.pathSeparator).last;
    try {
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(Uri.file(trimmed).toString(), title: fileName),
      );
      if (mounted) {
        setState(() {
          _loadedLocalSubtitles.removeWhere((e) => e.path == trimmed);
          _loadedLocalSubtitles.add((title: fileName, path: trimmed));
          _activeSubLocalPath = trimmed;
          _activeSubUrl = null;
          _activeSubFormat = null;
          _activeSubLabel = fileName;
        });
        if (_aiSubCtrl.enabled && !_aiSubCtrl.asrMode) {
          unawaited(_aiSubCtrl.enable(
            localPath: trimmed,
            sourceLabel: fileName,
            currentPositionSecs: _positionSecs,
          ));
        }
        _flashGestureHud('seek_feedback', text: '已加载字幕：$fileName');
      }
    } catch (_) {
      _flashGestureHud('seek_feedback', text: '字幕加载失败');
    }
  }

  Future<void> _pickAndLoadLocalSubtitle() async {
    final picked = await NativePlaybackChannel.pickFiles(
      extensions: NativePlaybackChannel.subtitleExtensions.toList(),
      title: '选择外挂字幕文件 (.srt / .ass / .vtt)',
    );
    if (picked.isNotEmpty) {
      await _loadExternalSubtitleFile(picked.first);
      return;
    }
    if (!mounted) return;
    // Fallback manual path input when native dialog isn't available or cancelled on mobile
    if (!_isDesktop) {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('加载本地外挂字幕'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: '/path/to/subtitle.ass'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('加载')),
          ],
        ),
      );
      final p = ctrl.text.trim();
      ctrl.dispose();
      if (ok == true && p.isNotEmpty) {
        await _loadExternalSubtitleFile(p);
      }
    }
  }

  Future<void> _openContextMenu(Offset globalPos) async {
    if (_screenLocked) return;
    _hideControlsTimer?.cancel();
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPos.dx, globalPos.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      color: const Color(0xF0171820),
      elevation: 18,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0x2AFFFFFF), width: 0.8),
      ),
      items: [
        _ctxItem('play_pause', _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            _paused ? '继续播放' : '暂停播放', 'Space'),
        if (_isDesktop)
          _ctxItem('fullscreen',
              _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
              _isFullscreen ? '退出全屏' : '进入全屏', 'F'),
        if (_isDesktop)
          _ctxItem('aot', _alwaysOnTop ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              _alwaysOnTop ? '取消窗口置顶' : '窗口置顶', 'T'),
        const PopupMenuDivider(height: 8),
        _ctxItem('speed', Icons.speed_rounded,
            '播放倍速 (${_speed.toStringAsFixed(_speed == _speed.roundToDouble() ? 1 : 2)}×)', '[ / ]'),
        _ctxItem('aspect', Icons.aspect_ratio_rounded, '画面比例 / 旋转 / 缩放', 'R'),
        _ctxItem('audio', Icons.audiotrack_rounded, '音轨与音频输出', ''),
        _ctxItem('subtitle', Icons.subtitles_outlined, '字幕轨道与样式', ''),
        _ctxItem('load_sub', Icons.upload_file_rounded, '加载本地外挂字幕…', ''),
        _ctxItem('danmaku', Icons.comment_outlined, _danmakuEnabled ? '弹幕设置（已开）' : '弹幕设置（已关）', 'D'),
        if (_chapters.isNotEmpty)
          _ctxItem('chapters', Icons.format_list_bulleted_rounded, '章节列表 (${_chapters.length})', 'C'),
        const PopupMenuDivider(height: 8),
        _ctxItem('screenshot', Icons.camera_alt_outlined, '高清含字幕截图', 'S'),
        _ctxItem('stats', Icons.info_outline_rounded, _showStats ? '隐藏硬件信息 HUD' : '显示硬件信息 HUD', 'I'),
        _ctxItem('tools', Icons.tune_rounded, '美颜滤镜 / 定时关闭 / 色彩均衡器', ''),
        if (_isDesktop) _ctxItem('shortcuts', Icons.keyboard_rounded, '快捷键一览', 'H'),
      ],
    );
    _scheduleHideControls();
    if (!mounted || selected == null) return;
    switch (selected) {
      case 'play_pause':
        await _togglePause();
        break;
      case 'fullscreen':
        await _toggleFullscreen();
        break;
      case 'aot':
        await _toggleAlwaysOnTop();
        break;
      case 'speed':
        _openSpeedSheet();
        break;
      case 'aspect':
        _openAspectSheet();
        break;
      case 'audio':
        _openAudioSheet();
        break;
      case 'subtitle':
        _openSubtitleSheet();
        break;
      case 'load_sub':
        await _pickAndLoadLocalSubtitle();
        break;
      case 'danmaku':
        _openDanmakuSheet();
        break;
      case 'chapters':
        _openChaptersSheet();
        break;
      case 'screenshot':
        await _takeScreenshot();
        break;
      case 'stats':
        setState(() => _showStats = !_showStats);
        break;
      case 'tools':
        _openMoreToolsSheet();
        break;
      case 'shortcuts':
        _openShortcutsDialog();
        break;
    }
  }

  PopupMenuItem<String> _ctxItem(String value, IconData icon, String label, String shortcut) {
    return PopupMenuItem<String>(
      value: value,
      height: 36,
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFFD0D4DE)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
          if (shortcut.isNotEmpty) ...[
            const SizedBox(width: 12),
            Text(
              shortcut,
              style: const TextStyle(color: VedroTheme.fg3, fontSize: 11, fontFamily: 'monospace'),
            ),
          ],
        ],
      ),
    );
  }

  void _onNativeFullscreenChanged() {
    if (!mounted) return;
    final fs = NativePlaybackChannel.fullscreenNotifier.value;
    if (_isFullscreen != fs) {
      setState(() => _isFullscreen = fs);
    }
  }

  Future<void> _toggleFullscreen() async {
    if (!_isDesktop) return;
    final next = await NativePlaybackChannel.toggleFullscreen();
    if (!mounted) return;
    setState(() {
      _isFullscreen = next;
      if (next) _enteredFullscreenHere = true;
    });
    _flashGestureHud('seek_feedback', text: next ? '已进入全屏 (F / Esc)' : '已退出全屏');
  }

  Future<void> _toggleAlwaysOnTop() async {
    if (!_isDesktop) return;
    final next = await NativePlaybackChannel.setAlwaysOnTop(!_alwaysOnTop);
    if (!mounted) return;
    setState(() => _alwaysOnTop = next);
    _flashGestureHud('seek_feedback', text: next ? '窗口已置顶 (T)' : '已取消置顶');
  }

  void _toggleScreenLock() {
    final next = !_screenLocked;
    _lockIconTimer?.cancel();
    setState(() {
      _screenLocked = next;
      _controlsVisible = !next;
      _lockIconVisible = next;
    });
    if (next) {
      _lockIconTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _lockIconVisible = false);
      });
    } else {
      _scheduleHideControls();
    }
  }

  void _revealLockIconBriefly() {
    _lockIconTimer?.cancel();
    setState(() => _lockIconVisible = true);
    _lockIconTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _lockIconVisible = false);
    });
  }

  Future<void> _loadChapters() async {
    final raw = await _readMpvProperty('chapter-list');
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        final parsed = <({String title, double timeSecs})>[];
        for (var i = 0; i < list.length; i++) {
          final item = list[i];
          if (item is Map) {
            final t = (item['time'] as num?)?.toDouble() ?? 0.0;
            final title = (item['title']?.toString().trim() ?? '');
            parsed.add((title: title.isEmpty ? '章节 ${i + 1}' : title, timeSecs: t));
          }
        }
        if (mounted && parsed.isNotEmpty) {
          setState(() => _chapters = parsed);
        }
      }
    } catch (_) {}
  }

  void _setSleepTimer({int minutes = 0, bool afterEpisode = false}) {
    _sleepTimer?.cancel();
    final initialSecs = minutes * 60;
    _sleepRemainingSecs = initialSecs;
    _sleepRemainingNotifier.value = initialSecs;
    setState(() {
      _sleepAfterEpisode = afterEpisode;
    });
    if (minutes > 0) {
      _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (_sleepRemainingSecs <= 1) {
          t.cancel();
          _sleepRemainingSecs = 0;
          _sleepRemainingNotifier.value = 0;
          _player.pause();
          Navigator.of(context).pop();
        } else {
          _sleepRemainingSecs -= 1;
          _sleepRemainingNotifier.value = _sleepRemainingSecs;
        }
      });
      _flashGestureHud('seek_feedback', text: '定时关闭：$minutes 分钟后');
    } else if (afterEpisode) {
      _flashGestureHud('seek_feedback', text: '定时关闭：播完本集后');
    } else {
      _flashGestureHud('seek_feedback', text: '已关闭定时休眠');
    }
  }

  Future<void> _stepFrame(bool forward) async {
    if (!_paused) await _player.pause();
    await _seekBy(forward ? 0.042 : -0.042);
    _flashGestureHud('seek_feedback', text: forward ? '下一帧 (+1f)' : '上一帧 (-1f)');
  }

  void _schedulePersistPlayerPrefs() {
    _persistPrefsTimer?.cancel();
    _persistPrefsTimer = Timer(const Duration(milliseconds: 600), _persistRememberedPlayerPrefs);
  }

  void _persistRememberedPlayerPrefs({bool notify = true}) {
    final p = widget.appState.prefs;
    final nextBrightness = p.rememberBrightness ? _brightness.clamp(0.15, 1.0) : p.savedBrightness;
    final nextVolume = p.rememberVolume ? (_muted ? 0.0 : _volume).clamp(0.0, _maxVolume) : p.savedVolume;
    final nextSpeed = (p.rememberSpeed && !_isSpeedBoost) ? _speed.clamp(0.25, 4.0) : p.defaultSpeed;
    final nextAspect = p.rememberAspect ? _aspectMode : p.defaultAspect;
    if ((nextBrightness - p.savedBrightness).abs() < 0.005 &&
        (nextVolume - p.savedVolume).abs() < 0.5 &&
        (nextSpeed - p.defaultSpeed).abs() < 0.005 &&
        nextAspect == p.defaultAspect) {
      return;
    }
    final nextPrefs = p.copyWith(
      savedBrightness: nextBrightness,
      savedVolume: nextVolume,
      defaultSpeed: nextSpeed,
      defaultAspect: nextAspect,
    );
    if (notify) {
      unawaited(widget.appState.updatePrefs(nextPrefs));
    } else {
      // Safe teardown persistence: update field & persist without notifying listeners during dispose()
      widget.appState.prefs = nextPrefs;
      unawaited(
        widget.appState.core
            .invoke('set_kv', {'key': 'vedro_prefs', 'value': nextPrefs.toJson()})
            .catchError((_) => null),
      );
    }
  }

  String _fmtNetSpeed(int bps) {
    if (bps <= 0) return '0 KB/s';
    if (bps < 1024) return '$bps B/s';
    if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(bps < 10 * 1024 ? 1 : 0)} KB/s';
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    NativePlaybackChannel.audioInterruptCountNotifier.removeListener(_onAudioInterrupted);
    NativePlaybackChannel.pipModeNotifier.removeListener(_onPipModeChanged);
    unawaited(NativePlaybackChannel.setAudioPlaybackActive(false));
    for (final s in _subs) {
      s.cancel();
    }
    _hideControlsTimer?.cancel();
    _gestureHudTimer?.cancel();
    _statsTimer?.cancel();
    _speedTimer?.cancel();
    _persistPrefsTimer?.cancel();
    _progressTimer?.cancel();
    _ticketRefreshTimer?.cancel();
    _sleepTimer?.cancel();
    _lockIconTimer?.cancel();
    _upNextTimer?.cancel();
    _pauseWakeLockTimer?.cancel();
    _statusBarTimer?.cancel();
    _keySeekFlushTimer?.cancel();
    _focusNode.dispose();
    _playPauseFocusNode.dispose();
    _unlockFocusNode.dispose();
    _drawerCloseFocusNode.dispose();
    _positionNotifier.dispose();
    _bufferedNotifier.dispose();
    _activeSegmentNotifier.dispose();
    _networkSpeedBpsNotifier.dispose();
    _sleepRemainingNotifier.dispose();
    _statsNotifier.dispose();
    _gestureHudNotifier.dispose();
    _statusBarNotifier.dispose();
    _aiSubCtrl.dispose();
    unawaited(LocalAsrManager.instance.unloadEngine());
    _persistRememberedPlayerPrefs(notify: false);
    if (_activeLocalPath != null && _activeLocalPath!.isNotEmpty && _positionSecs > 3.0) {
      final localDone = _durationSecs > 0 && _positionSecs >= _durationSecs - 15.0;
      unawaited(widget.appState.saveLocalResumeSecs(_activeLocalPath!, localDone ? 0.0 : _positionSecs));
    }
    if (_usingNativeBrightness) {
      unawaited(NativePlaybackChannel.resetScreenBrightness());
    }
    if (_isDesktop) {
      NativePlaybackChannel.playerHudAutoHideNotifier.value = false;
      NativePlaybackChannel.fullscreenNotifier.removeListener(_onNativeFullscreenChanged);
      NativePlaybackChannel.droppedFilesNotifier.removeListener(_onFilesDropped);
    }
    if (_enteredFullscreenHere && _isFullscreen) {
      unawaited(NativePlaybackChannel.setFullscreen(false));
    }
    if (_alwaysOnTop) {
      unawaited(NativePlaybackChannel.setAlwaysOnTop(false));
    }
    if (_isMobile) {
      NativePlaybackChannel.setPreferredFrameRate(0.0);
      SystemChrome.setPreferredOrientations(const []);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    NativePlaybackChannel.setKeepScreenOn(false);
    final restoreSkin = widget.appState.prefs.activeSkinFor(
      dynamicSeedOverride: widget.appState.dynamicPageSeedColor,
    );
    NativePlaybackChannel.syncWindowChrome(
      isLight: restoreSkin.isLight,
      canvasArgb: restoreSkin.canvas.toARGB32(),
      fgArgb: restoreSkin.fg.toARGB32(),
    );
    _reportStoppedAndCleanup();
    _player.dispose();
    super.dispose();
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    if (_paused || _loading || _showEpisodeDrawer || _hoveringChrome || _upNextCountdown > 0 || _hasEndedReplay) {
      return;
    }
    final delayMs = _isTv ? 6000 : 3400;
    _hideControlsTimer = Timer(Duration(milliseconds: delayMs), () {
      if (mounted &&
          !_paused &&
          !_scrubbing &&
          !_showEpisodeDrawer &&
          !_hoveringChrome &&
          _upNextCountdown == 0 &&
          !_hasEndedReplay) {
        setState(() => _controlsVisible = false);
        if (_isTv && !_focusNode.hasPrimaryFocus) {
          _focusNode.requestFocus();
        }
      }
    });
  }

  void _revealControls({bool focusPlayButton = false}) {
    _positionNotifier.value = _positionSecs;
    _bufferedNotifier.value = _bufferedSecs;
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    if (focusPlayButton) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controlsVisible && !_showEpisodeDrawer && !_screenLocked) {
          _playPauseFocusNode.requestFocus();
        }
      });
    }
    _scheduleHideControls();
  }

  void _flashGestureHud(String mode, {String text = ''}) {
    if (_disposed) return;
    _gestureHudTimer?.cancel();
    _gestureHudNotifier.value = (
      mode: mode,
      text: text.isNotEmpty ? text : _gestureHudNotifier.value.text,
    );
    _gestureHudTimer = Timer(const Duration(milliseconds: 950), () {
      if (!_disposed && mounted) {
        _gestureHudNotifier.value = (mode: null, text: '');
      }
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
    _cancelUpNextCountdown();
    await _reportStoppedAndCleanup();
    _completedTriggered = false;
    _hasEndedReplay = false;
    _customIntroSkipped = false;
    _customOutroSkipped = false;
    _quickSkipIntroDismissed = false;
    _autoRetryCount = 0;
    _hwFallbackAttempted = false;
    _isInitialEpisode = false;
    _aiSubCtrl.resetForNewMedia(mediaTitle: ep.displayName);
    _activeSubLocalPath = null;
    _activeSubUrl = null;
    _activeSubFormat = null;
    _activeSubLabel = null;
    unawaited(_applyMpvProperty('sub-visibility', 'yes'));
    final localNext = _localPathById[ep.id];
    setState(() {
      _currentItem = ep;
      if (localNext != null) _activeLocalPath = localNext;
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
    if (localNext == null) {
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
    }
    await _startPlayback(null);
    if (_danmakuEnabled) {
      unawaited(_loadDanmaku());
    }
  }

  Future<void> _applyInitialPreferencesToMpv({
    Map<String, String> prepOptions = const {},
  }) async {
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
    props['target-colorspace-hint'] = 'yes';
    props['volume-max'] = '${_maxVolume.round()}';
    // Mobile thermal protection: avoid per-frame 4K compute-shader peak detection
    // and heavy display-resample / dithering on battery-powered phone SoCs.
    final effComputePeak = !_isMobile && p.hdrComputePeak;
    props['hdr-compute-peak'] = effComputePeak ? 'yes' : 'no';
    props['tone-mapping'] = _toneMapping;
    props['video-sync'] = _isMobile ? 'audio' : p.videoSync;
    final effBufMb = _isMobile ? p.bufferSizeMb.clamp(32, 96) : p.bufferSizeMb;
    props['demuxer-max-bytes'] = '${effBufMb}MiB';
    if (_isMobile && !_anime4kActive) {
      props['scale'] = 'bilinear';
      props['cscale'] = 'bilinear';
      props['dscale'] = 'bilinear';
      props['dither-depth'] = 'no';
    }

    // Apply preferred audio & subtitle language priorities (honoring per-version override on initial ep!)
    final effAudioPref =
        (_isInitialEpisode ? widget.preferredAudioLangOverride : null) ?? p.preferredAudioLang;
    final effSubPref =
        (_isInitialEpisode ? widget.preferredSubLangOverride : null) ?? p.preferredSubLang;
    final alang = switch (effAudioPref) {
      'zh' => 'cmn,zh,chi,zho,chs,cn,mandarin',
      'yue' => 'yue,cantonese,zh-hk,zho,chi',
      'ja' => 'ja,jpn,jp',
      'en' => 'en,eng',
      'ko' => 'ko,kor',
      _ => '',
    };
    if (alang.isNotEmpty) {
      props['alang'] = alang;
    }
    if ((_isInitialEpisode && widget.initialSubtitleStreamIndex == -1) || effSubPref == 'off') {
      props['sid'] = 'no';
    } else {
      final slang = switch (effSubPref) {
        'zh' => 'chs,sc,zh-cn,zh-hans,zh,chi,zho,cn',
        'zh-Hant' => 'cht,tc,zh-tw,zh-hk,zh-hant,zho,chi,zh',
        'en' => 'en,eng',
        'ja' => 'ja,jpn,jp',
        _ => '',
      };
      if (slang.isNotEmpty) {
        props['slang'] = slang;
      }
    }

    if (p.audioDelayMs != 0) {
      props['audio-delay'] = (p.audioDelayMs / 1000.0).toStringAsFixed(3);
    }
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
    await _applyAspectMode(_aspectMode);
    if (_anime4kActive) {
      await _applyAnime4k(true);
    }
    if (_beautyPreset != 'off') {
      await _applyBeautyFilter(_beautyPreset, _beautyStrength, persist: false, showHud: false);
    }
    await _applyCustomMpvConf(p.customMpvConf);
    await _applyVolumeToEngine(_muted ? 0.0 : _volume);
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

  Future<void> _applyBeautyFilter(
    String presetId,
    double strength, {
    bool persist = true,
    bool showHud = true,
  }) async {
    final preset = BeautyFilterPreset.byId(presetId);
    final clamped = strength.clamp(0.15, 1.0);
    if (mounted) {
      setState(() {
        _beautyPreset = preset.id;
        _beautyStrength = clamped;
      });
    } else {
      _beautyPreset = preset.id;
      _beautyStrength = clamped;
    }

    if (preset.id == 'off') {
      await _applyMpvProperty('glsl-shaders', '');
    } else {
      // Desktop GPUs run our verified 5-tap YCbCr skin-smoothing GLSL pass in addition
      // to Flutter's instant ColorFilter.matrix; mobile stays strictly on Flutter's
      // zero-heat GPU ColorFilter.matrix to avoid driver quirks or thermal throttling.
      if (_isDesktop) {
        try {
          final shaderPath = await BeautyFilterEngine.prepareShaderFile(preset.id, clamped);
          if (shaderPath != null && shaderPath.isNotEmpty) {
            await _applyMpvProperty('glsl-shaders', shaderPath.replaceAll('\\', '/'));
          }
        } catch (_) {
          await _applyMpvProperty('glsl-shaders', '');
        }
      } else {
        await _applyMpvProperty('glsl-shaders', '');
      }
    }

    if (persist) {
      unawaited(widget.appState.updatePrefs(
        widget.appState.prefs.copyWith(
          beautyFilterPreset: preset.id,
          beautyFilterStrength: clamped,
        ),
      ));
    }
    if (showHud && mounted) {
      _flashGestureHud(
        'seek_feedback',
        text: preset.id == 'off'
            ? '已关闭美颜滤镜'
            : '美颜滤镜：${preset.label} (${(clamped * 100).round()}%)',
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
    await _aiSubCtrl.enable(
      subtitleUrl: src.url,
      localPath: src.localPath,
      format: src.format,
      sourceLabel: src.label,
      currentPositionSecs: _positionSecs,
      displayMode: widget.appState.prefs.aiSubtitleMode,
      targetLang: targetLangOverride ?? _aiSubCtrl.targetLang,
    );
    if (mounted) {
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
    await _aiSubCtrl.enableAsr(
      sourceUrl: _prepared?.proxyUrl,
      localPath: _activeLocalPath,
      currentPositionSecs: _positionSecs,
      durationSecs: _durationSecs,
      sourceLang: widget.appState.prefs.asrSourceLang,
      targetLang: _aiSubCtrl.targetLang,
      displayMode: widget.appState.prefs.aiSubtitleMode,
    );
    if (mounted) {
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
    const blocked = {
      'vo',
      'ao',
      'gpu-context',
      'gpu-api',
      'script',
      'scripts',
      'script-opts',
      'load-scripts',
      'input-ipc-server',
      'log-file',
      'ytdl-path',
      'dump-stream',
      'stream-dump',
      'o',
      'include',
      'config-dir',
    };
    for (final rawLine in raw.split('\n')) {
      final line = rawLine.split('#').first.trim();
      if (line.isEmpty) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final k = line.substring(0, eq).trim().toLowerCase();
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
        altTitle: queryOverride == null ? _currentItem.originalTitle : null,
        season: _currentItem.parentIndexNumber,
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
      setState(() {
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
        setState(() => _danmakuError = '读取本地弹幕失败：$e');
      }
    }
  }

  Future<void> _startPlayback(String? sourceId, {double? resumeFromSecs}) async {
    if (!mounted || _disposed) return;
    setState(() {
      _loading = true;
      _error = null;
      _hasEndedReplay = false;
    });
    final applyInitialOverrides = _isInitialEpisode;
    _isInitialEpisode = false;
    try {
      final p = widget.appState.prefs;

      // Support playing local offline downloaded file or direct http(s) stream URL directly!
      if (_activeLocalPath != null && _activeLocalPath!.isNotEmpty) {
        final localPath = _activeLocalPath!;
        final isNetworkDirect = NativePlaybackChannel.isAllowedHttpUrl(localPath);
        await _applyInitialPreferencesToMpv();
        double startSecs = resumeFromSecs ?? 0.0;
        if (resumeFromSecs == null && p.rememberPosition && !isNetworkDirect) {
          startSecs = await widget.appState.getLocalResumeSecs(localPath);
        }
        if (!mounted || _disposed) return;
        await _player.open(
          Media(
            localPath,
            start: startSecs > 3.0 ? Duration(milliseconds: (startSecs * 1000).round()) : null,
          ),
          play: true,
        );
        if (applyInitialOverrides &&
            widget.initialExternalSubtitlePath != null &&
            widget.initialExternalSubtitlePath!.trim().isNotEmpty) {
          await _loadExternalSubtitleFile(widget.initialExternalSubtitlePath!);
        } else if (!isNetworkDirect &&
            p.autoLoadExternalSubs &&
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
        if (!mounted || _disposed) return;
        setState(() {
          _loading = false;
          _paused = false;
        });
        _scheduleHideControls();
        _startTimers();
        return;
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
      if (!mounted || _disposed) return;

      final prep = PreparedPlaybackModel.fromJson(prepRaw);
      await _applyInitialPreferencesToMpv(prepOptions: prep.mpvOptions);
      if (!mounted || _disposed) return;

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
      if (!mounted || _disposed) return;

      if (applyInitialOverrides &&
          widget.initialExternalSubtitlePath != null &&
          widget.initialExternalSubtitlePath!.trim().isNotEmpty) {
        await _loadExternalSubtitleFile(widget.initialExternalSubtitlePath!);
      } else if ((applyInitialOverrides && widget.initialSubtitleStreamIndex == -1) ||
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
        final prefLang = p.preferredSubLang.toLowerCase();
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

      if (!p.incognitoMode) {
        unawaited(
          widget.appState.core
              .invoke('report_playback_start', {
                'position_ticks': startDur != null
                    ? startDur.inMicroseconds * 10
                    : _currentItem.playbackPositionTicks,
                if (_currentItem.runTimeTicks != null) 'run_time_ticks': _currentItem.runTimeTicks,
                'is_paused': false,
              })
              .catchError((_) => null),
        );
      }

      if (!mounted || _disposed) return;
      _autoRetryCount = 0;
      setState(() {
        _prepared = prep;
        _loading = false;
        _paused = false;
      });
      _scheduleHideControls();
      _startTimers();
    } catch (e) {
      if (mounted && !_disposed) {
        setState(() {
          _error = e.toString().replaceFirst('VedroCoreException: ', '');
          _loading = false;
          _controlsVisible = true;
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
      if (_activeLocalPath != null && _activeLocalPath!.isNotEmpty) {
        if (!_paused && _positionSecs > 3.0) {
          await widget.appState.saveLocalResumeSecs(_activeLocalPath!, _positionSecs);
        }
        return;
      }
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
        if (!mounted || _disposed) return;
        try {
          await widget.appState.core.invoke('refresh_stream_ticket');
        } catch (_) {}
      });
    }

    _speedTimer?.cancel();
    if (_activeLocalPath == null) {
      _speedTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (!mounted || _disposed) return;
        final showSpeed = widget.appState.prefs.showNetworkSpeed;
        if (!showSpeed && !_buffering && !_loading) return;
        try {
          // Lock-free atomic read from Rust StreamProxy (ZERO Isolate / JSON overhead!)
          int bps = widget.appState.core.proxySpeedBps;
          if (bps <= 0 && (_buffering || _loading)) {
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

  Future<void> _reportStoppedAndCleanup() async {
    if (_activeLocalPath != null) return;
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
      unawaited(_applyVolumeToEngine(restored));
    } else {
      _preMuteVolume = _volume;
      setState(() {
        _muted = true;
        _volume = 0;
      });
      unawaited(_applyVolumeToEngine(0));
    }
    _schedulePersistPlayerPrefs();
    _flashGestureHud('volume');
  }

  void _setVolume(double v) {
    final clamped = v.clamp(0.0, _maxVolume);
    setState(() {
      _volume = clamped;
      _muted = clamped <= 0.1;
    });
    unawaited(_applyVolumeToEngine(clamped));
    _schedulePersistPlayerPrefs();
  }

  void _setBrightness(double v) {
    final clamped = v.clamp(0.15, 1.0);
    if (_usingNativeBrightness) {
      _brightness = clamped;
      unawaited(NativePlaybackChannel.setScreenBrightness(clamped));
    } else {
      setState(() => _brightness = clamped);
    }
    _schedulePersistPlayerPrefs();
  }

  void _accumulateKeySeek(double delta) {
    _accumulatedKeySeekDelta += delta;
    final sign = _accumulatedKeySeekDelta >= 0 ? '+' : '';
    final previewTarget = (_positionSecs + _accumulatedKeySeekDelta)
        .clamp(0.0, _durationSecs > 0 ? _durationSecs : 86400.0);
    _flashGestureHud(
      'seek_feedback',
      text: '$sign${_accumulatedKeySeekDelta.round()}s (${_fmtTime(previewTarget)})',
    );
    _keySeekFlushTimer?.cancel();
    _keySeekFlushTimer = Timer(const Duration(milliseconds: 220), () {
      if (!mounted || _disposed) return;
      final d = _accumulatedKeySeekDelta;
      _accumulatedKeySeekDelta = 0.0;
      if (d.abs() > 0.01) {
        unawaited(_seekBy(d));
      }
    });
  }

  Future<void> _seekTo(double secs) async {
    final target = secs.clamp(0.0, _durationSecs > 0 ? _durationSecs : 86400.0);
    await _player.seek(Duration(milliseconds: (target * 1000).round()));
    _positionSecs = target;
    _positionNotifier.value = target;
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
    if (!_isSpeedBoost) _schedulePersistPlayerPrefs();
  }

  Future<void> _applyAspectMode(String mode) async {
    setState(() => _aspectMode = mode);
    _schedulePersistPlayerPrefs();
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
    if (_screenLocked) return;
    final step = widget.appState.prefs.seekStepSecs.toDouble();
    final ratio = width > 0 ? _lastTapDownPos.dx / width : 0.5;
    if (_isDesktop) {
      // Classic IINA / Infuse / PotPlayer desktop behavior: double-click toggles native Fullscreen!
      _toggleFullscreen();
      return;
    }
    if (ratio < 0.35) {
      _seekBy(-step, showHud: true);
    } else if (ratio > 0.65) {
      _seekBy(step, showHud: true);
    } else {
      _togglePause();
    }
  }

  void _handleBackNavigation() {
    if (_screenLocked) {
      _revealLockIconBriefly();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _screenLocked) _unlockFocusNode.requestFocus();
      });
      _flashGestureHud('seek_feedback', text: '屏幕已锁定，请先解锁');
      return;
    }
    if (_showEpisodeDrawer) {
      setState(() => _showEpisodeDrawer = false);
      _scheduleHideControls();
      return;
    }
    if (_upNextCountdown > 0) {
      setState(_cancelUpNextCountdown);
      return;
    }
    if (_isTv && _controlsVisible && _error == null && !_hasEndedReplay) {
      _hideControlsTimer?.cancel();
      setState(() => _controlsVisible = false);
      _focusNode.requestFocus();
      return;
    }
    if (_isDesktop && _isFullscreen) {
      _toggleFullscreen();
      return;
    }
    unawaited(_requestExit());
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent ev) {
    if (ev is! KeyDownEvent && ev is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = ev.logicalKey;
    final isRepeat = ev is KeyRepeatEvent;
    final step = widget.appState.prefs.seekStepSecs.toDouble();

    // 1. Hardware media keys work in every state (except when screen-locked)
    if (!_screenLocked) {
      if (key == LogicalKeyboardKey.mediaPlayPause) {
        if (!isRepeat) unawaited(_togglePause());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaPlay) {
        if (!isRepeat) {
          unawaited(_player.play());
          _revealControls();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaPause) {
        if (!isRepeat) {
          unawaited(_player.pause());
          _revealControls();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaStop) {
        if (!isRepeat) unawaited(_requestExit());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaFastForward) {
        _accumulateKeySeek(step);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaRewind) {
        _accumulateKeySeek(-step);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaTrackNext && _nextEpisode != null) {
        if (!isRepeat) unawaited(_switchEpisode(_nextEpisode!));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaTrackPrevious) {
        final idx = _currentEpisodeIndex;
        if (!isRepeat && idx > 0) {
          unawaited(_switchEpisode(_episodes[idx - 1]));
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.audioVolumeMute) {
        if (!isRepeat) _toggleMute();
        return KeyEventResult.handled;
      }
    }

    // 2. Back / Escape always routed through state-aware back handler
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (!isRepeat) _handleBackNavigation();
      return KeyEventResult.handled;
    }

    // 3. Screen-locked mode: reveal unlock pill & direct focus to it
    if (_screenLocked) {
      if (!isRepeat) {
        _revealLockIconBriefly();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _screenLocked) _unlockFocusNode.requestFocus();
        });
      }
      return key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter
          ? KeyEventResult.ignored
          : KeyEventResult.handled;
    }

    // 4. Episode Drawer open: let Flutter focus traversal drive D-Pad inside the drawer!
    if (_showEpisodeDrawer) {
      return KeyEventResult.ignored;
    }

    // 5. TV / D-Pad Remote Mode when OSD controls are visible:
    // Let Up/Down/Left/Right/OK navigate OSD buttons & Scrub Bar, while keeping OSD alive!
    final isSelect = key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA ||
        (_isTv && (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter));
    final isArrow = key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;

    if (_controlsVisible && _isTv && (isArrow || isSelect)) {
      _scheduleHideControls();
      if (_focusNode.hasPrimaryFocus) {
        // Focus hasn't entered OSD buttons yet -> move focus straight to Play/Pause
        _playPauseFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // 6. OSD hidden (or Desktop shortcuts): direct cinema transport controls
    if (isSelect) {
      if (!isRepeat) {
        if (_controlsVisible && !_focusNode.hasPrimaryFocus) {
          return KeyEventResult.ignored;
        }
        unawaited(_togglePause());
        _revealControls(focusPlayButton: _isTv);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      if (!isRepeat) unawaited(_togglePause());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _accumulateKeySeek(step);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _accumulateKeySeek(-step);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (_isTv) {
        if (!isRepeat) _revealControls(focusPlayButton: true);
      } else {
        _setVolume(_volume + 5);
        _flashGestureHud('volume');
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_isTv) {
        if (!isRepeat) _revealControls(focusPlayButton: true);
      } else {
        _setVolume(_volume - 5);
        _flashGestureHud('volume');
      }
      return KeyEventResult.handled;
    }

    if (isRepeat) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.keyF ||
        key == LogicalKeyboardKey.f11 ||
        (!_isTv && key == LogicalKeyboardKey.enter && _focusNode.hasPrimaryFocus)) {
      unawaited(_toggleFullscreen());
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyT) {
      unawaited(_toggleAlwaysOnTop());
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyL) {
      _toggleScreenLock();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyC && _chapters.isNotEmpty) {
      _openChaptersSheet();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyH) {
      _openShortcutsDialog();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.period) {
      unawaited(_stepFrame(true));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.comma) {
      unawaited(_stepFrame(false));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyI) {
      setState(() => _showStats = !_showStats);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyS) {
      unawaited(_takeScreenshot());
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyD) {
      final next = !_danmakuEnabled;
      setState(() => _danmakuEnabled = next);
      if (next && _danmakuComments.isEmpty) unawaited(_loadDanmaku());
      _flashGestureHud('seek_feedback', text: next ? '弹幕已开启' : '弹幕已关闭');
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyR) {
      unawaited(_rotateVideo());
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyN && _nextEpisode != null) {
      unawaited(_switchEpisode(_nextEpisode!));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.bracketRight) {
      unawaited(_setSpeed(_speed + 0.25));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.bracketLeft) {
      unawaited(_setSpeed(_speed - 0.25));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  IconData _seekBackIcon(int step) => switch (step) {
        5 => Icons.replay_5_rounded,
        30 => Icons.replay_30_rounded,
        _ => Icons.replay_10_rounded,
      };

  IconData _seekFwdIcon(int step) => switch (step) {
        5 => Icons.forward_5_rounded,
        30 => Icons.forward_30_rounded,
        _ => Icons.forward_10_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 760;
    final isMac = !kIsWeb && Platform.isMacOS;
    final isWin = !kIsWeb && Platform.isWindows;
    final topPad = MediaQuery.paddingOf(context).top;
    final step = widget.appState.prefs.seekStepSecs;
    final showSpecs = widget.appState.prefs.showSpecBadges;
    final specs = showSpecs
        ? <String>[
            if (_prepared?.dolbyVisionLabel != null) _prepared!.dolbyVisionLabel!,
            if (_prepared?.spatialAudioLabel != null) _prepared!.spatialAudioLabel!,
          ]
        : const <String>[];

    final hideCursor = !_controlsVisible && !_showEpisodeDrawer && !_paused && !_loading;
    final shouldAutoHideWinCaption = !_controlsVisible && !_showEpisodeDrawer;
    if (NativePlaybackChannel.playerHudAutoHideNotifier.value != shouldAutoHideWinCaption) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          NativePlaybackChannel.playerHudAutoHideNotifier.value = shouldAutoHideWinCaption;
        }
      });
    }
    final tvPadX = _isTv ? 32.0 : 0.0;
    final tvPadY = _isTv ? 18.0 : 0.0;
    final osdInteractive = _controlsVisible && !_showEpisodeDrawer && !_screenLocked && !_inPipMode;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent && !_showEpisodeDrawer && !_screenLocked) {
                final delta = event.scrollDelta.dy > 0 ? -4.0 : 4.0;
                _setVolume(_volume + delta);
                _flashGestureHud('volume');
              }
            },
            child: MouseRegion(
              cursor: hideCursor ? SystemMouseCursors.none : SystemMouseCursors.basic,
              onHover: (_) {
                final nowMs = DateTime.now().millisecondsSinceEpoch;
                if (nowMs - _lastHoverRevealMs < 250) return;
                _lastHoverRevealMs = nowMs;
                if (_screenLocked) {
                  _revealLockIconBriefly();
                } else if (!_inPipMode) {
                  _revealControls();
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: (d) => _openContextMenu(d.globalPosition),
                onTapDown: (d) => _lastTapDownPos = d.localPosition,
                onTap: () {
                  if (_inPipMode) return;
                  if (_screenLocked) {
                    _revealLockIconBriefly();
                    return;
                  }
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
                  if (_screenLocked || _inPipMode) return;
                  HapticFeedback.mediumImpact();
                  _preBoostSpeed = _speed;
                  setState(() => _isSpeedBoost = true);
                  _setSpeed(widget.appState.prefs.longPressSpeed);
                },
                onLongPressEnd: (_) {
                  if (!_isSpeedBoost) return;
                  setState(() => _isSpeedBoost = false);
                  _setSpeed(_preBoostSpeed);
                },
                onLongPressCancel: () {
                  if (!_isSpeedBoost) return;
                  setState(() => _isSpeedBoost = false);
                  _setSpeed(_preBoostSpeed);
                },
                onScaleStart: (d) {
                  if (_showEpisodeDrawer || _screenLocked || _inPipMode) return;
                  // Edge-swipe dead-zone so Android/iOS system back & notification swipes don't conflict
                  if (_isMobile && d.pointerCount == 1) {
                    final fp = d.localFocalPoint;
                    if (fp.dx < 28 ||
                        fp.dx > size.width - 28 ||
                        fp.dy < 36 ||
                        fp.dy > size.height - 36) {
                      _scaleAxis = 'blocked';
                      return;
                    }
                  }
                  _scaleAxis = null;
                  _scaleAnchor = d.localFocalPoint;
                  _pinchBaseZoom = _videoZoom;
                  if (d.pointerCount >= 2 && widget.appState.prefs.pinchToZoom) {
                    _scaleAxis = 'pinch';
                    _hideControlsTimer?.cancel();
                  }
                },
                onScaleUpdate: (d) {
                  if (_showEpisodeDrawer || _screenLocked || _inPipMode || _scaleAxis == 'blocked') {
                    return;
                  }
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
                      _setBrightness(_brightness + vDelta);
                      _flashGestureHud('brightness');
                    } else {
                      _setVolume(_volume + vDelta * 100);
                      _flashGestureHud('volume');
                    }
                  }
                },
                onScaleEnd: (_) {
                  if (_screenLocked) {
                    _scaleAxis = null;
                    return;
                  }
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
                    RepaintBoundary(
                      child: Builder(
                        builder: (_) {
                          final videoWidget = Video(
                            controller: _videoController,
                            controls: NoVideoControls,
                            fill: Colors.black,
                          );
                          final beautyMatrix = BeautyFilterEngine.buildColorMatrix(
                            _beautyPreset,
                            _beautyStrength,
                          );
                          if (beautyMatrix == null) return videoWidget;
                          return ColorFiltered(
                            colorFilter: ColorFilter.matrix(beautyMatrix),
                            child: videoWidget,
                          );
                        },
                      ),
                    ),

                    // Software brightness veil only when OS native brightness is unavailable (Desktop)
                    if (!_usingNativeBrightness && _brightness < 0.99)
                      IgnorePointer(
                        child: Container(
                          color: Colors.black.withValues(alpha: (1.0 - _brightness).clamp(0.0, 0.85)),
                        ),
                      ),

                    // AI Bilingual / ASR Lookahead Subtitle Overlay (isolated RepaintBoundary + ValueNotifier)
                    RepaintBoundary(
                      child: AiBilingualSubtitleOverlay(
                        controller: _aiSubCtrl,
                        subScale: _subScale,
                        translationFontScale: _aiSubFontScale,
                        subPos: _subPos,
                        colorHex: widget.appState.prefs.subtitleColorHex,
                        outlineWidth: widget.appState.prefs.subtitleOutlineWidth,
                        bgOpacity: widget.appState.prefs.subtitleBgOpacity,
                      ),
                    ),

                    // GPU-cached Canvas Danmaku overlay driven solely by _positionNotifier
                    if (_danmakuEnabled && !_inPipMode)
                      RepaintBoundary(
                        child: ValueListenableBuilder<double>(
                          valueListenable: _positionNotifier,
                          builder: (_, posSecs, __) => DanmakuLayer(
                            comments: _danmakuComments,
                            positionSecs: posSecs,
                            opacity: _danmakuOpacity,
                            fontSize: _danmakuFontSize,
                            speedSecs: _danmakuSpeedSecs,
                            areaFraction: _danmakuArea,
                            hideTop: _danmakuHideTop,
                            hideBottom: _danmakuHideBottom,
                          ),
                        ),
                      ),

                    if ((_loading || _buffering) && !_inPipMode)
                      Center(
                        child: ValueListenableBuilder<int>(
                          valueListenable: _networkSpeedBpsNotifier,
                          builder: (_, bps, __) {
                            final showNet = _activeLocalPath == null &&
                                widget.appState.prefs.showNetworkSpeed;
                            final label = _loading ? '正在加载' : '缓冲中';
                            return GlassSurface(
                              borderRadius: 16,
                              enableBlur: false,
                              color: const Color(0xD8121318),
                              borderColor: const Color(0x30FFFFFF),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.0,
                                      color: VedroTheme.fg,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    showNet && bps > 0
                                        ? '$label · ${_fmtNetSpeed(bps)}'
                                        : '$label…',
                                    style: const TextStyle(
                                      color: VedroTheme.fg,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      fontFeatures: [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                    // Live network download speed pill (zero full-page rebuild via ValueNotifier)
                    if (widget.appState.prefs.showNetworkSpeed &&
                        _activeLocalPath == null &&
                        !_showEpisodeDrawer &&
                        !_screenLocked &&
                        !_inPipMode)
                      Positioned(
                        top: (_controlsVisible ? topPad + 60 : topPad + 14) + tvPadY,
                        right: ((isWin && !_isFullscreen && !_controlsVisible) ? 148 : 20) + tvPadX,
                        child: IgnorePointer(
                          child: ValueListenableBuilder<int>(
                            valueListenable: _networkSpeedBpsNotifier,
                            builder: (_, bps, __) {
                              if (bps <= 0 && !_buffering && !_loading && !_controlsVisible) {
                                return const SizedBox.shrink();
                              }
                              return Container(
                                key: const ValueKey('player-network-speed-pill'),
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0x8C0D0E12),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.14),
                                    width: 0.7,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.arrow_downward_rounded,
                                      size: 11.5,
                                      color: bps > 0
                                          ? const Color(0xFF34D399)
                                          : Colors.white.withValues(alpha: 0.65),
                                    ),
                                    const SizedBox(width: 3.5),
                                    Text(
                                      _fmtNetSpeed(bps),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        fontFeatures: [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                    // Actionable Error Recovery Banner (Retry / Software Decode Retry / Dismiss)
                    if (_error != null && !_inPipMode)
                      Positioned(
                        bottom: 140 + tvPadY,
                        left: 24 + tvPadX,
                        right: 24 + tvPadX,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 540),
                            child: GlassSurface(
                              borderRadius: 14,
                              enableBlur: false,
                              color: const Color(0xEE221216),
                              borderColor: const Color(0x66FF6B6F),
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.error_outline_rounded,
                                          size: 18, color: VedroTheme.danger),
                                      const SizedBox(width: 8),
                                      const Expanded(
                                        child: Text(
                                          '播放遇到问题',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _error!,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFFCA5A5),
                                      fontSize: 12.5,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _DeckPillButton(
                                        label: '重试播放',
                                        active: true,
                                        onTap: () {
                                          _autoRetryCount = 0;
                                          unawaited(_startPlayback(
                                            _prepared?.mediaSourceId,
                                            resumeFromSecs: _positionSecs,
                                          ));
                                        },
                                      ),
                                      if (_hwDecodeEnabled)
                                        _DeckPillButton(
                                          label: '切换软解重试',
                                          onTap: () {
                                            setState(() => _hwDecodeEnabled = false);
                                            _autoRetryCount = 0;
                                            unawaited(_startPlayback(
                                              _prepared?.mediaSourceId,
                                              resumeFromSecs: _positionSecs,
                                            ));
                                          },
                                        ),
                                      _DeckPillButton(
                                        label: '关闭提示',
                                        onTap: () => setState(() => _error = null),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Up-Next 6-second Auto-Play Countdown Card
                    if (_upNextCountdown > 0 && _nextEpisode != null && !_inPipMode)
                      Positioned(
                        right: 28 + tvPadX,
                        bottom: (_controlsVisible ? 148 : 38) + tvPadY,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 340),
                          child: GlassSurface(
                            borderRadius: 16,
                            enableBlur: false,
                            color: const Color(0xE814161F),
                            borderColor: const Color(0x40FFFFFF),
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$_upNextCountdown 秒后自动播放下一集',
                                  style: const TextStyle(
                                    color: Color(0xFFB3B9C9),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_nextEpisode!.episodeCode ?? ''} ${_nextEpisode!.displayName}'.trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _DeckPillButton(
                                      label: '立即播放',
                                      active: true,
                                      onTap: () {
                                        final next = _nextEpisode;
                                        setState(_cancelUpNextCountdown);
                                        if (next != null) unawaited(_switchEpisode(next));
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    _DeckPillButton(
                                      label: '取消',
                                      onTap: () => setState(_cancelUpNextCountdown),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // End-of-Video Replay Overlay
                    if (_hasEndedReplay && _upNextCountdown == 0 && _error == null && !_inPipMode)
                      Center(
                        child: GlassSurface(
                          borderRadius: 18,
                          enableBlur: false,
                          color: const Color(0xE012141C),
                          borderColor: const Color(0x36FFFFFF),
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                '已播放完毕',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _DeckPillButton(
                                    label: '重新播放',
                                    active: true,
                                    onTap: () async {
                                      setState(() => _hasEndedReplay = false);
                                      await _seekTo(0);
                                      await _player.play();
                                    },
                                  ),
                                  if (_nextEpisode != null) ...[
                                    const SizedBox(width: 8),
                                    _DeckPillButton(
                                      label: '下一集',
                                      onTap: () => _switchEpisode(_nextEpisode!),
                                    ),
                                  ],
                                  const SizedBox(width: 8),
                                  _DeckPillButton(
                                    label: '退出',
                                    onTap: _requestExit,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Skip Intro / Outro floating button (also offers quick +85s pill for TV episodes without IntroSkipper)
                    if (!_showEpisodeDrawer && !_screenLocked && !_inPipMode && _upNextCountdown == 0)
                      ValueListenableBuilder<MediaSegmentModel?>(
                        valueListenable: _activeSegmentNotifier,
                        builder: (_, seg, __) {
                          if (seg != null) {
                            return Positioned(
                              right: 28 + tvPadX,
                              bottom: (_controlsVisible ? 142 : 34) + tvPadY,
                              child: PressableScale(
                                onTap: () => _seekTo(seg.endSecs),
                                hoverScale: 1.04,
                                pressScale: 0.94,
                                borderRadius: BorderRadius.circular(12),
                                child: GlassSurface(
                                  borderRadius: 12,
                                  enableBlur: false,
                                  color: const Color(0xDC181920),
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
                            );
                          }
                          final showQuickSkip = _controlsVisible &&
                              !_quickSkipIntroDismissed &&
                              _segments.isEmpty &&
                              _currentItem.type == 'Episode' &&
                              _durationSecs > 600 &&
                              _positionSecs >= 2.0 &&
                              _positionSecs < 240.0;
                          if (!showQuickSkip) return const SizedBox.shrink();
                          return Positioned(
                            right: 28 + tvPadX,
                            bottom: 142 + tvPadY,
                            child: PressableScale(
                              onTap: () {
                                setState(() => _quickSkipIntroDismissed = true);
                                unawaited(_seekBy(85, showHud: true));
                              },
                              hoverScale: 1.04,
                              pressScale: 0.94,
                              borderRadius: BorderRadius.circular(12),
                              child: const GlassSurface(
                                borderRadius: 12,
                                enableBlur: false,
                                color: Color(0xD6181920),
                                borderColor: Color(0x3CFFFFFF),
                                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '跳过片头 +85s',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(width: 5),
                                    Icon(Icons.fast_forward_rounded, size: 16, color: Colors.white),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                    if (_isSpeedBoost && !_inPipMode)
                      Positioned(
                        top: topPad + 48 + tvPadY,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: GlassSurface(
                            borderRadius: 20,
                            enableBlur: false,
                            color: const Color(0xD814161D),
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

                    if (_scrubbing && !_inPipMode)
                      Center(
                        child: GlassSurface(
                          borderRadius: 16,
                          enableBlur: false,
                          color: const Color(0xDC12141C),
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

                    // Isolated Gesture HUD (zero full-screen setState!)
                    if (!_scrubbing && !_inPipMode)
                      ValueListenableBuilder<({String? mode, String text})>(
                        valueListenable: _gestureHudNotifier,
                        builder: (_, hud, __) {
                          if (hud.mode == null) return const SizedBox.shrink();
                          return Center(
                            child: GlassSurface(
                              borderRadius: 16,
                              enableBlur: false,
                              color: const Color(0xDC12141C),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              child: _buildGestureHudContent(hud.mode!, hud.text),
                            ),
                          );
                        },
                      ),

                    if (_showStats && !_inPipMode)
                      Positioned(
                        top: topPad + 72 + tvPadY,
                        left: 24 + tvPadX,
                        child: ValueListenableBuilder<Map<String, dynamic>>(
                          valueListenable: _statsNotifier,
                          builder: (_, stats, __) => NerdStatsHud(stats: stats),
                        ),
                      ),

                    // Screen-lock minimal unlock button (focusable via D-Pad!)
                    if (_screenLocked && _lockIconVisible && !_inPipMode)
                      Positioned(
                        left: 24 + tvPadX,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: PressableScale(
                            focusNode: _unlockFocusNode,
                            onTap: _toggleScreenLock,
                            borderRadius: BorderRadius.circular(22),
                            child: const GlassSurface(
                              borderRadius: 22,
                              enableBlur: false,
                              color: Color(0xDC14151B),
                              borderColor: Color(0x38FFFFFF),
                              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock_open_rounded, size: 18, color: Colors.white),
                                  SizedBox(width: 6),
                                  Text('解锁屏幕',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Auto-hiding IINA / Apple TV+ chrome (ExcludeFocus when hidden so D-Pad never lands on invisible buttons!)
                    ExcludeFocus(
                      excluding: !osdInteractive,
                      child: IgnorePointer(
                        ignoring: !osdInteractive,
                        child: AnimatedOpacity(
                          opacity: osdInteractive ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 220),
                          curve: VedroTheme.easeOut,
                          child: Stack(
                            children: [
                              // Top Bar
                              Positioned(
                                top: tvPadY,
                                left: tvPadX,
                                right: tvPadX,
                                child: AnimatedSlide(
                                  offset: osdInteractive ? Offset.zero : const Offset(0, -0.22),
                                  duration: const Duration(milliseconds: 250),
                                  curve: VedroTheme.easeOut,
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
                                        (isMac && !_isFullscreen) ? 82 : 20,
                                        topPad + 12,
                                        (!kIsWeb && Platform.isWindows && !_isFullscreen) ? 148 : 20,
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
                                          // Mobile fullscreen live clock & battery %
                                          if (_isMobile)
                                            ValueListenableBuilder<
                                                ({String clock, int batteryPct, bool charging})>(
                                              valueListenable: _statusBarNotifier,
                                              builder: (_, info, __) {
                                                if (info.clock.isEmpty) {
                                                  return const SizedBox.shrink();
                                                }
                                                return Padding(
                                                  padding: const EdgeInsets.only(right: 10),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        info.clock,
                                                        style: const TextStyle(
                                                          color: Color(0xCCFFFFFF),
                                                          fontSize: 11.5,
                                                          fontWeight: FontWeight.w500,
                                                          fontFeatures: [
                                                            FontFeature.tabularFigures()
                                                          ],
                                                        ),
                                                      ),
                                                      if (info.batteryPct >= 0) ...[
                                                        const SizedBox(width: 6),
                                                        Icon(
                                                          info.charging
                                                              ? Icons.battery_charging_full_rounded
                                                              : (info.batteryPct <= 20
                                                                  ? Icons.battery_alert_rounded
                                                                  : Icons.battery_std_rounded),
                                                          size: 13.5,
                                                          color: info.batteryPct <= 20 && !info.charging
                                                              ? const Color(0xFFF87171)
                                                              : const Color(0xCCFFFFFF),
                                                        ),
                                                        const SizedBox(width: 2),
                                                        Text(
                                                          '${info.batteryPct}%',
                                                          style: const TextStyle(
                                                            color: Color(0xCCFFFFFF),
                                                            fontSize: 11,
                                                            fontFeatures: [
                                                              FontFeature.tabularFigures()
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          // Isolated sleep timer pill
                                          ValueListenableBuilder<int>(
                                            valueListenable: _sleepRemainingNotifier,
                                            builder: (_, remSecs, __) {
                                              if (remSecs <= 0 && !_sleepAfterEpisode) {
                                                return const SizedBox.shrink();
                                              }
                                              return Padding(
                                                padding: const EdgeInsets.only(right: 6),
                                                child: _DeckPillButton(
                                                  label: _sleepAfterEpisode
                                                      ? '本集后休眠'
                                                      : '休眠 ${_fmtTime(remSecs.toDouble())}',
                                                  active: true,
                                                  onTap: _openMoreToolsSheet,
                                                ),
                                              );
                                            },
                                          ),
                                          Tooltip(
                                            message: _hwDecodeEnabled
                                                ? '当前硬件解码，点击切至软解'
                                                : '当前软件解码，点击切至硬解',
                                            child: _DeckPillButton(
                                              label: _hwDecodeEnabled ? 'HW' : 'SW',
                                              active: _hwDecodeEnabled,
                                              onTap: _toggleHwDecode,
                                            ),
                                          ),
                                          if (wide && _chapters.isNotEmpty) ...[
                                            const SizedBox(width: 6),
                                            _CircleHudButton(
                                              icon: Icons.format_list_bulleted_rounded,
                                              tooltip: '章节列表 (C)',
                                              onTap: _openChaptersSheet,
                                            ),
                                          ],
                                          if (wide) ...[
                                            const SizedBox(width: 6),
                                            _CircleHudButton(
                                              icon: Icons.camera_alt_outlined,
                                              tooltip: '截图 (S)',
                                              onTap: _takeScreenshot,
                                            ),
                                          ],
                                          if (_episodes.length > 1) ...[
                                            const SizedBox(width: 6),
                                            _CircleHudButton(
                                              icon: Icons.video_library_outlined,
                                              tooltip: '选集',
                                              onTap: () {
                                                setState(() => _showEpisodeDrawer = true);
                                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                                  if (mounted && _showEpisodeDrawer) {
                                                    _drawerCloseFocusNode.requestFocus();
                                                  }
                                                });
                                              },
                                            ),
                                          ],
                                          if (wide) ...[
                                            const SizedBox(width: 6),
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
                                          ],
                                          if (_isDesktop && wide) ...[
                                            const SizedBox(width: 6),
                                            _CircleHudButton(
                                              icon: _alwaysOnTop
                                                  ? Icons.push_pin_rounded
                                                  : Icons.push_pin_outlined,
                                              active: _alwaysOnTop,
                                              tooltip: _alwaysOnTop ? '取消置顶 (T)' : '窗口置顶 (T)',
                                              onTap: _toggleAlwaysOnTop,
                                            ),
                                          ],
                                          if (widget.appState.prefs.enablePip &&
                                              NativePlaybackChannel.supportsNativePip) ...[
                                            const SizedBox(width: 6),
                                            _CircleHudButton(
                                              icon: Icons.picture_in_picture_alt_rounded,
                                              tooltip: '画中画',
                                              onTap: () => NativePlaybackChannel.enterPictureInPicture(
                                                aspectW: _videoWidth,
                                                aspectH: _videoHeight,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(width: 6),
                                          _CircleHudButton(
                                            icon: Icons.lock_outline_rounded,
                                            tooltip: '锁屏防误触 (L)',
                                            onTap: _toggleScreenLock,
                                          ),
                                          const SizedBox(width: 6),
                                          _CircleHudButton(
                                            icon: Icons.more_horiz_rounded,
                                            tooltip: '更多工具（定时 / A-B循环 / 色彩 / 快捷键）',
                                            onTap: _openMoreToolsSheet,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // Bottom Cinema Control Deck (no live BackdropFilter over 4K video!)
                              Positioned(
                                left: (wide ? 28 : 12) + tvPadX,
                                right: (wide ? 28 : 12) + tvPadX,
                                bottom: MediaQuery.paddingOf(context).bottom + (wide ? 22 : 12) + tvPadY,
                                child: AnimatedSlide(
                                  offset: osdInteractive ? Offset.zero : const Offset(0, 0.22),
                                  duration: const Duration(milliseconds: 260),
                                  curve: VedroTheme.easeOut,
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
                                      child: Builder(
                                        builder: (context) {
                                          final activeSkin = widget.appState.prefs.activeSkin;
                                          final osd = activeSkin.osdStyle;
                                          final isFullGradient = osd == 'cinema_gradient';
                                          final isMinimalGlass = osd == 'minimal_glass';
                                          return ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth: isFullGradient
                                                  ? 1680
                                                  : (isMinimalGlass ? 820 : 940),
                                            ),
                                            child: GlassSurface(
                                              borderRadius: isFullGradient
                                                  ? 12
                                                  : (isMinimalGlass
                                                      ? 28
                                                      : activeSkin.cardRadius.clamp(12.0, 24.0)),
                                              enableBlur: false,
                                              color: isFullGradient
                                                  ? const Color(0xEB08090E)
                                                  : (isMinimalGlass
                                                      ? Color.lerp(
                                                          const Color(0xD80C101C),
                                                          activeSkin.accent,
                                                          0.10,
                                                        )!
                                                      : const Color(0xDF111319)),
                                              borderColor: isMinimalGlass
                                                  ? activeSkin.accent.withValues(alpha: 0.34)
                                                  : const Color(0x28FFFFFF),
                                              padding: EdgeInsets.fromLTRB(
                                                wide ? 18 : 14,
                                                12,
                                                wide ? 18 : 14,
                                                12,
                                              ),
                                              child: LayoutBuilder(
                                                builder: (context, deckConstraints) {
                                                  final singleRowDeck = deckConstraints.maxWidth >= 680;
                                                  final speedPill = _DeckPillButton(
                                                    key: const ValueKey('player-speed-pill'),
                                                    label: _fmtSpeed(_speed),
                                                    active: (_speed - 1.0).abs() > 0.01,
                                                    onTap: _openSpeedSheet,
                                                  );

                                                  final transportCluster = Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      _DeckIconButton(
                                                        icon: _seekBackIcon(step),
                                                        tooltip: '后退 ${step}s',
                                                        onTap: () =>
                                                            _seekBy(-step.toDouble(), showHud: true),
                                                      ),
                                                      SizedBox(width: singleRowDeck ? 8 : 10),
                                                      PressableScale(
                                                        focusNode: _playPauseFocusNode,
                                                        onTap: _togglePause,
                                                        hoverScale: 1.07,
                                                        pressScale: 0.9,
                                                        borderRadius: BorderRadius.circular(999),
                                                        child: Container(
                                                          width: 44,
                                                          height: 44,
                                                          decoration: const BoxDecoration(
                                                            color: Colors.white,
                                                            shape: BoxShape.circle,
                                                            boxShadow: [
                                                              BoxShadow(
                                                                color: Color(0x55000000),
                                                                blurRadius: 14,
                                                                offset: Offset(0, 4),
                                                              ),
                                                            ],
                                                          ),
                                                          child: AnimatedSwitcher(
                                                            duration:
                                                                const Duration(milliseconds: 180),
                                                            switchInCurve: VedroTheme.springCurve,
                                                            transitionBuilder: (child, anim) =>
                                                                ScaleTransition(
                                                              scale: Tween<double>(
                                                                begin: 0.72,
                                                                end: 1.0,
                                                              ).animate(anim),
                                                              child: FadeTransition(
                                                                opacity: anim,
                                                                child: child,
                                                              ),
                                                            ),
                                                            child: Icon(
                                                              _paused
                                                                  ? Icons.play_arrow_rounded
                                                                  : Icons.pause_rounded,
                                                              key: ValueKey<bool>(_paused),
                                                              size: 26,
                                                              color: VedroTheme.canvas,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(width: singleRowDeck ? 8 : 10),
                                                      _DeckIconButton(
                                                        icon: _seekFwdIcon(step),
                                                        tooltip: '前进 ${step}s',
                                                        onTap: () =>
                                                            _seekBy(step.toDouble(), showHud: true),
                                                      ),
                                                      if (_nextEpisode != null) ...[
                                                        const SizedBox(width: 4),
                                                        _DeckIconButton(
                                                          icon: Icons.skip_next_rounded,
                                                          tooltip: '下一集 (N)',
                                                          onTap: () => _switchEpisode(_nextEpisode!),
                                                        ),
                                                      ],
                                                    ],
                                                  );

                                                  final screenToggleBtn = _isDesktop
                                                      ? _DeckIconButton(
                                                          icon: _isFullscreen
                                                              ? Icons.fullscreen_exit_rounded
                                                              : Icons.fullscreen_rounded,
                                                          tooltip: _isFullscreen
                                                              ? '退出全屏 (F / Esc)'
                                                              : '进入全屏 (F / 双击画面)',
                                                          onTap: _toggleFullscreen,
                                                        )
                                                      : (_isMobile
                                                          ? _DeckIconButton(
                                                              icon: Icons.screen_rotation_rounded,
                                                              tooltip: _isLandscapeOrientation
                                                                  ? '切换竖屏'
                                                                  : '切换横屏',
                                                              onTap: _toggleMobileOrientation,
                                                            )
                                                          : const SizedBox(width: 34));

                                                  return Column(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      // Row 1: Custom precision Cinema Scrub Bar (isolated RepaintBoundary + ValueNotifier + D-Pad focusable!)
                                                      RepaintBoundary(
                                                        child: ListenableBuilder(
                                                          listenable: Listenable.merge([
                                                            _positionNotifier,
                                                            _bufferedNotifier,
                                                          ]),
                                                          builder: (_, __) => _CinemaScrubBar(
                                                            positionSecs: _scrubbing
                                                                ? _scrubTargetSecs
                                                                : _positionNotifier.value,
                                                            bufferedSecs: _bufferedNotifier.value,
                                                            durationSecs: _durationSecs,
                                                            segments: _segments,
                                                            chapterTimes: _chapters
                                                                .map((c) => c.timeSecs)
                                                                .toList(),
                                                            showRemaining: _showRemaining,
                                                            seekStepSecs: step.toDouble(),
                                                            fmtTime: _fmtTime,
                                                            onToggleRemaining: () => setState(() =>
                                                                _showRemaining = !_showRemaining),
                                                            onScrubStart: () =>
                                                                _hideControlsTimer?.cancel(),
                                                            onScrubUpdate: (secs) {
                                                              _positionSecs = secs;
                                                              _positionNotifier.value = secs;
                                                            },
                                                            onScrubEnd: (secs) {
                                                              _seekTo(secs);
                                                              _scheduleHideControls();
                                                            },
                                                            onDpadStep: (delta) {
                                                              _accumulateKeySeek(delta);
                                                              _scheduleHideControls();
                                                            },
                                                          ),
                                                        ),
                                                      ),
                                              const SizedBox(height: 10),
                                              if (singleRowDeck)
                                                Row(
                                                  children: [
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
                                                      width: 78,
                                                      child: _MiniVolumeBar(
                                                        value: (_volume / _maxVolume).clamp(0.0, 1.0),
                                                        onChanged: (ratio) =>
                                                            _setVolume(ratio * _maxVolume),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    speedPill,
                                                    Expanded(child: Center(child: transportCluster)),
                                                    Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
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
                                                          key: const ValueKey('player-beauty-pill'),
                                                          label: _beautyPreset == 'off'
                                                              ? '美颜'
                                                              : '美颜·${BeautyFilterPreset.byId(_beautyPreset).label}',
                                                          active: _beautyPreset != 'off',
                                                          onTap: _openBeautyFilterSheet,
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
                                                        const SizedBox(width: 6),
                                                        screenToggleBtn,
                                                      ],
                                                    ),
                                                  ],
                                                )
                                              else ...[
                                                // Compact portrait / narrow landscape 2-tier layout:
                                                // Tier 1: [Speed Pill (never clipped)] | [Transport] | [Rotate/Fullscreen]
                                                Row(
                                                  children: [
                                                    speedPill,
                                                    Expanded(child: Center(child: transportCluster)),
                                                    screenToggleBtn,
                                                  ],
                                                ),
                                                const SizedBox(height: 10),
                                                // Tier 2: Full-width smooth scrollable quick-action strip
                                                SizedBox(
                                                  width: double.infinity,
                                                  child: SingleChildScrollView(
                                                    scrollDirection: Axis.horizontal,
                                                    child: Row(
                                                      children: [
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
                                                          key: const ValueKey('player-beauty-pill-compact'),
                                                          label: _beautyPreset == 'off'
                                                              ? '美颜'
                                                              : '美颜·${BeautyFilterPreset.byId(_beautyPreset).label}',
                                                          active: _beautyPreset != 'off',
                                                          onTap: _openBeautyFilterSheet,
                                                        ),
                                                        const SizedBox(width: 6),
                                                        _DeckPillButton(
                                                          label: '画面',
                                                          onTap: _openHdrSheet,
                                                        ),
                                                        const SizedBox(width: 6),
                                                        _DeckPillButton(
                                                          label: '比例',
                                                          onTap: _openAspectSheet,
                                                        ),
                                                        if ((_prepared?.allSources.length ?? 0) > 1) ...[
                                                          const SizedBox(width: 6),
                                                          _DeckPillButton(
                                                            label: '版本',
                                                            onTap: _openVersionSheet,
                                                          ),
                                                        ],
                                                        if (_episodes.length > 1) ...[
                                                          const SizedBox(width: 6),
                                                          _DeckPillButton(
                                                            label: '选集',
                                                            onTap: () => setState(() => _showEpisodeDrawer = true),
                                                          ),
                                                        ],
                                                        if (_chapters.isNotEmpty) ...[
                                                          const SizedBox(width: 6),
                                                          _DeckPillButton(
                                                            label: '章节',
                                                            onTap: _openChaptersSheet,
                                                          ),
                                                        ],
                                                        const SizedBox(width: 6),
                                                        _DeckPillButton(
                                                          label: '截图',
                                                          onTap: _takeScreenshot,
                                                        ),
                                                        const SizedBox(width: 6),
                                                        _DeckPillButton(
                                                          label: '参数',
                                                          active: _showStats,
                                                          onTap: () => setState(() => _showStats = !_showStats),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                ],
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                  // Click-outside scrim when Episode Drawer is open
                  if (_showEpisodeDrawer && !_inPipMode)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _showEpisodeDrawer = false);
                          _scheduleHideControls();
                        },
                        child: Container(color: const Color(0x66000000)),
                      ),
                    ),

                  // Slide-out high-contrast Episode Drawer (unmounted children & ExcludeFocus when hidden!)
                  if (_showEpisodeDrawer && !_inPipMode)
                    Positioned(
                      top: topPad + (isMac ? 42 : 16) + tvPadY,
                      bottom: 16 + tvPadY,
                      right: 16 + tvPadX,
                      width: (size.width - 32).clamp(260.0, 356.0),
                      child: FocusTraversalGroup(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xF8151720),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFF2D3142), width: 1.0),
                            boxShadow: const [
                              BoxShadow(color: Color(0xB8000000), blurRadius: 32, offset: Offset(0, 12)),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Builder(
                            builder: (ctx) {
                              final accent = Theme.of(ctx).colorScheme.secondary;
                              final ordered = _epDrawerDescending
                                  ? _episodes.reversed.toList()
                                  : _episodes;
                              final chunkSize = ordered.length >= 400 ? 100 : 50;
                              final rangeCount =
                                  ordered.isEmpty ? 0 : ((ordered.length - 1) ~/ chunkSize) + 1;
                              final safeRangeIdx =
                                  rangeCount == 0 ? 0 : _epDrawerRangeIdx.clamp(0, rangeCount - 1);
                              final start = safeRangeIdx * chunkSize;
                              final end = (start + chunkSize).clamp(0, ordered.length);
                              final visibleEps =
                                  rangeCount > 1 ? ordered.sublist(start, end) : ordered;

                              return Column(
                                children: [
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      16,
                                      (isWin && !_isFullscreen) ? 38 : 10,
                                      8,
                                      8,
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          '选集 (${_episodes.length})',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const Spacer(),
                                        IconButton(
                                          tooltip: _epDrawerDescending ? '切换正序' : '切换倒序',
                                          visualDensity: VisualDensity.compact,
                                          icon: Icon(
                                            _epDrawerDescending
                                                ? Icons.arrow_upward_rounded
                                                : Icons.arrow_downward_rounded,
                                            size: 17,
                                            color: VedroTheme.fg2,
                                          ),
                                          onPressed: () => setState(() {
                                            _epDrawerDescending = !_epDrawerDescending;
                                            _epDrawerRangeIdx = 0;
                                          }),
                                        ),
                                        IconButton(
                                          tooltip: _epDrawerGrid ? '切换列表视图' : '切换数字网格',
                                          visualDensity: VisualDensity.compact,
                                          icon: Icon(
                                            _epDrawerGrid
                                                ? Icons.view_list_rounded
                                                : Icons.grid_view_rounded,
                                            size: 17,
                                            color: VedroTheme.fg2,
                                          ),
                                          onPressed: () =>
                                              setState(() => _epDrawerGrid = !_epDrawerGrid),
                                        ),
                                        IconButton(
                                          focusNode: _drawerCloseFocusNode,
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(Icons.close_rounded,
                                              size: 18, color: VedroTheme.fg2),
                                          onPressed: () {
                                            setState(() => _showEpisodeDrawer = false);
                                            _scheduleHideControls();
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (rangeCount > 1)
                                    SizedBox(
                                      height: 36,
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                                        itemCount: rangeCount,
                                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                                        itemBuilder: (_, rIdx) {
                                          final rStart = rIdx * chunkSize;
                                          final rEnd = (rStart + chunkSize).clamp(0, ordered.length);
                                          final firstNum =
                                              ordered[rStart].indexNumber ?? (rStart + 1);
                                          final lastNum =
                                              ordered[rEnd - 1].indexNumber ?? rEnd;
                                          final active = rIdx == safeRangeIdx;
                                          return PressableScale(
                                            onTap: () => setState(() => _epDrawerRangeIdx = rIdx),
                                            hoverScale: 1.03,
                                            pressScale: 0.95,
                                            borderRadius: BorderRadius.circular(8),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: active
                                                    ? accent
                                                    : const Color(0xFF1F2230),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                '$firstNum-$lastNum',
                                                style: TextStyle(
                                                  color: active
                                                      ? const Color(0xFF0B0B0D)
                                                      : const Color(0xFFD5D9E6),
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                  fontFeatures: const [FontFeature.tabularFigures()],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  const Divider(height: 1, color: Color(0xFF262936)),
                                  Expanded(
                                    child: _epDrawerGrid
                                        ? GridView.builder(
                                            padding: const EdgeInsets.all(12),
                                            gridDelegate:
                                                const SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 5,
                                              mainAxisSpacing: 8,
                                              crossAxisSpacing: 8,
                                              childAspectRatio: 1.25,
                                            ),
                                            itemCount: visibleEps.length,
                                            itemBuilder: (_, idx) {
                                              final ep = visibleEps[idx];
                                              final playing = ep.id == _currentItem.id;
                                              final numLabel = '${ep.indexNumber ?? (start + idx + 1)}';
                                              return Tooltip(
                                                message: ep.displayName,
                                                child: PressableScale(
                                                  onTap: () => _switchEpisode(ep),
                                                  hoverScale: 1.04,
                                                  pressScale: 0.94,
                                                  borderRadius: BorderRadius.circular(9),
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: playing
                                                          ? accent
                                                          : const Color(0xFF1F2230),
                                                      borderRadius: BorderRadius.circular(9),
                                                      border: Border.all(
                                                        color: playing
                                                            ? accent
                                                            : const Color(0xFF2F3346),
                                                        width: 0.9,
                                                      ),
                                                    ),
                                                    alignment: Alignment.center,
                                                    child: Text(
                                                      numLabel,
                                                      style: TextStyle(
                                                        color: playing
                                                            ? const Color(0xFF0B0B0D)
                                                            : (ep.played
                                                                ? const Color(0xFF8B90A4)
                                                                : Colors.white),
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.w600,
                                                        fontFeatures: const [
                                                          FontFeature.tabularFigures(),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          )
                                        : ListView.separated(
                                            padding: const EdgeInsets.all(12),
                                            itemCount: visibleEps.length,
                                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                                            itemBuilder: (_, idx) {
                                              final ep = visibleEps[idx];
                                              final playing = ep.id == _currentItem.id;
                                              return PressableScale(
                                                onTap: () => _switchEpisode(ep),
                                                hoverScale: 1.01,
                                                pressScale: 0.97,
                                                borderRadius: BorderRadius.circular(11),
                                                child: Container(
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color: playing
                                                        ? const Color(0xFF1F2B44)
                                                        : const Color(0xFF1D202C),
                                                    borderRadius: BorderRadius.circular(11),
                                                    border: Border.all(
                                                      color: playing
                                                          ? accent
                                                          : const Color(0xFF2B2F40),
                                                      width: playing ? 1.2 : 0.8,
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
                                                              displayWidth: 84,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment.start,
                                                          children: [
                                                            Text(
                                                              '${ep.indexNumber ?? (start + idx + 1)}. ${ep.displayName}',
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: TextStyle(
                                                                color: playing
                                                                    ? Colors.white
                                                                    : VedroTheme.fg,
                                                                fontSize: 13,
                                                                fontWeight: playing
                                                                    ? FontWeight.w600
                                                                    : FontWeight.w500,
                                                              ),
                                                            ),
                                                            if (fmtDurationTicks(ep.runTimeTicks)
                                                                .isNotEmpty)
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
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildGestureHudContent(String mode, String feedbackText) {
    if (mode == 'seek_feedback') {
      return Text(
        feedbackText,
        style: const TextStyle(
          color: VedroTheme.fg,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      );
    }
    final isBrightness = mode == 'brightness';
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
            VedroPrecisionSlider(
              label: '画面缩放',
              value: _videoZoom,
              min: -0.5,
              max: 1.5,
              step: 0.05,
              defaultValue: 0.0,
              snapValues: const [0.0, 0.25, 0.5, 1.0],
              ticks: const [(-0.5, '50%'), (0.0, '100%'), (0.5, '150%'), (1.0, '200%'), (1.5, '250%')],
              valueText: '${(100 * (1 + _videoZoom)).round()}%',
              onChanged: (next) {
                setModal(() => _videoZoom = next);
                _setVideoZoom(next, showHud: false);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openDanmakuSheet() {
    final queryCtrl = TextEditingController(
      text: _currentItem.seriesName ?? _currentItem.displayName,
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
                  child: Text('弹幕匹配与样式', style: TextStyle(color: VedroTheme.fg, fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _pickLocalDanmakuXml();
                  },
                  icon: const Icon(Icons.upload_file_rounded, size: 15),
                  label: const Text('本地 XML', style: TextStyle(fontSize: 12)),
                ),
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
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 10),
              child: Text(
                _danmakuLoading || _danmakuSearching
                    ? '正在从弹弹Play / B站弹幕库检索匹配…'
                    : (_danmakuError != null
                        ? '提示：$_danmakuError'
                        : (_danmakuComments.isNotEmpty
                            ? '当前弹幕：${_danmakuMatchTitle ?? ''}（共 ${_danmakuComments.length} 条）'
                            : '自动联合检索 弹弹Play + B站番剧/影视弹幕库')),
                style: TextStyle(
                  color: _danmakuError != null
                      ? VedroTheme.danger
                      : (_danmakuComments.isNotEmpty ? const Color(0xFF34D399) : VedroTheme.fg3),
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
                      onSubmitted: (_) async {
                        final kw = queryCtrl.text.trim();
                        if (kw.isEmpty) return;
                        setModal(() {
                          _danmakuEnabled = true;
                          _danmakuSearching = true;
                        });
                        setState(() => _danmakuEnabled = true);
                        await Future.wait([
                          _loadDanmaku(queryOverride: kw),
                          widget.appState.searchDanmakuCandidates(kw).then((c) {
                            if (mounted) _danmakuCandidates = c;
                          }).catchError((_) {}),
                        ]);
                        if (ctx.mounted) setModal(() => _danmakuSearching = false);
                      },
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '输入番剧或电影名称搜索弹幕…',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: (_danmakuLoading || _danmakuSearching)
                        ? null
                        : () async {
                            final kw = queryCtrl.text.trim();
                            if (kw.isEmpty) return;
                            setModal(() {
                              _danmakuEnabled = true;
                              _danmakuSearching = true;
                            });
                            setState(() => _danmakuEnabled = true);
                            await Future.wait([
                              _loadDanmaku(queryOverride: kw),
                              widget.appState.searchDanmakuCandidates(kw).then((c) {
                                if (mounted) _danmakuCandidates = c;
                              }).catchError((_) {}),
                            ]);
                            if (ctx.mounted) setModal(() => _danmakuSearching = false);
                          },
                    child: Text(
                      (_danmakuLoading || _danmakuSearching) ? '搜索中…' : '搜索匹配',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
            if (_danmakuCandidates.isNotEmpty) ...[
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 168),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _danmakuCandidates.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, cIdx) {
                    final cand = _danmakuCandidates[cIdx];
                    final badge = (cand['source_badge'] ?? '').toString();
                    final cTitle = (cand['title'] ?? '').toString();
                    final eps = ((cand['episodes'] as List<dynamic>?) ?? const [])
                        .whereType<Map<String, dynamic>>()
                        .toList();
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1F2B),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: const Color(0x22FFFFFF), width: 0.7),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0x285B9BFF),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  badge,
                                  style: const TextStyle(
                                    color: Color(0xFF93C5FD),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  cTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          SizedBox(
                            height: 28,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: eps.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 6),
                              itemBuilder: (_, eIdx) {
                                final ep = eps[eIdx];
                                final lbl = (ep['label'] ?? '${eIdx + 1}').toString();
                                return PressableScale(
                                  hoverScale: 1.03,
                                  pressScale: 0.94,
                                  borderRadius: BorderRadius.circular(7),
                                  onTap: () async {
                                    setModal(() => _danmakuLoading = true);
                                    try {
                                      final loaded = await widget.appState.loadDanmakuTarget(
                                        provider: (ep['provider'] ?? 'dandan').toString(),
                                        targetId: (ep['target_id'] ?? '').toString(),
                                        title: '$cTitle · $lbl',
                                      );
                                      if (mounted) {
                                        setState(() {
                                          _danmakuComments = loaded.comments;
                                          _danmakuMatchTitle = loaded.title;
                                          _danmakuEnabled = true;
                                          _danmakuError = loaded.comments.isEmpty
                                              ? '该分集暂无弹幕'
                                              : null;
                                        });
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        setState(() => _danmakuError = '$e');
                                      }
                                    } finally {
                                      if (mounted) _danmakuLoading = false;
                                      if (ctx.mounted) setModal(() {});
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF25293A),
                                      borderRadius: BorderRadius.circular(7),
                                      border: Border.all(color: const Color(0x28FFFFFF), width: 0.6),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      lbl,
                                      style: const TextStyle(color: Colors.white, fontSize: 11.5),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
            const Divider(height: 22),
            VedroPrecisionSlider(
              label: '不透明度',
              value: _danmakuOpacity,
              min: 0.2,
              max: 1.0,
              step: 0.05,
              defaultValue: 0.82,
              valueText: '${(_danmakuOpacity * 100).round()}%',
              onChanged: (v) {
                setModal(() => _danmakuOpacity = v);
                setState(() => _danmakuOpacity = v);
                widget.appState.updatePrefs(widget.appState.prefs.copyWith(danmakuOpacity: v));
              },
            ),
            VedroPrecisionSlider(
              label: '弹幕字号',
              value: _danmakuFontSize,
              min: 12.0,
              max: 32.0,
              step: 1.0,
              defaultValue: 18.0,
              valueText: '${_danmakuFontSize.round()} pt',
              onChanged: (v) {
                setModal(() => _danmakuFontSize = v);
                setState(() => _danmakuFontSize = v);
                widget.appState.updatePrefs(widget.appState.prefs.copyWith(danmakuFontSize: v));
              },
            ),
            VedroPrecisionSlider(
              label: '滚动时长（越小越快）',
              value: _danmakuSpeedSecs,
              min: 4.0,
              max: 15.0,
              step: 0.5,
              defaultValue: 9.0,
              valueText: '${_danmakuSpeedSecs.toStringAsFixed(1)}s',
              onChanged: (v) {
                setModal(() => _danmakuSpeedSecs = v);
                setState(() => _danmakuSpeedSecs = v);
                widget.appState.updatePrefs(widget.appState.prefs.copyWith(danmakuSpeedSecs: v));
              },
            ),
            VedroPrecisionSlider(
              label: '显示区域',
              value: _danmakuArea,
              min: 0.25,
              max: 1.0,
              step: 0.05,
              defaultValue: 0.5,
              snapValues: const [0.25, 0.5, 0.75, 1.0],
              ticks: const [(0.25, '1/4 屏'), (0.5, '半屏'), (0.75, '3/4 屏'), (1.0, '全屏')],
              valueText: '${(_danmakuArea * 100).round()}%',
              onChanged: (v) {
                setModal(() => _danmakuArea = v);
                setState(() => _danmakuArea = v);
                widget.appState.updatePrefs(widget.appState.prefs.copyWith(danmakuArea: v));
              },
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
    showGlassSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          key: const ValueKey('player-speed-sheet'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    const Icon(Icons.speed_rounded, size: 19, color: Colors.white),
                    const SizedBox(width: 8),
                    const Text(
                      '播放倍速',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '拖动滑块实时无级调节',
                      style: const TextStyle(color: VedroTheme.fg3, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              VedroPrecisionSlider(
                label: '当前速率',
                value: _speed.clamp(0.25, 3.0),
                min: 0.25,
                max: 3.0,
                step: 0.05,
                defaultValue: 1.0,
                snapValues: const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0],
                ticks: const [
                  (0.25, '0.25×'),
                  (0.5, '0.5×'),
                  (1.0, '1.0×'),
                  (1.5, '1.5×'),
                  (2.0, '2.0×'),
                  (3.0, '3.0×'),
                ],
                valueText: _fmtSpeed(_speed),
                onChanged: (s) {
                  setModal(() {});
                  _setSpeed(s);
                },
              ),
            ],
          ),
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
            const Divider(height: 18),
            VedroPrecisionSlider(
              label: '音频同步偏移',
              value: _audioDelaySecs,
              min: -3.0,
              max: 3.0,
              step: 0.05,
              defaultValue: 0.0,
              centeredOrigin: true,
              snapValues: const [0.0],
              ticks: const [(-3.0, '-3s'), (-1.0, '-1s'), (0.0, '0s'), (1.0, '+1s'), (3.0, '+3s')],
              valueText: '${_audioDelaySecs >= 0 ? '+' : ''}${_audioDelaySecs.toStringAsFixed(2)}s',
              onChanged: (v) async {
                setModal(() => _audioDelaySecs = v);
                setState(() => _audioDelaySecs = v);
                await _applyMpvProperty('audio-delay', v.toStringAsFixed(2));
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
    unawaited(LocalAsrManager.instance.refreshStatus());
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
            // YouTube-style AI Auto-Translate Bilingual Subtitle & ASR Speech-to-Subtitle Card
            ListenableBuilder(
              listenable: Listenable.merge([_aiSubCtrl, LocalAsrManager.instance]),
              builder: (context, _) {
                final prefs = widget.appState.prefs;
                final aiReady = prefs.isAiReady;
                final isLocalAsr = prefs.asrEngine == 'local';
                final asrReady = widget.appState.isAsrReadyForPlayback;
                final aiTransActive = _aiSubCtrl.enabled && !_aiSubCtrl.asrMode;
                final asrActive = _aiSubCtrl.enabled && _aiSubCtrl.asrMode;
                final accent = Theme.of(context).colorScheme.secondary;
                final statusText = !_aiSubCtrl.enabled
                    ? (aiReady
                        ? '像 YouTube 一样一键自动翻译当前字幕为双语，提前预读后续台词'
                        : '请先在「设置 → AI 翻译」开启并配置模型')
                    : _aiSubCtrl.isLoadingCues
                        ? '正在读取完整字幕并提前预读翻译…'
                        : _aiSubCtrl.asrMode
                            ? (_aiSubCtrl.isTranscribing
                                ? 'AI 语音识别中（已识别 ${_aiSubCtrl.totalCues} 句${aiReady ? ' · 已译 ${_aiSubCtrl.translatedCount} 句' : ''}）…'
                                : 'AI 听音字幕已就绪 · 已识别 ${_aiSubCtrl.totalCues} 句${aiReady ? ' · 已译 ${_aiSubCtrl.translatedCount} 句' : ''}')
                            : _aiSubCtrl.isLiveFallbackMode
                                ? '实时逐句翻译模式 → ${_aiSubCtrl.targetLang}'
                                : '已预读翻译 ${_aiSubCtrl.translatedCount} / ${_aiSubCtrl.totalCues} 句 → ${_aiSubCtrl.targetLang}';

                return Container(
                  key: const ValueKey('player-ai-sub-card'),
                  margin: const EdgeInsets.fromLTRB(4, 6, 4, 10),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  decoration: BoxDecoration(
                    color: _aiSubCtrl.enabled
                        ? accent.withValues(alpha: 0.14)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _aiSubCtrl.enabled
                          ? accent.withValues(alpha: 0.45)
                          : Colors.white.withValues(alpha: 0.12),
                      width: 0.8,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.translate_rounded, size: 17, color: accent),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'AI 自动翻译（双语字幕）',
                              style: TextStyle(
                                color: VedroTheme.fg,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Transform.scale(
                            scale: 0.78,
                            child: CupertinoSwitch(
                              key: const ValueKey('player-ai-sub-toggle'),
                              value: aiTransActive,
                              onChanged: (v) async {
                                if (v) {
                                  await _enableAiSubtitleTranslation();
                                } else {
                                  await _disableAiSubtitle();
                                }
                                setModal(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                      Text(
                        statusText,
                        style: const TextStyle(color: VedroTheme.fg2, fontSize: 11.5, height: 1.35),
                      ),
                      if (_aiSubCtrl.lastError != null && _aiSubCtrl.lastError!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                _aiSubCtrl.lastError!,
                                style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 11),
                              ),
                            ),
                            if (_aiSubCtrl.asrCircuitOpen) ...[
                              const SizedBox(width: 8),
                              _DeckPillButton(
                                label: '重试识别',
                                active: true,
                                onTap: () {
                                  _aiSubCtrl.retryAsr();
                                  setModal(() {});
                                },
                              ),
                            ] else if (_aiSubCtrl.translateCircuitOpen) ...[
                              const SizedBox(width: 8),
                              _DeckPillButton(
                                label: '重试翻译',
                                active: true,
                                onTap: () {
                                  _aiSubCtrl.retryTranslation();
                                  setModal(() {});
                                },
                              ),
                            ],
                          ],
                        ),
                      ],
                      if (_aiSubCtrl.isUsingBilibiliPublicApi) ...[
                        const SizedBox(height: 4),
                        const Text(
                          '已启用哔哩哔哩公益接口防过载限速（单并发 + 本地缓存复用）',
                          style: TextStyle(color: VedroTheme.fg3, fontSize: 10.5),
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Compact single-row YouTube-style dropdown pickers (Target Language + Bilingual Layout)
                      Row(
                        children: [
                          Expanded(
                            child: PopupMenuButton<String>(
                              key: const ValueKey('player-ai-lang-dropdown'),
                              tooltip: '选择翻译目标语言',
                              color: const Color(0xF01C1E26),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                              ),
                              onSelected: (langId) async {
                                unawaited(widget.appState.updatePrefs(
                                  prefs.copyWith(aiTargetLang: langId),
                                ));
                                if (!_aiSubCtrl.enabled) {
                                  await _enableAiSubtitleTranslation(targetLangOverride: langId);
                                } else {
                                  await _aiSubCtrl.setTargetLang(langId);
                                }
                                setModal(() {});
                              },
                              itemBuilder: (_) => AiSubtitleTargetLanguage.all.map((lang) {
                                final isCur = _aiSubCtrl.targetLang == lang.id;
                                return PopupMenuItem<String>(
                                  value: lang.id,
                                  height: 36,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          lang.id,
                                          style: TextStyle(
                                            color: isCur ? accent : VedroTheme.fg,
                                            fontSize: 13,
                                            fontWeight: isCur ? FontWeight.w600 : FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                      if (isCur)
                                        Icon(Icons.check_rounded, size: 16, color: accent),
                                    ],
                                  ),
                                );
                              }).toList(),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.14),
                                    width: 0.7,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Text(
                                      '目标',
                                      style: TextStyle(color: VedroTheme.fg3, fontSize: 11.5),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _aiSubCtrl.targetLang,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: VedroTheme.fg,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 16,
                                      color: VedroTheme.fg2,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: PopupMenuButton<String>(
                              key: const ValueKey('player-ai-mode-dropdown'),
                              tooltip: '选择双语字幕排版',
                              color: const Color(0xF01C1E26),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                              ),
                              onSelected: (modeId) {
                                _aiSubCtrl.setDisplayMode(modeId);
                                unawaited(widget.appState.updatePrefs(
                                  prefs.copyWith(aiSubtitleMode: modeId),
                                ));
                                setModal(() {});
                              },
                              itemBuilder: (_) => const [
                                ('bilingual_trans_top', '双语 · 译文在上'),
                                ('bilingual_orig_top', '双语 · 原文在上'),
                                ('translated_only', '仅显示译文'),
                              ].map((item) {
                                final isCur = _aiSubCtrl.displayMode == item.$1;
                                return PopupMenuItem<String>(
                                  value: item.$1,
                                  height: 36,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.$2,
                                          style: TextStyle(
                                            color: isCur ? accent : VedroTheme.fg,
                                            fontSize: 13,
                                            fontWeight: isCur ? FontWeight.w600 : FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                      if (isCur)
                                        Icon(Icons.check_rounded, size: 16, color: accent),
                                    ],
                                  ),
                                );
                              }).toList(),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.14),
                                    width: 0.7,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Text(
                                      '排版',
                                      style: TextStyle(color: VedroTheme.fg3, fontSize: 11.5),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        switch (_aiSubCtrl.displayMode) {
                                          'bilingual_orig_top' => '原文在上',
                                          'translated_only' => '仅译文',
                                          _ => '译文在上',
                                        },
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: VedroTheme.fg,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 16,
                                      color: VedroTheme.fg2,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      VedroPrecisionSlider(
                        key: const ValueKey('player-ai-sub-font-slider'),
                        label: '翻译字幕字号',
                        value: _aiSubFontScale,
                        min: 0.6,
                        max: 1.8,
                        step: 0.05,
                        defaultValue: 1.0,
                        snapValues: const [0.8, 1.0, 1.25, 1.5],
                        valueText: '${(_aiSubFontScale * 100).round()}%',
                        onChanged: (v) {
                          setModal(() => _aiSubFontScale = v);
                          setState(() => _aiSubFontScale = v);
                          unawaited(widget.appState.updatePrefs(
                            prefs.copyWith(aiSubtitleFontScale: v),
                          ));
                        },
                      ),
                      const Divider(height: 18, color: Color(0x1FFFFFFF)),
                      Row(
                        children: [
                          Icon(Icons.graphic_eq_rounded, size: 16, color: accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'AI 语音识别生成字幕（无字幕视频适用）',
                                  style: TextStyle(
                                    color: VedroTheme.fg,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  asrReady
                                      ? (isLocalAsr
                                          ? '本地离线 SenseVoice 识别${aiReady ? ' + 自动双语翻译' : ''}（免 Key · 无录屏弹窗）'
                                          : '云端自动切片识别音频${aiReady ? '并翻译为双语' : ''}（${prefs.asrModel}）')
                                      : (isLocalAsr
                                          ? '请先在「设置 → AI 翻译」一键下载本地离线模型 (~229 MB，免 Key)'
                                          : '请先在「设置 → AI 翻译」配置 Groq / 硅基流动 / 本地 Whisper'),
                                  style: const TextStyle(color: VedroTheme.fg3, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Transform.scale(
                            scale: 0.78,
                            child: CupertinoSwitch(
                              key: const ValueKey('player-ai-asr-toggle'),
                              value: asrActive,
                              onChanged: (v) async {
                                if (v) {
                                  await _enableAiAsrSubtitle();
                                } else {
                                  await _disableAiSubtitle();
                                }
                                setModal(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0x28FFFFFF), width: 0.8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _pickAndLoadLocalSubtitle();
                },
                icon: const Icon(Icons.upload_file_rounded, size: 16),
                label: const Text('加载本地外挂字幕 (.srt / .ass / .vtt，也支持直接拖入窗口)',
                    style: TextStyle(fontSize: 12.5)),
              ),
            ),
            ..._loadedLocalSubtitles.map((ls) => _SheetOptionRow(
                  label: ls.title,
                  subtitle: '本地外挂字幕',
                  selected: _activeSubLocalPath == ls.path,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _loadExternalSubtitleFile(ls.path);
                  },
                )),
            _SheetOptionRow(
              label: '关闭字幕',
              selected: _player.state.track.subtitle.id == 'no' && !_aiSubCtrl.enabled,
              onTap: () async {
                Navigator.pop(ctx);
                _aiSubCtrl.disable();
                unawaited(LocalAsrManager.instance.unloadEngine());
                _activeSubLocalPath = null;
                _activeSubUrl = null;
                await _applyMpvProperty('sub-visibility', 'yes');
                await _player.setSubtitleTrack(SubtitleTrack.no());
              },
            ),
            ...embeddedSubs.map((t) => _SheetOptionRow(
                  label: t.title ?? t.language ?? '字幕 #${t.id}',
                  subtitle: [t.codec, t.language].whereType<String>().join(' · '),
                  selected: _activeSubUrl == null &&
                      _activeSubLocalPath == null &&
                      _player.state.track.subtitle.id == t.id,
                  onTap: () async {
                    Navigator.pop(ctx);
                    _activeSubLocalPath = null;
                    _activeSubUrl = null;
                    _activeSubFormat = t.codec;
                    _activeSubLabel = t.title ?? t.language ?? '字幕 #${t.id}';
                    await _player.setSubtitleTrack(t);
                    if (_aiSubCtrl.enabled && !_aiSubCtrl.asrMode) {
                      await _enableAiSubtitleTranslation();
                    }
                  },
                )),
            ...extSubs.map((s) => _SheetOptionRow(
                  label: s['title']?.toString() ?? '外挂字幕',
                  subtitle: '${s['codec'] ?? 'srt'} · ${s['language'] ?? '外挂'}',
                  selected: s['url'] != null && _activeSubUrl == s['url'].toString(),
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (s['url'] != null) {
                      _activeSubLocalPath = null;
                      _activeSubUrl = s['url'].toString();
                      _activeSubFormat = s['codec']?.toString();
                      _activeSubLabel = s['title']?.toString();
                      await _player.setSubtitleTrack(
                        SubtitleTrack.uri(
                          s['url'].toString(),
                          title: s['title']?.toString(),
                          language: s['language']?.toString(),
                        ),
                      );
                      if (_aiSubCtrl.enabled && !_aiSubCtrl.asrMode) {
                        await _enableAiSubtitleTranslation();
                      }
                    }
                  },
                )),
            const Divider(height: 22),
            VedroPrecisionSlider(
              label: '字号缩放',
              value: _subScale,
              min: 0.5,
              max: 2.0,
              step: 0.05,
              defaultValue: 1.0,
              snapValues: const [0.75, 1.0, 1.25, 1.5],
              valueText: '${(_subScale * 100).round()}%',
              onChanged: (v) async {
                setModal(() => _subScale = v);
                setState(() => _subScale = v);
                await _applyMpvProperty('sub-scale', v.toStringAsFixed(2));
              },
            ),
            VedroPrecisionSlider(
              label: '垂直位置',
              value: _subPos.toDouble(),
              min: 60,
              max: 100,
              step: 1,
              defaultValue: 96,
              valueText: '$_subPos%',
              onChanged: (v) async {
                final iv = v.round();
                setModal(() => _subPos = iv);
                setState(() => _subPos = iv);
                await _applyMpvProperty('sub-pos', '$iv');
              },
            ),
            VedroPrecisionSlider(
              label: '时间偏移',
              value: _subDelaySecs.clamp(-5.0, 5.0),
              min: -5.0,
              max: 5.0,
              step: 0.1,
              defaultValue: 0.0,
              centeredOrigin: true,
              snapValues: const [0.0],
              valueText: '${_subDelaySecs >= 0 ? '+' : ''}${_subDelaySecs.toStringAsFixed(2)}s',
              onChanged: (v) async {
                setModal(() => _subDelaySecs = v);
                setState(() => _subDelaySecs = v);
                await _applyMpvProperty('sub-delay', v.toStringAsFixed(2));
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (delta, lbl) in const [
                    (-0.5, '-0.5s'),
                    (-0.05, '-50ms'),
                    (0.0, '归零'),
                    (0.05, '+50ms'),
                    (0.5, '+0.5s'),
                  ])
                    _DeckPillButton(
                      label: lbl,
                      active: delta == 0.0 && _subDelaySecs.abs() < 0.01,
                      onTap: () async {
                        final next = delta == 0.0
                            ? 0.0
                            : (_subDelaySecs + delta).clamp(-30.0, 30.0);
                        setModal(() => _subDelaySecs = next);
                        setState(() => _subDelaySecs = next);
                        await _applyMpvProperty('sub-delay', next.toStringAsFixed(2));
                      },
                    ),
                ],
              ),
            ),
            // Quick in-player subtitle color, outline & background box controls
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
              child: Row(
                children: [
                  const Text('字幕颜色', style: TextStyle(color: VedroTheme.fg2, fontSize: 13)),
                  const Spacer(),
                  for (final (hex, color) in const [
                    ('#FFFFFF', Color(0xFFFFFFFF)),
                    ('#FFE066', Color(0xFFFFE066)),
                    ('#7DD3FC', Color(0xFF7DD3FC)),
                    ('#86EFAC', Color(0xFF86EFAC)),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: PressableScale(
                        onTap: () async {
                          unawaited(widget.appState.updatePrefs(
                            widget.appState.prefs.copyWith(subtitleColorHex: hex),
                          ));
                          await _applyMpvProperty('sub-color', hex);
                          setModal(() {});
                          if (mounted) setState(() {});
                        },
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: widget.appState.prefs.subtitleColorHex.toUpperCase() == hex
                                  ? Theme.of(ctx).colorScheme.secondary
                                  : const Color(0x55FFFFFF),
                              width: widget.appState.prefs.subtitleColorHex.toUpperCase() == hex
                                  ? 2.2
                                  : 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            VedroPrecisionSlider(
              label: '字幕描边粗细',
              value: widget.appState.prefs.subtitleOutlineWidth.clamp(0.0, 5.0),
              min: 0.0,
              max: 5.0,
              step: 0.2,
              defaultValue: 2.4,
              valueText: widget.appState.prefs.subtitleOutlineWidth.toStringAsFixed(1),
              onChanged: (v) async {
                unawaited(widget.appState.updatePrefs(
                  widget.appState.prefs.copyWith(subtitleOutlineWidth: v),
                ));
                await _applyMpvProperty('sub-border-size', v.toStringAsFixed(1));
                setModal(() {});
                if (mounted) setState(() {});
              },
            ),
            VedroPrecisionSlider(
              label: '字幕背景黑框',
              value: widget.appState.prefs.subtitleBgOpacity.clamp(0.0, 0.85),
              min: 0.0,
              max: 0.85,
              step: 0.05,
              defaultValue: 0.0,
              valueText: '${(widget.appState.prefs.subtitleBgOpacity * 100).round()}%',
              onChanged: (v) async {
                unawaited(widget.appState.updatePrefs(
                  widget.appState.prefs.copyWith(subtitleBgOpacity: v),
                ));
                await _applyMpvProperty(
                  'sub-back-color',
                  '0.0/0.0/0.0/${v.toStringAsFixed(2)}',
                );
                setModal(() {});
                if (mounted) setState(() {});
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
                                .replaceAll('\\', '/')
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

  void _openChaptersSheet() {
    showGlassSheet<void>(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              '章节列表 (${_chapters.length})',
              style: const TextStyle(color: VedroTheme.fg, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          for (var i = 0; i < _chapters.length; i++)
            _SheetOptionRow(
              label: _chapters[i].title,
              subtitle: _fmtTime(_chapters[i].timeSecs),
              selected: _positionSecs >= _chapters[i].timeSecs &&
                  (i + 1 >= _chapters.length || _positionSecs < _chapters[i + 1].timeSecs),
              onTap: () {
                Navigator.pop(ctx);
                _seekTo(_chapters[i].timeSecs);
              },
            ),
        ],
      ),
    );
  }

  void _openBeautyFilterSheet() {
    showGlassSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '美颜滤镜（低功耗 GPU）',
                style: TextStyle(color: VedroTheme.fg, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    BeautyFilterPreset.byId(_beautyPreset).subtitle,
                    style: const TextStyle(color: VedroTheme.fg2, fontSize: 12.5),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: BeautyFilterPreset.all.map((preset) {
                      return _DeckPillButton(
                        label: preset.label,
                        active: _beautyPreset == preset.id,
                        onTap: () async {
                          await _applyBeautyFilter(preset.id, _beautyStrength);
                          setModal(() {});
                        },
                      );
                    }).toList(),
                  ),
                  if (_beautyPreset != 'off') ...[
                    const SizedBox(height: 12),
                    VedroPrecisionSlider(
                      label: '美颜强度',
                      value: _beautyStrength,
                      min: 0.15,
                      max: 1.0,
                      step: 0.05,
                      defaultValue: 0.55,
                      snapValues: const [0.35, 0.55, 0.80],
                      valueText: '${(_beautyStrength * 100).round()}%',
                      onChanged: (v) async {
                        setModal(() => _beautyStrength = v);
                        await _applyBeautyFilter(_beautyPreset, v, showHud: false);
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0x1CF59E0B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0x40F59E0B), width: 0.7),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.local_fire_department_outlined, size: 15, color: Color(0xFFFBBF24)),
                        SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            BeautyFilterEngine.thermalNotice,
                            style: TextStyle(color: Color(0xFFFDE68A), fontSize: 11.5, height: 1.4),
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

  void _openMoreToolsSheet() {
    showGlassSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text('播放工具与画面均衡器', style: TextStyle(color: VedroTheme.fg, fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),

            // Sleep Timer
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('定时关闭', style: TextStyle(color: VedroTheme.fg2, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _DeckPillButton(
                        label: '关闭',
                        active: !_sleepAfterEpisode && _sleepRemainingSecs == 0,
                        onTap: () {
                          _setSleepTimer();
                          setModal(() {});
                        },
                      ),
                      _DeckPillButton(
                        label: '播完本集',
                        active: _sleepAfterEpisode,
                        onTap: () {
                          _setSleepTimer(afterEpisode: true);
                          setModal(() {});
                        },
                      ),
                      for (final m in [15, 30, 60, 90])
                        _DeckPillButton(
                          label: '$m 分钟',
                          active: !_sleepAfterEpisode &&
                              _sleepRemainingSecs > (m - 1) * 60 &&
                              _sleepRemainingSecs <= m * 60,
                          onTap: () {
                            _setSleepTimer(minutes: m);
                            setModal(() {});
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(height: 20),

            // Loop file + A-B Loop
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('单集循环播放', style: TextStyle(color: VedroTheme.fg, fontSize: 13.5)),
                  ),
                  Transform.scale(
                    scale: 0.78,
                    child: CupertinoSwitch(
                      value: _loopFile,
                      onChanged: (v) async {
                        setModal(() => _loopFile = v);
                        setState(() => _loopFile = v);
                        await _applyMpvProperty('loop-file', v ? 'inf' : 'no');
                      },
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  const Text('A-B 复读', style: TextStyle(color: VedroTheme.fg2, fontSize: 13)),
                  const Spacer(),
                  _DeckPillButton(
                    label: _loopPointA == null ? '设 A 点' : 'A ${_fmtTime(_loopPointA!)}',
                    active: _loopPointA != null,
                    onTap: () {
                      setModal(() => _loopPointA = _positionSecs);
                      setState(() => _loopPointA = _positionSecs);
                    },
                  ),
                  const SizedBox(width: 6),
                  _DeckPillButton(
                    label: _loopPointB == null ? '设 B 点' : 'B ${_fmtTime(_loopPointB!)}',
                    active: _loopPointB != null,
                    onTap: () {
                      if (_loopPointA != null && _positionSecs > _loopPointA! + 0.5) {
                        setModal(() => _loopPointB = _positionSecs);
                        setState(() => _loopPointB = _positionSecs);
                      }
                    },
                  ),
                  if (_loopPointA != null || _loopPointB != null) ...[
                    const SizedBox(width: 6),
                    _DeckPillButton(
                      label: '清除',
                      onTap: () {
                        setModal(() {
                          _loopPointA = null;
                          _loopPointB = null;
                        });
                        setState(() {
                          _loopPointA = null;
                          _loopPointB = null;
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),

            const Divider(height: 20),

            // Ultra-Low-Power Single-Pass GPU Beauty Filter
            Padding(
              key: const ValueKey('player-beauty-filter-section'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '美颜滤镜',
                        style: TextStyle(
                          color: VedroTheme.fg2,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        BeautyFilterPreset.byId(_beautyPreset).subtitle,
                        style: const TextStyle(color: VedroTheme.fg3, fontSize: 11.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: BeautyFilterPreset.all.map((preset) {
                      return _DeckPillButton(
                        label: preset.label,
                        active: _beautyPreset == preset.id,
                        onTap: () async {
                          await _applyBeautyFilter(preset.id, _beautyStrength);
                          setModal(() {});
                        },
                      );
                    }).toList(),
                  ),
                  if (_beautyPreset != 'off') ...[
                    const SizedBox(height: 8),
                    VedroPrecisionSlider(
                      label: '美颜强度',
                      value: _beautyStrength,
                      min: 0.15,
                      max: 1.0,
                      step: 0.05,
                      defaultValue: 0.55,
                      snapValues: const [0.35, 0.55, 0.80],
                      valueText: '${(_beautyStrength * 100).round()}%',
                      onChanged: (v) async {
                        setModal(() => _beautyStrength = v);
                        await _applyBeautyFilter(_beautyPreset, v, showHud: false);
                      },
                    ),
                  ],
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0x1CF59E0B),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: const Color(0x40F59E0B), width: 0.7),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.local_fire_department_outlined, size: 14, color: Color(0xFFFBBF24)),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            BeautyFilterEngine.thermalNotice,
                            style: TextStyle(color: Color(0xFFFDE68A), fontSize: 11, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 20),

            // Video Color Equalizer (MPV brightness / contrast / saturation / gamma)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Text('色彩均衡器', style: TextStyle(color: VedroTheme.fg2, fontSize: 13, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (_eqBrightness != 0 || _eqContrast != 0 || _eqSaturation != 0 || _eqGamma != 0)
                    TextButton(
                      onPressed: () async {
                        setModal(() {
                          _eqBrightness = 0;
                          _eqContrast = 0;
                          _eqSaturation = 0;
                          _eqGamma = 0;
                        });
                        await _applyMpvProperty('brightness', '0');
                        await _applyMpvProperty('contrast', '0');
                        await _applyMpvProperty('saturation', '0');
                        await _applyMpvProperty('gamma', '0');
                      },
                      child: const Text('复位', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
            VedroPrecisionSlider(
              label: '亮度',
              value: _eqBrightness.toDouble(),
              min: -50,
              max: 50,
              step: 1,
              defaultValue: 0,
              centeredOrigin: true,
              snapValues: const [0],
              valueText: '${_eqBrightness >= 0 ? '+' : ''}$_eqBrightness',
              onChanged: (val) async {
                final v = val.round();
                setModal(() => _eqBrightness = v);
                await _applyMpvProperty('brightness', '$v');
              },
            ),
            VedroPrecisionSlider(
              label: '对比度',
              value: _eqContrast.toDouble(),
              min: -50,
              max: 50,
              step: 1,
              defaultValue: 0,
              centeredOrigin: true,
              snapValues: const [0],
              valueText: '${_eqContrast >= 0 ? '+' : ''}$_eqContrast',
              onChanged: (val) async {
                final v = val.round();
                setModal(() => _eqContrast = v);
                await _applyMpvProperty('contrast', '$v');
              },
            ),
            VedroPrecisionSlider(
              label: '饱和度',
              value: _eqSaturation.toDouble(),
              min: -50,
              max: 50,
              step: 1,
              defaultValue: 0,
              centeredOrigin: true,
              snapValues: const [0],
              valueText: '${_eqSaturation >= 0 ? '+' : ''}$_eqSaturation',
              onChanged: (val) async {
                final v = val.round();
                setModal(() => _eqSaturation = v);
                await _applyMpvProperty('saturation', '$v');
              },
            ),
            VedroPrecisionSlider(
              label: '伽马值',
              value: _eqGamma.toDouble(),
              min: -50,
              max: 50,
              step: 1,
              defaultValue: 0,
              centeredOrigin: true,
              snapValues: const [0],
              valueText: '${_eqGamma >= 0 ? '+' : ''}$_eqGamma',
              onChanged: (val) async {
                final v = val.round();
                setModal(() => _eqGamma = v);
                await _applyMpvProperty('gamma', '$v');
              },
            ),

            if (_isDesktop) ...[
              const Divider(height: 20),
              ListTile(
                dense: true,
                leading: const Icon(Icons.keyboard_rounded, size: 19, color: VedroTheme.fg2),
                title: const Text('桌面快捷键一览', style: TextStyle(color: VedroTheme.fg, fontSize: 13.5)),
                trailing: const Text('H', style: TextStyle(color: VedroTheme.fg3, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _openShortcutsDialog();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openShortcutsDialog() {
    const shortcuts = [
      ('空格', '播放 / 暂停'),
      ('F / Enter / 双击画面', '进入 / 退出原生全屏'),
      ('Esc', '退出全屏（窗口模式下退出播放）'),
      ('← / →', '快退 / 快进'),
      ('↑ / ↓ / 滚轮', '音量加减'),
      ('[ / ]', '降低 / 提高倍速'),
      (', / .', '逐帧后退 / 前进'),
      ('T', '窗口置顶开关'),
      ('L', '锁屏防误触'),
      ('S', '高清含字幕截图'),
      ('D', '弹幕开关'),
      ('R', '画面旋转 90°'),
      ('C', '打开章节列表'),
      ('I', '硬件解码与码率 HUD'),
      ('M', '静音切换'),
      ('N', '下一集'),
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('桌面快捷键指南', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: shortcuts.map((s) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF21232E),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0x22FFFFFF), width: 0.7),
                        ),
                        child: Text(
                          s.$1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(s.$2, style: const TextStyle(color: VedroTheme.fg2, fontSize: 13)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.layers_rounded, size: 18, color: VedroTheme.fg2),
                const SizedBox(width: 8),
                Text(
                  '切换片源版本 (${sources.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ...sources.map((src) {
            final title = src.name?.isNotEmpty == true
                ? src.name!
                : (src.container?.toUpperCase() ?? '原画');
            final meta = [
              if (src.container != null && src.container!.isNotEmpty) src.container!.toUpperCase(),
              if (src.videoStreams.isNotEmpty && src.videoStreams.first.height != null)
                '${src.videoStreams.first.height}p',
              if (fmtFileSize(src.size).isNotEmpty) fmtFileSize(src.size),
              if ((src.bitrate ?? 0) > 0) '${(src.bitrate! / 1000000).toStringAsFixed(1)} Mbps',
              if (src.audioStreams.isNotEmpty) '${src.audioStreams.length} 音轨',
              if (src.subtitleStreams.isNotEmpty) '${src.subtitleStreams.length} 字幕',
            ].join(' · ');
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SheetOptionRow(
                label: title,
                subtitle: meta.isNotEmpty ? meta : null,
                selected: src.id == _prepared?.mediaSourceId,
                onTap: () {
                  Navigator.pop(ctx);
                  _startPlayback(src.id, resumeFromSecs: _positionSecs);
                },
              ),
            );
          }),
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
    this.chapterTimes = const [],
    required this.showRemaining,
    this.seekStepSecs = 10.0,
    required this.fmtTime,
    required this.onToggleRemaining,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
    this.onDpadStep,
  });

  final double positionSecs;
  final double bufferedSecs;
  final double durationSecs;
  final List<MediaSegmentModel> segments;
  final List<double> chapterTimes;
  final bool showRemaining;
  final double seekStepSecs;
  final String Function(double) fmtTime;
  final VoidCallback onToggleRemaining;
  final VoidCallback onScrubStart;
  final ValueChanged<double> onScrubUpdate;
  final ValueChanged<double> onScrubEnd;
  final ValueChanged<double>? onDpadStep;

  @override
  State<_CinemaScrubBar> createState() => _CinemaScrubBarState();
}

class _CinemaScrubBarState extends State<_CinemaScrubBar> {
  bool _hovering = false;
  bool _dragging = false;
  bool _focused = false;
  double? _hoverRatio;

  double _ratioFromDx(double dx, double width) =>
      width <= 0 ? 0.0 : (dx / width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final dur = widget.durationSecs > 0 ? widget.durationSecs : 1.0;
    final posRatio = (widget.positionSecs / dur).clamp(0.0, 1.0);
    final bufRatio = (widget.bufferedSecs / dur).clamp(0.0, 1.0);
    final active = _hovering || _dragging || _focused;
    final trackH = active ? 6.5 : 4.0;
    final accent = Theme.of(context).colorScheme.secondary;

    final compactTime = MediaQuery.sizeOf(context).width < 480;
    final rightTimeText = widget.showRemaining && widget.durationSecs > 0
        ? '-${widget.fmtTime((widget.durationSecs - widget.positionSecs).clamp(0, widget.durationSecs))}'
        : widget.fmtTime(widget.durationSecs);

    return Row(
      children: [
        SizedBox(
          width: compactTime ? 48 : 60,
          child: Text(
            widget.fmtTime(widget.positionSecs),
            maxLines: 1,
            style: TextStyle(
              color: const Color(0xE0FFFFFF),
              fontSize: compactTime ? 11.5 : 12,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Focus(
            onFocusChange: (hasFocus) {
              if (_focused != hasFocus) setState(() => _focused = hasFocus);
            },
            onKeyEvent: (_, ev) {
              if (ev is KeyDownEvent || ev is KeyRepeatEvent) {
                if (ev.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  widget.onDpadStep?.call(-widget.seekStepSecs);
                  return KeyEventResult.handled;
                }
                if (ev.logicalKey == LogicalKeyboardKey.arrowRight) {
                  widget.onDpadStep?.call(widget.seekStepSecs);
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: _focused
                    ? Border.all(color: Colors.white.withValues(alpha: 0.92), width: 1.8)
                    : null,
              ),
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
                            // Chapter tick marks
                            if (widget.durationSecs > 0)
                              for (final t in widget.chapterTimes)
                                if (t > 1.0 && t < widget.durationSecs - 1.0)
                                  Positioned(
                                    left: (t / dur).clamp(0.0, 1.0) * w,
                                    child: Container(
                                      width: 2,
                                      height: trackH + 2,
                                      color: const Color(0xAA0B0B0D),
                                    ),
                                  ),
                            // Hover / TV-focus revealed sleek thumb
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
          ),
        ),
        const SizedBox(width: 8),
        PressableScale(
          onTap: widget.onToggleRemaining,
          hoverScale: 1.02,
          pressScale: 0.96,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: compactTime ? 54 : 64,
            child: Text(
              rightTimeText,
              maxLines: 1,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: const Color(0xA6FFFFFF),
                fontSize: compactTime ? 11.5 : 12,
                fontFeatures: const [FontFeature.tabularFigures()],
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
      borderRadius: BorderRadius.circular(999),
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
      borderRadius: BorderRadius.circular(999),
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
    super.key,
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
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: VedroTheme.easeOut,
        height: 31,
        padding: const EdgeInsets.symmetric(horizontal: 10.5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.active
              ? accent.withValues(alpha: 0.24)
              : (_hovered ? const Color(0x2AFFFFFF) : const Color(0x18FFFFFF)),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: widget.active ? accent.withValues(alpha: 0.68) : const Color(0x20FFFFFF),
            width: 0.75,
          ),
        ),
        child: Text(
          widget.label,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: widget.active ? accent : const Color(0xF0FFFFFF),
            fontSize: 12,
            fontWeight: widget.active ? FontWeight.w600 : FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
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
    return PressableScale(
      onTap: onTap,
      hoverScale: 1.01,
      pressScale: 0.98,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1F2A42) : const Color(0xFF1E202B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : const Color(0xFF2D3142),
            width: selected ? 1.4 : 0.9,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 19,
              color: selected ? accent : const Color(0xFF6E748A),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFB3B9C9),
                        fontSize: 12,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '当前',
                  style: TextStyle(
                    color: Color(0xFF0B0B0D),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
