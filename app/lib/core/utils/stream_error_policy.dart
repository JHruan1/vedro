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

  /// Grace window before executing a reconnect:
  /// - `hardOpenFailure`: 350ms to coalesce 2-4 duplicate mpv log lines into 1 clean retry.
  /// - `transientNetwork`: 1500ms silent verification so self-recovering probe/seek warnings
  ///   never trigger a user-visible toast or stream teardown.
  static int graceWindowMs(PlayerStreamErrorAction action) =>
      action == PlayerStreamErrorAction.hardOpenFailure ? 350 : 1500;

  static bool hasSelfRecovered({
    required PlayerStreamErrorAction action,
    required double anchorPosSecs,
    required double currentPosSecs,
    required bool hadDuration,
    required double currentDurationSecs,
    required bool paused,
  }) {
    if (currentPosSecs > anchorPosSecs + 0.35) return true;
    if (action == PlayerStreamErrorAction.transientNetwork &&
        !hadDuration &&
        currentDurationSecs > 0 &&
        !paused) {
      return true;
    }
    return false;
  }
}
