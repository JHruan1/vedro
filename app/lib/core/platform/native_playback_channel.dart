import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform channel bridging Flutter UI with native OS hardware & window capabilities:
/// - macOS: Native NSWindow Fullscreen, Titlebar Zoom, Always-on-Top, NSOpenPanel Picker, Drag-and-Drop
/// - Windows: Borderless Win32 Fullscreen, Zoom, Always-on-Top, IFileOpenDialog Picker, DXGI HDR10, WASAPI
/// - Android: MediaCodec Dolby Vision probe, AudioTrack IEC61937 Atmos, PiP, WakeLock
/// - iOS: Metal EDR + AVSampleBufferDisplayLayer Dolby Vision, AVAudioSession Spatial Audio, Idle Timer
class NativePlaybackChannel {
  static const MethodChannel _channel = MethodChannel('com.vedro.player/hardware');
  static final ValueNotifier<bool> fullscreenNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<List<String>> droppedFilesNotifier = ValueNotifier<List<String>>(const []);
  static bool _listenerBound = false;
  static String? _lastChromeSig;

  /// Syncs native OS window titlebar / frame / status-bar / nav-bar colors with the active Vedro page skin
  /// (Windows 11 DWM `DWMWA_CAPTION_COLOR` & `DWMWA_TEXT_COLOR`, macOS `NSWindow`, Android InsetsController, iOS UIWindow).
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

  static bool isVideoFile(String path) {
    final ext = _extOf(path);
    return videoExtensions.contains(ext);
  }

  static bool isSubtitleFile(String path) {
    final ext = _extOf(path);
    return subtitleExtensions.contains(ext);
  }

  static String _extOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot + 1 >= path.length) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  /// Given a dropped/picked local video file OR folder, returns a naturally-sorted list
  /// of playable video files in that folder plus the starting index.
  static ({List<String> files, int startIndex}) resolveLocalPlaylist(String path) {
    try {
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.directory) {
        final dir = Directory(path);
        final list = dir
            .listSync()
            .whereType<File>()
            .map((f) => f.path)
            .where(isVideoFile)
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        return (files: list, startIndex: 0);
      }
      if (type == FileSystemEntityType.file && isVideoFile(path)) {
        final parent = File(path).parent;
        final siblings = parent
            .listSync()
            .whereType<File>()
            .map((f) => f.path)
            .where(isVideoFile)
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        final idx = siblings.indexOf(path);
        if (siblings.isNotEmpty && idx >= 0) {
          return (files: siblings, startIndex: idx);
        }
        return (files: [path], startIndex: 0);
      }
    } catch (_) {}
    return (files: const [], startIndex: 0);
  }

  /// Finds matching sidecar subtitle files (`.srt`/`.ass`/`.vtt`) sharing the same stem as [videoPath].
  static List<String> findSidecarSubtitles(String videoPath) {
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
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('queryCapabilities');
      if (res != null) return res;
    } on MissingPluginException {
      // Fallback on headless test runner or hosts without plugin registered
    } catch (_) {}
    return const {
      'supports_hdr10': true,
      'supports_hlg': true,
      'supports_native_dolby_vision': false,
      'supports_atmos_bitstream': false,
      'supports_spatial_audio': false,
      'max_luminance_nits': 1000,
      'refresh_rate_hz': 60.0,
    };
  }

  static Future<int?> attachNativeVideoSurface() async {
    try {
      return await _channel.invokeMethod<int>('createVideoSurface');
    } catch (_) {
      return null;
    }
  }

  static Future<void> enterPictureInPicture() async {
    try {
      await _channel.invokeMethod<void>('enterPiP');
    } catch (_) {}
  }

  static Future<void> setKeepScreenOn(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setKeepScreenOn', {'enabled': enabled});
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
      await _channel.invokeMethod<void>('toggleZoom');
    } catch (_) {}
  }

  static Future<bool> setAlwaysOnTop(bool enabled) async {
    try {
      return (await _channel.invokeMethod<bool>('setAlwaysOnTop', {'enabled': enabled})) ?? enabled;
    } catch (_) {
      return enabled;
    }
  }

  /// Opens native macOS NSOpenPanel or Windows IFileOpenDialog.
  /// Returns selected file/folder paths, or empty list if cancelled/unsupported.
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

  /// Opens an external HTTP/HTTPS or custom scheme URL using the OS native handler
  /// (`Intent.ACTION_VIEW` on Android, `UIApplication.open` on iOS, `NSWorkspace` on macOS, `ShellExecuteW` on Windows).
  static Future<bool> openUrl(String url) async {
    try {
      final ok = await _channel.invokeMethod<bool>('openUrl', {'url': url});
      if (ok != null) return ok;
    } on MissingPluginException {
      return false;
    } catch (_) {}
    return false;
  }

  /// Launches a media stream URL in a native external player (`Infuse`, `VLC`, `Outplayer`, `MX Player`, `PotPlayer`, etc.).
  static Future<bool> launchExternalPlayer(
    String url, {
    String player = '',
    String title = '',
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('launchExternalPlayer', {
        'url': url,
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
