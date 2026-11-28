/// Pure, unit-testable classification and recovery policy for `libmpv` / `media_kit`
/// stream error log events.
///
/// Prevents false-positive reconnect storms on cloud-drive streams (115 / Quark / Aliyun / Alist)
/// where `libmpv` frequently emits 2-4 simultaneous log lines for a single event or non-fatal
/// `tcp:` / `eof` warnings during probe/seek that `libmpv` + Rust `StreamProxy` recover from
/// automatically.
enum PlayerStreamErrorAction {
  ignore,
  hwFallback,
  transientNetwork,
  hardOpenFailure,
  fatal,
}

class PlayerStreamErrorPolicy {
  const PlayerStreamErrorPolicy._();

  static const int maxAutoRetries = 3;

  static PlayerStreamErrorAction classify(
    String rawError, {
    required bool isLocalFile,
    required bool hwDecodeEnabled,
    required bool hwFallbackAttempted,
  }) {
    final trimmed = rawError.trim();
    if (trimmed.isEmpty) return PlayerStreamErrorAction.ignore;
    final lower = trimmed.toLowerCase();

    // Non-fatal external subtitle / attachment / metadata probing noise must never tear down video!
    final isExternalSubNoise = lower.contains('subtitle') ||
        lower.contains('/subtitles/') ||
        lower.contains('external file') ||
        lower.contains('external track') ||
        lower.contains('.srt') ||
        lower.contains('.ass') ||
        lower.contains('.ssa') ||
        lower.contains('.vtt');
    if (isExternalSubNoise && !lower.contains('fatal')) {
      return PlayerStreamErrorAction.ignore;
    }

    if (hwDecodeEnabled &&
        !hwFallbackAttempted &&
        (lower.contains('hwdec') ||
            lower.contains('codec') ||
            lower.contains('videotoolbox') ||
            lower.contains('mediacodec') ||
            lower.contains('d3d11') ||
            lower.contains('vaapi'))) {
      return PlayerStreamErrorAction.hwFallback;
    }

    if (!isLocalFile) {
      if (lower.contains('failed to open') || lower.contains('loading failed')) {
        return PlayerStreamErrorAction.hardOpenFailure;
      }
      if (lower.contains('http') ||
          lower.contains('tcp') ||
          lower.contains('eof') ||
          lower.contains('timeout') ||
          lower.contains('network') ||
          lower.contains('connection')) {
        return PlayerStreamErrorAction.transientNetwork;
      }
    }

    return PlayerStreamErrorAction.fatal;
  }

  /// Sanitize a saved Continue Watching resume timestamp so we never seek to < 3s
  /// or right into the final 8 seconds (which triggers immediate EOF / false reconnects).
  static double? sanitizeResumeSecs({
    required double resumeSecs,
    required double totalDurationSecs,
  }) {
    if (!resumeSecs.isFinite || resumeSecs < 3.0) return null;
    if (totalDurationSecs.isFinite &&
        totalDurationSecs > 15.0 &&
        resumeSecs >= totalDurationSecs - 8.0) {
      return null;
    }
    return resumeSecs;
  }

  /// Grace window before executing a reconnect:
  /// - `hardOpenFailure`: 500ms (or 1200ms during an active resume/seek) to coalesce
  ///   duplicate mpv log lines into 1 clean retry.
  /// - `transientNetwork`: 2500ms normally, extended to 5000ms during Continue Watching
  ///   resume or scrub seeks so multi-GB cloud-drive byte jumps never false-trigger
  ///   a user-visible "网络波动，正在自动重连" toast or tear down a healthy seek.
  static int graceWindowMs(
    PlayerStreamErrorAction action, {
    bool isResumingOrSeeking = false,
  }) {
    if (action == PlayerStreamErrorAction.hardOpenFailure) {
      return isResumingOrSeeking ? 1200 : 500;
    }
    return isResumingOrSeeking ? 5000 : 2500;
  }

  static bool hasSelfRecovered({
    required PlayerStreamErrorAction action,
    required double anchorPosSecs,
    required double currentPosSecs,
    required bool hadDuration,
    required double currentDurationSecs,
    required bool paused,
    double anchorBufferedSecs = 0.0,
    double currentBufferedSecs = 0.0,
    int proxySpeedBps = 0,
    bool buffering = false,
    bool isResumingOrSeeking = false,
    double resumeTargetSecs = 0.0,
  }) {
    if (currentPosSecs > anchorPosSecs + 0.35) return true;
    // Resume seek landed near the intended timestamp and finished buffering!
    if (isResumingOrSeeking &&
        resumeTargetSecs > 3.0 &&
        currentPosSecs > 1.0 &&
        (currentPosSecs - resumeTargetSecs).abs() <= 15.0 &&
        !buffering) {
      return true;
    }
    if (action == PlayerStreamErrorAction.transientNetwork &&
        !hadDuration &&
        currentDurationSecs > 0 &&
        !paused) {
      return true;
    }
    // Demuxer buffer actively grew during the grace window -> data is flowing cleanly!
    if (action == PlayerStreamErrorAction.transientNetwork &&
        currentBufferedSecs > anchorBufferedSecs + 0.5) {
      return true;
    }
    // During Continue Watching resume/seek, active StreamProxy throughput proves upstream is healthy.
    if (action == PlayerStreamErrorAction.transientNetwork &&
        isResumingOrSeeking &&
        proxySpeedBps > 0 &&
        (buffering || currentBufferedSecs > anchorBufferedSecs + 0.1)) {
      return true;
    }
    return false;
  }

  /// Whether a pending transient reconnect should quietly defer another check instead of
  /// tearing down a stream whose Rust StreamProxy is still actively downloading chunks.
  static bool shouldDeferReconnect({
    required PlayerStreamErrorAction action,
    required bool paused,
    required int proxySpeedBps,
    required bool buffering,
    required bool isResumingOrSeeking,
    required int deferCount,
  }) {
    if (action != PlayerStreamErrorAction.transientNetwork) return false;
    if (paused || deferCount >= 2) return false;
    return proxySpeedBps > 0 && (buffering || isResumingOrSeeking);
  }
}
