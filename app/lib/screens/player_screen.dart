import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/models/models.dart';
import '../core/platform/native_playback_channel.dart';
import '../core/theme/prism_theme.dart';
import '../state/app_state.dart';
import '../widgets/badge_strip.dart';
import '../widgets/nerd_stats_hud.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.item,
    required this.appState,
    this.mediaSourceId,
  });

  final MediaItemModel item;
  final PrismAppState appState;
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
  double _volume = 100.0;
  double _subDelaySecs = 0.0;
  String _toneMapping = 'bt2446a';
  String _audioMode = 'auto';
  bool _nightMode = false;
  bool _dialogueBoost = false;

  final List<StreamSubscription<dynamic>> _subs = [];
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
      if (mounted) setState(() => _paused = !playing);
    }));
    _subs.add(_player.stream.position.listen((pos) {
      if (mounted) setState(() => _positionSecs = pos.inMilliseconds / 1000.0);
    }));
    _subs.add(_player.stream.duration.listen((dur) {
      if (mounted && dur.inMilliseconds > 0) {
        setState(() => _durationSecs = dur.inMilliseconds / 1000.0);
      }
    }));
    _subs.add(_player.stream.error.listen((err) {
      if (mounted && err.isNotEmpty) {
        setState(() => _error = '播放内核提示: $err');
      }
    }));

    _startPlayback(widget.mediaSourceId);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _statsTimer?.cancel();
    _progressTimer?.cancel();
    _ticketRefreshTimer?.cancel();
    _focusNode.dispose();
    NativePlaybackChannel.setKeepScreenOn(false);
    _reportStoppedAndCleanup();
    _player.dispose();
    super.dispose();
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
      // 1. Rust Core negotiates PlaybackInfo, mints StreamTicket, starts bounded Range Proxy (<=2 conns),
      //    runs binary MKV/MP4 Dolby Vision & Atmos inspector, and computes optimal libmpv options!
      final prepRaw = await widget.appState.core.invoke('prepare_playback', {
        'item_id': widget.item.id,
        if (sourceId != null) 'media_source_id': sourceId,
        'inspect_header': true,
      }) as Map<String, dynamic>;

      final prep = PreparedPlaybackModel.fromJson(prepRaw);

      // 2. Apply Rust-computed Dolby Vision / HDR10+ / HWDec / Dolby Atmos properties onto bundled libmpv
      const skipKeys = {'vo', 'ao', 'gpu-api', 'gpu-context'};
      for (final entry in prep.mpvOptions.entries) {
        if (skipKeys.contains(entry.key)) continue;
        await _applyMpvProperty(entry.key, entry.value);
      }
      // Enable zero-copy hardware decoding + Dolby Vision RPU tone mapping
      await _applyMpvProperty('hwdec', 'auto-safe');
      await _applyMpvProperty('hwdec-codecs', 'all');
      await _applyMpvProperty('target-colorspace-hint', 'yes');
      await _applyMpvProperty('hdr-compute-peak', 'yes');
      await _applyMpvProperty('tone-mapping', _toneMapping);

      // 3. Open local Rust Range proxy URL in GPU-accelerated libmpv VideoController!
      final startDur = widget.item.playbackPositionTicks > 0
          ? Duration(microseconds: widget.item.playbackPositionTicks ~/ 10)
          : null;

      await _player.open(
        Media(prep.proxyUrl, start: startDur),
        play: true,
      );

      // 4. Attach default external sidecar subtitle from embygo/Emby if present
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

      // 5. Report playback start to embygo / Emby / Jellyfin
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

    // Keep embygo's 5-minute session freshness active and sync progress every 10s
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

    // Proactively hot-swap embygo StreamTicket every 7 minutes so long pauses never expire!
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
  }

  Future<void> _seekTo(double secs) async {
    final target = secs.clamp(0.0, _durationSecs > 0 ? _durationSecs : 86400.0);
    await _player.seek(Duration(milliseconds: (target * 1000).round()));
    setState(() => _positionSecs = target);
  }

  Future<void> _seekBy(double delta) async {
    await _seekTo(_positionSecs + delta);
  }

  Future<void> _setSpeed(double s) async {
    final clamped = s.clamp(0.25, 4.0);
    await _player.setRate(clamped);
    setState(() => _speed = clamped);
  }

  void _handleKey(KeyEvent ev) {
    if (ev is! KeyDownEvent) return;
    final key = ev.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      _togglePause();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(10);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-10);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _volume = (_volume + 5).clamp(0, 150);
      _player.setVolume(_volume);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _volume = (_volume - 5).clamp(0, 150);
      _player.setVolume(_volume);
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
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _controlsVisible = !_controlsVisible),
          onDoubleTap: _togglePause,
          onLongPressStart: (_) => _setSpeed(2.0),
          onLongPressEnd: (_) => _setSpeed(1.0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // REAL hardware-accelerated GPU Video Surface (libmpv + Vulkan/Metal/D3D11/MediaCodec)
              Video(
                controller: _videoController,
                controls: NoVideoControls,
                fill: Colors.black,
              ),
              if (_loading)
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 14),
                      Text('正在建立 Rust DirectPlay 缓存与杜比视界/全景声管线...'),
                    ],
                  ),
                ),
              if (_error != null)
                Positioned(
                  bottom: 110,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_error!, style: const TextStyle(color: Colors.white)),
                  ),
                ),
              if (_showStats)
                Positioned(
                  top: 76,
                  left: 20,
                  child: NerdStatsHud(stats: _stats),
                ),
              if (_controlsVisible) ...[
                // Top bar
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 36, 16, 18),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xCC000000), Colors.transparent],
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.item.seriesName != null
                                    ? '${widget.item.seriesName} ${widget.item.episodeCode ?? ''} · ${widget.item.name}'
                                    : widget.item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                              if (_prepared != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: BadgeStrip(
                                    compact: true,
                                    badges: [
                                      'DirectPlay',
                                      if (_prepared!.dolbyVisionLabel != null) _prepared!.dolbyVisionLabel!,
                                      if (_prepared!.spatialAudioLabel != null) _prepared!.spatialAudioLabel!,
                                      if (_prepared!.usesStreamTicket) 'StreamTicket',
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '硬件/码流统计 (I)',
                          icon: Icon(Icons.analytics_outlined, color: _showStats ? PrismTheme.accent : null),
                          onPressed: () => setState(() => _showStats = !_showStats),
                        ),
                        IconButton(
                          tooltip: '画中画',
                          icon: const Icon(Icons.picture_in_picture_alt_rounded),
                          onPressed: NativePlaybackChannel.enterPictureInPicture,
                        ),
                      ],
                    ),
                  ),
                ),
                // Bottom control deck
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xDD000000), Colors.transparent],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(_fmtTime(_positionSecs), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                            Expanded(
                              child: Slider(
                                value: _positionSecs.clamp(0.0, _durationSecs > 0 ? _durationSecs : 1.0),
                                max: _durationSecs > 0 ? _durationSecs : 1.0,
                                onChanged: _seekTo,
                              ),
                            ),
                            Text(_fmtTime(_durationSecs), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.replay_10_rounded),
                              onPressed: () => _seekBy(-10),
                            ),
                            IconButton(
                              iconSize: 38,
                              icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                              onPressed: _togglePause,
                            ),
                            IconButton(
                              icon: const Icon(Icons.forward_10_rounded),
                              onPressed: () => _seekBy(10),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () => _setSpeed(_speed >= 2.0 ? 1.0 : _speed + 0.25),
                              child: Text('${_speed.toStringAsFixed(2)}x'),
                            ),
                            IconButton(
                              tooltip: '杜比视界 & HDR 映射',
                              icon: const Icon(Icons.hdr_on_rounded, color: PrismTheme.dolbyGold),
                              onPressed: _openHdrSheet,
                            ),
                            IconButton(
                              tooltip: '杜比全景声 & 音轨',
                              icon: const Icon(Icons.surround_sound_rounded, color: PrismTheme.atmosCyan),
                              onPressed: _openAudioSheet,
                            ),
                            IconButton(
                              tooltip: '字幕选择',
                              icon: const Icon(Icons.subtitles_rounded),
                              onPressed: _openSubtitleSheet,
                            ),
                            if ((_prepared?.allSources.length ?? 0) > 1)
                              IconButton(
                                tooltip: '切换版本',
                                icon: const Icon(Icons.layers_rounded),
                                onPressed: _openVersionSheet,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openHdrSheet() {
    const algos = {
      'bt.2446a': 'BT.2446a（推荐：自然色彩与高光保留）',
      'spline': 'Spline（libplacebo 曲线动态映射）',
      'st2094-40': 'ST.2094-40（HDR10+/杜比视界动态元）',
      'reinhard': 'Reinhard（高亮温和压缩）',
      'hable': 'Hable（电影感曲线）',
      'clip': 'Clip（原生 HDR 直通无压缩）',
    };
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            const Text('杜比视界 & HDR 渲染管线', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            if (_prepared != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                child: Text(_prepared!.hdrExplanation, style: const TextStyle(color: PrismTheme.textSecondary, fontSize: 12.5)),
              ),
            ...algos.entries.map((e) {
              final selected = e.key == _toneMapping;
              return ListTile(
                leading: Icon(
                  selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? PrismTheme.dolbyGold : PrismTheme.textSecondary,
                ),
                title: Text(e.value),
                onTap: () async {
                  Navigator.pop(ctx);
                  setState(() => _toneMapping = e.key);
                  await _applyMpvProperty('tone-mapping', e.key);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _openAudioSheet() {
    const modes = {
      'auto': '自动（优先硬件源码直通 / 空间音频）',
      'passthrough_bitstream': 'HDMI 源码直通（TrueHD Atmos / E-AC-3 JOC / DTS:X）',
      'spatial_audio': '系统空间音频（Apple Spatial Audio / Android Spatializer）',
      'headphone_binaural': '耳机双耳空间化（HRTF / BS2B）',
      'pcm_stereo': '发烧级 32-bit Float 立体声 PCM',
    };
    final audioTracks = _player.state.tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              if (audioTracks.isNotEmpty) ...[
                const Text('音轨切换', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ...audioTracks.map((t) {
                  final active = _player.state.track.audio.id == t.id;
                  return ListTile(
                    leading: Icon(active ? Icons.volume_up_rounded : Icons.audiotrack_rounded,
                        color: active ? PrismTheme.atmosCyan : null),
                    title: Text(t.title ?? t.language ?? '音轨 #${t.id}'),
                    subtitle: Text([t.codec, t.language, t.channels].whereType<String>().join(' • ')),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _player.setAudioTrack(t);
                    },
                  );
                }),
                const Divider(),
              ],
              const Text('杜比全景声 & 音频输出', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ...modes.entries.map((e) {
                final selected = e.key == _audioMode;
                return ListTile(
                  leading: Icon(
                    selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: selected ? PrismTheme.atmosCyan : PrismTheme.textSecondary,
                  ),
                  title: Text(e.value),
                  onTap: () async {
                    setModal(() => _audioMode = e.key);
                    setState(() => _audioMode = e.key);
                    await _applyAudioMode();
                  },
                );
              }),
              SwitchListTile(
                title: const Text('夜间模式（动态范围压缩 DRC）'),
                value: _nightMode,
                onChanged: (v) async {
                  setModal(() => _nightMode = v);
                  setState(() => _nightMode = v);
                  await _applyAudioMode();
                },
              ),
              SwitchListTile(
                title: const Text('人声对白增强'),
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

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              const Text('字幕轨（内封 ASS/PGS + embygo 外挂侧车）', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ListTile(
                leading: const Icon(Icons.subtitles_off_rounded),
                title: const Text('关闭字幕'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _player.setSubtitleTrack(SubtitleTrack.no());
                },
              ),
              ...embeddedSubs.map((t) => ListTile(
                    leading: const Icon(Icons.subtitles_rounded),
                    title: Text(t.title ?? t.language ?? '内封字幕 #${t.id}'),
                    subtitle: Text([t.codec, t.language].whereType<String>().join(' • ')),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _player.setSubtitleTrack(t);
                    },
                  )),
              ...extSubs.map((s) => ListTile(
                    leading: const Icon(Icons.closed_caption_rounded, color: PrismTheme.embygoGreen),
                    title: Text(s['title']?.toString() ?? '外挂字幕'),
                    subtitle: Text('${s['codec'] ?? 'srt'} • ${s['language'] ?? 'external'}'),
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
              const Divider(),
              Row(
                children: [
                  const Text('字幕时间偏移：'),
                  Text('${_subDelaySecs.toStringAsFixed(1)}s', style: const TextStyle(fontFamily: 'monospace')),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () async {
                      setModal(() => _subDelaySecs -= 0.2);
                      await _applyMpvProperty('sub-delay', _subDelaySecs.toStringAsFixed(2));
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () async {
                      setModal(() => _subDelaySecs += 0.2);
                      await _applyMpvProperty('sub-delay', _subDelaySecs.toStringAsFixed(2));
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openVersionSheet() {
    final sources = _prepared?.allSources ?? const [];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            const Text('切换媒体版本', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ...sources.map((src) => ListTile(
                  leading: Icon(
                    src.id == _prepared?.mediaSourceId ? Icons.check_circle_rounded : Icons.movie_outlined,
                    color: src.id == _prepared?.mediaSourceId ? PrismTheme.accent : null,
                  ),
                  title: Text(src.displayLabel),
                  onTap: () {
                    Navigator.pop(ctx);
                    _startPlayback(src.id);
                  },
                )),
          ],
        ),
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
}
