import 'dart:async';

import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// Normalized subtitle cue with millisecond timestamps.
class SubtitleCueModel {
  const SubtitleCueModel({
    required this.idx,
    required this.startMs,
    required this.endMs,
    required this.text,
  });

  final int idx;
  final int startMs;
  final int endMs;
  final String text;

  factory SubtitleCueModel.fromJson(Map<String, dynamic> j, [int fallbackIdx = 0]) =>
      SubtitleCueModel(
        idx: (j['idx'] as num?)?.toInt() ?? fallbackIdx,
        startMs: (j['start_ms'] as num?)?.toInt() ?? 0,
        endMs: (j['end_ms'] as num?)?.toInt() ?? 0,
        text: (j['text'] ?? '').toString().trim(),
      );
}

/// Immutable snapshot delivered to `AiBilingualSubtitleOverlay` via `ValueNotifier`
/// so playback updates NEVER trigger full-screen `setState()` rebuilds.
class BilingualCueSnapshot {
  const BilingualCueSnapshot({
    required this.original,
    this.translated,
    this.pendingTranslation = false,
    this.statusHint,
  });

  final String original;
  final String? translated;
  final bool pendingTranslation;
  final String? statusHint;

  @override
  bool operator ==(Object other) =>
      other is BilingualCueSnapshot &&
      other.original == original &&
      other.translated == translated &&
      other.pendingTranslation == pendingTranslation &&
      other.statusHint == statusHint;

  @override
  int get hashCode => Object.hash(original, translated, pendingTranslation, statusHint);
}

/// Supported YouTube-style quick target languages for in-player AI subtitle translation.
class AiSubtitleTargetLanguage {
  const AiSubtitleTargetLanguage(this.id, this.shortLabel);
  final String id;
  final String shortLabel;

  static const List<AiSubtitleTargetLanguage> all = [
    AiSubtitleTargetLanguage('简体中文', '简中'),
    AiSubtitleTargetLanguage('繁體中文', '繁中'),
    AiSubtitleTargetLanguage('English', 'English'),
    AiSubtitleTargetLanguage('日本語', '日本語'),
    AiSubtitleTargetLanguage('한국어', '한국어'),
    AiSubtitleTargetLanguage('Français', 'Français'),
    AiSubtitleTargetLanguage('Español', 'Español'),
  ];
}

/// Lookahead AI Bilingual Subtitle + Speech-to-Subtitle (ASR) Engine.
///
/// Supports three seamless operating modes:
/// 1. **Cue Prefetch Mode**: loads full SRT/VTT/ASS cues via Rust (`load_subtitle_cues`),
///    then continuously prefetches & translates upcoming dialogue in context-aware batches
///    ahead of playback (`[pos - 2s, pos + lookaheadSecs]`), re-centering immediately on seek.
/// 2. **AI Speech-to-Subtitle (ASR) Mode**: for subtitle-less videos (e.g. raw Japanese / English
///    streams), slices upcoming 25-second audio windows via pure-Rust `symphonia` + Whisper /
///    SenseVoice API (`ai_transcribe_audio_slice`), populates timestamped cues, and automatically
///    translates them into bilingual subtitles when AI translation is enabled!
/// 3. **Live Fallback Mode**: if an embedded track cannot be extracted ahead of time, translates
///    incoming `_player.stream.subtitle` lines live with an in-memory per-language cache.
class AiSubtitleTranslatorController extends ChangeNotifier {
  AiSubtitleTranslatorController({
    required this.appState,
    this.mediaTitle,
  })  : _displayMode = appState.prefs.aiSubtitleMode,
        _targetLang = appState.prefs.aiTargetLang;

  final VedroAppState appState;
  String? mediaTitle;

  final ValueNotifier<BilingualCueSnapshot?> activeCueNotifier =
      ValueNotifier<BilingualCueSnapshot?>(null);

  bool _enabled = false;
  bool _asrMode = false;
  bool _isLoadingCues = false;
  bool _isLiveFallbackMode = false;
  String _displayMode;
  String _targetLang;
  String? _lastError;
  String? _activeSourceLabel;

  // Subtitle cues sorted by startMs
  List<SubtitleCueModel> _cues = const [];
  // Per-target-language cue index -> translated text cache
  final Map<String, Map<int, String>> _translationsByLang = {};
  // Per-target-language live text -> translated text cache (for fallback mode)
  final Map<String, Map<String, String>> _liveCacheByLang = {};
  final Set<String> _inFlightBatchKeys = {};
  final Set<String> _inFlightLiveKeys = {};

  // ASR audio slicing state (fixed 25s slice windows keyed by slice index)
  static const double asrSliceSecs = 25.0;
  String? _asrSourceUrl;
  String? _asrLocalPath;
  String? _asrSourceLang;
  double _mediaDurationSecs = 0;
  final Set<int> _asrDoneSlices = {};
  final Set<int> _asrInFlightSlices = {};
  String _lastAsrPromptTail = '';

  int _generation = 0;
  double _lastPositionSecs = 0;
  double _lastDelaySecs = 0;
  String _lastLiveOriginal = '';
  bool _disposed = false;

  bool get enabled => _enabled;
  bool get asrMode => _asrMode;
  bool get isLoadingCues => _isLoadingCues;
  bool get isTranslating => _inFlightBatchKeys.isNotEmpty || _inFlightLiveKeys.isNotEmpty;
  bool get isTranscribing => _asrInFlightSlices.isNotEmpty;
  bool get isLiveFallbackMode => _isLiveFallbackMode;
  String get displayMode => _displayMode;
  String get targetLang => _targetLang;
  String? get lastError => _lastError;
  String? get activeSourceLabel => _activeSourceLabel;
  int get totalCues => _cues.length;
  int get translatedCount => _translationsByLang[_targetLang]?.length ?? 0;

  Map<int, String> get _curLangMap =>
      _translationsByLang.putIfAbsent(_targetLang, () => <int, String>{});

  Map<String, String> get _curLiveMap =>
      _liveCacheByLang.putIfAbsent(_targetLang, () => <String, String>{});

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Enable YouTube-style AI bilingual translation for an existing subtitle source (or live fallback).
  Future<void> enable({
    String? subtitleUrl,
    String? localPath,
    String? format,
    String? sourceLabel,
    double currentPositionSecs = 0,
    String? displayMode,
    String? targetLang,
  }) async {
    final gen = ++_generation;
    _enabled = true;
    _asrMode = false;
    _lastError = null;
    _activeSourceLabel = sourceLabel;
    _lastPositionSecs = currentPositionSecs;
    if (displayMode != null && displayMode.isNotEmpty) {
      _displayMode = displayMode;
    }
    if (targetLang != null && targetLang.isNotEmpty) {
      _targetLang = targetLang;
    }
    _inFlightBatchKeys.clear();
    _inFlightLiveKeys.clear();
    _asrInFlightSlices.clear();
    _cues = const [];
    _translationsByLang.clear();

    final hasSource = (localPath != null && localPath.trim().isNotEmpty) ||
        (subtitleUrl != null && subtitleUrl.trim().isNotEmpty);

    if (!hasSource) {
      _isLoadingCues = false;
      _isLiveFallbackMode = true;
      _safeNotify();
      _refreshActiveCue();
      return;
    }

    _isLoadingCues = true;
    _isLiveFallbackMode = false;
    _safeNotify();

    try {
      final rawCues = await appState.loadSubtitleCues(
        url: subtitleUrl,
        localPath: localPath,
        format: format,
      );
      if (gen != _generation || _disposed) return;

      final parsed = <SubtitleCueModel>[];
      for (var i = 0; i < rawCues.length; i++) {
        final cue = SubtitleCueModel.fromJson(rawCues[i], i);
        if (cue.text.isNotEmpty) {
          parsed.add(SubtitleCueModel(
            idx: parsed.length,
            startMs: cue.startMs,
            endMs: cue.endMs,
            text: cue.text,
          ));
        }
      }
      parsed.sort((a, b) => a.startMs.compareTo(b.startMs));
      // Re-index cleanly after sort so binary search & context windows align 1:1
      _cues = [
        for (var i = 0; i < parsed.length; i++)
          SubtitleCueModel(
            idx: i,
            startMs: parsed[i].startMs,
            endMs: parsed[i].endMs,
            text: parsed[i].text,
          ),
      ];
      _isLoadingCues = false;
      if (_cues.isEmpty) {
        // Server returned empty or non-text subtitle; degrade cleanly to live mode
        _isLiveFallbackMode = true;
      } else {
        _isLiveFallbackMode = false;
        _scheduleLookaheadBatches(_lastPositionSecs);
      }
      _refreshActiveCue();
      _safeNotify();
    } catch (e) {
      if (gen != _generation || _disposed) return;
      _isLoadingCues = false;
      _isLiveFallbackMode = true;
      _lastError = '未能提前读取字幕文件，已切至实时逐句翻译（${_cleanError(e)}）';
      _safeNotify();
      _refreshActiveCue();
    }
  }

  /// Enable AI Speech-to-Subtitle (ASR) lookahead mode for videos with NO subtitle tracks!
  ///
  /// Automatically extracts 25-second audio slices ahead of playback in pure Rust, transcribes
  /// speech via Whisper/SenseVoice API, and automatically translates cues into bilingual subtitles
  /// when AI text translation is enabled.
  Future<void> enableAsr({
    String? sourceUrl,
    String? localPath,
    double currentPositionSecs = 0,
    double durationSecs = 0,
    String? sourceLang,
    String? targetLang,
    String? displayMode,
  }) async {
    ++_generation;
    _enabled = true;
    _asrMode = true;
    _isLoadingCues = false;
    _isLiveFallbackMode = false;
    _lastError = null;
    _activeSourceLabel = 'AI 语音识别';
    _asrSourceUrl = sourceUrl;
    _asrLocalPath = localPath;
    _asrSourceLang = sourceLang ?? appState.prefs.asrSourceLang;
    _mediaDurationSecs = durationSecs;
    _lastPositionSecs = currentPositionSecs;
    if (targetLang != null && targetLang.isNotEmpty) {
      _targetLang = targetLang;
    }
    if (displayMode != null && displayMode.isNotEmpty) {
      _displayMode = displayMode;
    }
    _cues = const [];
    _translationsByLang.clear();
    _inFlightBatchKeys.clear();
    _asrDoneSlices.clear();
    _asrInFlightSlices.clear();
    _lastAsrPromptTail = '';
    _safeNotify();

    _scheduleAsrSlices(currentPositionSecs);
    _refreshActiveCue();
  }

  void disable() {
    ++_generation;
    _enabled = false;
    _asrMode = false;
    _isLoadingCues = false;
    _isLiveFallbackMode = false;
    _lastError = null;
    _inFlightBatchKeys.clear();
    _inFlightLiveKeys.clear();
    _asrInFlightSlices.clear();
    activeCueNotifier.value = null;
    _safeNotify();
  }

  void setDisplayMode(String mode) {
    if (_displayMode == mode) return;
    _displayMode = mode;
    _refreshActiveCue();
    _safeNotify();
  }

  /// YouTube-style instant target language switch inside the player.
  Future<void> setTargetLang(String lang) async {
    final trimmed = lang.trim();
    if (trimmed.isEmpty || _targetLang == trimmed) return;
    _targetLang = trimmed;
    _lastError = null;
    _inFlightBatchKeys.clear();
    _inFlightLiveKeys.clear();
    _safeNotify();
    if (!_enabled) return;
    if (_cues.isNotEmpty) {
      _scheduleLookaheadBatches(_lastPositionSecs);
    } else if (_isLiveFallbackMode && _lastLiveOriginal.isNotEmpty) {
      onLiveSubtitleText(_lastLiveOriginal);
    }
    _refreshActiveCue();
  }

  void resetForNewMedia({String? mediaTitle}) {
    this.mediaTitle = mediaTitle;
    ++_generation;
    _enabled = false;
    _asrMode = false;
    _isLoadingCues = false;
    _isLiveFallbackMode = false;
    _lastError = null;
    _activeSourceLabel = null;
    _cues = const [];
    _translationsByLang.clear();
    _liveCacheByLang.clear();
    _inFlightBatchKeys.clear();
    _inFlightLiveKeys.clear();
    _asrDoneSlices.clear();
    _asrInFlightSlices.clear();
    _lastLiveOriginal = '';
    _lastAsrPromptTail = '';
    activeCueNotifier.value = null;
    _safeNotify();
  }

  /// Lightweight playback clock tick (O(log N) cue lookup, zero `notifyListeners()` spam).
  void updatePosition(double positionSecs, {double delaySecs = 0.0, double durationSecs = 0.0}) {
    _lastPositionSecs = positionSecs;
    _lastDelaySecs = delaySecs;
    if (durationSecs > 0) _mediaDurationSecs = durationSecs;
    if (!_enabled || _disposed) return;

    if (_asrMode) {
      _scheduleAsrSlices(positionSecs);
    }
    if (_cues.isNotEmpty) {
      _refreshActiveCue();
      if (appState.prefs.isAiReady) {
        _scheduleLookaheadBatches(positionSecs);
      }
    } else if (_asrMode && _asrInFlightSlices.isNotEmpty) {
      activeCueNotifier.value = const BilingualCueSnapshot(
        original: '',
        statusHint: 'AI 正在识别当前片段语音…',
      );
    }
  }

  /// Live fallback entrypoint driven by `_player.stream.subtitle` when full cue prefetch
  /// is unavailable (e.g. unextractable embedded track).
  void onLiveSubtitleText(String rawText) {
    final cleaned = rawText.trim();
    _lastLiveOriginal = cleaned;
    if (!_enabled || !_isLiveFallbackMode || _disposed) return;

    if (cleaned.isEmpty) {
      activeCueNotifier.value = null;
      return;
    }

    final cached = _curLiveMap[cleaned];
    if (cached != null) {
      activeCueNotifier.value = BilingualCueSnapshot(
        original: cleaned,
        translated: cached,
      );
      return;
    }

    activeCueNotifier.value = BilingualCueSnapshot(
      original: cleaned,
      pendingTranslation: appState.prefs.isAiReady,
    );

    if (!appState.prefs.isAiReady) return;
    final key = '$_targetLang::$cleaned';
    if (!_inFlightLiveKeys.add(key)) return;

    final gen = _generation;
    final langAtStart = _targetLang;
    unawaited(() async {
      try {
        final res = await appState.aiTranslateSubtitleBatch(
          lines: [
            {'idx': 0, 'text': cleaned},
          ],
          mediaTitle: mediaTitle,
          targetLang: langAtStart,
        );
        if (gen != _generation || _disposed) return;
        final translated = res[0];
        if (translated != null && translated.isNotEmpty) {
          _liveCacheByLang.putIfAbsent(langAtStart, () => <String, String>{})[cleaned] = translated;
          if (_targetLang == langAtStart && _lastLiveOriginal == cleaned) {
            activeCueNotifier.value = BilingualCueSnapshot(
              original: cleaned,
              translated: translated,
            );
          }
        }
      } catch (e) {
        if (gen == _generation && !_disposed) {
          _lastError = _cleanError(e);
          _safeNotify();
        }
      } finally {
        _inFlightLiveKeys.remove(key);
      }
    }());
  }

  void _refreshActiveCue() {
    if (!_enabled || _disposed) {
      activeCueNotifier.value = null;
      return;
    }
    if (_isLiveFallbackMode) {
      if (_lastLiveOriginal.isEmpty) {
        activeCueNotifier.value = null;
      } else {
        final cached = _curLiveMap[_lastLiveOriginal];
        activeCueNotifier.value = BilingualCueSnapshot(
          original: _lastLiveOriginal,
          translated: cached,
          pendingTranslation: cached == null && appState.prefs.isAiReady,
        );
      }
      return;
    }
    if (_cues.isEmpty) {
      activeCueNotifier.value = (_isLoadingCues || _asrInFlightSlices.isNotEmpty)
          ? BilingualCueSnapshot(
              original: '',
              statusHint: _asrMode ? 'AI 正在听音识别字幕…' : '正在读取字幕并预读翻译…',
            )
          : null;
      return;
    }

    final posMs = ((_lastPositionSecs - _lastDelaySecs) * 1000).round();
    final active = _findActiveCues(posMs);
    if (active.isEmpty) {
      activeCueNotifier.value = null;
      return;
    }

    final langMap = _curLangMap;
    final origLines = <String>[];
    final transLines = <String>[];
    var anyPending = false;
    for (final c in active) {
      origLines.add(c.text);
      final t = langMap[c.idx];
      if (t != null && t.isNotEmpty) {
        transLines.add(t);
      } else {
        anyPending = true;
      }
    }

    activeCueNotifier.value = BilingualCueSnapshot(
      original: origLines.join('\n'),
      translated: transLines.isEmpty ? null : transLines.join('\n'),
      pendingTranslation: anyPending && appState.prefs.isAiReady,
    );
  }

  List<SubtitleCueModel> _findActiveCues(int posMs) {
    if (_cues.isEmpty) return const [];
    // Binary search for the first cue with startMs > posMs
    var lo = 0;
    var hi = _cues.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_cues[mid].startMs <= posMs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    // Scan backwards a small window to catch overlapping simultaneous cues
    final out = <SubtitleCueModel>[];
    final scanStart = (lo - 8).clamp(0, _cues.length);
    for (var i = scanStart; i < lo; i++) {
      final c = _cues[i];
      if (posMs >= c.startMs && posMs <= c.endMs) {
        out.add(c);
      }
    }
    return out;
  }

  void _scheduleLookaheadBatches(double positionSecs) {
    if (!_enabled || _cues.isEmpty || !appState.prefs.isAiReady) return;
    // Cap concurrent batch LLM calls to 2 so lookahead stays fast without rate-limit spikes
    if (_inFlightBatchKeys.length >= 2) return;

    final batchSize = appState.prefs.aiSubtitleBatchSize.clamp(8, 32);
    final lookaheadSecs = appState.prefs.aiSubtitleLookaheadSecs.clamp(30, 300);
    final windowStartMs = ((positionSecs - _lastDelaySecs - 2.0) * 1000).round();
    final windowEndMs = ((positionSecs - _lastDelaySecs + lookaheadSecs) * 1000).round();

    final langMap = _curLangMap;
    // Find the first untranslated cue inside [windowStartMs, windowEndMs]
    int? firstUntranslated;
    for (var i = 0; i < _cues.length; i++) {
      final c = _cues[i];
      if (c.endMs < windowStartMs) continue;
      if (c.startMs > windowEndMs) break;
      if (!langMap.containsKey(c.idx) && !_isCueInFlight(c.idx)) {
        firstUntranslated = i;
        break;
      }
    }
    if (firstUntranslated == null) return;

    final batchCues = <SubtitleCueModel>[];
    for (var i = firstUntranslated; i < _cues.length && batchCues.length < batchSize; i++) {
      final c = _cues[i];
      if (!langMap.containsKey(c.idx) && !_isCueInFlight(c.idx)) {
        batchCues.add(c);
      }
    }
    if (batchCues.isEmpty) return;

    // Collect up to 3 preceding dialogue cues for natural context continuity
    final ctxStart = (firstUntranslated - 3).clamp(0, firstUntranslated);
    final contextLines = <String>[
      for (var i = ctxStart; i < firstUntranslated; i++) _cues[i].text,
    ];

    final batchKey =
        '$_targetLang::${batchCues.first.idx}-${batchCues.last.idx}::${batchCues.length}';
    if (!_inFlightBatchKeys.add(batchKey)) return;
    _safeNotify();

    final gen = _generation;
    final langAtStart = _targetLang;
    unawaited(() async {
      try {
        final translations = await appState.aiTranslateSubtitleBatch(
          lines: batchCues.map((c) => {'idx': c.idx, 'text': c.text}).toList(),
          context: contextLines,
          mediaTitle: mediaTitle,
          targetLang: langAtStart,
        );
        if (gen != _generation || _disposed) return;
        if (translations.isNotEmpty) {
          final map = _translationsByLang.putIfAbsent(langAtStart, () => <int, String>{});
          map.addAll(translations);
          _lastError = null;
        }
      } catch (e) {
        if (gen == _generation && !_disposed) {
          _lastError = _cleanError(e);
        }
      } finally {
        _inFlightBatchKeys.remove(batchKey);
        if (gen == _generation && !_disposed) {
          _refreshActiveCue();
          _safeNotify();
          // Chain next lookahead batch smoothly if more untranslated cues remain in window
          if (_lastError == null) {
            _scheduleLookaheadBatches(_lastPositionSecs);
          }
        }
      }
    }());
  }

  bool _isCueInFlight(int cueIdx) {
    final prefix = '$_targetLang::';
    for (final key in _inFlightBatchKeys) {
      if (!key.startsWith(prefix)) continue;
      final rangePart = key.substring(prefix.length).split('::').first;
      final bounds = rangePart.split('-');
      if (bounds.length == 2) {
        final s = int.tryParse(bounds[0]);
        final e = int.tryParse(bounds[1]);
        if (s != null && e != null && cueIdx >= s && cueIdx <= e) {
          return true;
        }
      }
    }
    return false;
  }

  void _scheduleAsrSlices(double positionSecs) {
    if (!_enabled || !_asrMode || !appState.prefs.isAsrReady) return;
    // Keep at most 1 ASR slice in-flight to keep mobile CPU/network super cool & ordered
    if (_asrInFlightSlices.isNotEmpty) return;

    final currentSlice = (positionSecs.clamp(0.0, 86400.0) / asrSliceSecs).floor();
    // Always prioritize current slice first, then look ahead 1 slice (+25s ahead)
    final candidates = [currentSlice, currentSlice + 1];
    int? targetSlice;
    for (final s in candidates) {
      final sliceStart = s * asrSliceSecs;
      if (_mediaDurationSecs > 0 && sliceStart >= _mediaDurationSecs) continue;
      if (!_asrDoneSlices.contains(s) && !_asrInFlightSlices.contains(s)) {
        targetSlice = s;
        break;
      }
    }
    if (targetSlice == null) return;

    _asrInFlightSlices.add(targetSlice);
    _safeNotify();

    final gen = _generation;
    final sliceIdx = targetSlice;
    final startSecs = sliceIdx * asrSliceSecs;
    unawaited(() async {
      try {
        final rawCues = await appState.transcribeAudioSlice(
          sourceUrl: _asrSourceUrl,
          localPath: _asrLocalPath,
          startSecs: startSecs,
          durationSecs: asrSliceSecs,
          sourceLang: _asrSourceLang,
          prompt: _lastAsrPromptTail.isNotEmpty ? _lastAsrPromptTail : null,
        );
        if (gen != _generation || _disposed) return;

        _asrDoneSlices.add(sliceIdx);
        if (rawCues.isNotEmpty) {
          final merged = List<SubtitleCueModel>.from(_cues);
          final sliceStartMs = (startSecs * 1000).round();
          final sliceEndMs = ((startSecs + asrSliceSecs) * 1000).round();
          // Replace any overlapping cues in this slice window cleanly
          merged.removeWhere((c) => c.startMs >= sliceStartMs && c.startMs < sliceEndMs);
          for (final rc in rawCues) {
            final parsed = SubtitleCueModel.fromJson(rc, merged.length);
            if (parsed.text.isNotEmpty) {
              merged.add(parsed);
            }
          }
          merged.sort((a, b) => a.startMs.compareTo(b.startMs));

          // Preserve existing translations by matching `(startMs, text)` key when re-indexing!
          final oldTextTrans = <String, Map<String, String>>{};
          for (final entry in _translationsByLang.entries) {
            final byKey = <String, String>{};
            for (final oldCue in _cues) {
              final tr = entry.value[oldCue.idx];
              if (tr != null) {
                byKey['${oldCue.startMs}::${oldCue.text}'] = tr;
              }
            }
            oldTextTrans[entry.key] = byKey;
          }

          _cues = [
            for (var i = 0; i < merged.length; i++)
              SubtitleCueModel(
                idx: i,
                startMs: merged[i].startMs,
                endMs: merged[i].endMs,
                text: merged[i].text,
              ),
          ];

          for (final entry in oldTextTrans.entries) {
            final rebuilt = <int, String>{};
            for (final c in _cues) {
              final tr = entry.value['${c.startMs}::${c.text}'];
              if (tr != null) rebuilt[c.idx] = tr;
            }
            _translationsByLang[entry.key] = rebuilt;
          }

          final tailText = rawCues
              .map((c) => (c['text'] ?? '').toString().trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (tailText.isNotEmpty) {
            final joined = tailText.join(' ');
            _lastAsrPromptTail =
                joined.length > 140 ? joined.substring(joined.length - 140) : joined;
          }
        }
        _lastError = null;
      } catch (e) {
        if (gen == _generation && !_disposed) {
          _lastError = _cleanError(e);
        }
      } finally {
        _asrInFlightSlices.remove(sliceIdx);
        if (gen == _generation && !_disposed) {
          _refreshActiveCue();
          _safeNotify();
          if (appState.prefs.isAiReady && _cues.isNotEmpty) {
            _scheduleLookaheadBatches(_lastPositionSecs);
          }
          if (_lastError == null) {
            _scheduleAsrSlices(_lastPositionSecs);
          }
        }
      }
    }());
  }

  static String _cleanError(Object e) => e
      .toString()
      .replaceFirst('VedroCoreException: ', '')
      .replaceFirst('Exception: ', '');

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    activeCueNotifier.dispose();
    super.dispose();
  }
}

/// Cinema-grade bilingual subtitle overlay driven purely by `ValueListenableBuilder`.
/// Respects user's subtitle scale, vertical position, color, outline width, and background opacity.
class AiBilingualSubtitleOverlay extends StatelessWidget {
  const AiBilingualSubtitleOverlay({
    super.key,
    required this.controller,
    required this.subScale,
    required this.subPos,
    required this.colorHex,
    required this.outlineWidth,
    required this.bgOpacity,
  });

  final AiSubtitleTranslatorController controller;
  final double subScale;
  final int subPos;
  final String colorHex;
  final double outlineWidth;
  final double bgOpacity;

  Color _parseColor(String hex) {
    final clean = hex.trim().replaceFirst('#', '');
    if (clean.length == 6) {
      final v = int.tryParse('FF$clean', radix: 16);
      if (v != null) return Color(v);
    } else if (clean.length == 8) {
      final v = int.tryParse(clean, radix: 16);
      if (v != null) return Color(v);
    }
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ValueListenableBuilder<BilingualCueSnapshot?>(
          valueListenable: controller.activeCueNotifier,
          builder: (context, snap, _) {
            if (snap == null) return const SizedBox.shrink();

            final size = MediaQuery.sizeOf(context);
            final compact = size.width < 600;
            final baseFont = (compact ? 17.5 : 23.0) * subScale.clamp(0.5, 2.0);
            // subPos: 100 => bottom edge (~26px), 60 => lifted ~38% up the screen
            final bottomInset =
                (22.0 + ((100 - subPos.clamp(60, 100)) / 40.0) * (size.height * 0.34))
                    .clamp(18.0, size.height * 0.48);

            if (snap.original.isEmpty && (snap.statusHint?.isNotEmpty ?? false)) {
              return Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, bottomInset),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0x9E0E0F14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 0.7),
                    ),
                    child: Text(
                      snap.statusHint!,
                      style: const TextStyle(
                        color: Color(0xDEFFFFFF),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            }

            final primaryColor = _parseColor(colorHex);
            final mode = controller.displayMode;
            final hasTrans = snap.translated != null && snap.translated!.trim().isNotEmpty;
            final shadows = outlineWidth <= 0.1
                ? const <Shadow>[]
                : <Shadow>[
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.92),
                      blurRadius: (outlineWidth * 1.4).clamp(1.0, 6.0),
                      offset: const Offset(0, 1.2),
                    ),
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.78),
                      blurRadius: (outlineWidth * 2.4).clamp(2.0, 9.0),
                      offset: Offset.zero,
                    ),
                  ];

            String? topLine;
            String? bottomLine;
            bool topIsPrimary = true;

            if (mode == 'translated_only') {
              topLine = hasTrans ? snap.translated : snap.original;
              bottomLine = null;
            } else if (mode == 'bilingual_orig_top') {
              topLine = snap.original;
              bottomLine = hasTrans ? snap.translated : null;
              topIsPrimary = !hasTrans;
            } else {
              // Default: bilingual_trans_top (translated prominent on top, original crisp underneath)
              if (hasTrans) {
                topLine = snap.translated;
                bottomLine = snap.original;
              } else {
                topLine = snap.original;
                bottomLine = null;
              }
            }

            final effectiveBgAlpha = bgOpacity > 0.01 ? bgOpacity.clamp(0.0, 0.85) : 0.42;

            return Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 48,
                  0,
                  compact ? 16 : 48,
                  bottomInset,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: compact ? size.width - 32 : 960),
                  child: Container(
                    key: const ValueKey('ai-bilingual-subtitle-box'),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: effectiveBgAlpha),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (topLine != null && topLine.isNotEmpty)
                          Text(
                            topLine,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: topIsPrimary
                                  ? primaryColor
                                  : primaryColor.withValues(alpha: 0.80),
                              fontSize: topIsPrimary ? baseFont : baseFont * 0.78,
                              fontWeight: topIsPrimary ? FontWeight.w600 : FontWeight.w500,
                              height: 1.32,
                              shadows: shadows,
                            ),
                          ),
                        if (bottomLine != null && bottomLine.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            bottomLine,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: topIsPrimary
                                  ? primaryColor.withValues(alpha: 0.82)
                                  : primaryColor,
                              fontSize: topIsPrimary ? baseFont * 0.78 : baseFont,
                              fontWeight: topIsPrimary ? FontWeight.w500 : FontWeight.w600,
                              height: 1.3,
                              shadows: shadows,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
