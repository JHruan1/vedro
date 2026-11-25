import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../state/app_state.dart';
import 'detail_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'playlists_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key, required this.appState});
  final PrismAppState appState;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;

  void _openItem(MediaItemModel item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailScreen(item: item, appState: widget.appState),
      ),
    );
  }

  void _openLibrary(MediaItemModel lib) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LibraryScreen(
          appState: widget.appState,
          initialLibrary: lib,
          onItemTap: _openItem,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final pages = [
      HomeScreen(
        appState: widget.appState,
        onItemTap: _openItem,
        onLibraryTap: _openLibrary,
      ),
      LibraryScreen(
        appState: widget.appState,
        onItemTap: _openItem,
      ),
      SearchScreen(
        appState: widget.appState,
        onItemTap: _openItem,
      ),
      PlaylistsScreen(
        appState: widget.appState,
        onItemTap: _openItem,
      ),
      SettingsScreen(appState: widget.appState),
    ];

    const destinations = [
      NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: '首页'),
      NavigationDestination(icon: Icon(Icons.video_library_outlined), selectedIcon: Icon(Icons.video_library_rounded), label: '媒体库'),
      NavigationDestination(icon: Icon(Icons.search_rounded), selectedIcon: Icon(Icons.search_rounded), label: '搜索'),
      NavigationDestination(icon: Icon(Icons.playlist_play_rounded), selectedIcon: Icon(Icons.playlist_play_rounded), label: '片单'),
      NavigationDestination(icon: Icon(Icons.tune_rounded), selectedIcon: Icon(Icons.tune_rounded), label: '设置'),
    ];

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Icon(Icons.play_circle_filled_rounded, size: 34),
              ),
              destinations: destinations
                  .map((d) => NavigationRailDestination(
                        icon: d.icon,
                        selectedIcon: d.selectedIcon,
                        label: Text(d.label),
                      ))
                  .toList(),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: pages[_index]),
          ],
        ),
      );
    }

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: destinations,
      ),
    );
  }
}
