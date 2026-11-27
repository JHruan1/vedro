import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
import '../core/services/local_asr_engine.dart';
import '../widgets/nerd_stats_hud.dart';
import '../widgets/vedro_artwork.dart';
import '../widgets/vedro_ui.dart';
import '../widgets/windows_immersive_frame.dart';

part 'player/player_controls.dart';
part 'player/player_engine.dart';
part 'player/player_hud.dart';
part 'player/player_sheets.dart';
part 'player/player_subtitle_sheet.dart';
part 'player/player_widgets.dart';

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
    this.directNetworkUrl,
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
  final String? directNetworkUrl;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _videoController;

  late MediaItemModel _currentItem;
  late List<MediaSegmentModel> _segments;
  String? _activeLocalPath;
  String? _activeNetworkUrl;
  List<MediaItemModel> _localEpisodes = const [];
  final Map<String, String> _localPathById = {};
  final List<({String title, String path})> _loadedLocalSubtitles = [];

  bool get _isLocalFile => _activeLocalPath != null && _activeLocalPath!.isNotEmpty;
  bool get _isDirectNetwork => _activeNetworkUrl != null && _activeNetworkUrl!.isNotEmpty;
  bool get _isServerStream => !_isLocalFile && !_isDirectNetwork;

  PreparedPlaybackModel? _prepared;
  final ValueNotifier<Map<String, dynamic>> _statsNotifier =
      ValueNotifier<Map<String, dynamic>>(const {});
  bool _loading = true;
  bool _buffering = false;
  String? _error;
  bool _disposed = false;
  bool _isInitialEpisode = true;
  int _playbackGen = 0;
  int _danmakuGen = 0;
  int _autoRetryCount = 0;
  double _retryAnchorSecs = -1.0;
  bool _hwFallbackAttempted = false;
  bool _inPipMode = false;
  bool _enteringPip = false;
  Timer? _enteringPipResetTimer;
  bool _sheetOpen = false;
  int _lastAudioInterruptCount = 0;
  bool _usingNativeBrightness = false;
  int _videoWidth = 16;
  int _videoHeight = 9;
  int _lastHoverRevealMs = 0;
  String? _lastNowPlayingSig;
  int _lastNowPlayingTickMs = 0;
  Timer? _beautyShaderDebounce;

  // End-of-video Replay & Up-Next 6s Countdown state
  bool _hasEndedReplay = false;
  int _upNextCountdown = 0;
  Timer? _upNextTimer;
  Timer? _pauseWakeLockTimer;
  bool _quickSkipIntroDismissed = false;
  final ValueNotifier<bool> _quickSkipEligibleNotifier = ValueNotifier<bool>(false);

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
  bool _audioDucked = false;
  double _brightness = 1.0;

  // Color equalizer & beauty filter & audio delay & A-B loop & chapters & sleep timer
  int _eqBrightness = 0;
  int _eqContrast = 0;
  int _eqSaturation = 0;
  int _eqGamma = 0;
  String _beautyPreset = 'off';
  double _beautyStrength = 0.55;
  BeautyFilterParams _beautyParams = BeautyFilterParams.off;
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
  bool _deinterlace = false;
  bool _hflip = false;
  bool _vflip = false;
  bool _anime4kActive = false;
  double _subDelaySecs = 0.0;
  double _subScale = 1.0;
  int _subPos = 96;
  String _subFontFamily = '';
  bool _forceAssOverride = false;
  String? _secondarySubTrackId;
  String _aspectMode = 'fit';
  String _toneMapping = 'bt.2446a';
  String _audioMode = 'auto';
  bool _nightMode = false;
  bool _dialogueBoost = false;
  bool _loudnessNorm = false;
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
  final _drawerActiveEpFocusNode = FocusNode(debugLabel: 'player-drawer-active-ep');
  final _upNextPlayFocusNode = FocusNode(debugLabel: 'player-upnext-play');
  final _replayFocusNode = FocusNode(debugLabel: 'player-replay');
  final _errorRetryFocusNode = FocusNode(debugLabel: 'player-error-retry');
  final _skipIntroFocusNode = FocusNode(debugLabel: 'player-skip-intro');

  List<MediaItemModel> get _episodes =>
      _localEpisodes.isNotEmpty ? _localEpisodes : (widget.playlistEpisodes ?? const []);

  int get _currentEpisodeIndex => _episodes.indexWhere((e) => e.id == _currentItem.id);

  MediaItemModel? get _prevEpisode {
    final idx = _currentEpisodeIndex;
    if (idx > 0 && idx - 1 < _episodes.length) return _episodes[idx - 1];
    return null;
  }

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

  double get _maxVolume => widget.appState.prefs.maxVolumePercent.toDouble().clamp(100.0, 150.0);

  static String _normalizeToneMapping(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'bt2446a' || 'bt.2446a' => 'bt.2446a',
      'st2094_40' || 'st2094-40' => 'st2094-40',
      'st2094_10' || 'st2094-10' => 'st2094-10',
      'spline' => 'spline',
      'reinhard' => 'reinhard',
      'hable' => 'hable',
      'clip' => 'clip',
      _ => 'bt.2446a',
    };
  }

  String? get _trackPrefScopeId => _currentItem.seriesId ?? (_isServerStream ? _currentItem.id : null);

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
    final rawNet = widget.directNetworkUrl?.trim();
    final rawLocal = widget.localFilePath?.trim();
    if (rawNet != null && rawNet.isNotEmpty) {
      _activeNetworkUrl = rawNet;
      _activeLocalPath = null;
    } else if (rawLocal != null &&
        rawLocal.isNotEmpty &&
        NativePlaybackChannel.isAllowedMediaUrl(rawLocal)) {
      // Defensive normalization when a caller passes a stream URL via localFilePath
      _activeNetworkUrl = rawLocal;
      _activeLocalPath = null;
    } else {
      _activeLocalPath = rawLocal;
      _activeNetworkUrl = null;
    }
    if (widget.localPlaylistPaths != null && widget.localPlaylistPaths!.isNotEmpty) {
      _buildLocalPlaylist(widget.localPlaylistPaths!);
    } else if (_isLocalFile) {
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
    _toneMapping = _normalizeToneMapping((widget.appState.settings['tone_mapping'] ?? 'bt.2446a').toString());
    _audioMode = (widget.appState.settings['audio_mode'] ?? 'auto').toString();
    _nightMode = widget.appState.settings['night_mode'] == true;
    _dialogueBoost = widget.appState.settings['dialogue_boost'] == true;
    _beautyPreset = p.beautyFilterPreset;
    _beautyStrength = p.beautyFilterStrength;
    _beautyParams = BeautyFilterEngine.resolveParams(
      presetId: p.beautyFilterPreset,
      strength: p.beautyFilterStrength,
      smooth: p.beautySmooth,
      whiten: p.beautyWhiten,
      rosy: p.beautyRosy,
      clarity: p.beautyClarity,
    );
    _aiSubFontScale = p.aiSubtitleFontScale;
    _aiSubCtrl = AiSubtitleTranslatorController(
      appState: widget.appState,
      mediaTitle: _currentItem.displayName,
    );

    WidgetsBinding.instance.addObserver(this);
    _lastAudioInterruptCount = NativePlaybackChannel.audioInterruptCountNotifier.value;
    NativePlaybackChannel.audioInterruptCountNotifier.addListener(_onAudioInterrupted);
    NativePlaybackChannel.pipModeNotifier.addListener(_onPipModeChanged);
    NativePlaybackChannel.mediaActionNotifier.addListener(_onNativeMediaAction);
    unawaited(NativePlaybackChannel.setAudioPlaybackActive(true));
    unawaited(NativePlaybackChannel.setAutoPipEnabled(p.enablePip));
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
        unawaited(NativePlaybackChannel.setAutoPipEnabled(
          playing && widget.appState.prefs.enablePip && !_disposed,
        ));
        _syncNowPlaying(force: true);
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
      // Reset reconnect counter ONLY once playback actually makes real forward progress (>= 2s)
      if (_autoRetryCount > 0 && _retryAnchorSecs >= 0 && (secs - _retryAnchorSecs) >= 2.0) {
        _autoRetryCount = 0;
        _retryAnchorSecs = -1.0;
      }
      if (_upNextCountdown > 0 && _durationSecs > 15 && secs < _durationSecs - 10.0) {
        setState(() {
          _cancelUpNextCountdown();
          _completedTriggered = false;
        });
      }
      _checkAutoSkipSegments(secs);
      if (_loopPointA != null && _loopPointB != null && secs >= _loopPointB!) {
        _seekTo(_loopPointA!);
      }
      final nextSeg = _activeSegment;
      final curSeg = _activeSegmentNotifier.value;
      if (nextSeg?.type != curSeg?.type || nextSeg?.endTicks != curSeg?.endTicks) {
        _activeSegmentNotifier.value = nextSeg;
      }
      final quickSkipEligible = !_quickSkipIntroDismissed &&
          _segments.isEmpty &&
          _currentItem.type == 'Episode' &&
          _durationSecs > 600 &&
          secs >= 2.0 &&
          secs < 240.0;
      if (_quickSkipEligibleNotifier.value != quickSkipEligible) {
        _quickSkipEligibleNotifier.value = quickSkipEligible;
      }
      _syncNowPlaying();
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
        _syncNowPlaying(force: true);
        if (_chapters.isEmpty) {
          unawaited(_loadChapters());
        }
      }
    }));
    _subs.add(_player.stream.completed.listen((done) {
      if (!done || !mounted) return;
      if (_isLocalFile) {
        unawaited(widget.appState.saveLocalResumeSecs(_activeLocalPath!, 0.0));
        unawaited(widget.appState.recordLocalHistory(
          title: _currentItem.displayName,
          target: _activeLocalPath!,
          isNetworkUrl: false,
          positionSecs: 0.0,
          durationSecs: _durationSecs,
        ));
      } else if (_isServerStream && !widget.appState.prefs.incognitoMode && _durationSecs > 0) {
        // Explicitly report completion at full duration so Emby/Jellyfin marks the item watched
        final doneTicks = (_durationSecs * 10000000).round();
        unawaited(widget.appState.core
            .invoke('report_playback_stopped', {
              'item_id': _currentItem.id,
              if (_prepared?.mediaSourceId != null) 'media_source_id': _prepared!.mediaSourceId,
              if (_prepared?.playSessionId != null) 'play_session_id': _prepared!.playSessionId,
              if (_prepared?.streamId != null) 'stream_id': _prepared!.streamId,
              'position_ticks': doneTicks,
              'run_time_ticks': doneTicks,
              'is_paused': true,
            })
            .catchError((_) => null));
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _hasEndedReplay && _replayFocusNode.canRequestFocus) {
            _replayFocusNode.requestFocus();
          }
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
    if (!mounted || _disposed) return;
    _statusBarTimer?.cancel();
    _statusBarTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && !_disposed) unawaited(_refreshMobileStatusBar());
    });
  }

  void _syncNowPlaying({bool force = false}) {
    if (_disposed) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final title = _currentItem.seriesName != null
        ? '${_currentItem.seriesName} ${_currentItem.episodeCode ?? ''}'.trim()
        : _currentItem.displayName;
    final subtitle = _currentItem.seriesName != null ? _currentItem.displayName : '';
    final sig = '$title|$subtitle|${!_paused}|${_durationSecs.round()}|${_speed.toStringAsFixed(2)}';
    if (!force && sig == _lastNowPlayingSig && nowMs - _lastNowPlayingTickMs < 2000) return;
    _lastNowPlayingSig = sig;
    _lastNowPlayingTickMs = nowMs;
    unawaited(NativePlaybackChannel.updateNowPlaying(
      title: title,
      subtitle: subtitle,
      durationSecs: _durationSecs,
      positionSecs: _positionSecs,
      playing: !_paused,
      speed: _speed,
      hasNext: _nextEpisode != null,
      hasPrevious: _prevEpisode != null,
    ));
  }

  void _onNativeMediaAction() {
    if (!mounted || _disposed) return;
    final payload = NativePlaybackChannel.mediaActionNotifier.value;
    if (payload == null || payload.isEmpty) return;
    NativePlaybackChannel.mediaActionNotifier.value = null;
    final action = (payload['action'] ?? '').toString().toLowerCase();
    if (action.isEmpty) return;
    final step = widget.appState.prefs.seekStepSecs.toDouble();
    switch (action) {
      case 'play':
        unawaited(_player.play());
        break;
      case 'pause':
        unawaited(_player.pause());
        break;
      case 'toggle':
      case 'toggle_play':
        unawaited(_togglePause());
        break;
      case 'next':
        if (_nextEpisode != null) unawaited(_switchEpisode(_nextEpisode!));
        break;
      case 'prev':
      case 'previous':
        if (_prevEpisode != null) unawaited(_switchEpisode(_prevEpisode!));
        break;
      case 'seek_fwd':
        unawaited(_seekBy(step, showHud: true));
        break;
      case 'seek_back':
        unawaited(_seekBy(-step, showHud: true));
        break;
      case 'seek':
        final posSecs = (payload['position_secs'] as num?)?.toDouble();
        final posMs = (payload['position_ms'] as num?)?.toDouble();
        final target = posSecs ?? (posMs != null ? posMs / 1000.0 : null);
        if (target != null && target.isFinite && target >= 0) {
          unawaited(_seekTo(target));
        }
        break;
      case 'duck':
        if (!_audioDucked && !_muted) {
          _audioDucked = true;
          unawaited(_applyVolumeToEngine((_volume * 0.25).clamp(0.0, 40.0)));
        }
        break;
      case 'unduck':
        if (_audioDucked) {
          _audioDucked = false;
          unawaited(_applyVolumeToEngine(_muted ? 0.0 : _volume));
        }
        break;
      case 'stop':
        unawaited(_requestExit());
        break;
    }
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
    _enteringPip = false;
    _enteringPipResetTimer?.cancel();
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

  Future<void> _enterPipSafely() async {
    _enteringPip = true;
    _enteringPipResetTimer?.cancel();
    _enteringPipResetTimer = Timer(const Duration(milliseconds: 1600), () {
      _enteringPip = false;
    });
    final ok = await NativePlaybackChannel.enterPictureInPicture(
      aspectW: _videoWidth,
      aspectH: _videoHeight,
    );
    if (!ok) {
      _enteringPip = false;
      _enteringPipResetTimer?.cancel();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      unawaited(_flushCurrentProgress());
      if (!widget.appState.prefs.backgroundAudio && !_inPipMode && !_enteringPip && !_paused) {
        unawaited(_player.pause());
      }
    } else if (state == AppLifecycleState.resumed) {
      _enteringPip = false;
      if (!_paused) {
        NativePlaybackChannel.setKeepScreenOn(true);
      }
    }
  }

  Future<void> _flushCurrentProgress() async {
    if (widget.appState.prefs.incognitoMode) return;
    if (_isLocalFile) {
      if (_positionSecs > 3.0) {
        await widget.appState.saveLocalResumeSecs(_activeLocalPath!, _positionSecs);
        await widget.appState.recordLocalHistory(
          title: _currentItem.displayName,
          target: _activeLocalPath!,
          isNetworkUrl: false,
          positionSecs: _positionSecs,
          durationSecs: _durationSecs,
        );
      }
      return;
    }
    if (_isDirectNetwork) {
      if (_positionSecs > 3.0) {
        await widget.appState.recordLocalHistory(
          title: _currentItem.displayName,
          target: _activeNetworkUrl!,
          isNetworkUrl: true,
          positionSecs: _positionSecs,
          durationSecs: _durationSecs,
        );
      }
      return;
    }
    if (_prepared == null) return;
    try {
      await widget.appState.core.invoke('report_playback_progress', {
        'item_id': _currentItem.id,
        'media_source_id': _prepared!.mediaSourceId,
        'play_session_id': _prepared!.playSessionId,
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

    // 2. Automatic transient network / stream-ticket retry (up to 2x, bounded until real 2s progress!)
    if (!_isLocalFile &&
        _autoRetryCount < 2 &&
        (lower.contains('http') ||
            lower.contains('tcp') ||
            lower.contains('eof') ||
            lower.contains('timeout') ||
            lower.contains('network') ||
            lower.contains('connection') ||
            lower.contains('failed to open'))) {
      _autoRetryCount += 1;
      _retryAnchorSecs = _positionSecs;
      final attempt = _autoRetryCount;
      final retryGen = _playbackGen;
      _flashGestureHud('seek_feedback', text: '网络波动，正在自动重连（第 $attempt/2 次）…');
      unawaited(() async {
        try {
          if (_isServerStream && _prepared?.usesStreamTicket == true) {
            await widget.appState.core.invoke('refresh_stream_ticket');
          }
        } catch (_) {}
        await Future<void>.delayed(Duration(milliseconds: 800 * attempt));
        if (!mounted || _disposed || retryGen != _playbackGen) return;
        await _startPlayback(_prepared?.mediaSourceId, resumeFromSecs: _positionSecs);
      }());
      return;
    }

    setState(() {
      _error = err;
      _loading = false;
      _controlsVisible = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _error != null && _errorRetryFocusNode.canRequestFocus) {
        _errorRetryFocusNode.requestFocus();
      }
    });
  }

  void _startUpNextCountdown() {
    _upNextTimer?.cancel();
    setState(() {
      _upNextCountdown = 6;
      _controlsVisible = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _upNextCountdown > 0 && _upNextPlayFocusNode.canRequestFocus) {
        _upNextPlayFocusNode.requestFocus();
      }
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
        unawaited(_switchEpisode(_nextEpisode!, overridePositionSecs: _durationSecs));
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
    if (!mounted || _disposed || !_isServerStream) return;
    final realAudios = tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final realSubs = tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
    if (realAudios.isEmpty && realSubs.isEmpty) return;

    final srcId = (_prepared?.mediaSourceId.isNotEmpty == true)
        ? _prepared!.mediaSourceId
        : ((widget.mediaSourceId != null && widget.mediaSourceId!.isNotEmpty)
            ? widget.mediaSourceId!
            : (_prepared?.allSources.isNotEmpty == true ? _prepared!.allSources.first.id : 'default'));
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
    final rot = (vp.rotate ?? _videoRotate) % 360;
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
      final pickedPath = await showDialog<String>(
        context: context,
        builder: (ctx) => VedroControllerScope<TextEditingController>(
          create: () => TextEditingController(),
          dispose: (c) => c.dispose(),
          builder: (ctx, ctrl) => AlertDialog(
            title: const Text('加载本地外挂字幕'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: '/path/to/subtitle.ass'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('加载'),
              ),
            ],
          ),
        ),
      );
      if (mounted && pickedPath != null && pickedPath.isNotEmpty) {
        await _loadExternalSubtitleFile(pickedPath);
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
    final parsed = <({String title, double timeSecs})>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw);
        if (list is List) {
          for (var i = 0; i < list.length; i++) {
            final item = list[i];
            if (item is Map) {
              final t = (item['time'] as num?)?.toDouble() ?? 0.0;
              final title = (item['title']?.toString().trim() ?? '');
              parsed.add((title: title.isEmpty ? '章节 ${i + 1}' : title, timeSecs: t));
            }
          }
        }
      } catch (_) {}
    }
    if (parsed.isEmpty && _currentItem.chapters.isNotEmpty) {
      for (var i = 0; i < _currentItem.chapters.length; i++) {
        final ch = _currentItem.chapters[i];
        parsed.add((
          title: ch.name.trim().isEmpty ? '章节 ${i + 1}' : ch.name.trim(),
          timeSecs: ch.startPositionTicks / 10000000.0,
        ));
      }
    }
    if (mounted && parsed.isNotEmpty) {
      setState(() => _chapters = parsed);
    }
  }

  Future<void> _jumpChapter(bool next) async {
    if (_chapters.isEmpty) return;
    var curIdx = 0;
    for (var i = 0; i < _chapters.length; i++) {
      if (_positionSecs >= _chapters[i].timeSecs - 0.5) curIdx = i;
    }
    final targetIdx = next
        ? (curIdx + 1).clamp(0, _chapters.length - 1)
        : ((_positionSecs - _chapters[curIdx].timeSecs > 3.0) ? curIdx : (curIdx - 1).clamp(0, _chapters.length - 1));
    final target = _chapters[targetIdx];
    await _seekTo(target.timeSecs);
    _flashGestureHud('seek_feedback', text: '${next ? '下一章' : '上一章'}：${target.title}');
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
    final platform = _player.platform;
    var stepped = false;
    if (platform is NativePlayer) {
      try {
        await platform.command([forward ? 'frame-step' : 'frame-back-step']);
        stepped = true;
      } catch (_) {}
    }
    if (!stepped) {
      await _seekBy(forward ? 0.042 : -0.042);
    }
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

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    NativePlaybackChannel.audioInterruptCountNotifier.removeListener(_onAudioInterrupted);
    NativePlaybackChannel.pipModeNotifier.removeListener(_onPipModeChanged);
    NativePlaybackChannel.mediaActionNotifier.removeListener(_onNativeMediaAction);
    unawaited(NativePlaybackChannel.updateNowPlaying(title: '', playing: false, active: false));
    unawaited(NativePlaybackChannel.setAutoPipEnabled(false));
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
    _enteringPipResetTimer?.cancel();
    _beautyShaderDebounce?.cancel();
    _focusNode.dispose();
    _playPauseFocusNode.dispose();
    _unlockFocusNode.dispose();
    _drawerCloseFocusNode.dispose();
    _drawerActiveEpFocusNode.dispose();
    _upNextPlayFocusNode.dispose();
    _replayFocusNode.dispose();
    _errorRetryFocusNode.dispose();
    _skipIntroFocusNode.dispose();
    _positionNotifier.dispose();
    _bufferedNotifier.dispose();
    _activeSegmentNotifier.dispose();
    _quickSkipEligibleNotifier.dispose();
    _networkSpeedBpsNotifier.dispose();
    _sleepRemainingNotifier.dispose();
    _statsNotifier.dispose();
    _gestureHudNotifier.dispose();
    _statusBarNotifier.dispose();
    _aiSubCtrl.dispose();
    unawaited(LocalAsrManager.instance.unloadEngine());
    _persistRememberedPlayerPrefs(notify: false);
    if (!widget.appState.prefs.incognitoMode && _positionSecs > 3.0) {
      final done = _durationSecs > 0 && _positionSecs >= _durationSecs - 15.0;
      if (_isLocalFile) {
        unawaited(widget.appState.saveLocalResumeSecs(_activeLocalPath!, done ? 0.0 : _positionSecs));
        unawaited(widget.appState.recordLocalHistory(
          title: _currentItem.displayName,
          target: _activeLocalPath!,
          isNetworkUrl: false,
          positionSecs: done ? 0.0 : _positionSecs,
          durationSecs: _durationSecs,
        ));
      } else if (_isDirectNetwork) {
        unawaited(widget.appState.recordLocalHistory(
          title: _currentItem.displayName,
          target: _activeNetworkUrl!,
          isNetworkUrl: true,
          positionSecs: done ? 0.0 : _positionSecs,
          durationSecs: _durationSecs,
        ));
      }
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

  void _setPlayerState(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) => _buildPlayerScaffold(context);
}
