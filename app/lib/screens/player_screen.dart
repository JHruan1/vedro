import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  String _toneMapping = 'bt2446a';
  String _audioMode = 'auto';
  bool _nightMode = false;
  bool _dialogueBoost = false;

  Timer? _statsTimer;
  Timer? _progressTimer;
  Timer? _ticketRefreshTimer;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    NativePlaybackChannel.setKeepScreenOn(true);
    _startPlayback(widget.mediaSourceId);
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _progressTimer?.cancel();
    _ticketRefreshTimer?.cancel();
    _focusNode.dispose();
    NativePlaybackChannel.setKeepScreenOn(false);
    _reportStoppedAndCleanup();
    super.dispose();
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
      final wid = await NativePlaybackChannel.attachNativeVideoSurface();
      final startSecs = widget.item.playbackPositionTicks > 0
          ? widget.item.playbackPositionTicks / 10000000.0
          : null;

      await widget.appState.core.invoke('player_start', {
        'url': prep.proxyUrl,
        if (startSecs != null) 'start_secs': startSecs,
        if (wid != null) 'wid': wid,
        if (prep.inspectedJson != null) 'inspected': prep.inspectedJson,
      });

      // Attach default external sidecar subtitle from embygo/Emby if present
      for (final sub in prep.externalSubtitles) {
        if (sub['is_default'] == true) {
          await widget.appState.core.invoke('player_add_subtitle', {
            'url': sub['url'],
            'title': sub['title'],
            'language': sub['language'],
          });
          break;
        }
      }

      await widget.appState.core.invoke('report_playback_start', {
        'position_ticks': widget.item.playbackPositionTicks,
        'is_paused': false,
      });

      setState(() {
        _prepared = prep;
        _loading = false;
        _paused = false;
      });
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
    _statsTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      try {
        final s = await widget.appState.core.invoke('player_stats') as Map<String, dynamic>;
        final pb = (s['playback'] as Map<String, dynamic>?) ?? const {};
        if (mounted) {
          setState(() {
            _stats = s;
            _paused = pb['paused'] == true;
            _positionSecs = (pb['position_secs'] as num?)?.toDouble() ?? _positionSecs;
            _durationSecs = (pb['duration_secs'] as num?)?.toDouble() ?? _durationSecs;
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
    await widget.appState.core.invoke('player_toggle_pause');
    setState(() => _paused = !_paused);
  }

  Future<void> _seekTo(double secs) async {
    final target = secs.clamp(0.0, _durationSecs > 0 ? _durationSecs : 86400.0);
    await widget.appState.core.invoke('player_seek', {'seconds': target, 'relative': false});
    setState(() => _positionSecs = target);
  }

  Future<void> _seekBy(double delta) async {
    await widget.appState.core.invoke('player_seek', {'seconds': delta, 'relative': true});
  }

  Future<void> _setSpeed(double s) async {
    await widget.appState.core.invoke('player_set_speed', {'speed': s});
    setState(() => _speed = s);
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
      widget.appState.core.invoke('player_set_volume', {'volume': _volume});
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _volume = (_volume - 5).clamp(0, 150);
      widget.appState.core.invoke('player_set_volume', {'volume': _volume});
    } else if (key == LogicalKeyboardKey.keyI) {
      setState(() => _showStats = !_showStats);
    } else if (key == LogicalKeyboardKey.bracketRight) {
      _setSpeed((_speed + 0.25).clamp(0.5, 4.0));
    } else if (key == LogicalKeyboardKey.bracketLeft) {
      _setSpeed((_speed - 0.25).clamp(0.5, 4.0));
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
          onLongPressStart: (_) => _setSpeed(2.0),
          onLongPressEnd: (_) => _setSpeed(1.0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Native hardware video surface backdrop (libmpv/libplacebo or AVSampleBufferDisplayLayer / MediaCodec)
              Center(
                child: _loading
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 14),
                          Text('正在建立 DirectPlay 高速缓存与杜比视界/全景声管线...'),
                        ],
                      )
                    : _error != null
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                          )
                        : const SizedBox.expand(),
              ),
              if (_showStats)
                Positioned(
                  top: 72,
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
      'bt2446a': 'BT.2446a（推荐：自然色彩与高光保留）',
      'spline': 'Spline（libplacebo 曲线动态映射）',
      'st2094_40': 'ST.2094-40（HDR10+/杜比视界动态元）',
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
                  await widget.appState.core.invoke('player_set_tone_mapping', {'algorithm': e.key});
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
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
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
                    await widget.appState.core.invoke('player_set_audio_mode', {
                      'mode': e.key,
                      'night_mode': _nightMode,
                      'dialogue_boost': _dialogueBoost,
                    });
                  },
                );
              }),
              SwitchListTile(
                title: const Text('夜间模式（动态范围压缩 DRC）'),
                value: _nightMode,
                onChanged: (v) async {
                  setModal(() => _nightMode = v);
                  setState(() => _nightMode = v);
                  await widget.appState.core.invoke('player_set_audio_mode', {
                    'mode': _audioMode,
                    'night_mode': _nightMode,
                    'dialogue_boost': _dialogueBoost,
                  });
                },
              ),
              SwitchListTile(
                title: const Text('人声对白增强'),
                value: _dialogueBoost,
                onChanged: (v) async {
                  setModal(() => _dialogueBoost = v);
                  setState(() => _dialogueBoost = v);
                  await widget.appState.core.invoke('player_set_audio_mode', {
                    'mode': _audioMode,
                    'night_mode': _nightMode,
                    'dialogue_boost': _dialogueBoost,
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSubtitleSheet() {
    final subs = _prepared?.externalSubtitles ?? const [];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
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
                await widget.appState.core.invoke('player_set_subtitle_track', {'track_id': -1});
              },
            ),
            ...subs.map((s) => ListTile(
                  leading: const Icon(Icons.closed_caption_rounded),
                  title: Text(s['title']?.toString() ?? '外挂字幕'),
                  subtitle: Text('${s['codec'] ?? 'srt'} • ${s['language'] ?? 'unknown'}'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await widget.appState.core.invoke('player_add_subtitle', {
                      'url': s['url'],
                      'title': s['title'],
                      'language': s['language'],
                    });
                  },
                )),
          ],
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
