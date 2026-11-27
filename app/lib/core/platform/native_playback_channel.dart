import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform channel bridging Flutter UI with native OS hardware & window capabilities:
/// - macOS: Native NSWindow Fullscreen, Titlebar Zoom, Always-on-Top, NSOpenPanel Picker, Drag-and-Drop
/// - Windows: Borderless Win32 Fullscreen, Zoom, Always-on-Top, IFileOpenDialog Picker, DXGI HDR10, WASAPI
/// - Android & Android TV: TV/Leanback detection, AudioFocus/BecomingNoisy, real Brightness, Battery, Wi-Fi, PiP, WakeLock
/// - iOS: Lazy AVAudioSession + interruption/route-change pause, real Brightness, Battery, EDR HDR/DoVi, Idle Timer
/// - Linux: GTK Fullscreen, Always-on-Top, Idle Inhibit WakeLock, Safe URL open
class NativePlaybackChannel {
  static const MethodChannel _channel = MethodChannel('com.vedro.player/hardware');
  static final ValueNotifier<bool> fullscreenNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> maximizedNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> playerHudAutoHideNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> pipModeNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<int> audioInterruptCountNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<Map<String, dynamic>?> mediaActionNotifier =
      ValueNotifier<Map<String, dynamic>?>(null);
  static final ValueNotifier<List<String>> droppedFilesNotifier = ValueNotifier<List<String>>(const []);
  static bool detectedAndroidTv = false;
  static bool supportsNativePip = false;
  static bool _listenerBound = false;
  static String? _lastChromeSig;

  /// Defense-in-depth HTTP/HTTPS URL validator shared across all external openers.
  static bool isAllowedHttpUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.contains(RegExp(r'[\s\x00-\x1F\x7F]'))) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    return uri.host.isNotEmpty;
  }

  /// Media stream URL validator supporting HTTP(S), RTSP(S), RTMP(S), MMS, UDP, RTP.
  static bool isAllowedMediaUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.contains(RegExp(r'[\s\x00-\x1F\x7F]'))) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    const allowed = {'http', 'https', 'rtsp', 'rtsps', 'rtmp', 'rtmps', 'mms', 'udp', 'rtp'};
    if (!allowed.contains(scheme)) return false;
    return uri.host.isNotEmpty;
  }

  /// Syncs native OS window titlebar / frame / status-bar / nav-bar colors with the active Vedro page skin.
  static Future<void> syncWindowChrome({
    required bool isLight,
    required int canvasArgb,
    required int fgArgb,
  }) async {
    final sig = '$isLight:$canvasArgb:$fgArgb';
    if (_lastChromeSig == sig) return;
    _lastChromeSig = sig;
    try {
      await _channel.invokeMethod<void>('setWindowChrome', {
        'is_light': isLight,
        'canvas_argb': canvasArgb,
        'fg_argb': fgArgb,
      });
    } catch (_) {}
  }

  static const Set<String> videoExtensions = {
    'mkv', 'mp4', 'm4v', 'mov', 'ts', 'm2ts', 'webm', 'avi', 'flv', 'wmv', 'mpg', 'mpeg', 'ogm', 'iso', 'strm',
  };

  static const Set<String> subtitleExtensions = {
    'srt', 'ass', 'ssa', 'vtt', 'sub', 'sup', 'idx', 'smi',
  };

  static bool isVideoFile(String path) => videoExtensions.contains(_extOf(path));

  static bool isSubtitleFile(String path) => subtitleExtensions.contains(_extOf(path));

  static String _extOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot + 1 >= path.length) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  static ({List<String> files, int startIndex}) resolveLocalPlaylist(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return (files: const [], startIndex: 0);
    // Android SAF content:// URIs cannot be queried via dart:io FileSystemEntity,
    // and libmpv / media_kit opens content:// directly via ContentResolver.
    if (trimmed.startsWith('content://')) {
      return (files: [trimmed], startIndex: 0);
    }
    try {
      final type = FileSystemEntity.typeSync(trimmed);
      if (type == FileSystemEntityType.directory) {
        final dir = Directory(trimmed);
        final list = dir
            .listSync()
            .whereType<File>()
            .map((f) => f.path)
            .where(isVideoFile)
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        return (files: list, startIndex: 0);
      }
      if (type == FileSystemEntityType.file && isVideoFile(trimmed)) {
        final parent = File(trimmed).parent;
        final siblings = parent
            .listSync()
            .whereType<File>()
            .map((f) => f.path)
            .where(isVideoFile)
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        final idx = siblings.indexOf(trimmed);
        if (siblings.isNotEmpty && idx >= 0) {
          return (files: siblings, startIndex: idx);
        }
        return (files: [trimmed], startIndex: 0);
      }
    } catch (_) {}
    return (files: const [], startIndex: 0);
  }

  static List<String> findSidecarSubtitles(String videoPath) {
    if (videoPath.trim().startsWith('content://')) return const [];
    try {
      final file = File(videoPath);
      final name = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : '';
      final dot = name.lastIndexOf('.');
      final stem = (dot > 0 ? name.substring(0, dot) : name).toLowerCase();
      if (stem.isEmpty) return const [];
      return file.parent
          .listSync()
          .whereType<File>()
          .where((f) {
            if (!isSubtitleFile(f.path)) return false;
            final fn = f.uri.pathSegments.isNotEmpty ? f.uri.pathSegments.last.toLowerCase() : '';
            return fn.startsWith(stem);
          })
          .map((f) => f.path)
          .toList()
        ..sort();
    } catch (_) {
      return const [];
    }
  }

  static void ensureWindowListener() {
    if (_listenerBound) return;
    _listenerBound = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'fullscreenChanged' && call.arguments is Map) {
        final fs = (call.arguments as Map)['fullscreen'] == true;
        if (fullscreenNotifier.value != fs) {
          fullscreenNotifier.value = fs;
        }
      } else if (call.method == 'pipModeChanged' && call.arguments is Map) {
        final inPip = (call.arguments as Map)['in_pip'] == true;
        if (pipModeNotifier.value != inPip) {
          pipModeNotifier.value = inPip;
        }
      } else if (call.method == 'audioInterrupted') {
        audioInterruptCountNotifier.value = audioInterruptCountNotifier.value + 1;
      } else if (call.method == 'mediaAction' && call.arguments is Map) {
        final raw = Map<String, dynamic>.from(call.arguments as Map);
        raw['_ts'] = DateTime.now().microsecondsSinceEpoch;
        mediaActionNotifier.value = raw;
      } else if (call.method == 'filesDropped' && call.arguments is Map) {
        final raw = (call.arguments as Map)['paths'];
        if (raw is List) {
          final paths = raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
          if (paths.isNotEmpty) {
            droppedFilesNotifier.value = List<String>.from(paths);
          }
        }
      }
    });
  }

  static Future<Map<String, dynamic>> queryDisplayAndAudioCapabilities() async {
    ensureWindowListener();
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('queryCapabilities');
      if (res != null) {
        detectedAndroidTv = res['is_tv'] == true;
        supportsNativePip = res['supports_pip'] == true;
        return res;
      }
    } on MissingPluginException {
      // Fallback on headless test runner or hosts without plugin registered
    } catch (_) {}
    return const {
      'is_tv': false,
      'has_touchscreen': false,
      'supports_pip': false,
      'supports_hdr10': false,
      'supports_hlg': false,
      'supports_native_dolby_vision': false,
      'supports_atmos_bitstream': false,
      'supports_spatial_audio': false,
      'max_luminance_nits': 400,
      'refresh_rate_hz': 60.0,
    };
  }

  static Future<void> setAudioPlaybackActive(bool active) async {
    ensureWindowListener();
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    try {
      await _channel.invokeMethod<void>('setAudioPlaybackActive', {'active': active});
    } catch (_) {}
  }

  static Future<double?> getScreenBrightness() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return null;
    try {
      final v = await _channel.invokeMethod<num>('getScreenBrightness');
      return v?.toDouble().clamp(0.01, 1.0);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setScreenBrightness(double value) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    try {
      await _channel.invokeMethod<void>('setScreenBrightness', {
        'value': value.clamp(0.01, 1.0),
      });
    } catch (_) {}
  }

  static Future<void> resetScreenBrightness() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    try {
      await _channel.invokeMethod<void>('resetScreenBrightness');
    } catch (_) {}
  }

  static Future<({int level, bool charging})?> getBatteryInfo() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return null;
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getBatteryInfo');
      if (res != null) {
        final lvl = (res['level'] as num?)?.toInt() ?? -1;
        if (lvl >= 0) {
          return (level: lvl.clamp(0, 100), charging: res['charging'] == true);
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> isWifiConnected() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return true;
    try {
      final ok = await _channel.invokeMethod<bool>('isWifiConnected');
      return ok ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<int?> attachNativeVideoSurface() async {
    try {
      return await _channel.invokeMethod<int>('createVideoSurface');
    } catch (_) {
      return null;
    }
  }

  static Future<bool> enterPictureInPicture({int aspectW = 16, int aspectH = 9}) async {
    ensureWindowListener();
    try {
      final ok = await _channel.invokeMethod<bool>('enterPiP', {
        'aspect_w': aspectW,
        'aspect_h': aspectH,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setAutoPipEnabled(bool enabled, {int aspectW = 16, int aspectH = 9}) async {
    if (kIsWeb || !Platform.isAndroid) return;
    ensureWindowListener();
    try {
      await _channel.invokeMethod<void>('setAutoPipEnabled', {
        'enabled': enabled,
        'aspect_w': aspectW,
        'aspect_h': aspectH,
      });
    } catch (_) {}
  }

  /// Sync OS lock-screen / Bluetooth / AirPods / TV CEC Now Playing metadata & playback state.
  static Future<void> updateNowPlaying({
    required String title,
    String subtitle = '',
    bool playing = false,
    double positionSecs = 0.0,
    double durationSecs = 0.0,
    double speed = 1.0,
    bool hasNext = false,
    bool hasPrevious = false,
    bool active = true,
  }) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS)) return;
    ensureWindowListener();
    final safePos = positionSecs.isFinite && positionSecs > 0 ? positionSecs : 0.0;
    final safeDur = durationSecs.isFinite && durationSecs > 0 ? durationSecs : 0.0;
    try {
      await _channel.invokeMethod<void>('updateNowPlaying', {
        'title': title,
        'subtitle': subtitle,
        'is_playing': playing,
        'playing': playing,
        'position_ms': (safePos * 1000).round(),
        'duration_ms': (safeDur * 1000).round(),
        'position_secs': safePos,
        'duration_secs': safeDur,
        'speed': speed.isFinite ? speed : 1.0,
        'has_next': hasNext,
        'has_previous': hasPrevious,
        'active': active,
      });
    } catch (_) {}
  }

  /// Export a PNG screenshot to the OS Photos/Gallery (mobile) or Pictures/Vedro folder (desktop).
  static Future<String?> saveScreenshotToGallery(Uint8List bytes, String fileName) async {
    if (bytes.isEmpty) return null;
    try {
      final res = await _channel.invokeMethod<dynamic>('saveScreenshotToGallery', {
        'bytes': bytes,
        'file_name': fileName,
      });
      if (res is String && res.isNotEmpty) return res;
      if (res == true) return fileName;
    } catch (_) {}
    return null;
  }

  static Future<void> setKeepScreenOn(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setKeepScreenOn', {'enabled': enabled});
    } catch (_) {}
  }

  static Future<void> setPreferredFrameRate(double fps) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setPreferredFrameRate', {'fps': fps});
    } catch (_) {}
  }

  static Future<bool> isFullscreen() async {
    ensureWindowListener();
    try {
      final fs = (await _channel.invokeMethod<bool>('isFullscreen')) ?? false;
      fullscreenNotifier.value = fs;
      return fs;
    } catch (_) {
      return fullscreenNotifier.value;
    }
  }

  static Future<bool> toggleFullscreen() async {
    ensureWindowListener();
    try {
      final fs = (await _channel.invokeMethod<bool>('toggleFullscreen')) ?? false;
      fullscreenNotifier.value = fs;
      return fs;
    } catch (_) {
      return fullscreenNotifier.value;
    }
  }

  static Future<bool> setFullscreen(bool enabled) async {
    ensureWindowListener();
    try {
      final fs =
          (await _channel.invokeMethod<bool>('setFullscreen', {'enabled': enabled})) ?? enabled;
      fullscreenNotifier.value = fs;
      return fs;
    } catch (_) {
      return fullscreenNotifier.value;
    }
  }

  static Future<void> toggleZoom() async {
    try {
      final zoomed = await _channel.invokeMethod<bool>('toggleZoom');
      if (zoomed != null) {
        maximizedNotifier.value = zoomed;
      }
    } catch (_) {}
  }

  static Future<bool> syncMaximizedState() async {
    if (kIsWeb || !Platform.isWindows) return false;
    try {
      final zoomed = (await _channel.invokeMethod<bool>('isMaximized')) ?? false;
      if (maximizedNotifier.value != zoomed) {
        maximizedNotifier.value = zoomed;
      }
      return zoomed;
    } catch (_) {
      return maximizedNotifier.value;
    }
  }

  static Future<void> minimizeWindow() async {
    try {
      await _channel.invokeMethod<void>('minimizeWindow');
    } catch (_) {}
  }

  static Future<void> closeWindow() async {
    try {
      await _channel.invokeMethod<void>('closeWindow');
    } catch (_) {}
  }

  static Future<void> startWindowDrag() async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      await _channel.invokeMethod<void>('startWindowDrag');
    } catch (_) {}
  }

  static Future<void> startWindowResize(String edge) async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      await _channel.invokeMethod<void>('startWindowResize', {'edge': edge});
    } catch (_) {}
  }

  static Future<void> showWindowSystemMenu() async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      await _channel.invokeMethod<void>('showWindowSystemMenu');
    } catch (_) {}
  }

  static Future<bool> setAlwaysOnTop(bool enabled) async {
    try {
      return (await _channel.invokeMethod<bool>('setAlwaysOnTop', {'enabled': enabled})) ?? enabled;
    } catch (_) {
      return enabled;
    }
  }

  static Future<List<String>> pickFiles({
    List<String> extensions = const [],
    bool allowDirectory = false,
    bool allowMultiple = false,
    String title = '选择文件',
  }) async {
    try {
      final res = await _channel.invokeMethod<List<dynamic>>('pickFiles', {
        'extensions': extensions,
        'allow_directory': allowDirectory,
        'allow_multiple': allowMultiple,
        'title': title,
      });
      if (res != null) {
        return res.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {}
    return const [];
  }

  static Future<bool> openUrl(String url) async {
    if (!isAllowedHttpUrl(url)) return false;
    final clean = url.trim();
    try {
      final ok = await _channel.invokeMethod<bool>('openUrl', {'url': clean});
      if (ok == true) return true;
    } on MissingPluginException {
      // Fallback below on desktop hosts without plugin handler
    } catch (_) {}
    if (!kIsWeb) {
      try {
        if (Platform.isMacOS) {
          await Process.start('open', [clean], mode: ProcessStartMode.detached);
          return true;
        }
        if (Platform.isLinux) {
          await Process.start('xdg-open', [clean], mode: ProcessStartMode.detached);
          return true;
        }
        if (Platform.isWindows) {
          await Process.start('explorer.exe', [clean], mode: ProcessStartMode.detached);
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  static Future<bool> launchExternalPlayer(
    String url, {
    String player = '',
    String title = '',
  }) async {
    if (!isAllowedHttpUrl(url)) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('launchExternalPlayer', {
        'url': url.trim(),
        'player': player,
        'title': title,
      });
      if (ok != null) return ok;
    } on MissingPluginException {
      return false;
    } catch (_) {}
    return false;
  }
}
