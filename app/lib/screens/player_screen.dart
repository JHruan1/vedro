import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/models/models.dart';
import '../core/platform/native_playback_channel.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/nerd_stats_hud.dart';
import '../widgets/vedro_ui.dart';

/// Apple TV+ / Infuse style native cinema player with full touch & keyboard gestures:
/// - Single tap: toggle auto-hiding frosted HUD
/// - Double tap left / right / center: -10s / +10s / play-pause
/// - Horizontal drag: precision scrub with live frosted time & delta HUD
/// - Left vertical drag: smooth screen brightness dimmer HUD
/// - Right vertical drag: smooth volume HUD
/// - Long press: 2.0× speed boost with floating pill
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.item,
    required this.appState,
    this.mediaSourceId,
  });

  final MediaItemModel item;
  final VedroAppState appState;
  final String? mediaSourceId;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;

  PreparedPlaybackModel? _prepared;
  Map<String, dynamic> _stats = {};
  bool _loading = true;
  String? _error;

  bool _controlsVisible = true;
  bool _showStats = false;
  bool _paused = false;
  double _positionSecs = 0;
  double _durationSecs = 0;
  double _speed = 1.0;
  double _preBoostSpeed = 1.0;
  bool _isSpeedBoost = false;
  double _volume = 100.0;
  double _brightness = 1.0;
  double _subDelaySecs = 0.0;
  String _toneMapping = 'bt.2446a';
  String _audioMode = 'auto';
  bool _nightMode = false;
  bool _dialogueBoost = false;

  // Interactive gesture HUD state
  bool _scrubbing = false;
  double _scrubStartSecs = 0;
  double _scrubTargetSecs = 0;
  String? _gestureMode; // 'brightness' | 'volume' | 'seek_feedback'
  String _seekFeedbackText = '';
  Offset _lastTapDownPos = Offset.zero;

  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _hideControlsTimer;
  Timer? _gestureHudTimer;
  Timer? _statsTimer;
  Timer? _progressTimer;
  Timer? _ticketRefreshTimer;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    NativePlaybackChannel.setKeepScreenOn(true);

    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 128 * 1024 * 1024,
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
        setState(() => _positionSecs = pos.inMilliseconds / 1000.0);
      }
    }));
    _subs.add(_player.stream.duration.listen((dur) {
      if (mounted && dur.inMilliseconds > 0) {
        setState(() => _durationSecs = dur.inMilliseconds / 1000.0);
      }
    }));
    _subs.add(_player.stream.error.listen((err) {
      if (mounted && err.isNotEmpty) {
        setState(() => _error = err);
      }
    }));

    _startPlayback(widget.mediaSourceId);
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
    NativePlaybackChannel.setKeepScreenOn(false);
    _reportStoppedAndCleanup();
    _player.dispose();
    super.dispose();
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    if (_paused || _loading) return;
    _hideControlsTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted && !_paused && !_scrubbing) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _revealControls() {
    setState(() => _controlsVisible = true);
    _scheduleHideControls();
  }

  void _flashGestureHud(String mode, {String text = ''}) {
    _gestureHudTimer?.cancel();
    setState(() {
      _gestureMode = mode;
      if (text.isNotEmpty) _seekFeedbackText = text;
    });
    _gestureHudTimer = Timer(const Duration(milliseconds: 900), () {
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

  Future<void> _startPlayback(String? sourceId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prepRaw = await widget.appState.core.invoke('prepare_playback', {
        'item_id': widget.item.id,
        if (sourceId != null) 'media_source_id': sourceId,
        'inspect_header': true,
      }) as Map<String, dynamic>;

      final prep = PreparedPlaybackModel.fromJson(prepRaw);

      const skipKeys = {'vo', 'ao', 'gpu-api', 'gpu-context'};
      for (final entry in prep.mpvOptions.entries) {
        if (skipKeys.contains(entry.key)) continue;
        await _applyMpvProperty(entry.key, entry.value);
      }
      await _applyMpvProperty('hwdec', 'auto-safe');
      await _applyMpvProperty('hwdec-codecs', 'all');
      await _applyMpvProperty('target-colorspace-hint', 'yes');
      await _applyMpvProperty('hdr-compute-peak', 'yes');
      await _applyMpvProperty('tone-mapping', _toneMapping);

      final startDur = widget.item.playbackPositionTicks > 0
          ? Duration(microseconds: widget.item.playbackPositionTicks ~/ 10)
          : null;

      await _player.open(
        Media(prep.proxyUrl, start: startDur),
        play: true,
      );

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

      await widget.appState.core.invoke('report_playback_start', {
        'position_ticks': widget.item.playbackPositionTicks,
        if (widget.item.runTimeTicks != null) 'run_time_ticks': widget.item.runTimeTicks,
        'is_paused': false,
      });

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
    try {
      await widget.appState.core.invoke('report_playback_stopped', {
        'position_ticks': (_positionSecs * 10000000).round(),
        if (_durationSecs > 0) 'run_time_ticks': (_durationSecs * 10000000).round(),
        'is_paused': true,
      });
      await widget.appState.core.invoke('player_stop');
    } catch (_) {}
  }

  Future<void> _togglePause() async {
    await _player.playOrPause();
    _revealControls();
  }

  Future<void> _seekTo(double secs) async {
    final target = secs.clamp(0.0, _durationSecs > 0 ? _durationSecs : 86400.0);
    await _player.seek(Duration(milliseconds: (target * 1000).round()));
    if (mounted) setState(() => _positionSecs = target);
  }

  Future<void> _seekBy(double delta, {bool showHud = false}) async {
    await _seekTo(_positionSecs + delta);
    if (showHud) {
      final sign = delta >= 0 ? '+' : '';
      _flashGestureHud('seek_feedback', text: '$sign${delta.round()}s');
    }
  }

  Future<void> _setSpeed(double s) async {
    final clamped = s.clamp(0.25, 4.0);
    await _player.setRate(clamped);
    if (mounted) setState(() => _speed = clamped);
  }

  void _handleDoubleTap(double width) {
    final ratio = width > 0 ? _lastTapDownPos.dx / width : 0.5;
    if (ratio < 0.35) {
      _seekBy(-10, showHud: true);
    } else if (ratio > 0.65) {
      _seekBy(10, showHud: true);
    } else {
      _togglePause();
    }
  }

  void _handleKey(KeyEvent ev) {
    if (ev is! KeyDownEvent) return;
    final key = ev.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      _togglePause();
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(10, showHud: true);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-10, showHud: true);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _volume = (_volume + 5).clamp(0, 150);
      _player.setVolume(_volume);
      _flashGestureHud('volume');
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _volume = (_volume - 5).clamp(0, 150);
      _player.setVolume(_volume);
      _flashGestureHud('volume');
    } else if (key == LogicalKeyboardKey.keyI) {
      setState(() => _showStats = !_showStats);
    } else if (key == LogicalKeyboardKey.bracketRight) {
      _setSpeed(_speed + 0.25);
    } else if (key == LogicalKeyboardKey.bracketLeft) {
      _setSpeed(_speed - 0.25);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final specs = <String>[
      if (_prepared?.dolbyVisionLabel != null) _prepared!.dolbyVisionLabel!,
      if (_prepared?.spatialAudioLabel != null) _prepared!.spatialAudioLabel!,
    ];

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          onHover: (_) {
            if (!_controlsVisible) _revealControls();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _lastTapDownPos = d.localPosition,
            onTap: () {
              if (_controlsVisible) {
                _hideControlsTimer?.cancel();
                setState(() => _controlsVisible = false);
              } else {
                _revealControls();
              }
            },
            onDoubleTap: () => _handleDoubleTap(size.width),
            onLongPressStart: (_) {
              _preBoostSpeed = _speed;
              setState(() => _isSpeedBoost = true);
              _setSpeed(2.0);
            },
            onLongPressEnd: (_) {
              setState(() => _isSpeedBoost = false);
              _setSpeed(_preBoostSpeed);
            },
            onHorizontalDragStart: (_) {
              if (_durationSecs <= 0) return;
              _hideControlsTimer?.cancel();
              setState(() {
                _scrubbing = true;
                _scrubStartSecs = _positionSecs;
                _scrubTargetSecs = _positionSecs;
              });
            },
            onHorizontalDragUpdate: (d) {
              if (!_scrubbing) return;
              final deltaSecs = (d.delta.dx / size.width) * 180.0;
              setState(() {
                _scrubTargetSecs = (_scrubTargetSecs + deltaSecs).clamp(0.0, _durationSecs);
              });
            },
            onHorizontalDragEnd: (_) {
              if (!_scrubbing) return;
              final target = _scrubTargetSecs;
              setState(() => _scrubbing = false);
              _seekTo(target);
              _scheduleHideControls();
            },
            onVerticalDragUpdate: (d) {
              final delta = -d.delta.dy / (size.height * 0.55);
              if (_lastTapDownPos.dx < size.width * 0.5) {
                setState(() => _brightness = (_brightness + delta).clamp(0.15, 1.0));
                _flashGestureHud('brightness');
              } else {
                setState(() => _volume = (_volume + delta * 100).clamp(0.0, 150.0));
                _player.setVolume(_volume);
                _flashGestureHud('volume');
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                Video(
                  controller: _videoController,
                  controls: NoVideoControls,
                  fill: Colors.black,
                ),

                // Smooth software brightness dimmer overlay (left-side vertical swipe)
                if (_brightness < 0.99)
                  IgnorePointer(
                    child: Container(
                      color: Colors.black.withValues(alpha: (1.0 - _brightness).clamp(0.0, 0.85)),
                    ),
                  ),

                if (_loading)
                  const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: VedroTheme.fg,
                      ),
                    ),
                  ),

                if (_error != null)
                  Positioned(
                    bottom: 116,
                    left: 24,
                    right: 24,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: GlassSurface(
                          borderRadius: 12,
                          color: const Color(0xD8241214),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: VedroTheme.danger, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Long-press 2× speed pill
                if (_isSpeedBoost)
                  Positioned(
                    top: 44,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GlassSurface(
                        borderRadius: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fast_forward_rounded, size: 15, color: VedroTheme.fg),
                            SizedBox(width: 6),
                            Text(
                              '2.0×',
                              style: TextStyle(
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

                // Precision scrub HUD
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

                // Brightness / Volume / ±10s gesture feedback HUD
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
                    top: 84,
                    left: 24,
                    child: NerdStatsHud(stats: _stats),
                  ),

                // Auto-hiding Apple TV+ frosted top & bottom chrome
                IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Stack(
                      children: [
                        // Top bar
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: EdgeInsets.fromLTRB(
                              20,
                              MediaQuery.paddingOf(context).top + 12,
                              20,
                              24,
                            ),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xB8000000), Colors.transparent],
                              ),
                            ),
                            child: Row(
                              children: [
                                PressableScale(
                                  onTap: () => Navigator.of(context).pop(),
                                  child: GlassSurface(
                                    borderRadius: 20,
                                    blur: 18,
                                    color: const Color(0x55141417),
                                    padding: const EdgeInsets.all(9),
                                    child: const Icon(
                                      Icons.arrow_back_ios_new_rounded,
                                      size: 16,
                                      color: VedroTheme.fg,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        widget.item.seriesName != null
                                            ? '${widget.item.seriesName} ${widget.item.episodeCode ?? ''} · ${widget.item.name}'
                                            : widget.item.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: VedroTheme.fg,
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                      if (specs.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        SpecGlyphRow(specs: specs),
                                      ],
                                    ],
                                  ),
                                ),
                                _ChromeIconButton(
                                  icon: Icons.info_outline_rounded,
                                  active: _showStats,
                                  tooltip: '播放信息 (I)',
                                  onTap: () => setState(() => _showStats = !_showStats),
                                ),
                                const SizedBox(width: 8),
                                _ChromeIconButton(
                                  icon: Icons.picture_in_picture_alt_rounded,
                                  tooltip: '画中画',
                                  onTap: NativePlaybackChannel.enterPictureInPicture,
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Floating frosted bottom deck
                        Positioned(
                          left: 20,
                          right: 20,
                          bottom: MediaQuery.paddingOf(context).bottom + 18,
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 820),
                              child: GlassSurface(
                                borderRadius: 18,
                                blur: 28,
                                color: const Color(0xBA141417),
                                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        SizedBox(
                                          width: 56,
                                          child: Text(
                                            _fmtTime(_scrubbing ? _scrubTargetSecs : _positionSecs),
                                            style: const TextStyle(
                                              color: VedroTheme.fg2,
                                              fontSize: 12,
                                              fontFeatures: [FontFeature.tabularFigures()],
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Slider(
                                            value: (_scrubbing ? _scrubTargetSecs : _positionSecs)
                                                .clamp(0.0, _durationSecs > 0 ? _durationSecs : 1.0),
                                            max: _durationSecs > 0 ? _durationSecs : 1.0,
                                            onChangeStart: (_) => _hideControlsTimer?.cancel(),
                                            onChanged: (v) => setState(() => _positionSecs = v),
                                            onChangeEnd: (v) {
                                              _seekTo(v);
                                              _scheduleHideControls();
                                            },
                                          ),
                                        ),
                                        SizedBox(
                                          width: 56,
                                          child: Text(
                                            _fmtTime(_durationSecs),
                                            textAlign: TextAlign.right,
                                            style: const TextStyle(
                                              color: VedroTheme.fg3,
                                              fontSize: 12,
                                              fontFeatures: [FontFeature.tabularFigures()],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        _ChromeIconButton(
                                          icon: Icons.replay_10_rounded,
                                          onTap: () => _seekBy(-10, showHud: true),
                                        ),
                                        const SizedBox(width: 4),
                                        _ChromeIconButton(
                                          icon: _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                                          iconSize: 28,
                                          onTap: _togglePause,
                                        ),
                                        const SizedBox(width: 4),
                                        _ChromeIconButton(
                                          icon: Icons.forward_10_rounded,
                                          onTap: () => _seekBy(10, showHud: true),
                                        ),
                                        const Spacer(),
                                        GestureDetector(
                                          onTap: _openSpeedSheet,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                            decoration: BoxDecoration(
                                              color: const Color(0x16FFFFFF),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              '${_speed.toStringAsFixed(_speed == _speed.roundToDouble() ? 1 : 2)}×',
                                              style: const TextStyle(
                                                color: VedroTheme.fg,
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w500,
                                                fontFeatures: [FontFeature.tabularFigures()],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        _ChromeIconButton(
                                          icon: Icons.hdr_on_rounded,
                                          tooltip: 'HDR 与杜比视界',
                                          onTap: _openHdrSheet,
                                        ),
                                        _ChromeIconButton(
                                          icon: Icons.spatial_audio_off_rounded,
                                          tooltip: '音轨与杜比全景声',
                                          onTap: _openAudioSheet,
                                        ),
                                        _ChromeIconButton(
                                          icon: Icons.subtitles_outlined,
                                          tooltip: '字幕',
                                          onTap: _openSubtitleSheet,
                                        ),
                                        if ((_prepared?.allSources.length ?? 0) > 1)
                                          _ChromeIconButton(
                                            icon: Icons.layers_outlined,
                                            tooltip: '切换版本',
                                            onTap: _openVersionSheet,
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
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
    final progress = isBrightness ? _brightness : (_volume / 150.0).clamp(0.0, 1.0);
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
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('HDR 与杜比视界', style: TextStyle(color: VedroTheme.fg, fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          if (_prepared != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              child: Text(_prepared!.hdrExplanation, style: const TextStyle(color: VedroTheme.fg3, fontSize: 12.5)),
            ),
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
              child: Text('字幕', style: TextStyle(color: VedroTheme.fg, fontSize: 16, fontWeight: FontWeight.w600)),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Text('时间偏移', style: TextStyle(color: VedroTheme.fg2, fontSize: 13.5)),
                  const SizedBox(width: 10),
                  Text(
                    '${_subDelaySecs >= 0 ? '+' : ''}${_subDelaySecs.toStringAsFixed(1)}s',
                    style: const TextStyle(
                      color: VedroTheme.fg,
                      fontSize: 13,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  _ChromeIconButton(
                    icon: Icons.remove_rounded,
                    onTap: () async {
                      setModal(() => _subDelaySecs -= 0.2);
                      await _applyMpvProperty('sub-delay', _subDelaySecs.toStringAsFixed(2));
                    },
                  ),
                  const SizedBox(width: 6),
                  _ChromeIconButton(
                    icon: Icons.add_rounded,
                    onTap: () async {
                      setModal(() => _subDelaySecs += 0.2);
                      await _applyMpvProperty('sub-delay', _subDelaySecs.toStringAsFixed(2));
                    },
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

class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.active = false,
    this.iconSize = 20,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool active;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final btn = PressableScale(
      onTap: onTap,
      hoverScale: 1.06,
      pressScale: 0.9,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active ? const Color(0x28FFFFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: iconSize,
          color: active ? VedroTheme.accent : VedroTheme.fg,
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: btn) : btn;
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
                    style: const TextStyle(
                      color: VedroTheme.fg,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: const TextStyle(color: VedroTheme.fg3, fontSize: 12)),
                  ],
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_rounded, size: 18, color: VedroTheme.accent),
          ],
        ),
      ),
    );
  }
}
