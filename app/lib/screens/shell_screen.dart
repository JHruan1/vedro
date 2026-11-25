import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/vedro_ui.dart';
import 'detail_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'playlists_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key, required this.appState});
  final VedroAppState appState;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;

  static const _tabs = [
    _NavTab(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: '首页'),
    _NavTab(icon: Icons.grid_view_outlined, activeIcon: Icons.grid_view_rounded, label: '媒体库'),
    _NavTab(icon: Icons.search_rounded, activeIcon: Icons.search_rounded, label: '搜索'),
    _NavTab(icon: Icons.bookmark_border_rounded, activeIcon: Icons.bookmark_rounded, label: '片单'),
    _NavTab(icon: Icons.tune_rounded, activeIcon: Icons.tune_rounded, label: '设置'),
  ];

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

    if (wide) {
      return Scaffold(
        backgroundColor: VedroTheme.canvas,
        body: Row(
          children: [
            Container(
              width: 72,
              decoration: const BoxDecoration(
                color: VedroTheme.surface,
                border: Border(right: BorderSide(color: VedroTheme.line, width: 0.8)),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 18),
                    const VedroBrandMark(size: 32),
                    const SizedBox(height: 24),
                    for (var i = 0; i < _tabs.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                        child: _SidebarButton(
                          tab: _tabs[i],
                          selected: i == _index,
                          onTap: () => setState(() => _index = i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(index: _index, children: pages),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: VedroTheme.canvas,
      extendBody: true,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: GlassSurface(
            borderRadius: 22,
            blur: 32,
            color: const Color(0xCC141417),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  _BottomTabButton(
                    tab: _tabs[i],
                    selected: i == _index,
                    onTap: () => setState(() => _index = i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab {
  const _NavTab({required this.icon, required this.activeIcon, required this.label});
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({required this.tab, required this.selected, required this.onTap});
  final _NavTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      hoverScale: 1.04,
      pressScale: 0.94,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? VedroTheme.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? VedroTheme.lineStrong : Colors.transparent,
            width: 0.6,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? tab.activeIcon : tab.icon,
              size: 20,
              color: selected ? VedroTheme.fg : VedroTheme.fg3,
            ),
            const SizedBox(height: 4),
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? VedroTheme.fg : VedroTheme.fg3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomTabButton extends StatelessWidget {
  const _BottomTabButton({required this.tab, required this.selected, required this.onTap});
  final _NavTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? const Color(0x1CFFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? tab.activeIcon : tab.icon,
                size: 20,
                color: selected ? VedroTheme.fg : VedroTheme.fg3,
              ),
              const SizedBox(height: 2),
              Text(
                tab.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? VedroTheme.fg : VedroTheme.fg3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
