import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/models.dart';
import '../core/platform/platform_perf.dart';
import '../core/theme/display_profile.dart';
import '../core/theme/vedro_motion.dart';
import '../core/theme/vedro_scroll.dart';
import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/home_layout_sheet.dart';
import '../widgets/horizontal_rail.dart';
import '../widgets/media_card.dart';
import '../widgets/server_card_grid.dart';
import '../widgets/vedro_artwork.dart';
import '../widgets/vedro_peek_menu.dart';
import '../widgets/vedro_ui.dart';
import 'player_screen.dart';

part 'home/home_chrome.dart';
part 'home/home_context_menu.dart';
part 'home/home_hero_banner.dart';
part 'home/home_welcome_hub.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.appState,
    required this.onItemTap,
    required this.onQuickPlay,
    required this.onLibraryTap,
    this.topNavClearance = 72.0,
    this.onGenreTap,
    this.onOpenFavorites,
    this.onOpenLocalMedia,
    this.onOpenNetworkUrl,
    required this.onOpenServerHub,
    required this.onOpenAddServer,
    required this.onOpenSettings,
    this.onScrollChanged,
  });

  final VedroAppState appState;
  final void Function(MediaItemModel, {String? heroPrefix}) onItemTap;
  final void Function(MediaItemModel) onQuickPlay;
  final void Function(MediaItemModel) onLibraryTap;
  final double topNavClearance;
  final ValueChanged<String>? onGenreTap;
  final VoidCallback? onOpenFavorites;
  final VoidCallback? onOpenLocalMedia;
  final VoidCallback? onOpenNetworkUrl;
  final VoidCallback onOpenServerHub;
  final void Function([String? initialUrl]) onOpenAddServer;
  final VoidCallback onOpenSettings;
  final ValueChanged<bool>? onScrollChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scrollCtrl = VedroScrollController();
  final ValueNotifier<double> _scrollOffsetNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<double> _pullProgress = ValueNotifier<double>(0.0);
  final ValueNotifier<bool> _refreshing = ValueNotifier<bool>(false);
  bool _pullArmed = false;

  /// When the current `ready` stage first appeared: sections created shortly
  /// after get a staggered spring entrance; later lazily-built ones stay static.
  String? _readyStageKey;
  DateTime? _readyStageAt;
  String? _lastStageKey;

  /// Scroll offset at which the pinned mobile bar becomes fully frosted.
  double _topBarSolidAfter = 8.0;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _scrollOffsetNotifier.dispose();
    _pullProgress.dispose();
    _refreshing.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final offset = _scrollCtrl.offset;
    widget.onScrollChanged?.call(offset > 24);
    // Clamp (instead of skipping) so a fast fling past the hero never leaves
    // scroll-driven chrome stuck at a stale mid-way value.
    final clamped = math.min(offset, 760.0);
    if (clamped != _scrollOffsetNotifier.value) {
      _scrollOffsetNotifier.value = clamped;
    }
  }

  /// iOS stretch-to-refresh: rubber-band past [_kPullToRefreshTrigger] arms it
  /// (with a haptic tick); releasing fires the refresh. Pushing back cancels.
  bool _onScrollNotification(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical || _refreshing.value) return false;
    if (n is ScrollUpdateNotification || n is OverscrollNotification) {
      final pull = math.max(0.0, -n.metrics.pixels);
      final dragging = n is ScrollUpdateNotification
          ? n.dragDetails != null
          : (n as OverscrollNotification).dragDetails != null;
      _pullProgress.value = (pull / _kPullToRefreshTrigger).clamp(0.0, 1.0);
      if (dragging) {
        if (!_pullArmed && pull >= _kPullToRefreshTrigger) {
          _pullArmed = true;
          HapticFeedback.mediumImpact();
        } else if (_pullArmed && pull < _kPullToRefreshTrigger * 0.8) {
          _pullArmed = false;
        }
      } else if (_pullArmed) {
        _triggerPullRefresh();
      }
    } else if (n is ScrollEndNotification) {
      if (_pullArmed) {
        _triggerPullRefresh();
      } else {
        _pullProgress.value = 0.0;
      }
    }
    return false;
  }

  Future<void> _triggerPullRefresh() async {
    _pullArmed = false;
    _pullProgress.value = 0.0;
    _refreshing.value = true;
    try {
      await widget.appState.refreshHome();
    } catch (_) {
      // Errors surface through `homeError`; the indicator just settles.
    } finally {
      if (mounted) _refreshing.value = false;
    }
  }

  /// Pick up to 6 featured Hero slides strictly requiring real widescreen landscape artwork,
  /// leading with recent popular TV Series (`近期热播`) from server playback statistics.
  List<({MediaItemModel item, String eyebrow})> _pickFeatured() {
    final app = widget.appState;
    final pool = <({MediaItemModel item, String eyebrow})>[];
    for (final i in app.popular.where((e) => e.type == 'Series')) {
      pool.add((item: i, eyebrow: '近期热播'));
    }
    for (final i in app.popular.where((e) => e.type != 'Series')) {
      pool.add((item: i, eyebrow: '热门电影'));
    }
    for (final i in app.resume) {
      pool.add((item: i, eyebrow: '继续播放'));
    }
    for (final i in app.nextUp) {
      pool.add((item: i, eyebrow: '接下来播放'));
    }
    for (final i in app.favorites) {
      pool.add((item: i, eyebrow: '我的收藏'));
    }
    for (final entry in app.parsedLatestByLibrary) {
      for (final i in entry.items) {
        pool.add((item: i, eyebrow: '最新加入 · ${entry.library.name}'));
      }
    }

    final seen = <String>{};
    final landscapeOnly = <({MediaItemModel item, String eyebrow})>[];
    for (final entry in pool) {
      final key = entry.item.seriesId ?? entry.item.id;
      if (!seen.add(key)) continue;
      final art = app.backdropArt(entry.item);
      if (art != null && !art.isPoster) {
        landscapeOnly.add(entry);
        if (landscapeOnly.length >= 6) break;
      }
    }
    return landscapeOnly;
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.appState;
    final skin = VedroSkin.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final reduceMotion = PlatformPerfProfile.shouldReduceMotion(context);
    final serverTag = app.activeServerId ?? 'none';

    late final Widget stageChild;
    late final String stageKey;

    if (!app.isSignedIn) {
      stageKey = 'welcome';
      stageChild = _ServerWelcomeHub(
        appState: app,
        wide: wide,
        onOpenAddServer: widget.onOpenAddServer,
        onOpenLocalMedia: widget.onOpenLocalMedia,
        onOpenNetworkUrl: widget.onOpenNetworkUrl,
        onOpenServerHub: widget.onOpenServerHub,
        onOpenSettings: widget.onOpenSettings,
      );
    } else if (app.switchingToServerName != null && !app.hasAnyHomeContent) {
      stageKey = 'switching:$serverTag';
      stageChild = _buildServerSwitchingStage(skin, app.switchingToServerName!);
    } else if (app.isLoadingHome && !app.hasAnyHomeContent) {
      stageKey = 'loading:$serverTag';
      stageChild = ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          HeroSkeleton(),
          RailSkeleton(landscape: true),
          RailSkeleton(landscape: false),
        ],
      );
    } else if (app.homeError != null && !app.hasAnyHomeContent) {
      stageKey = 'error:$serverTag';
      stageChild = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 36, color: skin.fg3),
              const SizedBox(height: 14),
              Text(
                app.homeError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: skin.fg2, fontSize: 14),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                children: [
                  FilledButton(
                    onPressed: app.refreshHome,
                    child: const Text('重试'),
                  ),
                  OutlinedButton(
                    onPressed: widget.onOpenServerHub,
                    child: const Text('切换线路 / 服务器'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    } else if (!app.isLoadingHome && !app.hasAnyHomeContent && app.homeError == null) {
      stageKey = 'empty:$serverTag';
      stageChild = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.video_library_outlined, size: 38, color: skin.fg3),
              const SizedBox(height: 14),
              Text(
                '当前服务器媒体库为空',
                style: TextStyle(color: skin.fg, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                '请确认服务器已完成媒体库扫描，或切换其他服务器。',
                textAlign: TextAlign.center,
                style: TextStyle(color: skin.fg3, fontSize: 13),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                children: [
                  FilledButton(
                    onPressed: app.refreshHome,
                    child: const Text('刷新首页'),
                  ),
                  OutlinedButton(
                    onPressed: widget.onOpenServerHub,
                    child: const Text('切换服务器'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    } else {
      stageKey = 'ready:$serverTag';
      stageChild = _buildLoadedHomeBody(context, app, skin, wide);
    }

    if (stageKey.startsWith('ready:') && _readyStageKey != stageKey) {
      _readyStageKey = stageKey;
      _readyStageAt = DateTime.now();
    }
    if (_lastStageKey != stageKey) {
      _lastStageKey = stageKey;
      // A new stage mounts a fresh scroll view at offset 0: reset scroll-driven chrome.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final live = _scrollCtrl.hasClients && _scrollCtrl.positions.length == 1
            ? math.min(_scrollCtrl.offset, 760.0)
            : 0.0;
        _scrollOffsetNotifier.value = live;
        widget.onScrollChanged?.call(live > 24);
      });
    }

    final stage = AnimatedSwitcher(
      duration: Duration(milliseconds: reduceMotion ? 0 : 420),
      switchInCurve: VedroTheme.easeOut,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        if (reduceMotion) return child;
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1.0).animate(anim),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(stageKey),
        child: stageChild,
      ),
    );

    if (!app.isSignedIn) return stage;
    final safeTop = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        Positioned.fill(child: stage),
        if (!wide)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _HomeMobileTopBar(
              appState: app,
              scrollOffset: _scrollOffsetNotifier,
              solidAfter: stageKey.startsWith('ready:') ? _topBarSolidAfter : 8.0,
              onOpenServerHub: widget.onOpenServerHub,
              onOpenFavorites: widget.onOpenFavorites,
            ),
          ),
        Positioned(
          top: wide ? widget.topNavClearance + 6 : safeTop + 62,
          left: 0,
          right: 0,
          child: Center(
            child: _PullRefreshIndicator(progress: _pullProgress, refreshing: _refreshing),
          ),
        ),
      ],
    );
  }

  Widget _buildServerSwitchingStage(VedroSkin skin, String serverName) {
    return Stack(
      key: const ValueKey('home-server-switching-stage'),
      fit: StackFit.expand,
      children: [
        ListView(
          physics: const NeverScrollableScrollPhysics(),
          children: const [
            HeroSkeleton(),
            RailSkeleton(landscape: true),
            RailSkeleton(landscape: false),
          ],
        ),
        Center(
          child: GlassSurface(
            borderRadius: 20,
            blur: 28,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BreathingBrandMark(size: 32),
                const SizedBox(width: 14),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '正在切换至「$serverName」',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: skin.fg,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '正在同步媒体库与海报墙…',
                        style: TextStyle(color: skin.fg3, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadedHomeBody(
    BuildContext context,
    VedroAppState app,
    VedroSkin skin,
    bool wide,
  ) {

    final showHero = app.showHomeHero && skin.heroStyle != 'compact_minimal';
    final featured = showHero
        ? _pickFeatured()
        : const <({MediaItemModel item, String eyebrow})>[];
    final caps = app.capabilities;
    final resumeIds = app.resume.map((e) => e.id).toSet();
    final nextItems = app.nextUp.where((e) => !resumeIds.contains(e.id)).toList();

    final latestMap = <String, List<MediaItemModel>>{
      for (final entry in app.parsedLatestByLibrary) entry.library.id: entry.items,
    };

    final profile = DisplayMetricsProfile.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final prefs = app.prefs;
    final padX = prefs.horizontalMargin(wide);
    final gap = prefs.cardGap(wide);
    final topGap = prefs.sectionTopGap(wide);
    final libCardW = (wide ? 248.0 : 164.0) * prefs.posterScale.clamp(0.75, 1.25);
    final libStripVPad = wide ? 18.0 : 4.0;
    final libRailH = PosterCardLayout.libraryCardHeight(
          cardWidth: libCardW,
          textScaler: textScaler,
          devicePixelRatio: profile.devicePixelRatio,
        ) +
        libStripVPad;

    final size = MediaQuery.sizeOf(context);
    final safeTop = MediaQuery.paddingOf(context).top;
    final mobileHeroH = (size.height * 0.49).clamp(328.0, 420.0);
    _topBarSolidAfter = (featured.isNotEmpty && skin.heroStyle == 'full_bleed')
        ? math.max(8.0, mobileHeroH - safeTop - 64)
        : 8.0;

    final readyAt = _readyStageAt;
    final animateEntrance = !PlatformPerfProfile.shouldReduceMotion(context) &&
        readyAt != null &&
        DateTime.now().difference(readyAt) < const Duration(milliseconds: 900);
    var sectionIndex = 0;
    Widget sectionSliver({required Widget child}) {
      final i = sectionIndex++;
      return SliverToBoxAdapter(
        child: VedroEntrance(
          delay: Duration(milliseconds: 70 + i.clamp(0, 6) * 55),
          offsetY: 26,
          enabled: animateEntrance && i < 7,
          child: child,
        ),
      );
    }

    final dynamicSectionSlivers = <Widget>[];
    for (final sec in app.homeSections) {
      if (!sec.visible) continue;
      switch (sec.id) {
        case 'libraries':
          if (app.views.isNotEmpty) {
            dynamicSectionSlivers.add(
              sectionSliver(
                child: CustomHorizontalRail(
                  title: '媒体库',
                  height: libRailH,
                  padXOverride: padX,
                  spacingOverride: gap,
                  topGapOverride: wide ? topGap : (topGap - 3).clamp(6.0, 24.0),
                  itemCount: app.views.length,
                  itemBuilder: (_, idx) {
                    final view = app.views[idx];
                    final libItems = latestMap[view.id] ?? const <MediaItemModel>[];
                    MediaItemModel? cover;
                    for (final candidate in libItems) {
                      if (app.backdropArt(candidate)?.isPoster == false) {
                        cover = candidate;
                        break;
                      }
                    }
                    cover ??= libItems.isNotEmpty ? libItems.first : null;
                    return LibraryCard(
                      library: view,
                      coverItem: cover,
                      appState: app,
                      width: libCardW,
                      onTap: () => widget.onLibraryTap(view),
                    );
                  },
                ),
              ),
            );
          }
          break;
        case 'resume':
          if (app.resume.isNotEmpty) {
            dynamicSectionSlivers.add(
              sectionSliver(
                child: HorizontalMediaRail(
                  title: '继续播放',
                  items: app.resume,
                  appState: app,
                  isResume: true,
                  onItemTap: (item) => widget.onItemTap(item),
                  onItemQuickPlay: widget.onQuickPlay,
                  onItemLongPressWithRect: (item, rect) => showMediaItemContextSheet(
                    context: context,
                    item: item,
                    appState: app,
                    anchorRect: rect,
                    landscapePreview: true,
                    onOpenDetail: () => widget.onItemTap(item),
                    onQuickPlay: () => widget.onQuickPlay(item),
                    allowHideFromResume: caps?.supportsHideFromResume == true,
                  ),
                ),
              ),
            );
          }
          break;
        case 'next_up':
          if (nextItems.isNotEmpty) {
            dynamicSectionSlivers.add(
              sectionSliver(
                child: HorizontalMediaRail(
                  title: '接下来播放',
                  items: nextItems,
                  appState: app,
                  landscape: true,
                  onItemTap: (item) => widget.onItemTap(item),
                  onItemQuickPlay: widget.onQuickPlay,
                  onItemLongPressWithRect: (item, rect) => showMediaItemContextSheet(
                    context: context,
                    item: item,
                    appState: app,
                    anchorRect: rect,
                    landscapePreview: true,
                    onOpenDetail: () => widget.onItemTap(item),
                    onQuickPlay: () => widget.onQuickPlay(item),
                  ),
                ),
              ),
            );
          }
          break;
        case 'favorites':
          if (app.favorites.isNotEmpty) {
            dynamicSectionSlivers.add(
              sectionSliver(
                child: HorizontalMediaRail(
                  title: '我的收藏',
                  items: app.favorites,
                  appState: app,
                  heroPrefix: 'fav',
                  onItemTap: (item) => widget.onItemTap(item, heroPrefix: 'fav'),
                  onItemQuickPlay: widget.onQuickPlay,
                  onItemLongPressWithRect: (item, rect) => showMediaItemContextSheet(
                    context: context,
                    item: item,
                    appState: app,
                    anchorRect: rect,
                    onOpenDetail: () => widget.onItemTap(item, heroPrefix: 'fav'),
                    onQuickPlay: () => widget.onQuickPlay(item),
                  ),
                ),
              ),
            );
          }
          break;
        case 'latest':
          for (final entry in app.parsedLatestByLibrary) {
            final lib = entry.library;
            final items = entry.items;
            if (items.isEmpty) continue;
            dynamicSectionSlivers.add(
              sectionSliver(
                child: HorizontalMediaRail(
                  title: '最新加入 · ${lib.name}',
                  items: items,
                  appState: app,
                  heroPrefix: 'lat-${lib.id}',
                  onItemTap: (item) => widget.onItemTap(item, heroPrefix: 'lat-${lib.id}'),
                  onItemQuickPlay: widget.onQuickPlay,
                  onItemLongPressWithRect: (item, rect) => showMediaItemContextSheet(
                    context: context,
                    item: item,
                    appState: app,
                    anchorRect: rect,
                    onOpenDetail: () => widget.onItemTap(item, heroPrefix: 'lat-${lib.id}'),
                    onQuickPlay: () => widget.onQuickPlay(item),
                  ),
                  onSeeAll: () => widget.onLibraryTap(lib),
                ),
              ),
            );
          }
          break;
        case 'suggestions':
          if (app.suggestions.isNotEmpty) {
            dynamicSectionSlivers.add(
              sectionSliver(
                child: HorizontalMediaRail(
                  title: '猜你喜欢',
                  items: app.suggestions,
                  appState: app,
                  heroPrefix: 'sug',
                  onItemTap: (item) => widget.onItemTap(item, heroPrefix: 'sug'),
                  onItemQuickPlay: widget.onQuickPlay,
                  onItemLongPressWithRect: (item, rect) => showMediaItemContextSheet(
                    context: context,
                    item: item,
                    appState: app,
                    anchorRect: rect,
                    onOpenDetail: () => widget.onItemTap(item, heroPrefix: 'sug'),
                    onQuickPlay: () => widget.onQuickPlay(item),
                  ),
                ),
              ),
            );
          }
          break;
      }
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: CustomScrollView(
        controller: _scrollCtrl,
        cacheExtent: PlatformPerfProfile.scrollCacheExtent,
        slivers: [
          if (featured.isNotEmpty)
            SliverToBoxAdapter(
              child: _CinemaHeroBanner(
                featured: featured,
                appState: app,
                scrollOffsetListenable: _scrollOffsetNotifier,
                topNavClearance: widget.topNavClearance,
                onPlay: widget.onQuickPlay,
                onDetail: (item) => widget.onItemTap(item, heroPrefix: 'hero'),
                onGenreTap: widget.onGenreTap,
              ),
            )
          else
            SliverToBoxAdapter(
              child: SizedBox(
                height: wide ? widget.topNavClearance : safeTop + 60,
              ),
            ),

          if (app.remoteBannerMessage != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(padX, 12, padX, 0),
                child: GlassSurface(
                  borderRadius: 12,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.cast_connected_rounded, size: 16, color: skin.fg2),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          app.remoteBannerMessage!,
                          style: TextStyle(color: skin.fg, fontSize: 13),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: '关闭提示',
                        icon: Icon(Icons.close_rounded, size: 16, color: skin.fg3),
                        onPressed: app.dismissRemoteBanner,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          ...dynamicSectionSlivers,

          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(padX, wide ? 40 : 30, padX, wide ? 56 : 112),
              child: Center(
                child: PressableScale(
                  onTap: () => showHomeLayoutSheet(context: context, appState: app),
                  hoverScale: 1.03,
                  pressScale: 0.94,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: skin.subtleChipBg,
                      borderRadius: BorderRadius.circular(skin.radiusForPill(36)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tune_rounded, size: 15, color: skin.fg2),
                        const SizedBox(width: 7),
                        Text(
                          '自定义首页',
                          style: TextStyle(
                            color: skin.fg2,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}
