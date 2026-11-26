import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'core/ffi/vedro_bridge.dart';
import 'core/theme/vedro_skin.dart';
import 'core/theme/vedro_theme.dart';
import 'screens/shell_screen.dart';
import 'state/app_state.dart';
import 'widgets/app_lock_gate.dart';
import 'widgets/vedro_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

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

  String? dbPath;
  try {
    final dir = await getApplicationSupportDirectory();
    dbPath = '${dir.path}/vedro.db';
  } catch (_) {
    dbPath = null;
  }

  final core = VedroFfiBridge.open(dbPath: dbPath);
  runApp(VedroApp(core: core));
}

class VedroApp extends StatefulWidget {
  const VedroApp({super.key, required this.core});
  final VedroCoreClient core;

  @override
  State<VedroApp> createState() => _VedroAppState();
}

class _VedroAppState extends State<VedroApp> {
  late final VedroAppState _appState;

  @override
  void initState() {
    super.initState();
    _appState = VedroAppState(widget.core)..initialize();
  }

  @override
  void dispose() {
    _appState.dispose();
    widget.core.dispose();
    super.dispose();
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
          theme: VedroTheme.fromSkin(skin),
          scrollBehavior: const VedroScrollBehavior(),
          home: AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlayStyle,
            child: AppLockGate(
              appState: _appState,
              child: AnimatedSwitcher(
                duration: Duration(milliseconds: _appState.prefs.reduceMotion ? 0 : 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
