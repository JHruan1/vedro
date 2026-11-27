part of '../player_screen.dart';

/// Aspect, Danmaku, Speed, HDR, Audio, Chapters, Beauty Camera, More Tools, Shortcuts & Version sheets.
extension _PlayerSheetsExt on _PlayerScreenState {
  void _openAspectSheet() {
    const modes = {
      'fit': '原始比例（适应屏幕）',
      'fill': '铺满屏幕（等比裁切黑边）',
      'stretch': '拉伸铺满（无黑边）',
      '16:9': '强制 16:9',
      '21:9': '宽银幕 21:9',
      '2.35:1': '超宽银幕 2.35:1',
      '4:3': '经典 4:3',
    };
    const angles = [0, 90, 180, 270];
    _openPlayerSheet<void>(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('画面旋转', style: TextStyle(color: VedroTheme.fg2, fontSize: 13.5)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final angle in angles)
                        _DeckPillButton(
                          label: '$angle°',
                          active: _videoRotate == angle,
                          onTap: () {
                            setModal(() => _videoRotate = angle);
                            _rotateVideo(angle);
                          },
                        ),
                    ],
                  ),
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
              ticks: const [(-0.5, '71%'), (0.0, '100%'), (0.5, '141%'), (1.0, '200%'), (1.5, '283%')],
              valueText: '${(100 * math.pow(2.0, _videoZoom)).round()}%',
              onChanged: (next) {
                setModal(() => _videoZoom = next);
                _setVideoZoom(next, showHud: false);
              },
            ),
            const Divider(height: 18),
            SwitchListTile(
              dense: true,
              title: const Text('水平镜像翻转', style: TextStyle(color: VedroTheme.fg, fontSize: 13.5)),
              value: _hflip,
              onChanged: (v) async {
                setModal(() => _hflip = v);
                _setPlayerState(() => _hflip = v);
                await _applyVideoFilterChain();
              },
            ),
            SwitchListTile(
              dense: true,
              title: const Text('垂直上下翻转', style: TextStyle(color: VedroTheme.fg, fontSize: 13.5)),
              value: _vflip,
              onChanged: (v) async {
                setModal(() => _vflip = v);
                _setPlayerState(() => _vflip = v);
                await _applyVideoFilterChain();
              },
            ),
            Tooltip(
              message: '老片源 / 1080i 电视录播出现锯齿拉丝时开启',
              child: SwitchListTile(
                dense: true,
                title: const Text('去隔行 (Deinterlace)', style: TextStyle(color: VedroTheme.fg, fontSize: 13.5)),
                value: _deinterlace,
                onChanged: (v) async {
                  setModal(() => _deinterlace = v);
                  _setPlayerState(() => _deinterlace = v);
                  await _applyVideoFilterChain();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDanmakuSheet() {
    _openPlayerSheet<void>(
      builder: (ctx) => VedroControllerScope<TextEditingController>(
        create: () => TextEditingController(
          text: _currentItem.seriesName ?? _currentItem.displayName,
        ),
        dispose: (c) => c.dispose(),
        builder: (ctx, queryCtrl) => StatefulBuilder(
          builder: (ctx, setModal) {
          Future<void> runSearch() async {
            final kw = queryCtrl.text.trim();
            if (kw.isEmpty || _danmakuLoading || _danmakuSearching) return;
            setModal(() {
              _danmakuEnabled = true;
              _danmakuSearching = true;
            });
            _setPlayerState(() => _danmakuEnabled = true);
            try {
              await Future.wait([
                _loadDanmaku(queryOverride: kw),
                widget.appState.searchDanmakuCandidates(kw).then((c) {
                  if (mounted) _danmakuCandidates = c;
                }).catchError((_) {}),
              ]);
            } finally {
              if (mounted) _danmakuSearching = false;
              if (ctx.mounted) setModal(() {});
            }
          }

          return ListView(
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
                    _setPlayerState(() => _danmakuEnabled = v);
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
                    ? '检索中…'
                    : (_danmakuError != null
                        ? '$_danmakuError'
                        : (_danmakuComments.isNotEmpty
                            ? '${_danmakuMatchTitle ?? ''} · ${_danmakuComments.length}'
                            : '弹弹Play · B站')),
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
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => unawaited(runSearch()),
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
                        : () => unawaited(runSearch()),
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
                                        _setPlayerState(() {
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
                                        _setPlayerState(() => _danmakuError = '$e');
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
                _setPlayerState(() => _danmakuOpacity = v);
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
                _setPlayerState(() => _danmakuFontSize = v);
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
                _setPlayerState(() => _danmakuSpeedSecs = v);
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
                _setPlayerState(() => _danmakuArea = v);
                widget.appState.updatePrefs(widget.appState.prefs.copyWith(danmakuArea: v));
              },
            ),
            SwitchListTile(
              dense: true,
              title: const Text('屏蔽顶部固定弹幕', style: TextStyle(color: VedroTheme.fg, fontSize: 13.5)),
              value: _danmakuHideTop,
              onChanged: (v) {
                setModal(() => _danmakuHideTop = v);
                _setPlayerState(() => _danmakuHideTop = v);
                widget.appState.updatePrefs(widget.appState.prefs.copyWith(danmakuHideTop: v));
              },
            ),
            SwitchListTile(
              dense: true,
              title: const Text('屏蔽底部固定弹幕', style: TextStyle(color: VedroTheme.fg, fontSize: 13.5)),
              value: _danmakuHideBottom,
              onChanged: (v) {
                setModal(() => _danmakuHideBottom = v);
                _setPlayerState(() => _danmakuHideBottom = v);
                widget.appState.updatePrefs(widget.appState.prefs.copyWith(danmakuHideBottom: v));
              },
            ),
          ],
        );
        },
      ),
      ),
    );
  }

  void _openSpeedSheet() {
    _openPlayerSheet<void>(
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
    // Keys match Rust `ToneMappingAlgorithm` snake_case values AND `SettingsScreen`
    const algos = {
      'bt2446a': 'BT.2446a（自然高光保留）',
      'spline': 'Spline（曲线动态映射）',
      'st2094_40': 'ST.2094-40（动态元数据）',
      'reinhard': 'Reinhard（高亮温和压缩）',
      'hable': 'Hable（电影感曲线）',
      'clip': 'Clip（直通无压缩）',
    };
    final currentNormalized = _PlayerScreenState._normalizeToneMapping(_toneMapping);
    _openPlayerSheet<void>(
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
                _setPlayerState(() => _anime4kActive = v);
                await _applyAnime4k(v);
              },
            ),
            const Divider(height: 16),
            ...algos.entries.map((e) => _SheetOptionRow(
                  label: e.value,
                  selected: _PlayerScreenState._normalizeToneMapping(e.key) == currentNormalized,
                  onTap: () async {
                    Navigator.pop(ctx);
                    final mpvVal = _PlayerScreenState._normalizeToneMapping(e.key);
                    _setPlayerState(() => _toneMapping = mpvVal);
                    await _applyMpvProperty('tone-mapping', mpvVal);
                    unawaited(widget.appState.saveSettings({
                      ...widget.appState.settings,
                      'tone_mapping': e.key,
                    }));
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

    _openPlayerSheet<void>(
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
                      final scopeId = _trackPrefScopeId;
                      final prefVal = (t.language ?? '').trim().isNotEmpty
                          ? t.language!.trim()
                          : (t.title ?? t.id);
                      if (scopeId != null && prefVal.isNotEmpty) {
                        unawaited(widget.appState.setTrackPreference(scopeId, audioLang: prefVal));
                      }
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
                    _setPlayerState(() => _audioMode = e.key);
                    await _applyAudioMode();
                    unawaited(widget.appState.saveSettings({
                      ...widget.appState.settings,
                      'audio_mode': e.key,
                    }));
                  },
                )),
            const Divider(height: 18),
            SwitchListTile(
              dense: true,
              title: const Text('夜间模式 (DRC)', style: TextStyle(color: VedroTheme.fg, fontSize: 13.5)),
              value: _nightMode,
              onChanged: (v) async {
                setModal(() => _nightMode = v);
                _setPlayerState(() => _nightMode = v);
                await _applyAudioMode();
                unawaited(widget.appState.saveSettings({
                  ...widget.appState.settings,
                  'night_mode': v,
                }));
              },
            ),
            SwitchListTile(
              dense: true,
              title: const Text('人声对白增强', style: TextStyle(color: VedroTheme.fg, fontSize: 13.5)),
              value: _dialogueBoost,
              onChanged: (v) async {
                setModal(() => _dialogueBoost = v);
                _setPlayerState(() => _dialogueBoost = v);
                await _applyAudioMode();
                unawaited(widget.appState.saveSettings({
                  ...widget.appState.settings,
                  'dialogue_boost': v,
                }));
              },
            ),
            SwitchListTile(
              dense: true,
              title: const Text('响度均衡 (Dynaudnorm)', style: TextStyle(color: VedroTheme.fg, fontSize: 13.5)),
              subtitle: const Text('自动拉平电影中对白轻、爆炸响的音量落差', style: TextStyle(color: VedroTheme.fg3, fontSize: 11.5)),
              value: _loudnessNorm,
              onChanged: (v) async {
                setModal(() => _loudnessNorm = v);
                _setPlayerState(() => _loudnessNorm = v);
                await _applyAudioMode();
              },
            ),
            const Divider(height: 18),
            VedroPrecisionSlider(
              label: '音频同步偏移',
              value: _audioDelaySecs.clamp(-5.0, 5.0),
              min: -5.0,
              max: 5.0,
              step: 0.05,
              defaultValue: 0.0,
              centeredOrigin: true,
              snapValues: const [0.0],
              ticks: const [(-5.0, '-5s'), (-2.0, '-2s'), (0.0, '0s'), (2.0, '+2s'), (5.0, '+5s')],
              valueText: '${_audioDelaySecs >= 0 ? '+' : ''}${_audioDelaySecs.toStringAsFixed(2)}s',
              onChanged: (v) async {
                setModal(() => _audioDelaySecs = v);
                _setPlayerState(() => _audioDelaySecs = v);
                await _applyMpvProperty('audio-delay', v.toStringAsFixed(2));
                unawaited(widget.appState.updatePrefs(
                  widget.appState.prefs.copyWith(audioDelayMs: (v * 1000).round()),
                ));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openChaptersSheet() {
    _openPlayerSheet<void>(
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '章节列表 (${_chapters.length})',
                    style: const TextStyle(color: VedroTheme.fg, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                _DeckPillButton(
                  label: '上一章',
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_jumpChapter(false));
                  },
                ),
                const SizedBox(width: 6),
                _DeckPillButton(
                  label: '下一章',
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_jumpChapter(true));
                  },
                ),
              ],
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

  List<Widget> _buildBeautyStackControls(BuildContext ctx, StateSetter setModal) {
    Future<void> updateChannel(BeautyFilterParams next) async {
      final preset = next.isActive ? 'custom' : 'off';
      if (ctx.mounted) {
        setModal(() {
          _beautyPreset = preset;
          _beautyParams = next;
        });
      }
      await _applyBeautyParams(
        preset,
        next,
        showHud: false,
        debounceShader: true,
      );
    }

    return [
      Text(
        _beautyParams.isActive
            ? '${BeautyFilterPreset.displayLabelFor(_beautyPreset, _beautyParams)} · ${_beautyParams.summaryLabel()}'
            : BeautyFilterPreset.byId('off').subtitle,
        style: const TextStyle(color: VedroTheme.fg2, fontSize: 12.5),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: BeautyFilterPreset.all.map((preset) {
          final isSelected = preset.id == 'off'
              ? !_beautyParams.isActive
              : (_beautyPreset == preset.id && _beautyParams.isActive);
          return _DeckPillButton(
            label: preset.label,
            active: isSelected,
            onTap: () async {
              await _applyBeautyPreset(preset.id);
              if (ctx.mounted) setModal(() {});
            },
          );
        }).toList(),
      ),
      const SizedBox(height: 12),
      VedroPrecisionSlider(
        label: '磨皮（肤质保边）',
        value: _beautyParams.smooth,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        defaultValue: 0.58,
        snapValues: const [0.0, 0.35, 0.60, 0.85],
        valueText: '${(_beautyParams.smooth * 100).round()}%',
        onChanged: (v) => updateChannel(_beautyParams.copyWith(smooth: v)),
      ),
      const SizedBox(height: 8),
      VedroPrecisionSlider(
        label: '美白（仅提亮肤色）',
        value: _beautyParams.whiten,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        defaultValue: 0.42,
        snapValues: const [0.0, 0.35, 0.60, 0.85],
        valueText: '${(_beautyParams.whiten * 100).round()}%',
        onChanged: (v) => updateChannel(_beautyParams.copyWith(whiten: v)),
      ),
      const SizedBox(height: 8),
      VedroPrecisionSlider(
        label: '粉嫩（气色与润唇）',
        value: _beautyParams.rosy,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        defaultValue: 0.30,
        snapValues: const [0.0, 0.30, 0.55, 0.80],
        valueText: '${(_beautyParams.rosy * 100).round()}%',
        onChanged: (v) => updateChannel(_beautyParams.copyWith(rosy: v)),
      ),
      const SizedBox(height: 8),
      VedroPrecisionSlider(
        label: '亮眼清晰（五官立体）',
        value: _beautyParams.clarity,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        defaultValue: 0.40,
        snapValues: const [0.0, 0.35, 0.60, 0.85],
        valueText: '${(_beautyParams.clarity * 100).round()}%',
        onChanged: (v) => updateChannel(_beautyParams.copyWith(clarity: v)),
      ),
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
    ];
  }

  void _openBeautyFilterSheet() {
    _openPlayerSheet<void>(
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '人像美颜相机（可叠加）',
                      style: TextStyle(color: VedroTheme.fg, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (_beautyParams.isActive)
                    TextButton(
                      onPressed: () async {
                        await _applyBeautyPreset('off');
                        if (ctx.mounted) setModal(() {});
                      },
                      child: const Text('全部归零', style: TextStyle(fontSize: 12.5)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildBeautyStackControls(ctx, setModal),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openMoreToolsSheet() {
    _openPlayerSheet<void>(
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
                        _setPlayerState(() => _loopFile = v);
                        await _applyMpvProperty('loop-file', v ? 'inf' : 'no');
                      },
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('A-B 复读', style: TextStyle(color: VedroTheme.fg2, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _DeckPillButton(
                        label: _loopPointA == null ? '设 A 点' : 'A ${_fmtTime(_loopPointA!)}',
                        active: _loopPointA != null,
                        onTap: () {
                          setModal(() => _loopPointA = _positionSecs);
                          _setPlayerState(() => _loopPointA = _positionSecs);
                        },
                      ),
                      _DeckPillButton(
                        label: _loopPointB == null ? '设 B 点' : 'B ${_fmtTime(_loopPointB!)}',
                        active: _loopPointB != null,
                        onTap: () {
                          if (_loopPointA != null && _positionSecs > _loopPointA! + 0.5) {
                            setModal(() => _loopPointB = _positionSecs);
                            _setPlayerState(() => _loopPointB = _positionSecs);
                          }
                        },
                      ),
                      if (_loopPointA != null || _loopPointB != null)
                        _DeckPillButton(
                          label: '清除',
                          onTap: () {
                            setModal(() {
                              _loopPointA = null;
                              _loopPointB = null;
                            });
                            _setPlayerState(() {
                              _loopPointA = null;
                              _loopPointB = null;
                            });
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(height: 20),

            // 2-Pass Portrait Beauty Camera (stackable smooth / whiten / rosy / clarity)
            Padding(
              key: const ValueKey('player-beauty-filter-section'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '人像美颜相机',
                        style: TextStyle(
                          color: VedroTheme.fg2,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _beautyParams.isActive
                              ? BeautyFilterPreset.displayLabelFor(_beautyPreset, _beautyParams)
                              : '可自由叠加磨皮/美白/粉嫩/亮眼',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: VedroTheme.fg3, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._buildBeautyStackControls(ctx, setModal),
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
      ('PgUp / PgDn', '上一章 / 下一章'),
      ('I', '硬件解码与码率 HUD'),
      ('M', '静音切换'),
      ('P / N', '上一集 / 下一集'),
    ];
    showVedroDialog<void>(
      context: context,
      builder: (ctx) => Theme(
        data: VedroTheme.dark(),
        child: AlertDialog(
          backgroundColor: const Color(0xFF171820),
          title: const Text(
            '桌面快捷键指南',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
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
      ),
    );
  }

  void _openVersionSheet() {
    final sources = _prepared?.allSources ?? const [];
    _openPlayerSheet<void>(
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
}
