import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/models.dart';
import '../core/platform/native_playback_channel.dart';
import '../core/platform/platform_perf.dart';
import '../core/theme/vedro_liquid_shader.dart';
import '../core/theme/vedro_motion.dart';
import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/home_layout_sheet.dart';
import '../widgets/server_sheets.dart';
import '../widgets/spotlight_search_dialog.dart';
import '../widgets/update_checker.dart';
import '../widgets/vedro_ui.dart';
import '../widgets/windows_immersive_frame.dart';
import 'detail_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'player_screen.dart';
import 'playlists_screen.dart';
import 'search_screen.dart';
import 'server_hub_screen.dart';
import 'settings_screen.dart';

part 'shell/shell_nav_chrome.dart';
part 'shell/shell_nav_helpers.dart';

/// Multi-architecture cinema shell adapting structurally to `VedroSkin.navLayout`:
/// - `'top_floating'`: Apple TV+ / ElegantFin full-width floating header
/// - `'left_rail'`: Scyfin / Plex / Infuse vertical left sidebar rail
/// - `'centered_capsule'`: Ultrachromic / visionOS floating centered glass capsule island
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key, required this.appState});
  final VedroAppState appState;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> with SingleTickerProviderStateMixin {
  int _index = 0;
  final Set<int> _visitedTabs = {0};
  final ValueNotifier<bool> _homeScrolledNotifier = ValueNotifier<bool>(false);
  bool _topHovering = false;
  bool _topNavFocused = false;
  DateTime? _lastBackPressedAt;
  final GlobalKey _pageStageKey = GlobalKey(debugLabel: 'vedro-shell-page-stage');
  final FocusScopeNode _navFocusScope = FocusScopeNode(debugLabel: 'vedro-shell-nav-scope');
  late final AnimationController _tabAnimCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: 1.0,
  );

  void _selectTab(int next) {
    if (_index == next && _visitedTabs.contains(next)) return;
    setState(() {
      _index = next;
      _visitedTabs.add(next);
    });
    _tabAnimCtrl.forward(from: 0.0);
  }

  void _onUpdateCheckerChanged() {
    final ignored = VedroUpdateChecker.instance.ignoredVersion ?? '';
    if (ignored.isNotEmpty && ignored != widget.appState.prefs.ignoredUpdateVersion) {
      widget.appState.updatePrefs(
        widget.appState.prefs.copyWith(ignoredUpdateVersion: ignored),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    NativePlaybackChannel.ensureWindowListener();
    NativePlaybackChannel.droppedFilesNotifier.addListener(_onGlobalFilesDropped);
    if (NativePlaybackChannel.droppedFilesNotifier.value.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onGlobalFilesDropped();
      });
    }
    VedroUpdateChecker.instance.attachCore(widget.appState.core);
    if (widget.appState.prefs.ignoredUpdateVersion.isNotEmpty) {
      VedroUpdateChecker.instance.ignoredVersion = widget.appState.prefs.ignoredUpdateVersion;
    }
    VedroUpdateChecker.instance.addListener(_onUpdateCheckerChanged);
    if (!kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(seconds: 3), () {
          if (!mounted || !widget.appState.prefs.autoCheckUpdates) return;
          VedroUpdateChecker.instance.checkOnceOnStartup(
            context,
            currentVersion: widget.appState.core.coreVersion,
          );
        });
      });
    }
  }

  @override
  void dispose() {
    _tabAnimCtrl.dispose();
    _navFocusScope.dispose();
    _homeScrolledNotifier.dispose();
    VedroUpdateChecker.instance.removeListener(_onUpdateCheckerChanged);
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
    var pickFolder = false;
    if ((PlatformPerfProfile.isWindows || PlatformPerfProfile.isLinux)) {
      final skin = VedroSkin.of(context);
      final choice = await showVedroDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: skin.surface,
          title: Text('本地播放', style: TextStyle(color: skin.fg, fontSize: 16)),
          content: Text(
            '请选择打开单个视频文件，或打开整个本地剧集文件夹。',
            style: TextStyle(color: skin.fg2, fontSize: 13.5),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'folder'),
              icon: const Icon(Icons.folder_rounded, size: 16),
              label: const Text('选择文件夹'),
            ),
            FilledButton.icon(
              autofocus: true,
              onPressed: () => Navigator.pop(ctx, 'file'),
              icon: const Icon(Icons.video_file_rounded, size: 16),
              label: const Text('选择视频文件'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      pickFolder = choice == 'folder';
    }
    final picked = await NativePlaybackChannel.pickFiles(
      extensions: pickFolder ? const [] : NativePlaybackChannel.videoExtensions.toList(),
      allowDirectory: pickFolder || (!kIsWeb && Platform.isMacOS),
      title: pickFolder ? '选择本地视频文件夹' : '选择本地视频文件',
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
    var rawName = targetPath.replaceAll('\\', '/').split('/').last;
    if (targetPath.startsWith('content://')) {
      try {
        rawName = Uri.decodeComponent(rawName).split(':').last.split('/').last;
      } catch (_) {}
    }
    final dot = rawName.lastIndexOf('.');
    final stem = (dot > 0 ? rawName.substring(0, dot) : rawName).trim();
    final title = stem.isNotEmpty ? stem : '本地视频';
    Navigator.of(context).push(
      vedroRoute(PlayerScreen(
        item: MediaItemModel(
          id: 'local_$startIndex',
          name: title,
          type: 'Video',
          indexNumber: startIndex + 1,
        ),
        appState: widget.appState,
        localFilePath: targetPath,
        localPlaylistPaths: files,
      )),
    );
  }

  void _launchLocalHistoryEntry(VedroLocalHistoryEntry entry) {
    if (entry.isNetworkUrl) {
      if (!NativePlaybackChannel.isAllowedMediaUrl(entry.target)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该记录缺少完整直链或协议不受支持，请重新输入链接')),
        );
        return;
      }
      Navigator.of(context).push(
        vedroRoute(PlayerScreen(
          item: MediaItemModel(
            id: 'net_${entry.target.hashCode}',
            name: entry.title,
            type: 'Video',
          ),
          appState: widget.appState,
          directNetworkUrl: entry.target,
        )),
      );
      return;
    }
    final resolved = NativePlaybackChannel.resolveLocalPlaylist(entry.target);
    if (resolved.files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地文件不存在或已被移动')),
      );
      return;
    }
    _launchLocalMedia(resolved.files, resolved.startIndex);
  }

  Future<void> _openNetworkUrlDialog() async {
    final skin = VedroSkin.of(context);
    String? err;
    final submitted = await showVedroDialog<String>(
      context: context,
      builder: (ctx) => VedroControllerScope<TextEditingController>(
        create: () => TextEditingController(),
        dispose: (c) => c.dispose(),
        builder: (ctx, urlCtrl) => StatefulBuilder(
          builder: (ctx, setModal) => AlertDialog(
            backgroundColor: skin.surface,
            title: Text('打开网络串流链接', style: TextStyle(color: skin.fg, fontSize: 16)),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: urlCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    style: TextStyle(color: skin.fg, fontSize: 13.5),
                    decoration: const InputDecoration(
                      labelText: '视频直链 / M3U8 / RTSP / RTMP 地址',
                      hintText: 'https://example.com/video.m3u8',
                    ),
                    onSubmitted: (_) {
                      final u = urlCtrl.text.trim();
                      if (!NativePlaybackChannel.isAllowedMediaUrl(u)) {
                        setModal(() => err = '请输入有效的 http(s) / rtsp / rtmp / rtp 串流链接');
                        return;
                      }
                      Navigator.pop(ctx, u);
                    },
                  ),
                  if (err != null) ...[
                    const SizedBox(height: 8),
                    Text(err!, style: const TextStyle(color: VedroTheme.danger, fontSize: 12)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  final u = urlCtrl.text.trim();
                  if (!NativePlaybackChannel.isAllowedMediaUrl(u)) {
                    setModal(() => err = '请输入有效的 http(s) / rtsp / rtmp / rtp 串流链接');
                    return;
                  }
                  Navigator.pop(ctx, u);
                },
                child: const Text('立即播放'),
              ),
            ],
          ),
        ),
      ),
    );
    if (submitted == null || submitted.isEmpty || !mounted) return;
    final uri = Uri.tryParse(submitted);
    final seg = (uri != null && uri.pathSegments.isNotEmpty)
        ? uri.pathSegments.last
        : (uri?.host ?? '网络串流');
    final title = seg.trim().isNotEmpty ? seg.trim() : '网络串流';
    Navigator.of(context).push(
      vedroRoute(PlayerScreen(
        item: MediaItemModel(
          id: 'net_${submitted.hashCode}',
          name: title,
          type: 'Video',
        ),
        appState: widget.appState,
        directNetworkUrl: submitted,
      )),
    );
  }

  void _handleRootBackPop(bool didPop) {
    if (didPop) return;
    if (_index != 0) {
      _selectTab(0);
      return;
    }
    if (PlatformPerfProfile.isTv && !_navFocusScope.hasFocus && _navFocusScope.canRequestFocus) {
      _navFocusScope.requestFocus();
      return;
    }
    if (!widget.appState.prefs.confirmExitApp) {
      SystemNavigator.pop();
      return;
    }
    final now = DateTime.now();
    if (_lastBackPressedAt != null &&
        now.difference(_lastBackPressedAt!) < const Duration(milliseconds: 2200)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPressedAt = now;
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          key: ValueKey('double-back-exit-toast'),
          behavior: SnackBarBehavior.floating,
          width: 172,
          duration: Duration(milliseconds: 2000),
          content: Text('再按一次退出', textAlign: TextAlign.center),
        ),
      );
  }

  static const _desktopNav = [
    (0, '首页', Icons.home_rounded),
    (1, '媒体库', Icons.dns_rounded),
    (3, '片单', Icons.bookmark_rounded),
    (4, '设置', Icons.tune_rounded),
  ];

  static const _mobileTabs = [
    _NavTab(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: '首页'),
    _NavTab(icon: Icons.dns_outlined, activeIcon: Icons.dns_rounded, label: '媒体库'),
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
      try {
        await widget.appState.switchToServerById(hit.serverId);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('切换服务器失败：${VedroErrorFormatter.friendly(e)}')),
          );
        }
        return;
      }
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
    showServerHubSheet(
      context: context,
      appState: widget.appState,
      onServerSwitched: () => _selectTab(0),
    );
  }

  Future<void> _openAddServer([String? initialUrl]) async {
    final added = await showAddServerSheet(
      context: context,
      appState: widget.appState,
      initialUrl: initialUrl,
    );
    if (added == true && mounted && _index == 1) {
      setState(() => _index = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 820;
    final signedIn = widget.appState.isSignedIn;
    final isLeftRail = wide && skin.navLayout == 'left_rail';
    final isCenteredCapsule = wide && skin.navLayout == 'centered_capsule';
    final isMinimalAutoHide = wide && skin.navLayout == 'minimal_auto_hide';
    final isTv = PlatformPerfProfile.isTv;
    final childTopInset = wide
        ? (isLeftRail
            ? ((!kIsWeb && Platform.isWindows) ? 36.0 : 16.0)
            : (isMinimalAutoHide ? 52.0 : 68.0))
        : ((!kIsWeb && Platform.isWindows) ? 36.0 : 0.0);

    _visitedTabs.add(_index);

    Widget buildTab(int idx) {
      if (!_visitedTabs.contains(idx)) return const SizedBox.shrink();
      final Widget page = switch (idx) {
        0 => HomeScreen(
            key: const ValueKey('tab-home'),
            appState: widget.appState,
            topNavClearance: wide ? (isLeftRail ? 24.0 : 72.0) : 0.0,
            onItemTap: (item, {String? heroPrefix}) =>
                _openItem(item, heroPrefix: heroPrefix),
            onQuickPlay: _quickPlay,
            onLibraryTap: _openLibrary,
            onGenreTap: _openGenre,
            onOpenFavorites: _openFavorites,
            onOpenLocalMedia: _openLocalMediaPicker,
            onOpenNetworkUrl: _openNetworkUrlDialog,
            onOpenServerHub: _openServerHub,
            onOpenAddServer: _openAddServer,
            onOpenSettings: () => _selectTab(4),
            onScrollChanged: (scrolled) {
              if (_homeScrolledNotifier.value != scrolled) {
                _homeScrolledNotifier.value = scrolled;
              }
            },
          ),
        1 => ServerHubScreen(
            key: const ValueKey('tab-server-hub'),
            appState: widget.appState,
            onServerSelected: () => _selectTab(0),
            onOpenAddServer: _openAddServer,
            onOpenLocalMedia: _openLocalMediaPicker,
            onOpenNetworkUrl: _openNetworkUrlDialog,
            onPlayLocalHistory: _launchLocalHistoryEntry,
            topInset: childTopInset,
          ),
        2 => SearchScreen(
            key: const ValueKey('tab-search'),
            appState: widget.appState,
            onSelectHit: _openAggregatedHit,
          ),
        3 => PlaylistsScreen(
            key: const ValueKey('tab-playlists'),
            appState: widget.appState,
            onItemTap: _openItem,
            onQuickPlay: _quickPlay,
            topInset: childTopInset,
          ),
        _ => SettingsScreen(
            key: const ValueKey('tab-settings'),
            appState: widget.appState,
            onOpenServerHub: _openServerHub,
            onOpenAddServer: _openAddServer,
            topInset: childTopInset,
          ),
      };
      return ExcludeFocus(
        excluding: _index != idx,
        child: TickerMode(
          enabled: _index == idx,
          child: RepaintBoundary(child: page),
        ),
      );
    }

    // Lazy-mounted IndexedStack: preserves Home scroll position & decoded textures
    // while each tab switch cross-fades smoothly over solid `skin.canvas` with
    // zero bright-then-dark fanart strobe!
    final reduceMotion = PlatformPerfProfile.shouldReduceMotion(context);
    final tabFade = CurvedAnimation(
      parent: _tabAnimCtrl,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
    );
    const settled = AlwaysStoppedAnimation<double>(1.0);
    final pageSwitcher = IndexedStack(
      index: _index,
      children: [
        for (var i = 0; i < 5; i++)
          FadeTransition(
            opacity: (i == _index && !reduceMotion)
                ? Tween<double>(begin: 0.92, end: 1.0).animate(tabFade)
                : settled,
            child: buildTab(i),
          ),
      ],
    );

    final keyedStage = KeyedSubtree(
      key: _pageStageKey,
      child: pageSwitcher,
    );

    // Every tab renders its own `VedroSkinCanvas` (Home renders its own Hero banner;
    // Search/Playlists/Servers/Settings render their own steady ambient backdrop).
    // Keeping the shell wrapper free of an extra fanart image eliminates the bright
    // flash-then-darken strobe when switching to Search / Favorites / Playlists!
    final homeHasHeroBackdrop = _index == 0 &&
        signedIn &&
        widget.appState.hasAnyHomeContent &&
        widget.appState.showHomeHero &&
        skin.heroStyle != 'compact_minimal';
    const String? fanartUrl = null;

    if (wide) {
      return PopScope(
        canPop: !widget.appState.prefs.confirmExitApp && _index == 0 && !isTv,
        onPopInvokedWithResult: (didPop, _) => _handleRootBackPop(didPop),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _openSpotlight,
            const SingleActivator(LogicalKeyboardKey.keyK, control: true): _openSpotlight,
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              backgroundColor: skin.canvas,
              body: VedroSkinCanvas(
                backdropImageUrl: fanartUrl,
                suppressTopOrb: homeHasHeroBackdrop,
                suppressBottomOrb: homeHasHeroBackdrop && skin.heroStyle == 'full_bleed',
                // Unified stable Row -> Expanded -> Stack tree so switching `navLayout`
                // (`left_rail` <-> `top_floating` <-> `centered_capsule` <-> `minimal_auto_hide`)
                // NEVER unmounts or resets `SettingsScreen` or scroll positions!
                child: Padding(
                  padding: isTv
                      ? const EdgeInsets.symmetric(horizontal: 24, vertical: 14)
                      : EdgeInsets.zero,
                  child: Row(
                    key: const ValueKey('shell-unified-desktop-row'),
                    children: [
                      if (isLeftRail)
                        FocusScope(
                          node: _navFocusScope,
                          child: _VerticalSidebarRail(
                            key: const ValueKey('shell-left-rail-layout'),
                            appState: widget.appState,
                            compact: !isTv && size.width < 1120,
                            activeIndex: _index,
                            navItems: _desktopNav,
                            onSelectIndex: _selectTab,
                            onOpenServerHub: _openServerHub,
                            onOpenSearch: _openSpotlight,
                            onOpenLocalMedia: _openLocalMediaPicker,
                            onOpenNetworkUrl: _openNetworkUrlDialog,
                            onOpenFavorites: _openFavorites,
                            onOpenLayout: () => showHomeLayoutSheet(
                              context: context,
                              appState: widget.appState,
                            ),
                            onRefresh: widget.appState.refreshHome,
                          ),
                        ),
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(child: keyedStage),
                            if (isLeftRail && !kIsWeb && Platform.isWindows)
                              const Positioned(
                                top: 0,
                                left: 0,
                                right: 138,
                                height: 36,
                                child: WindowsWindowDragArea(),
                              ),
                            if (!isLeftRail && isCenteredCapsule)
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                height: 64,
                                child: Stack(
                                  children: [
                                    const Positioned.fill(child: WindowsWindowDragArea()),
                                    Align(
                                      alignment: Alignment.topCenter,
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                                        child: FocusScope(
                                          node: _navFocusScope,
                                          child: _CenteredCapsuleNavIsland(
                                            key: const ValueKey('shell-centered-capsule-nav'),
                                            appState: widget.appState,
                                            activeIndex: _index,
                                            navItems: _desktopNav,
                                            onSelectIndex: _selectTab,
                                            onOpenServerHub: _openServerHub,
                                            onOpenSearch: _openSpotlight,
                                            onOpenLocalMedia: _openLocalMediaPicker,
                                            onOpenNetworkUrl: _openNetworkUrlDialog,
                                            onOpenFavorites: _openFavorites,
                                            onRefresh: widget.appState.refreshHome,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else if (!isLeftRail && isMinimalAutoHide)
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: FocusScope(
                                  node: _navFocusScope,
                                  child: Focus(
                                    canRequestFocus: false,
                                    onFocusChange: (focused) {
                                      if (_topNavFocused != focused) {
                                        setState(() => _topNavFocused = focused);
                                      }
                                    },
                                    child: ValueListenableBuilder<bool>(
                                      valueListenable: _homeScrolledNotifier,
                                      builder: (_, homeScrolled, __) {
                                        final topBarClear = _index == 0 &&
                                            signedIn &&
                                            !homeScrolled &&
                                            !skin.isLight &&
                                            skin.heroStyle == 'full_bleed';
                                        final topVisible = _topHovering ||
                                            _topNavFocused ||
                                            !homeScrolled ||
                                            _index != 0;
                                        return MouseRegion(
                                          onEnter: (_) => setState(() => _topHovering = true),
                                          onExit: (_) => setState(() => _topHovering = false),
                                          child: AnimatedOpacity(
                                            duration: const Duration(milliseconds: 200),
                                            opacity: topVisible ? 1.0 : 0.12,
                                            child: _FloatingDesktopHeader(
                                              appState: widget.appState,
                                              clear: topBarClear && !_topHovering && !_topNavFocused,
                                              activeIndex: _index,
                                              navItems: _desktopNav,
                                              onSelectIndex: _selectTab,
                                              onOpenServerHub: _openServerHub,
                                              onOpenSearch: _openSpotlight,
                                              onOpenLocalMedia: _openLocalMediaPicker,
                                              onOpenNetworkUrl: _openNetworkUrlDialog,
                                              onOpenFavorites: _openFavorites,
                                              onOpenLayout: () => showHomeLayoutSheet(
                                                context: context,
                                                appState: widget.appState,
                                              ),
                                              onRefresh: widget.appState.refreshHome,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              )
                            else if (!isLeftRail)
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: FocusScope(
                                  node: _navFocusScope,
                                  child: ValueListenableBuilder<bool>(
                                    valueListenable: _homeScrolledNotifier,
                                    builder: (_, homeScrolled, __) {
                                      final topBarClear = _index == 0 &&
                                          signedIn &&
                                          !homeScrolled &&
                                          !skin.isLight &&
                                          skin.heroStyle == 'full_bleed';
                                      return _FloatingDesktopHeader(
                                        appState: widget.appState,
                                        clear: topBarClear,
                                        activeIndex: _index,
                                        navItems: _desktopNav,
                                        onSelectIndex: _selectTab,
                                        onOpenServerHub: _openServerHub,
                                        onOpenSearch: _openSpotlight,
                                        onOpenLocalMedia: _openLocalMediaPicker,
                                        onOpenNetworkUrl: _openNetworkUrlDialog,
                                        onOpenFavorites: _openFavorites,
                                        onOpenLayout: () => showHomeLayoutSheet(
                                          context: context,
                                          appState: widget.appState,
                                        ),
                                        onRefresh: widget.appState.refreshHome,
                                      );
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final dockR = skin.pillRadius >= 100 ? 30.0 : skin.pillRadius.clamp(12.0, 26.0);
    final tabLensFill = skin.isLight
        ? Colors.black.withValues(alpha: 0.07)
        : Colors.white.withValues(alpha: 0.12);
    final mobileNav = skin.mobileNavStyle;
    final fullTabBar = mobileNav == 'full_tab_bar';

    void triggerMobileTabTap(int i) {
      if (skin.touchFeedbackStyle == 'spring_haptic') {
        HapticFeedback.lightImpact();
      } else if (skin.touchFeedbackStyle == 'subtle_scale') {
        HapticFeedback.selectionClick();
      }
      _selectTab(i);
    }

    final Widget bottomBar = ValueListenableBuilder<bool>(
      valueListenable: _homeScrolledNotifier,
      builder: (context, homeScrolled, _) {
        final shrunkByScroll =
            widget.appState.prefs.autoShrinkNavOnScroll && _index == 0 && homeScrolled;
        final compactIcons = mobileNav == 'compact_icon_only' ||
            !widget.appState.prefs.showNavLabels ||
            shrunkByScroll;
        if (fullTabBar) {
          final isLiquid = skin.isLiquidGlass;
          final barBlur = isLiquid && VedroLiquidGlassShader.isAvailable
              ? VedroLiquidGlassShader.gpuBlurSigma(VedroGlassDensity.chrome)
              : PlatformPerfProfile.clampLiveBlur(24);
          return RepaintBoundary(
            child: VedroLiquidGlassBackdrop(
              key: const ValueKey('mobile-nav-full-tab-bar'),
              borderRadius: 0,
              blurSigma: barBlur,
              enableRefraction: isLiquid,
              isLight: skin.isLight,
              accent: skin.accent,
              liquidSpecular: skin.liquidSpecular,
              density: VedroGlassDensity.chrome,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isLiquid
                      ? VedroLiquidGlassShader.liquidFillColor(
                          isLight: skin.isLight,
                          canvas: skin.canvas,
                          surface: skin.surface,
                          surface2: skin.surface2,
                          density: VedroGlassDensity.chrome,
                        )
                      : PlatformPerfProfile.adaptGlassFill(skin.glass),
                  gradient: isLiquid
                      ? VedroLiquidGlassShader.liquidSheenGradient(
                          isLight: skin.isLight,
                          accent: skin.accent,
                        )
                      : null,
                  border: Border(
                    top: BorderSide(
                      color: isLiquid
                          ? (skin.isLight
                              ? Colors.white.withValues(alpha: 0.78)
                              : Colors.white.withValues(alpha: 0.24))
                          : skin.border,
                      width: isLiquid ? 0.85 : 0.7,
                    ),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: VedroSlidingPillRow(
                      expand: true,
                      selectedIndex: _index,
                      pillInsets: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      pillDecoration: BoxDecoration(
                        color: tabLensFill,
                        borderRadius: BorderRadius.circular(skin.radiusForPill(46)),
                      ),
                      children: [
                        for (var i = 0; i < _mobileTabs.length; i++)
                          _BottomTabButton(
                            tab: _mobileTabs[i],
                            selected: i == _index,
                            iconOnly: false,
                            onTap: () => triggerMobileTabTap(i),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        return SafeArea(
          top: false,
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 460),
            curve: VedroSpringCurve.snappy,
            padding: EdgeInsets.fromLTRB(
              shrunkByScroll ? 56 : (compactIcons ? 42 : 18),
              0,
              shrunkByScroll ? 56 : (compactIcons ? 42 : 18),
              10,
            ),
            child: GlassSurface(
              key: ValueKey('mobile-nav-$mobileNav'),
              borderRadius: dockR,
              blur: skin.backdropBlur.clamp(24.0, 44.0),
              color: skin.isLiquidGlass ? null : skin.glass,
              borderColor: skin.borderStrong,
              padding: EdgeInsets.symmetric(
                horizontal: compactIcons ? 8 : 6,
                vertical: compactIcons ? 4.5 : 5.5,
              ),
              child: VedroSlidingPillRow(
                expand: true,
                selectedIndex: _index,
                pillInsets: const EdgeInsets.symmetric(horizontal: 2),
                pillDecoration: BoxDecoration(
                  color: tabLensFill,
                  borderRadius: BorderRadius.circular(skin.radiusForPill(46)),
                  border: Border.all(
                    color: skin.isLight
                        ? Colors.white.withValues(alpha: 0.7)
                        : Colors.white.withValues(alpha: 0.08),
                    width: 0.6,
                  ),
                ),
                children: [
                  for (var i = 0; i < _mobileTabs.length; i++)
                    _BottomTabButton(
                      tab: _mobileTabs[i],
                      selected: i == _index,
                      iconOnly: compactIcons,
                      onTap: () => triggerMobileTabTap(i),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );

    final narrowWinBar = !kIsWeb && Platform.isWindows;
    return PopScope(
      canPop: !widget.appState.prefs.confirmExitApp && _index == 0,
      onPopInvokedWithResult: (didPop, _) => _handleRootBackPop(didPop),
      child: Scaffold(
        backgroundColor: skin.canvas,
        extendBody: !fullTabBar,
        body: VedroSkinCanvas(
          backdropImageUrl: fanartUrl,
          suppressTopOrb: homeHasHeroBackdrop,
                suppressBottomOrb: homeHasHeroBackdrop && skin.heroStyle == 'full_bleed',
          child: narrowWinBar
              ? Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 36),
                      child: keyedStage,
                    ),
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 138,
                      height: 36,
                      child: WindowsWindowDragArea(),
                    ),
                  ],
                )
              : keyedStage,
        ),
        bottomNavigationBar: bottomBar,
      ),
    );
  }
}
