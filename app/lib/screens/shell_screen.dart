import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/models.dart';
import '../core/platform/native_playback_channel.dart';
import '../core/theme/vedro_skin.dart';
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

/// Skin-adaptive full-bleed cinema shell:
/// - Desktop: Floating translucent top bar adapting to active `VedroSkin` (light, dark, neon, film).
/// - Mobile: Floating frosted-glass bottom dock adapting geometry & colors to `VedroSkin`.
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
    final skin = VedroSkin.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final signedIn = widget.appState.isSignedIn;
    final topBarClear = _index == 0 && signedIn && !_homeScrolled && !skin.isLight;

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

    final body = VedroSkinCanvas(
      child: AnimatedSwitcher(
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
      ),
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
            backgroundColor: skin.canvas,
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

    final dockR = skin.pillRadius >= 100 ? 28.0 : skin.pillRadius.clamp(10.0, 24.0);
    return Scaffold(
      backgroundColor: skin.canvas,
      extendBody: true,
      body: body,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: GlassSurface(
            borderRadius: dockR,
            blur: 36,
            color: skin.glass,
            borderColor: skin.borderStrong,
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
    final skin = VedroSkin.of(context);
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
        final pillR = skin.radiusForPill(36);
        final isRoundBtn = skin.pillRadius >= 20;

        Widget headerCircleBtn({
          required String tooltip,
          required IconData icon,
          required VoidCallback onTap,
        }) {
          return Tooltip(
            message: tooltip,
            child: PressableScale(
              onTap: onTap,
              hoverScale: 1.06,
              pressScale: 0.92,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: clear ? const Color(0x1EFFFFFF) : skin.surface2,
                  shape: isRoundBtn ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: isRoundBtn ? null : BorderRadius.circular(pillR),
                  border: Border.all(
                    color: clear ? const Color(0x24FFFFFF) : skin.border,
                    width: 0.7,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: clear ? Colors.white : skin.fg2,
                ),
              ),
            ),
          );
        }

        final content = SafeArea(
          bottom: false,
          child: Container(
            height: 58,
            padding: EdgeInsets.fromLTRB(macTrafficClearance, 0, 28, 0),
            child: Row(
              children: [
                PressableScale(
                  onTap: onOpenServerHub,
                  hoverScale: 1.02,
                  pressScale: 0.97,
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.fromLTRB(6, 0, 10, 0),
                    decoration: BoxDecoration(
                      color: clear ? const Color(0x26FFFFFF) : skin.surface2,
                      borderRadius: BorderRadius.circular(pillR),
                      border: Border.all(
                        color: clear ? const Color(0x2EFFFFFF) : skin.border,
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
                            style: TextStyle(
                              color: clear ? Colors.white : skin.fg,
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
                              color: clear ? const Color(0x1CFFFFFF) : skin.subtleChipBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              routeName,
                              style: TextStyle(
                                color: clear ? const Color(0xCCFFFFFF) : skin.fg2,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: clear ? const Color(0xB8FFFFFF) : skin.fg3,
                        ),
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
                          color: activeIndex == idx
                              ? (clear
                                  ? const Color(0x28FFFFFF)
                                  : (skin.ctaStyle == 'contrast'
                                      ? skin.subtleChipHoverBg
                                      : skin.accent.withValues(alpha: skin.isLight ? 0.14 : 0.22)))
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(skin.radiusForPill(34)),
                          border: (activeIndex == idx && skin.frameStyle == 'neon' && !clear)
                              ? Border.all(color: skin.accent.withValues(alpha: 0.55), width: 0.8)
                              : null,
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: activeIndex == idx
                                ? (clear
                                    ? Colors.white
                                    : (skin.ctaStyle == 'contrast' ? skin.fg : skin.accent))
                                : (clear ? const Color(0xCCFFFFFF) : skin.fg2),
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
                PressableScale(
                  onTap: onOpenSearch,
                  hoverScale: 1.02,
                  pressScale: 0.97,
                  child: Container(
                    width: 224,
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: clear ? const Color(0x24FFFFFF) : skin.surface2,
                      borderRadius: BorderRadius.circular(pillR),
                      border: Border.all(
                        color: clear ? const Color(0x28FFFFFF) : skin.border,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: 16,
                          color: clear ? const Color(0xD9FFFFFF) : skin.fg3,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            appState.savedServers.length > 1 ? '聚合搜索' : '搜索',
                            style: TextStyle(
                              color: clear ? const Color(0xCCFFFFFF) : skin.fg3,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: clear ? const Color(0x1CFFFFFF) : skin.subtleChipBg,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '⌘K',
                            style: TextStyle(
                              color: clear ? const Color(0xB8FFFFFF) : skin.fg3,
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
                headerCircleBtn(
                  tooltip: '打开本地视频 / 文件夹（也支持直接拖入窗口）',
                  icon: Icons.folder_open_rounded,
                  onTap: onOpenLocalMedia,
                ),
                if (appState.isSignedIn) ...[
                  const SizedBox(width: 8),
                  headerCircleBtn(
                    tooltip: '我的收藏',
                    icon: Icons.favorite_border_rounded,
                    onTap: onOpenFavorites,
                  ),
                  const SizedBox(width: 8),
                  headerCircleBtn(
                    tooltip: '自定义首页布局',
                    icon: Icons.dashboard_customize_outlined,
                    onTap: onOpenLayout,
                  ),
                  const SizedBox(width: 8),
                  headerCircleBtn(
                    tooltip: '刷新首页',
                    icon: Icons.refresh_rounded,
                    onTap: onRefresh,
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
              decoration: BoxDecoration(
                color: skin.glass,
                border: Border(bottom: BorderSide(color: skin.border, width: 0.8)),
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
    final skin = VedroSkin.of(context);
    final activeColor = skin.ctaStyle == 'contrast' ? skin.fg : skin.accent;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: VedroTheme.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? (skin.ctaStyle == 'contrast'
                    ? skin.subtleChipHoverBg
                    : skin.accent.withValues(alpha: skin.isLight ? 0.14 : 0.20))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(skin.radiusForPill(44)),
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
                  color: selected ? activeColor : skin.fg3,
                ),
              ),
              const SizedBox(height: 2.5),
              Text(
                tab.label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? activeColor : skin.fg3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
