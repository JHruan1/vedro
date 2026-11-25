import 'package:flutter/material.dart';

import 'core/ffi/prism_bridge.dart';
import 'core/theme/prism_theme.dart';
import 'screens/server_connect_screen.dart';
import 'screens/shell_screen.dart';
import 'state/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final core = PrismFfiBridge.open();
  runApp(PrismPlayerApp(core: core));
}

class PrismPlayerApp extends StatefulWidget {
  const PrismPlayerApp({super.key, required this.core});
  final PrismCoreClient core;

  @override
  State<PrismPlayerApp> createState() => _PrismPlayerAppState();
}

class _PrismPlayerAppState extends State<PrismPlayerApp> {
  late final PrismAppState _appState;

  @override
  void initState() {
    super.initState();
    _appState = PrismAppState(widget.core)..initialize();
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
      title: 'Prism Player',
      debugShowCheckedModeBanner: false,
      theme: PrismTheme.dark(),
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
