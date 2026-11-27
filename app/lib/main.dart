import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'core/ffi/vedro_bridge.dart';
import 'core/platform/native_playback_channel.dart';
import 'core/platform/platform_perf.dart';
import 'core/theme/vedro_skin.dart';
import 'core/theme/vedro_theme.dart';
import 'screens/shell_screen.dart';
import 'state/app_state.dart';
import 'widgets/app_lock_gate.dart';
import 'widgets/local_asr_engine.dart';
import 'widgets/vedro_ui.dart';
import 'widgets/windows_immersive_frame.dart';

Future<void> main(List<String> args) async {
  runZonedGuarded<void>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      PlatformPerfProfile.configureImageCache();
      if (args.isNotEmpty) {
        final startupPaths = args
            .map((a) => a.trim())
            .where((a) => a.isNotEmpty && !a.startsWith('-'))
            .toList();
        if (startupPaths.isNotEmpty) {
          NativePlaybackChannel.droppedFilesNotifier.value = startupPaths;
        }
      }

      FlutterError.onError = (FlutterErrorDetails details) {
        if (kDebugMode) {
          FlutterError.presentError(details);
        } else {
          debugPrint('Vedro FlutterError: ${details.exceptionAsString()}');
        }
      };

      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        debugPrint('Vedro uncaught platform error: $error');
        return true;
      };

      if (!kDebugMode) {
        ErrorWidget.builder = (FlutterErrorDetails details) => const Material(
              color: Color(0xFF0B0B0D),
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded, color: Color(0xFFF87171), size: 36),
                      SizedBox(height: 10),
                      Text(
                        '当前视图渲染异常，请返回重试',
                        style: TextStyle(color: Color(0xDEFFFFFF), fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            );
      }

      try {
        // Unified Apple-style full-bleed edge-to-edge chrome on both iOS and Android
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
          systemStatusBarContrastEnforced: false,
          systemNavigationBarContrastEnforced: false,
        ));
      } catch (_) {}

      try {
        MediaKit.ensureInitialized();
      } catch (e) {
        debugPrint('MediaKit init warning: $e');
      }

      String? dbPath;
      try {
        final dir = await getApplicationSupportDirectory();
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        dbPath = '${dir.path}/vedro.db';
      } catch (_) {
        dbPath = null;
      }

      try {
        final core = VedroFfiBridge.open(dbPath: dbPath);
        runApp(VedroApp(core: core));
      } catch (e) {
        runApp(_VedroStartupFailureApp(error: e.toString(), dbPath: dbPath));
      }
    },
    (Object error, StackTrace stack) {
      debugPrint('Vedro zoned error: $error');
    },
  );
}

class _VedroStartupFailureApp extends StatefulWidget {
  const _VedroStartupFailureApp({required this.error, required this.dbPath});
  final String error;
  final String? dbPath;

  @override
  State<_VedroStartupFailureApp> createState() => _VedroStartupFailureAppState();
}

class _VedroStartupFailureAppState extends State<_VedroStartupFailureApp> {
  late String _error = widget.error;
  bool _copied = false;

  void _retry() {
    try {
      final core = VedroFfiBridge.open(dbPath: widget.dbPath);
      runApp(VedroApp(core: core));
    } catch (e) {
      setState(() {
        _error = e.toString();
        _copied = false;
      });
    }
  }

  Future<void> _copyError() async {
    try {
      await Clipboard.setData(ClipboardData(text: _error));
      if (mounted) setState(() => _copied = true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vedro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: const Color(0xFF0B0B0D),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFFBBF24), size: 46),
                  const SizedBox(height: 16),
                  const Text(
                    'Vedro 核心引擎启动失败',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    _error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 13, height: 1.45),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        autofocus: true,
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh_rounded, size: 17),
                        label: const Text('重试启动'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _copyError,
                        icon: Icon(
                          _copied ? Icons.check_rounded : Icons.copy_rounded,
                          size: 16,
                        ),
                        label: Text(_copied ? '已复制' : '复制错误详情'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VedroApp extends StatefulWidget {
  const VedroApp({super.key, required this.core});
  final VedroCoreClient core;

  @override
  State<VedroApp> createState() => _VedroAppState();
}

class _VedroAppState extends State<VedroApp> with WidgetsBindingObserver {
  late final VedroAppState _appState;
  String? _lastOverlaySig;
  String? _lastChromeSig;
  VedroSkin? _cachedSkin;
  ThemeData? _cachedTheme;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appState = VedroAppState(widget.core)..initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appState.setAppResumed(state == AppLifecycleState.resumed);
  }

  @override
  void didHaveMemoryPressure() {
    // Release decoded image cache & idle 230 MB ONNX ASR isolate immediately under OS RAM pressure
    try {
      PaintingBinding.instance.imageCache.clear();
    } catch (_) {}
    if (LocalAsrManager.instance.isWorkerLoaded && !LocalAsrManager.instance.isTranscribing) {
      unawaited(LocalAsrManager.instance.unloadEngine());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appState.dispose();
    widget.core.dispose();
    super.dispose();
  }

  ThemeData _resolveTheme(VedroSkin skin) {
    if (_cachedSkin == skin && _cachedTheme != null) {
      return _cachedTheme!;
    }
    _cachedSkin = skin;
    _cachedTheme = VedroTheme.fromSkin(skin);
    return _cachedTheme!;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _appState,
      builder: (context, _) {
        final sysBrightness = View.of(context).platformDispatcher.platformBrightness;
        final skin = _appState.prefs.activeSkinFor(
          systemBrightness: sysBrightness,
          dynamicSeedOverride: _appState.dynamicPageSeedColor,
        );
        final overlayStyle = SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: skin.isLight ? Brightness.dark : Brightness.light,
          statusBarBrightness: skin.isLight ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: skin.isLight ? Brightness.dark : Brightness.light,
          systemStatusBarContrastEnforced: false,
          systemNavigationBarContrastEnforced: false,
        );
        final overlaySig = '${skin.isLight}';
        if (_lastOverlaySig != overlaySig) {
          _lastOverlaySig = overlaySig;
          SystemChrome.setSystemUIOverlayStyle(overlayStyle);
        }
        final chromeSig = '${skin.isLight}:${skin.canvas.toARGB32()}:${skin.fg.toARGB32()}';
        if (_lastChromeSig != chromeSig) {
          _lastChromeSig = chromeSig;
          NativePlaybackChannel.syncWindowChrome(
            isLight: skin.isLight,
            canvasArgb: skin.canvas.toARGB32(),
            fgArgb: skin.fg.toARGB32(),
          );
        }

        final Widget child;
        if (!_appState.isInitialized || _appState.isAutoRestoring) {
          child = Scaffold(
            key: const ValueKey('splash'),
            backgroundColor: skin.canvas,
            body: VedroSkinCanvas(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BreathingBrandMark(size: 50),
                    const SizedBox(height: 18),
                    Text(
                      _appState.isAutoRestoring ? '正在连接媒体服务器…' : 'Vedro',
                      style: TextStyle(
                        color: skin.fg2,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        } else {
          child = ShellScreen(
            key: const ValueKey('shell'),
            appState: _appState,
          );
        }

        return MaterialApp(
          title: 'Vedro',
          debugShowCheckedModeBanner: false,
          theme: _resolveTheme(skin),
          scrollBehavior: const VedroScrollBehavior(),
          builder: (ctx, navChild) => WindowsImmersiveFrame(
            isLight: skin.isLight,
            child: AppLockGate(
              appState: _appState,
              child: navChild ?? const SizedBox.shrink(),
            ),
          ),
          home: AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlayStyle,
            child: AnimatedSwitcher(
              duration: Duration(milliseconds: _appState.prefs.reduceMotion ? 0 : 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
