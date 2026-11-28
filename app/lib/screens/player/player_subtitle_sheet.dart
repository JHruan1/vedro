part of '../player_screen.dart';

/// Subtitle track selection, typography styling, AI bilingual translation & Local Offline ASR sheet.
extension _PlayerSubtitleSheetExt on _PlayerScreenState {
  void _openSubtitleSheet() {
    unawaited(LocalAsrManager.instance.refreshStatus());
    final extSubs = _prepared?.externalSubtitles ?? const [];
    final embeddedSubs = _player.state.tracks.subtitle
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();

    _openPlayerSheet<void>(
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
                    ? (aiReady ? '双语预读翻译' : '未配置 AI 模型')
                    : _aiSubCtrl.isLoadingCues
                        ? '预读字幕中…'
                        : _aiSubCtrl.asrMode
                            ? (_aiSubCtrl.totalCues == 0
                                ? (_aiSubCtrl.isTranscribing ? '识别中…' : '等待人声…')
                                : '${_aiSubCtrl.isTranscribing ? '识别中' : '就绪'} · ${_aiSubCtrl.totalCues}${aiReady ? ' / 译 ${_aiSubCtrl.translatedCount}' : ''}')
                            : _aiSubCtrl.isLiveFallbackMode
                                ? '实时翻译 → ${_aiSubCtrl.targetLang}'
                                : '${_aiSubCtrl.translatedCount} / ${_aiSubCtrl.totalCues} → ${_aiSubCtrl.targetLang}';

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
                                if (ctx.mounted) setModal(() {});
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
                                  if (ctx.mounted) setModal(() {});
                                },
                              ),
                            ] else if (_aiSubCtrl.translateCircuitOpen) ...[
                              const SizedBox(width: 8),
                              _DeckPillButton(
                                label: '重试翻译',
                                active: true,
                                onTap: () {
                                  _aiSubCtrl.retryTranslation();
                                  if (ctx.mounted) setModal(() {});
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
                            child: VedroPullDownButton<String>(
                              key: const ValueKey('player-ai-lang-dropdown'),
                              prefixLabel: '目标',
                              value: _aiSubCtrl.targetLang,
                              expanded: true,
                              height: 34,
                              menuMinWidth: 180,
                              menuMaxWidth: 260,
                              items: AiSubtitleTargetLanguage.all
                                  .map(
                                    (lang) => VedroDropdownItem<String>(
                                      value: lang.id,
                                      label: lang.id,
                                    ),
                                  )
                                  .toList(),
                              onChanged: (langId) async {
                                unawaited(widget.appState.updatePrefs(
                                  widget.appState.prefs.copyWith(aiTargetLang: langId),
                                ));
                                if (!_aiSubCtrl.enabled) {
                                  await _enableAiSubtitleTranslation(targetLangOverride: langId);
                                } else {
                                  await _aiSubCtrl.setTargetLang(langId);
                                }
                                if (ctx.mounted) setModal(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: VedroPullDownButton<String>(
                              key: const ValueKey('player-ai-mode-dropdown'),
                              prefixLabel: '排版',
                              displayLabelOverride: switch (_aiSubCtrl.displayMode) {
                                'bilingual_orig_top' => '原文在上',
                                'translated_only' => '仅译文',
                                _ => '译文在上',
                              },
                              value: _aiSubCtrl.displayMode,
                              expanded: true,
                              height: 34,
                              menuMinWidth: 180,
                              menuMaxWidth: 260,
                              items: const [
                                VedroDropdownItem<String>(
                                  value: 'bilingual_trans_top',
                                  label: '双语 · 译文在上',
                                ),
                                VedroDropdownItem<String>(
                                  value: 'bilingual_orig_top',
                                  label: '双语 · 原文在上',
                                ),
                                VedroDropdownItem<String>(
                                  value: 'translated_only',
                                  label: '仅显示译文',
                                ),
                              ],
                              onChanged: (modeId) {
                                _aiSubCtrl.setDisplayMode(modeId);
                                unawaited(widget.appState.updatePrefs(
                                  widget.appState.prefs.copyWith(aiSubtitleMode: modeId),
                                ));
                                if (ctx.mounted) setModal(() {});
                              },
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
                          _setPlayerState(() => _aiSubFontScale = v);
                          unawaited(widget.appState.updatePrefs(
                            widget.appState.prefs.copyWith(aiSubtitleFontScale: v),
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
                                  'AI 听音字幕 (ASR)',
                                  style: TextStyle(
                                    color: VedroTheme.fg,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  asrReady
                                      ? (isLocalAsr ? '离线 SenseVoice' : prefs.asrModel)
                                      : (isLocalAsr ? '需在设置中下载离线模型' : '需在设置中配置 ASR'),
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
                                if (ctx.mounted) setModal(() {});
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
                _secondarySubTrackId = null;
                unawaited(_applyMpvProperty('secondary-sid', 'no'));
                await _applyMpvProperty('sub-visibility', 'yes');
                await _player.setSubtitleTrack(SubtitleTrack.no());
                final scopeId = _trackPrefScopeId;
                if (scopeId != null) {
                  unawaited(widget.appState.setTrackPreference(scopeId, subtitleLang: 'off'));
                }
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
                    final scopeId = _trackPrefScopeId;
                    final prefVal = (t.language ?? '').trim().isNotEmpty
                        ? t.language!.trim()
                        : (t.title ?? t.id);
                    if (scopeId != null && prefVal.isNotEmpty) {
                      unawaited(widget.appState.setTrackPreference(scopeId, subtitleLang: prefVal));
                    }
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
                      final scopeId = _trackPrefScopeId;
                      final prefVal = (s['language']?.toString() ?? '').trim().isNotEmpty
                          ? s['language'].toString().trim()
                          : (s['title']?.toString() ?? '');
                      if (scopeId != null && prefVal.isNotEmpty) {
                        unawaited(widget.appState.setTrackPreference(scopeId, subtitleLang: prefVal));
                      }
                      if (_aiSubCtrl.enabled && !_aiSubCtrl.asrMode) {
                        await _enableAiSubtitleTranslation();
                      }
                    }
                  },
                )),
            if (embeddedSubs.length >= 2) ...[
              const Divider(height: 18),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '副字幕双轨同显（顶部第二条字幕）',
                      style: TextStyle(color: VedroTheme.fg2, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _DeckPillButton(
                              label: '关闭',
                              active: _secondarySubTrackId == null,
                              onTap: () async {
                                setModal(() => _secondarySubTrackId = null);
                                _setPlayerState(() => _secondarySubTrackId = null);
                                await _applyMpvProperty('secondary-sid', 'no');
                              },
                            ),
                          ),
                          for (final t in embeddedSubs)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _DeckPillButton(
                                label: t.title ?? t.language ?? '字幕 #${t.id}',
                                active: _secondarySubTrackId == t.id,
                                onTap: () async {
                                  setModal(() => _secondarySubTrackId = t.id);
                                  _setPlayerState(() => _secondarySubTrackId = t.id);
                                  await _applyMpvProperty('secondary-sid', t.id);
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
                _setPlayerState(() => _subScale = v);
                await _applyMpvProperty('sub-scale', v.toStringAsFixed(2));
                unawaited(widget.appState.updatePrefs(
                  widget.appState.prefs.copyWith(subtitleFontScale: v),
                ));
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
                _setPlayerState(() => _subPos = iv);
                await _applyMpvProperty('sub-pos', '$iv');
                unawaited(widget.appState.updatePrefs(
                  widget.appState.prefs.copyWith(subtitlePos: iv),
                ));
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
                _setPlayerState(() => _subDelaySecs = v);
                await _applyMpvProperty('sub-delay', v.toStringAsFixed(2));
                unawaited(widget.appState.updatePrefs(
                  widget.appState.prefs.copyWith(subtitleDelaySecs: v),
                ));
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
                        _setPlayerState(() => _subDelaySecs = next);
                        await _applyMpvProperty('sub-delay', next.toStringAsFixed(2));
                        unawaited(widget.appState.updatePrefs(
                          widget.appState.prefs.copyWith(subtitleDelaySecs: next),
                        ));
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
                          if (ctx.mounted) setModal(() {});
                          if (mounted) _setPlayerState(() {});
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
                if (ctx.mounted) setModal(() {});
                if (mounted) _setPlayerState(() {});
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
                if (ctx.mounted) setModal(() {});
                if (mounted) _setPlayerState(() {});
              },
            ),
            SwitchListTile(
              dense: true,
              title: const Text('强制覆盖 ASS 字幕样式', style: TextStyle(color: VedroTheme.fg, fontSize: 13.5)),
              value: _forceAssOverride,
              onChanged: (v) async {
                setModal(() => _forceAssOverride = v);
                _setPlayerState(() => _forceAssOverride = v);
                await _applyMpvProperty('sub-ass-override', v ? 'force' : 'no');
                unawaited(widget.appState.updatePrefs(
                  widget.appState.prefs.copyWith(forceAssOverride: v),
                ));
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
                                _setPlayerState(() => _subFontFamily = family);
                                await _applyMpvProperty('sub-fonts-dir', widget.appState.fontsDirectoryPath);
                                await _applyMpvProperty('sub-font', family.isEmpty ? 'sans-serif' : family);
                                unawaited(widget.appState.updatePrefs(
                                  widget.appState.prefs.copyWith(subtitleFontFamily: family),
                                ));
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
}
