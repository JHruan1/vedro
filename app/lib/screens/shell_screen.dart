import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/spotlight_search_dialog.dart';
import '../widgets/vedro_ui.dart';
import 'detail_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'player_screen.dart';
import 'playlists_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// Full-bleed cinema viewing shell inspired by Apple TV+ / SenPlayer / Forward:
/// - Desktop: Floating top translucent glass header (clear over full-bleed Hero,
///   smoothly frosting on scroll) + global Spotlight Search (`⌘K` / `/`).
/// - Mobile: Floating frosted-glass bottom pill tab bar with smooth active state.
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key, required this.appState});
  final VedroAppState appState;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;
  bool _homeScrolled = false;

  static const _desktopNav = [
    (0, '首页'),
    (1, '媒体库'),
    (3, '片单'),
    (4, '设置'),
  ];

  static const _mobileTabs = [
    _NavTab(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: '首页'),
    _NavTab(icon: Icons.grid_view_outlined, activeIcon: Icons.grid_view_rounded, label: '媒体库'),
    _NavTab(icon: Icons.search_rounded, activeIcon: Icons.search_rounded, label: '搜索'),
    _NavTab(icon: Icons.bookmark_border_rounded, activeIcon: Icons.bookmark_rounded, label: '片单'),
    _NavTab(icon: Icons.tune_rounded, activeIcon: Icons.tune_rounded, label: '设置'),
  ];

  void _openItem(MediaItemModel item, {String? heroPrefix}) {
    Navigator.of(context).push(
      vedroRoute(DetailScreen(
        item: item,
        appState: widget.appState,
        heroTag: heroPrefix != null ? '$heroPrefix-${item.id}' : null,
      )),
    );
  }

  void _quickPlay(MediaItemModel item) {
    if (item.isPlayable) {
      Navigator.of(context).push(
        vedroRoute(PlayerScreen(item: item, appState: widget.appState)),
      );
    } else {
      _openItem(item);
    }
  }

  void _openLibrary(MediaItemModel lib) {
    Navigator.of(context).push(
      vedroRoute(LibraryScreen(
        appState: widget.appState,
        initialLibrary: lib,
        onItemTap: _openItem,
        onQuickPlay: _quickPlay,
        standalone: true,
      )),
    );
  }

  void _openSpotlight() {
    showSpotlightSearch(
      context: context,
      appState: widget.appState,
      onSelect: (item) => _openItem(item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final caps = widget.appState.capabilities;
    final serverName =
        caps?.serverName.isNotEmpty == true ? caps!.serverName : 'Vedro';
    final topBarClear = _index == 0 && !_homeScrolled;

    final pages = [
      HomeScreen(
        key: const ValueKey('tab-home'),
        appState: widget.appState,
        onItemTap: (item, {String? heroPrefix}) =>
            _openItem(item, heroPrefix: heroPrefix),
        onQuickPlay: _quickPlay,
        onLibraryTap: _openLibrary,
        onScrollChanged: (scrolled) {
          if (scrolled != _homeScrolled) {
            setState(() => _homeScrolled = scrolled);
          }
        },
      ),
      LibraryScreen(
        key: const ValueKey('tab-library'),
        appState: widget.appState,
        onItemTap: _openItem,
        onQuickPlay: _quickPlay,
        topInset: wide ? 64 : 0,
      ),
      SearchScreen(
        key: const ValueKey('tab-search'),
        appState: widget.appState,
        onItemTap: _openItem,
      ),
      PlaylistsScreen(
        key: const ValueKey('tab-playlists'),
        appState: widget.appState,
        onItemTap: _openItem,
        topInset: wide ? 64 : 0,
      ),
      SettingsScreen(
        key: const ValueKey('tab-settings'),
        appState: widget.appState,
        topInset: wide ? 64 : 0,
      ),
    ];

    final body = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: pages[_index],
    );

    if (wide) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _openSpotlight,
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): _openSpotlight,
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: VedroTheme.canvas,
            body: Stack(
              children: [
                Positioned.fill(child: body),
                // Floating translucent Apple TV+ / Forward top glass bar
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _FloatingDesktopHeader(
                    serverName: serverName,
                    clear: topBarClear,
                    activeIndex: _index,
                    navItems: _desktopNav,
                    onSelectIndex: (i) => setState(() => _index = i),
                    onOpenSearch: _openSpotlight,
                    onRefresh: widget.appState.refreshHome,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: VedroTheme.canvas,
      extendBody: true,
      body: body,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: GlassSurface(
            borderRadius: 24,
            blur: 32,
            color: const Color(0xD4141417),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (var i = 0; i < _mobileTabs.length; i++)
                  _BottomTabButton(
                    tab: _mobileTabs[i],
                    selected: i == _index,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _index = i);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingDesktopHeader extends StatelessWidget {
  const _FloatingDesktopHeader({
    required this.serverName,
    required this.clear,
    required this.activeIndex,
    required this.navItems,
    required this.onSelectIndex,
    required this.onOpenSearch,
    required this.onRefresh,
  });

  final String serverName;
  final bool clear;
  final int activeIndex;
  final List<(int, String)> navItems;
  final ValueChanged<int> onSelectIndex;
  final VoidCallback onOpenSearch;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final macTrafficClearance = !kIsWeb && Platform.isMacOS ? 82.0 : 28.0;
    final content = SafeArea(
      bottom: false,
      child: Container(
        height: 58,
        padding: EdgeInsets.fromLTRB(macTrafficClearance, 0, 28, 0),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => onSelectIndex(0),
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const VedroBrandMark(size: 28),
                  const SizedBox(width: 10),
                  Text(
                    serverName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            for (final (idx, label) in navItems)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: PressableScale(
                  onTap: () => onSelectIndex(idx),
                  hoverScale: 1.03,
                  pressScale: 0.96,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: VedroTheme.easeOut,
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: activeIndex == idx
                          ? const Color(0x20FFFFFF)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: activeIndex == idx
                            ? Colors.white
                            : (clear ? const Color(0xCCFFFFFF) : VedroTheme.fg2),
                        fontSize: 13.5,
                        fontWeight: activeIndex == idx ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            // Spotlight Search trigger pill
            PressableScale(
              onTap: onOpenSearch,
              hoverScale: 1.02,
              pressScale: 0.97,
              child: Container(
                width: 224,
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: clear ? const Color(0x24FFFFFF) : VedroTheme.surface2,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: clear ? const Color(0x28FFFFFF) : VedroTheme.line,
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 16,
                      color: clear ? const Color(0xD9FFFFFF) : VedroTheme.fg3,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '搜索',
                        style: TextStyle(
                          color: clear ? const Color(0xCCFFFFFF) : VedroTheme.fg3,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0x1CFFFFFF),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        '⌘K',
                        style: TextStyle(
                          color: Color(0xB8FFFFFF),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            PressableScale(
              onTap: onRefresh,
              hoverScale: 1.06,
              pressScale: 0.92,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: clear ? const Color(0x1EFFFFFF) : VedroTheme.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: clear ? const Color(0x24FFFFFF) : VedroTheme.line,
                    width: 0.7,
                  ),
                ),
                child: Icon(
                  Icons.refresh_rounded,
                  size: 17,
                  color: clear ? Colors.white : VedroTheme.fg2,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (clear) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x94000000), Colors.transparent],
          ),
        ),
        child: content,
      );
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xCC121216),
            border: Border(bottom: BorderSide(color: VedroTheme.line, width: 0.8)),
          ),
          child: content,
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
          duration: const Duration(milliseconds: 200),
          curve: VedroTheme.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? const Color(0x1EFFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
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
