import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/models.dart';
import '../core/platform/native_playback_channel.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/home_layout_sheet.dart';
import '../widgets/server_sheets.dart';
import '../widgets/spotlight_search_dialog.dart';
import '../widgets/vedro_ui.dart';
import 'detail_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'player_screen.dart';
import 'playlists_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// Full-bleed SenPlayer / Forward cinema shell:
/// - Always accessible from startup (Server Hub, Settings, Aggregated Search, Library).
/// - Desktop: Floating translucent top glass bar with 1-click Server & Route switcher pill + Spotlight (`⌘K`).
/// - Mobile: Floating frosted-glass bottom pill tab bar.
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key, required this.appState});
  final VedroAppState appState;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;
  bool _homeScrolled = false;

  @override
  void initState() {
    super.initState();
    NativePlaybackChannel.ensureWindowListener();
    NativePlaybackChannel.droppedFilesNotifier.addListener(_onGlobalFilesDropped);
  }

  @override
  void dispose() {
    NativePlaybackChannel.droppedFilesNotifier.removeListener(_onGlobalFilesDropped);
    super.dispose();
  }

  void _onGlobalFilesDropped() {
    if (!mounted) return;
    // If PlayerScreen is on top of navigator, let PlayerScreen consume the drop itself.
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final paths = NativePlaybackChannel.droppedFilesNotifier.value;
    if (paths.isEmpty) return;
    NativePlaybackChannel.droppedFilesNotifier.value = const [];
    for (final p in paths) {
      final resolved = NativePlaybackChannel.resolveLocalPlaylist(p);
      if (resolved.files.isNotEmpty) {
        _launchLocalMedia(resolved.files, resolved.startIndex);
        return;
      }
    }
  }

  Future<void> _openLocalMediaPicker() async {
    final picked = await NativePlaybackChannel.pickFiles(
      extensions: NativePlaybackChannel.videoExtensions.toList(),
      allowDirectory: true,
      title: '选择本地视频文件或文件夹',
    );
    if (picked.isEmpty || !mounted) return;
    final resolved = NativePlaybackChannel.resolveLocalPlaylist(picked.first);
    if (resolved.files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所选路径中未找到支持的视频文件')),
      );
      return;
    }
    _launchLocalMedia(resolved.files, resolved.startIndex);
  }

  void _launchLocalMedia(List<String> files, int startIndex) {
    final targetPath = files[startIndex.clamp(0, files.length - 1)];
    final name = targetPath.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    Navigator.of(context).push(
      vedroRoute(PlayerScreen(
        item: MediaItemModel(
          id: 'local_$startIndex',
          name: stem,
          type: 'Video',
          indexNumber: startIndex + 1,
        ),
        appState: widget.appState,
        localFilePath: targetPath,
        localPlaylistPaths: files,
      )),
    );
  }

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
        onGenreTap: _openGenre,
      )),
    );
  }

  void _openGenre(String genre) {
    Navigator.of(context).push(
      vedroRoute(LibraryScreen(
        appState: widget.appState,
        initialGenreName: genre,
        onItemTap: _openItem,
        onQuickPlay: _quickPlay,
        standalone: true,
      )),
    );
  }

  void _openFavorites() {
    Navigator.of(context).push(
      vedroRoute(LibraryScreen(
        appState: widget.appState,
        initialOnlyFavorite: true,
        customTitle: '我的收藏',
        onItemTap: _openItem,
        onQuickPlay: _quickPlay,
        standalone: true,
      )),
    );
  }

  Future<void> _openAggregatedHit(AggregatedSearchHit hit) async {
    if (hit.serverId.isNotEmpty && hit.serverId != widget.appState.activeServerId) {
      await widget.appState.switchToServerById(hit.serverId);
    }
    if (!mounted) return;
    _openItem(MediaItemModel(
      id: hit.id,
      name: hit.name,
      type: hit.type,
      primaryImageTag: hit.primaryImageTag,
    ));
  }

  void _quickPlay(MediaItemModel item) {
    if (item.isPlayable) {
      if (widget.appState.prefs.externalPlayer != 'builtin') {
        widget.appState.launchExternalPlayer(item).then((msg) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
          }
        }).catchError((Object e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('外部播放器打开失败：$e')));
          }
        });
        return;
      }
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
      onSelectHit: _openAggregatedHit,
    );
  }

  void _openServerHub() {
    showServerHubSheet(context: context, appState: widget.appState);
  }

  void _openAddServer([String? initialUrl]) {
    showAddServerSheet(
      context: context,
      appState: widget.appState,
      initialUrl: initialUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final signedIn = widget.appState.isSignedIn;
    final topBarClear = _index == 0 && signedIn && !_homeScrolled;

    final pages = [
      HomeScreen(
        key: const ValueKey('tab-home'),
        appState: widget.appState,
        onItemTap: (item, {String? heroPrefix}) =>
            _openItem(item, heroPrefix: heroPrefix),
        onQuickPlay: _quickPlay,
        onLibraryTap: _openLibrary,
        onGenreTap: _openGenre,
        onOpenFavorites: _openFavorites,
        onOpenLocalMedia: _openLocalMediaPicker,
        onOpenServerHub: _openServerHub,
        onOpenAddServer: _openAddServer,
        onOpenSettings: () => setState(() => _index = 4),
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
        onOpenAddServer: _openAddServer,
        topInset: wide ? 64 : 0,
      ),
      SearchScreen(
        key: const ValueKey('tab-search'),
        appState: widget.appState,
        onSelectHit: _openAggregatedHit,
      ),
      PlaylistsScreen(
        key: const ValueKey('tab-playlists'),
        appState: widget.appState,
        onItemTap: _openItem,
        onQuickPlay: _quickPlay,
        topInset: wide ? 64 : 0,
      ),
      SettingsScreen(
        key: const ValueKey('tab-settings'),
        appState: widget.appState,
        onOpenServerHub: _openServerHub,
        onOpenAddServer: _openAddServer,
        topInset: wide ? 64 : 0,
      ),
    ];

    final body = AnimatedSwitcher(
      duration: Duration(milliseconds: widget.appState.prefs.reduceMotion ? 0 : 260),
      switchInCurve: VedroTheme.easeOut,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.014),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
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
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _FloatingDesktopHeader(
                    appState: widget.appState,
                    clear: topBarClear,
                    activeIndex: _index,
                    navItems: _desktopNav,
                    onSelectIndex: (i) => setState(() => _index = i),
                    onOpenServerHub: _openServerHub,
                    onOpenSearch: _openSpotlight,
                    onOpenLocalMedia: _openLocalMediaPicker,
                    onOpenFavorites: _openFavorites,
                    onOpenLayout: () => showHomeLayoutSheet(
                      context: context,
                      appState: widget.appState,
                    ),
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
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: GlassSurface(
            borderRadius: 28,
            blur: 36,
            color: const Color(0xC4161619),
            borderColor: const Color(0x16FFFFFF),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
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
    required this.appState,
    required this.clear,
    required this.activeIndex,
    required this.navItems,
    required this.onSelectIndex,
    required this.onOpenServerHub,
    required this.onOpenSearch,
    required this.onOpenLocalMedia,
    required this.onOpenFavorites,
    required this.onOpenLayout,
    required this.onRefresh,
  });

  final VedroAppState appState;
  final bool clear;
  final int activeIndex;
  final List<(int, String)> navItems;
  final ValueChanged<int> onSelectIndex;
  final VoidCallback onOpenServerHub;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenLocalMedia;
  final VoidCallback onOpenFavorites;
  final VoidCallback onOpenLayout;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    NativePlaybackChannel.ensureWindowListener();
    return ValueListenableBuilder<bool>(
      valueListenable: NativePlaybackChannel.fullscreenNotifier,
      builder: (context, isFullscreen, _) {
        final macTrafficClearance = (!kIsWeb && Platform.isMacOS && !isFullscreen) ? 82.0 : 28.0;
        final routeName = appState.activeRouteDisplayName;
        final serverLabel = appState.isSignedIn ? appState.activeServerDisplayName : '选择服务器';
        final activeSrv = appState.activeServer;
        final cardStyle = activeSrv != null ? appState.serverCardStyleFor(activeSrv.id) : null;
        final cardTheme = activeSrv != null ? cardStyle?.resolveTheme(activeSrv.id) : null;

        final content = SafeArea(
          bottom: false,
          child: Container(
            height: 58,
            padding: EdgeInsets.fromLTRB(macTrafficClearance, 0, 28, 0),
        child: Row(
          children: [
            // Interactive Server + Multi-Route Switcher Pill
            PressableScale(
              onTap: onOpenServerHub,
              hoverScale: 1.02,
              pressScale: 0.97,
              child: Container(
                height: 36,
                padding: const EdgeInsets.fromLTRB(6, 0, 10, 0),
                decoration: BoxDecoration(
                  color: clear ? const Color(0x26FFFFFF) : VedroTheme.surface2,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: clear ? const Color(0x2EFFFFFF) : VedroTheme.line,
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (appState.isSignedIn && cardStyle != null && cardTheme != null)
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: cardTheme.accent.withValues(alpha: 0.22),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(cardStyle.iconData, size: 13.5, color: cardTheme.accent),
                      )
                    else
                      const VedroBrandMark(size: 24),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        serverLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (appState.isSignedIn && routeName != null && routeName.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0x1CFFFFFF),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          routeName,
                          style: const TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xB8FFFFFF)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 18),
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
                      color: activeIndex == idx ? const Color(0x20FFFFFF) : Colors.transparent,
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
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: NativePlaybackChannel.toggleZoom,
                child: const SizedBox.expand(),
              ),
            ),
            // Aggregated Spotlight Search pill
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
                        appState.savedServers.length > 1 ? '聚合搜索' : '搜索',
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
            const SizedBox(width: 8),
            Tooltip(
              message: '打开本地视频 / 文件夹（也支持直接拖入窗口）',
              child: PressableScale(
                onTap: onOpenLocalMedia,
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
                    Icons.folder_open_rounded,
                    size: 16,
                    color: clear ? Colors.white : VedroTheme.fg2,
                  ),
                ),
              ),
            ),
            if (appState.isSignedIn) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: '我的收藏',
                child: PressableScale(
                  onTap: onOpenFavorites,
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
                      Icons.favorite_border_rounded,
                      size: 16,
                      color: clear ? Colors.white : VedroTheme.fg2,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: '自定义首页布局',
                child: PressableScale(
                  onTap: onOpenLayout,
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
                      Icons.dashboard_customize_outlined,
                      size: 16,
                      color: clear ? Colors.white : VedroTheme.fg2,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: '刷新首页',
                child: PressableScale(
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
              ),
            ],
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
      },
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
          duration: const Duration(milliseconds: 220),
          curve: VedroTheme.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? const Color(0x20FFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: selected ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 220),
                curve: VedroTheme.easeOut,
                child: Icon(
                  selected ? tab.activeIcon : tab.icon,
                  size: 20,
                  color: selected ? Colors.white : VedroTheme.fg3,
                ),
              ),
              const SizedBox(height: 2.5),
              Text(
                tab.label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? Colors.white : VedroTheme.fg3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
