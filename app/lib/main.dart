import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'core/ffi/vedro_bridge.dart';
import 'core/theme/vedro_theme.dart';
import 'screens/server_connect_screen.dart';
import 'screens/shell_screen.dart';
import 'state/app_state.dart';

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
      home: ListenableBuilder(
        listenable: _appState,
        builder: (context, _) {
          if (!_appState.isInitialized) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (!_appState.isSignedIn) {
            return ServerConnectScreen(appState: _appState);
          }
          return ShellScreen(appState: _appState);
        },
      ),
    );
  }
}
