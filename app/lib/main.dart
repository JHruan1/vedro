import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'core/ffi/vedro_bridge.dart';
import 'core/theme/vedro_theme.dart';
import 'screens/shell_screen.dart';
import 'state/app_state.dart';
import 'widgets/vedro_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

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
    return MaterialApp(
      title: 'Vedro',
      debugShowCheckedModeBanner: false,
      theme: VedroTheme.dark(),
      scrollBehavior: const VedroScrollBehavior(),
      home: ListenableBuilder(
        listenable: _appState,
        builder: (context, _) {
          // Never trap users behind a full-screen login wall — launch directly into
          // the main Shell workspace (Home Server Hub, Settings, Aggregated Search).
          final Widget child;
          if (!_appState.isInitialized || _appState.isAutoRestoring) {
            child = Scaffold(
              key: const ValueKey('splash'),
              backgroundColor: VedroTheme.canvas,
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BreathingBrandMark(size: 50),
                    const SizedBox(height: 18),
                    Text(
                      _appState.isAutoRestoring ? '正在连接媒体服务器…' : 'Vedro',
                      style: const TextStyle(
                        color: VedroTheme.fg2,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          } else {
            child = ShellScreen(
              key: const ValueKey('shell'),
              appState: _appState,
            );
          }
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: child,
          );
        },
      ),
    );
  }
}
