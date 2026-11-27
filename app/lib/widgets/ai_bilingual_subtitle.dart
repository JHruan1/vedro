import 'dart:async';
import 'dart:math' as math;

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

  String get stableKey => '$startMs::$text';

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
    this.displayMode = 'bilingual_trans_top',
  });

  final String original;
  final String? translated;
  final bool pendingTranslation;
  final String? statusHint;
  final String displayMode;

  @override
  bool operator ==(Object other) =>
      other is BilingualCueSnapshot &&
      other.original == original &&
      other.translated == translated &&
      other.pendingTranslation == pendingTranslation &&
      other.statusHint == statusHint &&
      other.displayMode == displayMode;

  @override
  int get hashCode =>
      Object.hash(original, translated, pendingTranslation, statusHint, displayMode);
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

/// Rate-limiting policy for subtitle translation endpoints so shared public APIs
/// (such as Bilibili's free `index-translate.bilibili.com`) are always called politely.
class AiRateLimitPolicy {
  const AiRateLimitPolicy({
    required this.isPublicSharedApi,
    required this.maxConcurrency,
    required this.minIntervalMs,
    required this.maxLookaheadSecs,
    required this.minBatchSize,
    required this.maxBatchSize,
    required this.liveDebounceMs,
    required this.maxConsecutiveErrors,
    required this.backoffSecs,
  });

  final bool isPublicSharedApi;
  final int maxConcurrency;
  final int minIntervalMs;
  final int maxLookaheadSecs;
  final int minBatchSize;
  final int maxBatchSize;
  final int liveDebounceMs;
  final int maxConsecutiveErrors;
  final List<int> backoffSecs;
}

/// Lookahead AI Bilingual Subtitle + Speech-to-Subtitle (ASR) Engine.
///
/// Supports three seamless operating modes:
/// 1. **Cue Prefetch Mode**: loads full SRT/VTT/ASS cues via Rust (`load_subtitle_cues`),
///    persists & reuses local SQLite translations, and politely prefetches upcoming dialogue
///    in context-aware batches ahead of playback.
/// 2. **AI Speech-to-Subtitle (ASR) Mode**: slices upcoming 20-second audio windows via
///    pure-Rust `symphonia` + local offline SenseVoice or cloud ASR, with strict retry caps,
///    exponential backoff, and circuit-breaker protection against silent/unsupported tracks.
/// 3. **Live Fallback Mode**: translates incoming `_player.stream.subtitle` lines with
///    debouncing, non-linguistic filtering, and bounded per-language caching.
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

  static bool isBilibiliPublicEndpoint(String baseUrl) {
    final host = Uri.tryParse(baseUrl.trim())?.host.toLowerCase() ?? '';
    return host == 'index-translate.bilibili.com' || host.endsWith('.bilibili.com');
  }

  static AiRateLimitPolicy rateLimitPolicyFor(String baseUrl) {
    if (isBilibiliPublicEndpoint(baseUrl)) {
      return const AiRateLimitPolicy(
        isPublicSharedApi: true,
        maxConcurrency: 1,
        minIntervalMs: 2400,
        maxLookaheadSecs: 55,
        minBatchSize: 16,
        maxBatchSize: 24,
        liveDebounceMs: 2200,
        maxConsecutiveErrors: 3,
        backoffSecs: [6, 15, 45],
      );
    }
    return const AiRateLimitPolicy(
      isPublicSharedApi: false,
      maxConcurrency: 2,
      minIntervalMs: 350,
      maxLookaheadSecs: 300,
      minBatchSize: 8,
      maxBatchSize: 32,
      liveDebounceMs: 400,
      maxConsecutiveErrors: 4,
      backoffSecs: [3, 8, 20, 40],
    );
  }

  static bool isNonLinguisticCue(String raw) {
    final stripped = raw
        .replaceAll(RegExp(r'[\s\d\p{P}\p{S}♪♫🎵🎶]+', unicode: true), '')
        .trim();
    return stripped.isEmpty;
  }

  bool _enabled = false;
  bool _asrMode = false;
  bool _isLoadingCues = false;
  bool _isLiveFallbackMode = false;
  String _displayMode;
  String _targetLang;
  String? _lastError;
  String? _activeSourceLabel;

  // Process-wide polite rate-limit state shared across all controller instances for Bilibili public API.
  static DateTime? _globalBiliLastCompletedAt;
  static DateTime? _globalBiliCooldownUntil;

  @visibleForTesting
  static void resetGlobalRateLimitState() {
    _globalBiliLastCompletedAt = null;
    _globalBiliCooldownUntil = null;
  }

  // Subtitle cues sorted by startMs
  List<SubtitleCueModel> _cues = const [];
  // Per-target-language stable cue key (`startMs::text`) -> translated text cache
  // (immune to ASR re-sorting & cue index shifts!).
  final Map<String, Map<String, String>> _translationsByLang = {};
  // Per-target-language live text -> translated text cache (bounded to 1000 entries/lang)
  final Map<String, Map<String, String>> _liveCacheByLang = {};
  final Set<String> _inFlightBatchKeys = {};
  final Set<String> _inFlightCueKeys = {};
  final Set<String> _inFlightLiveKeys = {};
  // Cues already attempted for a language (`lang::startMs::text`), prevents infinite loops when LLM omits a cue
  final Set<String> _attemptedCueKeys = {};

  // Respectful translation pacing / backoff / circuit breaker state
  DateTime? _lastTranslateRequestAt;
  DateTime? _translateCooldownUntil;
  int _translateConsecutiveErrors = 0;
  bool _translateCircuitOpen = false;
  Timer? _translateDelayTimer;
  Timer? _liveDebounceTimer;
  Timer? _cachePersistTimer;
  String? _activeCacheKey;
  String? _pendingPersistCacheKey;
  String? _pendingPersistLang;

  // ASR audio slicing state (fixed 20s slice windows keyed by slice index)
  static const double asrSliceSecs = 20.0;
  static const int _maxAsrAttemptsPerSlice = 2;
  static const int _maxAsrConsecutiveErrors = 3;
  static const List<int> _asrBackoffSecs = [4, 10, 25];
  String? _asrSourceUrl;
  String? _asrLocalPath;
  String? _asrSourceLang;
  double _mediaDurationSecs = 0;
  final Set<int> _asrDoneSlices = {};
  final Set<int> _asrInFlightSlices = {};
  final Map<int, int> _asrFailedAttempts = {};
  bool _asrInitialSliceFinished = false;
  int _asrConsecutiveErrors = 0;
  bool _asrCircuitOpen = false;
  DateTime? _asrCooldownUntil;
  Timer? _asrDelayTimer;
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
  bool get asrCircuitOpen => _asrCircuitOpen;
  bool get translateCircuitOpen => _translateCircuitOpen;
  bool get isUsingBilibiliPublicApi => isBilibiliPublicEndpoint(appState.prefs.aiBaseUrl);
  String get displayMode => _displayMode;
  String get targetLang => _targetLang;
  String? get lastError => _lastError;
  String? get activeSourceLabel => _activeSourceLabel;
  int get totalCues => _cues.length;
  int get translatedCount => _translationsByLang[_targetLang]?.length ?? 0;

  Map<String, String> get _curLangMap =>
      _translationsByLang.putIfAbsent(_targetLang, () => <String, String>{});

  Map<String, String> get _curLiveMap =>
      _liveCacheByLang.putIfAbsent(_targetLang, () => <String, String>{});

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  void _flushPendingCachePersist() {
    final key = _pendingPersistCacheKey;
    final lang = _pendingPersistLang;
    _cachePersistTimer?.cancel();
    _cachePersistTimer = null;
    _pendingPersistCacheKey = null;
    _pendingPersistLang = null;
    if (key == null || lang == null) return;
    final map = _translationsByLang[lang];
    if (map == null || map.isEmpty || _cues.isEmpty) return;
    final indexed = <int, String>{};
    for (var i = 0; i < _cues.length; i++) {
      final tr = map[_cues[i].stableKey];
      if (tr != null && tr.isNotEmpty) indexed[i] = tr;
    }
    if (indexed.isNotEmpty) {
      unawaited(appState.saveAiTranslationCache(key, indexed));
    }
  }

  void _cancelTimers({bool flushCache = true}) {
    if (flushCache) _flushPendingCachePersist();
    _translateDelayTimer?.cancel();
    _translateDelayTimer = null;
    _liveDebounceTimer?.cancel();
    _liveDebounceTimer = null;
    _asrDelayTimer?.cancel();
    _asrDelayTimer = null;
    _cachePersistTimer?.cancel();
    _cachePersistTimer = null;
  }

  String? _computeSubtitleCacheKey(String targetLang) {
    if (_cues.isEmpty || _asrMode) return null;
    var h1 = 0x811c9dc5;
    var h2 = 0x01000193;
    void mix(String s) {
      for (var i = 0; i < s.length; i++) {
        final code = s.codeUnitAt(i);
        h1 = ((h1 ^ code) * 0x01000193) & 0xFFFFFFFF;
        h2 = ((h2 + (code << 5) - code) ^ (h1 >> 3)) & 0xFFFFFFFF;
      }
    }
    mix('$targetLang|${appState.prefs.aiModel}|${mediaTitle ?? ''}|${_cues.length}|');
    final step = math.max(1, _cues.length ~/ 24);
    for (var i = 0; i < _cues.length; i += step) {
      mix('${_cues[i].startMs}:${_cues[i].text}|');
    }
    mix('${_cues.last.startMs}:${_cues.last.text}');
    return '${h1.toRadixString(16).padLeft(8, '0')}${h2.toRadixString(16).padLeft(8, '0')}';
  }

  void _scheduleCachePersist(String cacheKey, String lang) {
    _pendingPersistCacheKey = cacheKey;
    _pendingPersistLang = lang;
    _cachePersistTimer?.cancel();
    _cachePersistTimer = Timer(const Duration(seconds: 2), () {
      if (_disposed) return;
      _flushPendingCachePersist();
    });
  }

  /// Update ASR media URL seamlessly when the player reconnects / falls back to SW decode.
  void updateAsrMediaSource({String? sourceUrl, String? localPath}) {
    if (sourceUrl != null && sourceUrl.isNotEmpty) _asrSourceUrl = sourceUrl;
    if (localPath != null && localPath.isNotEmpty) _asrLocalPath = localPath;
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
    _cancelTimers();
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
    _inFlightCueKeys.clear();
    _inFlightLiveKeys.clear();
    _attemptedCueKeys.clear();
    _asrInFlightSlices.clear();
    _asrInitialSliceFinished = false;
    _translateConsecutiveErrors = 0;
    _translateCircuitOpen = false;
    _translateCooldownUntil = null;
    _cues = const [];
    _translationsByLang.clear();
    _activeCacheKey = null;

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
        final cacheKey = _computeSubtitleCacheKey(_targetLang);
        _activeCacheKey = cacheKey;
        if (cacheKey != null) {
          final cached = await appState.loadAiTranslationCache(cacheKey);
          if (gen != _generation || _disposed) return;
          if (cached.isNotEmpty) {
            final map = _curLangMap;
            cached.forEach((idx, txt) {
              if (idx >= 0 && idx < _cues.length && txt.isNotEmpty) {
                map[_cues[idx].stableKey] = txt;
              }
            });
          }
        }
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
    _cancelTimers();
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
    _inFlightCueKeys.clear();
    _attemptedCueKeys.clear();
    _asrDoneSlices.clear();
    _asrInFlightSlices.clear();
    _asrFailedAttempts.clear();
    _asrInitialSliceFinished = false;
    _asrConsecutiveErrors = 0;
    _asrCircuitOpen = false;
    _asrCooldownUntil = null;
    _translateConsecutiveErrors = 0;
    _translateCircuitOpen = false;
    _translateCooldownUntil = null;
    _activeCacheKey = null;
    _lastAsrPromptTail = '';
    _safeNotify();

    _scheduleAsrSlices(currentPositionSecs);
    _refreshActiveCue();
  }

  /// Manual recovery after ASR circuit breaker pauses due to consecutive failures.
  void retryAsr() {
    if (!_enabled || !_asrMode || _disposed) return;
    _asrConsecutiveErrors = 0;
    _asrCircuitOpen = false;
    _asrCooldownUntil = null;
    _asrFailedAttempts.clear();
    _asrDelayTimer?.cancel();
    _asrDelayTimer = null;
    _lastError = null;
    _scheduleAsrSlices(_lastPositionSecs);
    _refreshActiveCue();
    _safeNotify();
  }

  /// Manual recovery after translation circuit breaker pauses due to rate-limit / upstream errors.
  void retryTranslation() {
    if (!_enabled || _disposed) return;
    _translateConsecutiveErrors = 0;
    _translateCircuitOpen = false;
    _translateCooldownUntil = null;
    _translateDelayTimer?.cancel();
    _translateDelayTimer = null;
    _lastError = null;
    if (_cues.isNotEmpty) {
      _scheduleLookaheadBatches(_lastPositionSecs);
    } else if (_isLiveFallbackMode && _lastLiveOriginal.isNotEmpty) {
      onLiveSubtitleText(_lastLiveOriginal);
    }
    _refreshActiveCue();
    _safeNotify();
  }

  void disable() {
    if (_disposed) return;
    ++_generation;
    _cancelTimers();
    _enabled = false;
    _asrMode = false;
    _isLoadingCues = false;
    _isLiveFallbackMode = false;
    _lastError = null;
    _inFlightBatchKeys.clear();
    _inFlightCueKeys.clear();
    _inFlightLiveKeys.clear();
    _asrInFlightSlices.clear();
    _asrCircuitOpen = false;
    _translateCircuitOpen = false;
    activeCueNotifier.value = null;
    _safeNotify();
  }

  void setDisplayMode(String mode) {
    if (_displayMode == mode || _disposed) return;
    _displayMode = mode;
    _refreshActiveCue();
    _safeNotify();
  }

  /// YouTube-style instant target language switch inside the player.
  Future<void> setTargetLang(String lang) async {
    final trimmed = lang.trim();
    if (trimmed.isEmpty || _targetLang == trimmed || _disposed) return;
    final gen = ++_generation;
    _flushPendingCachePersist();
    _translateDelayTimer?.cancel();
    _translateDelayTimer = null;
    _liveDebounceTimer?.cancel();
    _liveDebounceTimer = null;
    _targetLang = trimmed;
    _lastError = null;
    _inFlightBatchKeys.clear();
    _inFlightCueKeys.clear();
    _inFlightLiveKeys.clear();
    _attemptedCueKeys.removeWhere((k) => k.startsWith('$trimmed::'));
    _translateConsecutiveErrors = 0;
    _translateCircuitOpen = false;
    _translateCooldownUntil = null;
    _safeNotify();
    if (!_enabled) return;
    if (_cues.isNotEmpty) {
      final cacheKey = _computeSubtitleCacheKey(trimmed);
      _activeCacheKey = cacheKey;
      if (cacheKey != null && _curLangMap.isEmpty) {
        final cached = await appState.loadAiTranslationCache(cacheKey);
        if (gen != _generation || _disposed) return;
        if (cached.isNotEmpty) {
          final map = _curLangMap;
          cached.forEach((idx, txt) {
            if (idx >= 0 && idx < _cues.length && txt.isNotEmpty) {
              map[_cues[idx].stableKey] = txt;
            }
          });
        }
      }
      _scheduleLookaheadBatches(_lastPositionSecs);
    } else if (_isLiveFallbackMode && _lastLiveOriginal.isNotEmpty) {
      onLiveSubtitleText(_lastLiveOriginal);
    }
    _refreshActiveCue();
  }

  void resetForNewMedia({String? mediaTitle}) {
    if (_disposed) return;
    this.mediaTitle = mediaTitle;
    ++_generation;
    _cancelTimers();
    _enabled = false;
    _asrMode = false;
    _isLoadingCues = false;
    _isLiveFallbackMode = false;
    _lastError = null;
    _activeSourceLabel = null;
    _activeCacheKey = null;
    _cues = const [];
    _translationsByLang.clear();
    _liveCacheByLang.clear();
    _inFlightBatchKeys.clear();
    _inFlightCueKeys.clear();
    _inFlightLiveKeys.clear();
    _attemptedCueKeys.clear();
    _asrDoneSlices.clear();
    _asrInFlightSlices.clear();
    _asrFailedAttempts.clear();
    _asrInitialSliceFinished = false;
    _asrConsecutiveErrors = 0;
    _asrCircuitOpen = false;
    _asrCooldownUntil = null;
    _translateConsecutiveErrors = 0;
    _translateCircuitOpen = false;
    _translateCooldownUntil = null;
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
    _refreshActiveCue();
    if (_cues.isNotEmpty && appState.prefs.isAiReady) {
      _scheduleLookaheadBatches(positionSecs);
    }
  }

  /// Live fallback entrypoint driven by `_player.stream.subtitle` when full cue prefetch
  /// is unavailable (e.g. unextractable embedded track). Debounced & rate-limited.
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
        displayMode: _displayMode,
      );
      return;
    }

    if (isNonLinguisticCue(cleaned) || !appState.prefs.isAiReady || _translateCircuitOpen) {
      activeCueNotifier.value = BilingualCueSnapshot(
        original: cleaned,
        pendingTranslation: false,
        displayMode: _displayMode,
      );
      return;
    }

    activeCueNotifier.value = BilingualCueSnapshot(
      original: cleaned,
      pendingTranslation: true,
      displayMode: _displayMode,
    );

    final policy = rateLimitPolicyFor(appState.prefs.aiBaseUrl);
    _liveDebounceTimer?.cancel();
    final waitMs = _computeTranslateWaitMs(policy, baseDelayMs: policy.liveDebounceMs);
    _liveDebounceTimer = Timer(Duration(milliseconds: waitMs), () {
      _dispatchLiveTranslation(cleaned);
    });
  }

  void _dispatchLiveTranslation(String cleaned) {
    if (_disposed || !_enabled || !_isLiveFallbackMode || !appState.prefs.isAiReady) return;
    if (_translateCircuitOpen || _lastLiveOriginal != cleaned) return;
    if (_curLiveMap.containsKey(cleaned)) return;

    final policy = rateLimitPolicyFor(appState.prefs.aiBaseUrl);
    if (_inFlightLiveKeys.length >= policy.maxConcurrency) return;
    final key = '$_targetLang::$cleaned';
    if (!_inFlightLiveKeys.add(key)) return;

    _lastTranslateRequestAt = DateTime.now();
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
        _translateConsecutiveErrors = 0;
        _translateCooldownUntil = null;
        final translated = res[0];
        if (translated != null && translated.isNotEmpty) {
          final map = _liveCacheByLang.putIfAbsent(langAtStart, () => <String, String>{});
          if (map.length >= 1000) {
            map.remove(map.keys.first);
          }
          map[cleaned] = translated;
          if (_targetLang == langAtStart && _lastLiveOriginal == cleaned) {
            activeCueNotifier.value = BilingualCueSnapshot(
              original: cleaned,
              translated: translated,
              displayMode: _displayMode,
            );
          }
        }
      } catch (e) {
        if (gen == _generation && !_disposed) {
          _recordTranslateError(e, policy);
          _safeNotify();
        }
      } finally {
        final completedAt = DateTime.now();
        _lastTranslateRequestAt = completedAt;
        if (policy.isPublicSharedApi) {
          _globalBiliLastCompletedAt = completedAt;
        }
        _inFlightLiveKeys.remove(key);
      }
    }());
  }

  int _computeTranslateWaitMs(AiRateLimitPolicy policy, {int baseDelayMs = 0}) {
    final now = DateTime.now();
    var waitMs = baseDelayMs;
    if (_translateCooldownUntil != null && _translateCooldownUntil!.isAfter(now)) {
      final rem = _translateCooldownUntil!.difference(now).inMilliseconds;
      if (rem > waitMs) waitMs = rem;
    }
    if (policy.isPublicSharedApi &&
        _globalBiliCooldownUntil != null &&
        _globalBiliCooldownUntil!.isAfter(now)) {
      final rem = _globalBiliCooldownUntil!.difference(now).inMilliseconds;
      if (rem > waitMs) waitMs = rem;
    }
    if (_lastTranslateRequestAt != null) {
      final elapsed = now.difference(_lastTranslateRequestAt!).inMilliseconds;
      final rem = policy.minIntervalMs - elapsed;
      if (rem > waitMs) waitMs = rem;
    }
    if (policy.isPublicSharedApi && _globalBiliLastCompletedAt != null) {
      final elapsed = now.difference(_globalBiliLastCompletedAt!).inMilliseconds;
      final rem = policy.minIntervalMs - elapsed;
      if (rem > waitMs) waitMs = rem;
    }
    return waitMs.clamp(0, 60000);
  }

  void _recordTranslateError(Object e, AiRateLimitPolicy policy) {
    _translateConsecutiveErrors += 1;
    final idx = (_translateConsecutiveErrors - 1).clamp(0, policy.backoffSecs.length - 1);
    final waitSecs = policy.backoffSecs[idx];
    final until = DateTime.now().add(Duration(seconds: waitSecs));
    _translateCooldownUntil = until;
    if (policy.isPublicSharedApi) {
      if (_globalBiliCooldownUntil == null || until.isAfter(_globalBiliCooldownUntil!)) {
        _globalBiliCooldownUntil = until;
      }
    }
    if (_translateConsecutiveErrors >= policy.maxConsecutiveErrors) {
      _translateCircuitOpen = true;
      _lastError = policy.isPublicSharedApi
          ? '哔哩哔哩免费翻译接口触发限流或暂不可用，已自动暂停以保护公共接口（可稍后重试）'
          : 'AI 翻译连续失败，已自动暂停（${_cleanError(e)}）';
    } else {
      _lastError = _cleanError(e);
    }
  }

  void _refreshActiveCue() {
    if (_disposed) return;
    if (!_enabled) {
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
          pendingTranslation: cached == null &&
              appState.prefs.isAiReady &&
              !_translateCircuitOpen &&
              !isNonLinguisticCue(_lastLiveOriginal),
          displayMode: _displayMode,
        );
      }
      return;
    }
    if (_cues.isEmpty) {
      // Show a single steady hint ONLY during initial load or active first-slice ASR;
      // NEVER flicker after the first slice fails/returns silence or show a "0 cues" banner!
      final showLoadingHint = _isLoadingCues ||
          (_asrMode &&
              _asrInFlightSlices.isNotEmpty &&
              !_asrCircuitOpen &&
              !_asrInitialSliceFinished &&
              _asrDoneSlices.isEmpty);
      activeCueNotifier.value = showLoadingHint
          ? BilingualCueSnapshot(
              original: '',
              statusHint: _asrMode ? 'AI 正在识别语音字幕…' : '正在读取字幕并预读翻译…',
              displayMode: _displayMode,
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
      final sk = c.stableKey;
      final t = langMap[sk];
      if (t != null && t.isNotEmpty) {
        transLines.add(t);
      } else if (!_attemptedCueKeys.contains('$_targetLang::$sk')) {
        anyPending = true;
      }
    }

    activeCueNotifier.value = BilingualCueSnapshot(
      original: origLines.join('\n'),
      translated: transLines.isEmpty ? null : transLines.join('\n'),
      pendingTranslation: anyPending && appState.prefs.isAiReady && !_translateCircuitOpen,
      displayMode: _displayMode,
    );
  }

  List<SubtitleCueModel> _findActiveCues(int posMs) {
    if (_cues.isEmpty) return const [];
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

  int _lowerBoundStartMs(int targetMs) {
    var lo = 0;
    var hi = _cues.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_cues[mid].endMs < targetMs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return (lo - 4).clamp(0, _cues.length);
  }

  void _scheduleLookaheadBatches(
    double positionSecs, {
    bool fromPacingTimer = false,
    DateTime? seenGlobalAt,
    DateTime? seenGlobalCooldown,
  }) {
    if (!_enabled || _disposed || _cues.isEmpty || !appState.prefs.isAiReady || _translateCircuitOpen) {
      return;
    }
    final policy = rateLimitPolicyFor(appState.prefs.aiBaseUrl);
    if (_inFlightBatchKeys.length >= policy.maxConcurrency) return;

    // Respect per-instance and cross-controller global pacing/cooldown.
    // When woken by our own pacing Timer, only re-defer if a newer global request or cooldown
    // arrived while we slept (preserves both multi-controller Bilibili pacing and FakeAsync tests).
    final globalChanged = policy.isPublicSharedApi &&
        (_globalBiliLastCompletedAt != seenGlobalAt ||
            _globalBiliCooldownUntil != seenGlobalCooldown);
    final waitMs = (!fromPacingTimer || globalChanged) ? _computeTranslateWaitMs(policy) : 0;
    if (waitMs > 20) {
      if (!(_translateDelayTimer?.isActive ?? false)) {
        final snapGlobalAt = _globalBiliLastCompletedAt;
        final snapGlobalCooldown = _globalBiliCooldownUntil;
        _translateDelayTimer = Timer(Duration(milliseconds: waitMs + 25), () {
          if (!_disposed && _enabled) {
            _scheduleLookaheadBatches(
              _lastPositionSecs,
              fromPacingTimer: true,
              seenGlobalAt: snapGlobalAt,
              seenGlobalCooldown: snapGlobalCooldown,
            );
          }
        });
      }
      return;
    }

    final batchSize =
        appState.prefs.aiSubtitleBatchSize.clamp(policy.minBatchSize, policy.maxBatchSize);
    final lookaheadSecs =
        appState.prefs.aiSubtitleLookaheadSecs.clamp(30, policy.maxLookaheadSecs);
    final windowStartMs = ((positionSecs - _lastDelaySecs - 2.0) * 1000).round();
    final windowEndMs = ((positionSecs - _lastDelaySecs + lookaheadSecs) * 1000).round();

    final langMap = _curLangMap;
    // Binary-search to avoid O(N) full scan on every clock tick
    final startIdx = _lowerBoundStartMs(windowStartMs);
    int? firstUntranslated;
    for (var i = startIdx; i < _cues.length; i++) {
      final c = _cues[i];
      if (c.endMs < windowStartMs) continue;
      if (c.startMs > windowEndMs) break;
      final cueKey = '$_targetLang::${c.stableKey}';
      if (!langMap.containsKey(c.stableKey) &&
          !_attemptedCueKeys.contains(cueKey) &&
          !_inFlightCueKeys.contains(cueKey)) {
        firstUntranslated = i;
        break;
      }
    }
    if (firstUntranslated == null) return;

    final batchCues = <SubtitleCueModel>[];
    for (var i = firstUntranslated; i < _cues.length && batchCues.length < batchSize; i++) {
      final c = _cues[i];
      if (c.startMs > windowEndMs + 15000) break;
      final cueKey = '$_targetLang::${c.stableKey}';
      if (!langMap.containsKey(c.stableKey) &&
          !_attemptedCueKeys.contains(cueKey) &&
          !_inFlightCueKeys.contains(cueKey)) {
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
        '$_targetLang::${batchCues.first.startMs}-${batchCues.last.startMs}::${batchCues.length}';
    if (!_inFlightBatchKeys.add(batchKey)) return;
    final cueKeysInBatch = [for (final c in batchCues) '$_targetLang::${c.stableKey}'];
    _inFlightCueKeys.addAll(cueKeysInBatch);
    _lastTranslateRequestAt = DateTime.now();
    _safeNotify();

    final gen = _generation;
    final langAtStart = _targetLang;
    final cacheKeyAtStart = _activeCacheKey;
    // Map local sequential batch index (0..N-1) back to stableKey so ASR re-sorting can NEVER misalign results!
    final localToStable = <int, String>{
      for (var i = 0; i < batchCues.length; i++) i: batchCues[i].stableKey,
    };
    unawaited(() async {
      try {
        final translations = await appState.aiTranslateSubtitleBatch(
          lines: [
            for (var i = 0; i < batchCues.length; i++) {'idx': i, 'text': batchCues[i].text},
          ],
          context: contextLines,
          mediaTitle: mediaTitle,
          targetLang: langAtStart,
        );
        if (gen != _generation || _disposed) return;
        _translateConsecutiveErrors = 0;
        _translateCooldownUntil = null;
        for (final c in batchCues) {
          _attemptedCueKeys.add('$langAtStart::${c.stableKey}');
        }
        if (translations.isNotEmpty) {
          final map = _translationsByLang.putIfAbsent(langAtStart, () => <String, String>{});
          translations.forEach((localIdx, text) {
            final sk = localToStable[localIdx];
            if (sk != null && text.isNotEmpty) {
              map[sk] = text;
            }
          });
          _lastError = null;
          if (cacheKeyAtStart != null) {
            _scheduleCachePersist(cacheKeyAtStart, langAtStart);
          }
        }
      } catch (e) {
        if (gen == _generation && !_disposed) {
          _recordTranslateError(e, policy);
        }
      } finally {
        final completedAt = DateTime.now();
        _lastTranslateRequestAt = completedAt;
        if (policy.isPublicSharedApi) {
          _globalBiliLastCompletedAt = completedAt;
        }
        _inFlightBatchKeys.remove(batchKey);
        _inFlightCueKeys.removeAll(cueKeysInBatch);
        if (gen == _generation && !_disposed) {
          _refreshActiveCue();
          _safeNotify();
          if (!_translateCircuitOpen && _lastError == null) {
            _scheduleLookaheadBatches(_lastPositionSecs);
          }
        }
      }
    }());
  }

  void _scheduleAsrSlices(double positionSecs) {
    if (!_enabled || !_asrMode || _asrCircuitOpen || !appState.isAsrReadyForPlayback) return;
    // Keep at most 1 ASR slice in-flight to keep mobile CPU/network super cool & ordered
    if (_asrInFlightSlices.isNotEmpty) return;

    final now = DateTime.now();
    if (_asrCooldownUntil != null && _asrCooldownUntil!.isAfter(now)) {
      if (!(_asrDelayTimer?.isActive ?? false)) {
        final waitMs = _asrCooldownUntil!.difference(now).inMilliseconds + 50;
        _asrDelayTimer = Timer(Duration(milliseconds: waitMs), () {
          if (!_disposed && _enabled && _asrMode) {
            _scheduleAsrSlices(_lastPositionSecs);
          }
        });
      }
      return;
    }

    final currentSlice = (positionSecs.clamp(0.0, 86400.0) / asrSliceSecs).floor();
    // Always prioritize current slice first, then look ahead 1 slice (+20s ahead)
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
        _asrFailedAttempts.remove(sliceIdx);
        _asrConsecutiveErrors = 0;
        _asrCooldownUntil = null;
        if (rawCues.isNotEmpty) {
          final merged = List<SubtitleCueModel>.from(_cues);
          final sliceStartMs = (startSecs * 1000).round();
          final sliceEndMs = ((startSecs + asrSliceSecs) * 1000).round();
          merged.removeWhere((c) => c.startMs >= sliceStartMs && c.startMs < sliceEndMs);
          for (final rc in rawCues) {
            final parsed = SubtitleCueModel.fromJson(rc, merged.length);
            if (parsed.text.isNotEmpty) {
              merged.add(parsed);
            }
          }
          merged.sort((a, b) => a.startMs.compareTo(b.startMs));

          // Translations & attempted keys are keyed by stable `startMs::text`, so re-indexing
          // after ASR slice merge preserves every cached translation and in-flight batch intact!
          _cues = [
            for (var i = 0; i < merged.length; i++)
              SubtitleCueModel(
                idx: i,
                startMs: merged[i].startMs,
                endMs: merged[i].endMs,
                text: merged[i].text,
              ),
          ];

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
        _asrInitialSliceFinished = true;
        _lastError = null;
      } catch (e) {
        if (gen == _generation && !_disposed) {
          _asrInitialSliceFinished = true;
          final attempts = (_asrFailedAttempts[sliceIdx] ?? 0) + 1;
          _asrFailedAttempts[sliceIdx] = attempts;
          if (attempts >= _maxAsrAttemptsPerSlice) {
            // Stop retrying this broken slice forever so the player never flashes or burns CPU
            _asrDoneSlices.add(sliceIdx);
          }
          _asrConsecutiveErrors += 1;
          final backoffIdx = (_asrConsecutiveErrors - 1).clamp(0, _asrBackoffSecs.length - 1);
          _asrCooldownUntil = DateTime.now().add(Duration(seconds: _asrBackoffSecs[backoffIdx]));
          if (_asrConsecutiveErrors >= _maxAsrConsecutiveErrors) {
            _asrCircuitOpen = true;
            _lastError = '语音识别连续失败，已暂停以节省电量（${_cleanError(e)}）';
          } else {
            _lastError = _cleanError(e);
          }
        }
      } finally {
        _asrInFlightSlices.remove(sliceIdx);
        if (gen == _generation && !_disposed) {
          _refreshActiveCue();
          _safeNotify();
          if (appState.prefs.isAiReady && _cues.isNotEmpty && !_translateCircuitOpen) {
            _scheduleLookaheadBatches(_lastPositionSecs);
          }
          if (!_asrCircuitOpen && _lastError == null) {
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
    _flushPendingCachePersist();
    _disposed = true;
    ++_generation;
    _cancelTimers(flushCache: false);
    activeCueNotifier.dispose();
    super.dispose();
  }
}

/// Cinema-grade bilingual subtitle overlay driven purely by `ValueListenableBuilder`.
/// Respects user's subtitle scale, vertical position, font family, color, outline width, and background opacity.
class AiBilingualSubtitleOverlay extends StatelessWidget {
  const AiBilingualSubtitleOverlay({
    super.key,
    required this.controller,
    required this.subScale,
    this.translationFontScale = 1.0,
    required this.subPos,
    required this.colorHex,
    required this.outlineWidth,
    required this.bgOpacity,
    this.fontFamily,
  });

  final AiSubtitleTranslatorController controller;
  final double subScale;
  final double translationFontScale;
  final int subPos;
  final String colorHex;
  final double outlineWidth;
  final double bgOpacity;
  final String? fontFamily;

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
            final transScale = translationFontScale.clamp(0.6, 1.8);
            // subPos: 100 => bottom edge (~22px), 60 => lifted ~34% up the screen (PiP-safe upper bound!)
            final maxBottomInset = math.max(18.0, size.height * 0.48);
            final bottomInset =
                (22.0 + ((100 - subPos.clamp(60, 100)) / 40.0) * (size.height * 0.34))
                    .clamp(18.0, maxBottomInset);

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
            final mode = snap.displayMode;
            final hasTrans = snap.translated != null && snap.translated!.trim().isNotEmpty;
            final effectiveFontFamily =
                (fontFamily != null && fontFamily!.trim().isNotEmpty) ? fontFamily!.trim() : null;
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
            bool topIsTranslated = false;
            bool bottomIsTranslated = false;

            if (mode == 'translated_only') {
              topLine = hasTrans ? snap.translated : snap.original;
              topIsTranslated = hasTrans;
              bottomLine = null;
            } else if (mode == 'bilingual_orig_top') {
              topLine = snap.original;
              bottomLine = hasTrans ? snap.translated : null;
              bottomIsTranslated = hasTrans;
            } else {
              // Default: bilingual_trans_top (translated prominent on top, original crisp underneath)
              if (hasTrans) {
                topLine = snap.translated;
                bottomLine = snap.original;
                topIsTranslated = true;
              } else {
                topLine = snap.original;
                bottomLine = null;
              }
            }

            final effectiveBgAlpha = bgOpacity.isFinite ? bgOpacity.clamp(0.0, 0.85) : 0.0;

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
                  constraints: BoxConstraints(
                    maxWidth: compact ? math.max(120.0, size.width - 32) : 960,
                  ),
                  child: Container(
                    key: const ValueKey('ai-bilingual-subtitle-box'),
                    padding: EdgeInsets.symmetric(
                      horizontal: effectiveBgAlpha > 0.01 ? 14 : 6,
                      vertical: effectiveBgAlpha > 0.01 ? 7 : 3,
                    ),
                    decoration: effectiveBgAlpha > 0.01
                        ? BoxDecoration(
                            color: Colors.black.withValues(alpha: effectiveBgAlpha),
                            borderRadius: BorderRadius.circular(10),
                          )
                        : null,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (topLine != null && topLine.isNotEmpty)
                          Text(
                            topLine,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: effectiveFontFamily,
                              color: (topIsTranslated || !hasTrans)
                                  ? primaryColor
                                  : primaryColor.withValues(alpha: 0.82),
                              fontSize: topIsTranslated
                                  ? baseFont * transScale
                                  : (hasTrans ? baseFont * 0.78 : baseFont * transScale),
                              fontWeight: (topIsTranslated || !hasTrans)
                                  ? FontWeight.w600
                                  : FontWeight.w500,
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
                              fontFamily: effectiveFontFamily,
                              color: bottomIsTranslated
                                  ? primaryColor
                                  : primaryColor.withValues(alpha: 0.82),
                              fontSize: bottomIsTranslated
                                  ? baseFont * transScale
                                  : baseFont * 0.78,
                              fontWeight: bottomIsTranslated ? FontWeight.w600 : FontWeight.w500,
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
