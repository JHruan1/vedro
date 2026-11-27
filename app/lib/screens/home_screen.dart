import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/platform/platform_perf.dart';
import '../core/theme/display_profile.dart';
import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/home_layout_sheet.dart';
import '../widgets/horizontal_rail.dart';
import '../widgets/media_card.dart';
import '../widgets/server_card_grid.dart';
import '../widgets/vedro_artwork.dart';
import '../widgets/vedro_ui.dart';
import 'player_screen.dart';

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
  final _scrollCtrl = ScrollController();
  final ValueNotifier<double> _scrollOffsetNotifier = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _scrollOffsetNotifier.dispose();
    super.dispose();
  }

  void _onScroll() {
    final offset = _scrollCtrl.offset;
    widget.onScrollChanged?.call(offset > 24);
    if (offset < 760) {
      _scrollOffsetNotifier.value = offset;
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

    if (!app.isSignedIn) {
      return _ServerWelcomeHub(
        appState: app,
        wide: wide,
        onOpenAddServer: widget.onOpenAddServer,
        onOpenLocalMedia: widget.onOpenLocalMedia,
        onOpenNetworkUrl: widget.onOpenNetworkUrl,
        onOpenServerHub: widget.onOpenServerHub,
        onOpenSettings: widget.onOpenSettings,
      );
    }

    if (app.isLoadingHome && !app.hasAnyHomeContent) {
      return ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          HeroSkeleton(),
          RailSkeleton(landscape: true),
          RailSkeleton(landscape: false),
        ],
      );
    }

    if (app.homeError != null && !app.hasAnyHomeContent) {
      return Center(
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
    }

    if (!app.isLoadingHome && !app.hasAnyHomeContent && app.homeError == null) {
      return Center(
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
    }

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

    final dynamicSectionSlivers = <Widget>[];
    for (final sec in app.homeSections) {
      if (!sec.visible) continue;
      switch (sec.id) {
        case 'libraries':
          if (app.views.isNotEmpty) {
            dynamicSectionSlivers.add(
              SliverToBoxAdapter(
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
              SliverToBoxAdapter(
                child: HorizontalMediaRail(
                  title: '继续播放',
                  items: app.resume,
                  appState: app,
                  isResume: true,
                  onItemTap: (item) => widget.onItemTap(item),
                  onItemQuickPlay: widget.onQuickPlay,
                  onItemLongPress: (item) => showMediaItemContextSheet(
                    context: context,
                    item: item,
                    appState: app,
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
              SliverToBoxAdapter(
                child: HorizontalMediaRail(
                  title: '接下来播放',
                  items: nextItems,
                  appState: app,
                  landscape: true,
                  onItemTap: (item) => widget.onItemTap(item),
                  onItemQuickPlay: widget.onQuickPlay,
                  onItemLongPress: (item) => showMediaItemContextSheet(
                    context: context,
                    item: item,
                    appState: app,
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
              SliverToBoxAdapter(
                child: HorizontalMediaRail(
                  title: '我的收藏',
                  items: app.favorites,
                  appState: app,
                  heroPrefix: 'fav',
                  onItemTap: (item) => widget.onItemTap(item, heroPrefix: 'fav'),
                  onItemQuickPlay: widget.onQuickPlay,
                  onItemLongPress: (item) => showMediaItemContextSheet(
                    context: context,
                    item: item,
                    appState: app,
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
              SliverToBoxAdapter(
                child: HorizontalMediaRail(
                  title: '最新加入 · ${lib.name}',
                  items: items,
                  appState: app,
                  heroPrefix: 'lat-${lib.id}',
                  onItemTap: (item) => widget.onItemTap(item, heroPrefix: 'lat-${lib.id}'),
                  onItemQuickPlay: widget.onQuickPlay,
                  onItemLongPress: (item) => showMediaItemContextSheet(
                    context: context,
                    item: item,
                    appState: app,
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
              SliverToBoxAdapter(
                child: HorizontalMediaRail(
                  title: '猜你喜欢',
                  items: app.suggestions,
                  appState: app,
                  heroPrefix: 'sug',
                  onItemTap: (item) => widget.onItemTap(item, heroPrefix: 'sug'),
                  onItemQuickPlay: widget.onQuickPlay,
                  onItemLongPress: (item) => showMediaItemContextSheet(
                    context: context,
                    item: item,
                    appState: app,
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

    return RefreshIndicator(
      color: skin.fg,
      backgroundColor: skin.surface2,
      onRefresh: app.refreshHome,
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
                showMobileHeader: !wide,
                onPlay: widget.onQuickPlay,
                onDetail: (item) => widget.onItemTap(item, heroPrefix: 'hero'),
                onGenreTap: widget.onGenreTap,
                onOpenFavorites: widget.onOpenFavorites,
                onOpenServerHub: widget.onOpenServerHub,
                onRefresh: app.refreshHome,
              ),
            )
          else
            SliverToBoxAdapter(
              child: SizedBox(
                height: wide ? widget.topNavClearance : MediaQuery.paddingOf(context).top + 12,
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
              padding: EdgeInsets.fromLTRB(padX, wide ? 28 : 18, padX, wide ? 48 : 104),
              child: Center(
                child: PressableScale(
                  onTap: () => showHomeLayoutSheet(context: context, appState: app),
                  hoverScale: 1.03,
                  pressScale: 0.96,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: skin.panelSurface,
                      borderRadius: BorderRadius.circular(skin.radiusForPill(36)),
                      border: Border.all(color: skin.border, width: 0.8),
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

/// Universal long-press / right-click / TV context-menu action sheet for media cards.
void showMediaItemContextSheet({
  required BuildContext context,
  required MediaItemModel item,
  required VedroAppState appState,
  required VoidCallback onOpenDetail,
  VoidCallback? onQuickPlay,
  bool allowHideFromResume = false,
  VoidCallback? onMutated,
}) {
  final skin = VedroSkin.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  Future<void> openAddToPlaylistSheet() async {
    try {
      await appState.refreshPlaylists();
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('加载片单失败：${VedroErrorFormatter.friendly(e)}')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    showGlassSheet<void>(
      context: context,
      builder: (ctx) {
        final s = VedroSkin.of(ctx);
        final lists = appState.playlists;
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '加入片单',
                style: TextStyle(color: s.fg, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            if (lists.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('暂无片单，请先在片单页新建', style: TextStyle(color: s.fg3, fontSize: 13)),
              )
            else
              for (var i = 0; i < lists.length; i++)
                ListTile(
                  autofocus: i == 0,
                  leading: Icon(Icons.bookmark_outline_rounded, color: s.fg2),
                  title: Text(lists[i].name, style: TextStyle(color: s.fg, fontSize: 14)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      await appState.core.invoke('add_to_playlist', {
                        'playlist_id': lists[i].id,
                        'item_ids': [item.id],
                      });
                      messenger.showSnackBar(
                        SnackBar(content: Text('已加入片单「${lists[i].name}」')),
                      );
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('加入片单失败：${VedroErrorFormatter.friendly(e)}')),
                      );
                    }
                  },
                ),
          ],
        );
      },
    );
  }

  showGlassSheet<void>(
    context: context,
    builder: (ctx) => ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.cardTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: skin.fg, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              if (item.cardSubtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  item.cardSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: skin.fg3, fontSize: 12.5),
                ),
              ],
            ],
          ),
        ),
        if (onQuickPlay != null && item.isPlayable)
          ListTile(
            autofocus: true,
            leading: Icon(Icons.play_arrow_rounded, color: skin.accent),
            title: Text(
              item.playbackPositionTicks > 0 ? '继续播放' : '立即播放',
              style: TextStyle(color: skin.fg, fontSize: 14.5, fontWeight: FontWeight.w500),
            ),
            onTap: () {
              Navigator.pop(ctx);
              onQuickPlay();
            },
          ),
        if (item.isPlayable && item.playbackPositionTicks > 0)
          ListTile(
            leading: Icon(Icons.replay_rounded, color: skin.fg2),
            title: Text('从头播放', style: TextStyle(color: skin.fg, fontSize: 14.5)),
            onTap: () {
              Navigator.pop(ctx);
              final restartItem = MediaItemModel(
                id: item.id,
                name: item.name,
                type: item.type,
                seriesId: item.seriesId,
                seriesName: item.seriesName,
                parentIndexNumber: item.parentIndexNumber,
                indexNumber: item.indexNumber,
                runTimeTicks: item.runTimeTicks,
                playbackPositionTicks: 0,
                mediaSources: item.mediaSources,
                chapters: item.chapters,
              );
              navigator.push(vedroRoute(PlayerScreen(item: restartItem, appState: appState)));
            },
          ),
        ListTile(
          autofocus: !(onQuickPlay != null && item.isPlayable),
          leading: Icon(Icons.info_outline_rounded, color: skin.fg2),
          title: Text('查看详情', style: TextStyle(color: skin.fg, fontSize: 14.5)),
          onTap: () {
            Navigator.pop(ctx);
            onOpenDetail();
          },
        ),
        if (item.type != 'Person' && item.type != 'Folder') ...[
          ListTile(
            leading: Icon(
              item.played ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
              color: item.played ? skin.accent : skin.fg2,
            ),
            title: Text(
              item.played ? '标为未看' : '标为已看',
              style: TextStyle(color: skin.fg, fontSize: 14.5),
            ),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                await appState.togglePlayed(item);
                onMutated?.call();
                messenger.showSnackBar(
                  SnackBar(content: Text(item.played ? '已标为未看' : '已标为已看')),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('操作失败：${VedroErrorFormatter.friendly(e)}')),
                );
              }
            },
          ),
          ListTile(
            leading: Icon(
              item.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: item.isFavorite ? VedroTheme.danger : skin.fg2,
            ),
            title: Text(
              item.isFavorite ? '取消收藏' : '加入收藏',
              style: TextStyle(color: skin.fg, fontSize: 14.5),
            ),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                await appState.toggleFavorite(item);
                onMutated?.call();
                messenger.showSnackBar(
                  SnackBar(content: Text(item.isFavorite ? '已取消收藏' : '已加入收藏')),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('操作失败：${VedroErrorFormatter.friendly(e)}')),
                );
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.playlist_add_rounded, color: skin.fg2),
            title: Text('加入片单', style: TextStyle(color: skin.fg, fontSize: 14.5)),
            onTap: () {
              Navigator.pop(ctx);
              unawaited(openAddToPlaylistSheet());
            },
          ),
        ],
        if (allowHideFromResume)
          ListTile(
            leading: const Icon(Icons.visibility_off_outlined, color: VedroTheme.danger),
            title: const Text(
              '从继续观看移除',
              style: TextStyle(color: VedroTheme.danger, fontSize: 14.5),
            ),
            onTap: () {
              Navigator.pop(ctx);
              unawaited(appState.hideFromResume(item.id).then((_) {
                onMutated?.call();
              }).catchError((Object e) {
                if (context.mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('移除失败：${VedroErrorFormatter.friendly(e)}')),
                  );
                }
              }));
            },
          ),
      ],
    ),
  );
}

/// SenPlayer / Forward Home Server Hub shown on startup when no server is active yet.
class _ServerWelcomeHub extends StatelessWidget {
  const _ServerWelcomeHub({
    required this.appState,
    required this.wide,
    required this.onOpenAddServer,
    this.onOpenLocalMedia,
    this.onOpenNetworkUrl,
    required this.onOpenServerHub,
    required this.onOpenSettings,
  });

  final VedroAppState appState;
  final bool wide;
  final void Function([String? initialUrl]) onOpenAddServer;
  final VoidCallback? onOpenLocalMedia;
  final VoidCallback? onOpenNetworkUrl;
  final VoidCallback onOpenServerHub;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final saved = appState.savedServers;
    final discovered = appState.discoveredServers;
    final btnR = skin.pillRadius >= 100 ? 12.0 : skin.pillRadius.clamp(6.0, 16.0);

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, wide ? 84 : 28, 24, wide ? 48 : 112),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: saved.length > 1 ? 940 : 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: VedroBrandMark(size: 56)),
                const SizedBox(height: 18),
                Text(
                  'Vedro',
                  textAlign: TextAlign.center,
                  style: skin.applyHeadlineMood(
                    TextStyle(
                      color: skin.fg,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.7,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '连接媒体服务器或打开本地视频',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: skin.fg3, fontSize: 13.5),
                ),
                const SizedBox(height: 28),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    PressableScale(
                      onTap: () => onOpenAddServer(),
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        decoration: BoxDecoration(
                          color: skin.primaryCtaBg,
                          gradient: skin.primaryCtaGradient,
                          borderRadius: BorderRadius.circular(btnR),
                          border: skin.primaryCtaBorder,
                          boxShadow: skin.primaryCtaShadow,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded, size: 19, color: skin.primaryCtaFg),
                            const SizedBox(width: 6),
                            Text(
                              '添加媒体服务器',
                              style: TextStyle(
                                color: skin.primaryCtaFg,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (onOpenLocalMedia != null)
                      PressableScale(
                        onTap: onOpenLocalMedia,
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          decoration: BoxDecoration(
                            color: skin.surface2,
                            borderRadius: BorderRadius.circular(btnR),
                            border: Border.all(color: skin.border, width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.folder_open_rounded, size: 17, color: skin.fg2),
                              const SizedBox(width: 7),
                              Text(
                                '本地播放',
                                style: TextStyle(
                                  color: skin.fg,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (onOpenNetworkUrl != null)
                      PressableScale(
                        onTap: onOpenNetworkUrl,
                        borderRadius: BorderRadius.circular(btnR),
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          decoration: BoxDecoration(
                            color: skin.surface2,
                            borderRadius: BorderRadius.circular(btnR),
                            border: Border.all(color: skin.border, width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.link_rounded, size: 17, color: skin.fg2),
                              const SizedBox(width: 7),
                              Text(
                                '网络链接',
                                style: TextStyle(
                                  color: skin.fg,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    PressableScale(
                      onTap: onOpenSettings,
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                          color: skin.surface2,
                          borderRadius: BorderRadius.circular(btnR),
                          border: Border.all(color: skin.border, width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.tune_rounded, size: 17, color: skin.fg2),
                            const SizedBox(width: 7),
                            Text(
                              '播放器设置',
                              style: TextStyle(
                                color: skin.fg,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                if (saved.isNotEmpty) ...[
                  const SizedBox(height: 36),
                  ServerCardGrid(
                    appState: appState,
                    onSelectServer: (srv) => appState.restoreSavedServer(srv),
                    onAddServer: () => onOpenAddServer(),
                  ),
                ],

                if (discovered.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    '局域网发现',
                    style: TextStyle(
                      color: skin.fg2,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: discovered.map((d) {
                      final addr = d['address']?.toString() ?? '';
                      return PressableScale(
                        onTap: () => onOpenAddServer(addr),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                          decoration: BoxDecoration(
                            color: skin.surface,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: skin.border, width: 0.7),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.wifi_tethering_rounded, size: 15, color: skin.fg2),
                              const SizedBox(width: 8),
                              Text(
                                '${d['name'] ?? addr}',
                                style: TextStyle(color: skin.fg, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Multi-personality Home Hero Stage supporting 3 structural layouts:
/// - `'full_bleed'`: Edge-to-edge full-screen cinema Hero (zero white border boxes on thumbnails, sealed bottom seam!)
/// - `'framed_stage'`: ElegantFin / Jellyseerr inset panoramic rounded card stage
/// - `'split_showcase'`: Criterion / Kinfolk editorial 2-column magazine showcase
class _CinemaHeroBanner extends StatefulWidget {
  const _CinemaHeroBanner({
    required this.featured,
    required this.appState,
    required this.scrollOffsetListenable,
    required this.topNavClearance,
    required this.showMobileHeader,
    required this.onPlay,
    required this.onDetail,
    this.onGenreTap,
    this.onOpenFavorites,
    required this.onOpenServerHub,
    required this.onRefresh,
  });

  final List<({MediaItemModel item, String eyebrow})> featured;
  final VedroAppState appState;
  final ValueListenable<double> scrollOffsetListenable;
  final double topNavClearance;
  final bool showMobileHeader;
  final void Function(MediaItemModel) onPlay;
  final void Function(MediaItemModel) onDetail;
  final ValueChanged<String>? onGenreTap;
  final VoidCallback? onOpenFavorites;
  final VoidCallback onOpenServerHub;
  final VoidCallback onRefresh;

  @override
  State<_CinemaHeroBanner> createState() => _CinemaHeroBannerState();
}

class _CinemaHeroBannerState extends State<_CinemaHeroBanner> {
  late final PageController _pageCtrl = PageController();
  int _active = 0;
  bool _paused = false;
  bool _userDragging = false;
  bool _hovered = false;
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    _syncDynamicHeroColor();
    _armTimer();
  }

  @override
  void didUpdateWidget(covariant _CinemaHeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_active >= widget.featured.length) {
      _active = 0;
      if (_pageCtrl.hasClients) {
        _pageCtrl.jumpToPage(0);
      }
    }
    if (oldWidget.featured != widget.featured) {
      _syncDynamicHeroColor();
    }
  }

  void _syncDynamicHeroColor() {
    if (widget.featured.isEmpty) return;
    final safeIdx = _active.clamp(0, widget.featured.length - 1);
    final target = widget.featured[safeIdx].item;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.appState.updateDynamicSeedFromItem(target);
      }
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _armTimer() {
    _autoTimer?.cancel();
    if (widget.featured.length < 2 || _paused || _userDragging) return;
    _autoTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted || _userDragging) return;
      // Skip invisible background Hero advances when scrolled past or on another tab/route!
      if (!TickerMode.of(context) || widget.scrollOffsetListenable.value > 380) {
        _armTimer();
        return;
      }
      final next = (_active + 1) % widget.featured.length;
      _select(next);
    });
  }

  void _select(int index) {
    if (widget.featured.isEmpty) return;
    final target = index.clamp(0, widget.featured.length - 1);
    if (_pageCtrl.hasClients && widget.featured.length > 1) {
      _pageCtrl.animateToPage(
        target,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      setState(() => _active = target);
      _syncDynamicHeroColor();
    }
    _armTimer();
  }

  void _onPageChanged(int index) {
    if (_active == index) return;
    setState(() => _active = index);
    _syncDynamicHeroColor();
    _armTimer();
  }

  /// Borderless floating preview thumbnails (ZERO white border boxes!) + sleek active indicator bar.
  /// Width-aware so 960dp TV and split_showcase narrow columns NEVER overflow or collide with CTAs.
  Widget _buildBorderlessPreviewStrip(
    VedroSkin skin, {
    bool onLightSurface = false,
    double? maxWidth,
  }) {
    final count = widget.featured.length;
    if (count == 0) return const SizedBox.shrink();
    double thumbW = 92;
    double spacing = 10;
    if (maxWidth != null && maxWidth.isFinite) {
      final fullNeed = count * thumbW + (count - 1) * spacing;
      if (fullNeed > maxWidth) {
        spacing = 7;
        final fitW = (maxWidth - (count - 1) * spacing) / count;
        if (fitW < 54) {
          return _buildCapsuleDots(skin: skin, onLightSurface: onLightSurface);
        }
        thumbW = fitW.clamp(54.0, 92.0);
      }
    }
    final thumbH = (thumbW * 9 / 16).roundToDouble();
    final barActiveColor = skin.ctaStyle == 'contrast'
        ? (onLightSurface ? skin.fg : Colors.white)
        : skin.accent;
    return Row(
      key: const ValueKey('hero-preview-strip'),
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final active = i == _active;
        final entry = widget.featured[i];
        return Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : spacing),
          child: PressableScale(
            onTap: () => _select(i),
            hoverScale: 1.05,
            pressScale: 0.95,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: active ? 1.04 : 0.94,
                  duration: const Duration(milliseconds: 220),
                  curve: VedroTheme.easeOut,
                  child: Container(
                    width: thumbW,
                    height: thumbH,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(skin.cardRadius.clamp(6.0, 11.0)),
                      boxShadow: active
                          ? const [
                              BoxShadow(
                                color: Color(0xA6000000),
                                blurRadius: 18,
                                offset: Offset(0, 7),
                              ),
                            ]
                          : const [
                              BoxShadow(
                                color: Color(0x40000000),
                                blurRadius: 8,
                                offset: Offset(0, 3),
                              ),
                            ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: AnimatedOpacity(
                      opacity: active ? 1.0 : 0.42,
                      duration: const Duration(milliseconds: 220),
                      child: VedroArtwork(
                        item: entry.item,
                        appState: widget.appState,
                        landscape: true,
                        width: 320,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: VedroTheme.easeOut,
                  width: active ? (thumbW * 0.30).clamp(18.0, 28.0) : 8,
                  height: 3,
                  decoration: BoxDecoration(
                    color: active
                        ? barActiveColor
                        : (onLightSurface
                            ? skin.fg.withValues(alpha: 0.18)
                            : const Color(0x38FFFFFF)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCapsuleDots({bool onLightSurface = false, required VedroSkin skin}) {
    final activeColor = onLightSurface ? skin.fg : Colors.white;
    final inactiveColor = onLightSurface ? skin.fg.withValues(alpha: 0.24) : const Color(0x52FFFFFF);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.featured.length, (i) {
        final active = i == _active;
        return PressableScale(
          onTap: () => _select(i),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: VedroTheme.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 22 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active ? activeColor : inactiveColor,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildMobileTopBar() {
    final skin = VedroSkin.of(context);
    final serverName = widget.appState.activeServerDisplayName;
    final routeName = widget.appState.activeRouteDisplayName;
    final pillBg = skin.isLight ? const Color(0xCCFFFFFF) : const Color(0x58141417);
    final pillFg = skin.isLight ? skin.fg : Colors.white;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: Row(
          children: [
            PressableScale(
              onTap: widget.onOpenServerHub,
              child: GlassSurface(
                borderRadius: 18,
                blur: 18,
                color: pillBg,
                borderColor: skin.isLight ? skin.border : Colors.transparent,
                padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const VedroBrandMark(size: 22),
                    const SizedBox(width: 7),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        routeName != null ? '$serverName · $routeName' : serverName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: pillFg,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: skin.isLight ? skin.fg2 : const Color(0xCCFFFFFF),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            if (widget.onOpenFavorites != null) ...[
              PressableScale(
                onTap: widget.onOpenFavorites,
                child: GlassSurface(
                  borderRadius: 18,
                  blur: 18,
                  color: pillBg,
                  borderColor: skin.isLight ? skin.border : Colors.transparent,
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.favorite_border_rounded, size: 17, color: pillFg),
                ),
              ),
              const SizedBox(width: 8),
            ],
            PressableScale(
              onTap: widget.onRefresh,
              child: GlassSurface(
                borderRadius: 18,
                blur: 18,
                color: pillBg,
                borderColor: skin.isLight ? skin.border : Colors.transparent,
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.refresh_rounded, size: 17, color: pillFg),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroInfoColumn({
    required BuildContext context,
    required VedroSkin skin,
    required MediaItemModel item,
    required String eyebrow,
    required String? logoUrl,
    required bool wide,
    required bool onPhoto,
  }) {
    final textPrimary = onPhoto ? Colors.white : skin.fg;
    final textSecondary = onPhoto ? const Color(0xD9FFFFFF) : skin.fg2;
    final textMuted = onPhoto ? const Color(0xC0FFFFFF) : skin.fg3;
    final pillR = skin.radiusForPill(44);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 360),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: Column(
        key: ValueKey(item.id),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            eyebrow,
            style: TextStyle(
              color: onPhoto ? textMuted : skin.accent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          if (logoUrl != null && skin.preferClearLogo && (onPhoto || !skin.isLight))
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: wide ? 104 : 74,
                maxWidth: wide ? 420 : 280,
              ),
              child: Image.network(
                logoUrl,
                cacheWidth: 640,
                filterQuality: FilterQuality.medium,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                errorBuilder: (_, __, ___) => _HeroTitleText(
                  text: item.cardTitle,
                  wide: wide,
                  color: textPrimary,
                ),
              ),
            )
          else
            _HeroTitleText(text: item.cardTitle, wide: wide, color: textPrimary),
          if (item.communityRating != null ||
              item.productionYear != null ||
              item.genres.isNotEmpty ||
              (item.type == 'Episode' && item.cardSubtitle.isNotEmpty)) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (item.type == 'Episode' && item.cardSubtitle.isNotEmpty)
                  Text(
                    item.cardSubtitle,
                    style: TextStyle(color: textSecondary, fontSize: 13.5),
                  ),
                if (item.communityRating != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.star_rounded,
                        size: 15,
                        color: onPhoto ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
                      ),
                      const SizedBox(width: 2.5),
                      Text(
                        item.communityRating!.toStringAsFixed(1),
                        style: TextStyle(
                          color: onPhoto ? const Color(0xF2FFFFFF) : const Color(0xFFD97706),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                if (item.productionYear != null)
                  Text(
                    '${item.productionYear}',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 13.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                for (final g in item.genres.take(4))
                  PressableScale(
                    onTap: widget.onGenreTap == null ? null : () => widget.onGenreTap!(g),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      child: Text(
                        g,
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (item.cleanOverview.isNotEmpty) ...[
            SizedBox(height: wide ? 10 : 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Text(
                item.cleanOverview,
                maxLines: wide ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textSecondary,
                  fontSize: wide ? 14 : 12.5,
                  height: wide ? 1.55 : 1.42,
                ),
              ),
            ),
          ],
          SizedBox(height: wide ? 22 : 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PressableScale(
                onTap: () => widget.onPlay(item),
                hoverScale: 1.03,
                pressScale: 0.96,
                child: Container(
                  height: wide ? 44 : 38,
                  padding: EdgeInsets.symmetric(horizontal: wide ? 26 : 20),
                  decoration: BoxDecoration(
                    color: onPhoto && skin.isLight ? Colors.white : skin.primaryCtaBg,
                    gradient: onPhoto && skin.isLight ? null : skin.primaryCtaGradient,
                    borderRadius: BorderRadius.circular(pillR),
                    border: onPhoto && skin.isLight ? null : skin.primaryCtaBorder,
                    boxShadow: onPhoto
                        ? const [
                            BoxShadow(
                              color: Color(0x48000000),
                              blurRadius: 18,
                              offset: Offset(0, 6),
                            ),
                          ]
                        : skin.primaryCtaShadow,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        size: 22,
                        color: onPhoto && skin.isLight
                            ? const Color(0xFF09090B)
                            : skin.primaryCtaFg,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '播放',
                        style: TextStyle(
                          color: onPhoto && skin.isLight
                              ? const Color(0xFF09090B)
                              : skin.primaryCtaFg,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              PressableScale(
                onTap: () => widget.onDetail(item),
                hoverScale: 1.03,
                pressScale: 0.96,
                child: onPhoto
                    ? GlassSurface(
                        borderRadius: pillR,
                        blur: 24,
                        color: const Color(0x40FFFFFF),
                        borderColor: Colors.transparent,
                        padding: EdgeInsets.symmetric(
                          horizontal: wide ? 22 : 18,
                          vertical: wide ? 11 : 8.5,
                        ),
                        child: Text(
                          '详情',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: wide ? 14.5 : 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : Container(
                        height: wide ? 44 : 38,
                        padding: EdgeInsets.symmetric(horizontal: wide ? 22 : 18),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: skin.surface2,
                          borderRadius: BorderRadius.circular(pillR),
                          border: Border.all(color: skin.borderStrong, width: 0.8),
                        ),
                        child: Text(
                          '详情',
                          style: TextStyle(
                            color: skin.fg,
                            fontSize: wide ? 14.5 : 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 820;
    final padX = widget.appState.prefs.horizontalMargin(wide);
    final current = widget.featured[_active];
    final item = current.item;
    final logoUrl = widget.appState.logoArtUrl(item);

    Widget wrapHeroInteraction(Widget child) {
      return Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) {
          if (focused) {
            _paused = true;
            _autoTimer?.cancel();
          } else if (!_hovered) {
            _paused = false;
            _armTimer();
          }
        },
        child: MouseRegion(
          onEnter: (_) {
            setState(() => _hovered = true);
            _paused = true;
            _autoTimer?.cancel();
          },
          onExit: (_) {
            setState(() => _hovered = false);
            _paused = false;
            _armTimer();
          },
          child: child,
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Layout Mode B: Criterion / Kinfolk 2-Column Editorial Split Showcase
    // -------------------------------------------------------------------------
    if (wide && skin.heroStyle == 'split_showcase') {
      final cardR = skin.cardRadius.clamp(8.0, 24.0);
      return wrapHeroInteraction(
        Padding(
          key: const ValueKey('hero-split-showcase'),
          padding: EdgeInsets.fromLTRB(padX, widget.topNavClearance + 14, padX, 12),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: skin.panelSurface,
              borderRadius: BorderRadius.circular(cardR),
              border: skin.cardBorder(),
              boxShadow: skin.posterShadow(),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 5,
                  child: _buildHeroInfoColumn(
                    context: context,
                    skin: skin,
                    item: item,
                    eyebrow: current.eyebrow,
                    logoUrl: logoUrl,
                    wide: true,
                    onPhoto: false,
                  ),
                ),
                const SizedBox(width: 28),
                Expanded(
                  flex: 6,
                  child: LayoutBuilder(
                    builder: (_, colConstraints) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(cardR),
                              boxShadow: skin.posterShadow(hovered: true),
                            ),
                            foregroundDecoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(cardR),
                              border: skin.cardBorder(),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                for (var i = 0; i < widget.featured.length; i++)
                                  AnimatedOpacity(
                                    opacity: i == _active ? 1.0 : 0.0,
                                    duration: const Duration(milliseconds: 480),
                                    curve: Curves.easeOutCubic,
                                    child: VedroArtwork(
                                      item: widget.featured[i].item,
                                      appState: widget.appState,
                                      isHero: true,
                                      showInitials: false,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (widget.featured.length > 1) ...[
                          const SizedBox(height: 14),
                          _buildBorderlessPreviewStrip(
                            skin,
                            onLightSurface: skin.isLight,
                            maxWidth: colConstraints.maxWidth,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Layout Mode C: ElegantFin / Jellyseerr Framed Rounded Panoramic Stage
    // -------------------------------------------------------------------------
    if (skin.heroStyle == 'framed_stage') {
      final stageR = skin.cardRadius.clamp(10.0, 26.0);
      final stageH = (size.height * (wide ? 0.56 : 0.44)).clamp(310.0, 560.0);
      final stageStripMaxW = (size.width - padX * 2 - 420).clamp(180.0, 620.0);
      return wrapHeroInteraction(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showMobileHeader) _buildMobileTopBar(),
            Padding(
              key: const ValueKey('hero-framed-stage'),
              padding: EdgeInsets.fromLTRB(
                padX,
                wide ? widget.topNavClearance + 8 : 4,
                padX,
                4,
              ),
              child: Container(
                height: stageH,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(stageR),
                  boxShadow: skin.posterShadow(hovered: true),
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(stageR),
                  border: skin.cardBorder(),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n is ScrollStartNotification && n.dragDetails != null) {
                          _userDragging = true;
                          _autoTimer?.cancel();
                        } else if (n is ScrollEndNotification && _userDragging) {
                          _userDragging = false;
                          _armTimer();
                        }
                        return false;
                      },
                      child: PageView.builder(
                        key: const ValueKey('hero-page-view'),
                        controller: _pageCtrl,
                        itemCount: widget.featured.length,
                        physics: const BouncingScrollPhysics(),
                        onPageChanged: _onPageChanged,
                        itemBuilder: (ctx, idx) {
                          final slide = widget.featured[idx];
                          final slideLogo = widget.appState.logoArtUrl(slide.item);
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => widget.onDetail(slide.item),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                VedroArtwork(
                                  item: slide.item,
                                  appState: widget.appState,
                                  isHero: true,
                                  alignment: const Alignment(0, -0.45),
                                  showInitials: false,
                                ),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                      stops: const [0.0, 0.55, 1.0],
                                      colors: skin.isLight
                                          ? [
                                              skin.surface.withValues(alpha: 0.94),
                                              skin.surface.withValues(alpha: 0.58),
                                              skin.surface.withValues(alpha: 0.06),
                                            ]
                                          : const [
                                              Color(0xD808090E),
                                              Color(0x6E08090E),
                                              Color(0x1808090E),
                                            ],
                                    ),
                                  ),
                                ),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      stops: const [0.0, 0.45, 1.0],
                                      colors: skin.isLight
                                          ? [
                                              skin.surface.withValues(alpha: 0.08),
                                              skin.surface.withValues(alpha: 0.24),
                                              skin.surface.withValues(alpha: 0.90),
                                            ]
                                          : const [
                                              Color(0x2808090E),
                                              Color(0x3808090E),
                                              Color(0xDE08090E),
                                            ],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: wide ? 34 : 16,
                                  right: wide ? size.width * 0.34 : 16,
                                  bottom: wide ? 32 : 28,
                                  child: _buildHeroInfoColumn(
                                    context: context,
                                    skin: skin,
                                    item: slide.item,
                                    eyebrow: slide.eyebrow,
                                    logoUrl: slideLogo,
                                    wide: wide,
                                    onPhoto: !skin.isLight,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    if (widget.featured.length > 1)
                      Positioned(
                        right: wide ? 28 : 16,
                        left: wide ? null : 16,
                        bottom: wide ? 26 : 10,
                        child: wide
                            ? _buildBorderlessPreviewStrip(
                                skin,
                                onLightSurface: skin.isLight,
                                maxWidth: stageStripMaxW,
                              )
                            : _buildCapsuleDots(skin: skin, onLightSurface: skin.isLight),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Layout Mode A (Default): Apple TV+ Full-Bleed Cinema Hero
    // - Horizontal `PageView.builder` swipeable left/right with 1:1 finger physics!
    // - `ClipRect` + direct canvas gradient dissolve (zero offscreen saveLayer!)
    // -------------------------------------------------------------------------
    final heroH = wide
        ? (size.height * 0.70).clamp(460.0, 740.0)
        : (size.height * 0.49).clamp(328.0, 420.0);
    final canvasColor = skin.canvas;
    final fullBleedStripMaxW = (size.width - padX * 2 - 420).clamp(180.0, 620.0);

    return wrapHeroInteraction(
      SizedBox(
        key: const ValueKey('hero-full-bleed'),
        height: heroH,
        child: Stack(
          fit: StackFit.expand,
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is ScrollStartNotification && n.dragDetails != null) {
                  _userDragging = true;
                  _autoTimer?.cancel();
                } else if (n is ScrollEndNotification && _userDragging) {
                  _userDragging = false;
                  _armTimer();
                }
                return false;
              },
              child: PageView.builder(
                key: const ValueKey('hero-page-view'),
                controller: _pageCtrl,
                itemCount: widget.featured.length,
                physics: const BouncingScrollPhysics(),
                onPageChanged: _onPageChanged,
                itemBuilder: (ctx, idx) {
                  final slide = widget.featured[idx];
                  final slideLogo = widget.appState.logoArtUrl(slide.item);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onDetail(slide.item),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Direct zero-saveLayer gradient dissolve into `skin.canvas` (no offscreen ShaderMask!)
                        RepaintBoundary(
                          child: ClipRect(
                            key: ValueKey('hero-alpha-mask-$idx'),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Positioned.fill(
                                  child: VedroArtwork(
                                    item: slide.item,
                                    appState: widget.appState,
                                    isHero: true,
                                    alignment: const Alignment(0, -0.46),
                                    showInitials: false,
                                  ),
                                ),
                                if (wide)
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                        stops: const [0.0, 0.48, 0.82, 1.0],
                                        colors: skin.isLight
                                            ? [
                                                canvasColor.withValues(alpha: 0.88),
                                                canvasColor.withValues(alpha: 0.52),
                                                canvasColor.withValues(alpha: 0.12),
                                                Colors.transparent,
                                              ]
                                            : [
                                                canvasColor.withValues(alpha: 0.84),
                                                canvasColor.withValues(alpha: 0.44),
                                                canvasColor.withValues(alpha: 0.08),
                                                Colors.transparent,
                                              ],
                                      ),
                                    ),
                                  ),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      stops: (!wide && skin.isLight)
                                          ? const [0.0, 0.22, 0.48, 0.78, 1.0]
                                          : const [0.0, 0.28, 0.62, 0.90, 1.0],
                                      colors: skin.isLight
                                          ? [
                                              canvasColor.withValues(alpha: 0.36),
                                              Colors.transparent,
                                              canvasColor.withValues(alpha: wide ? 0.46 : 0.72),
                                              canvasColor.withValues(alpha: 0.96),
                                              canvasColor,
                                            ]
                                          : [
                                              canvasColor.withValues(alpha: 0.36),
                                              Colors.transparent,
                                              canvasColor.withValues(alpha: 0.42),
                                              canvasColor.withValues(alpha: 0.94),
                                              canvasColor,
                                            ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: padX,
                          right: wide ? size.width * 0.36 : padX,
                          bottom: wide ? 44 : 28,
                          child: _buildHeroInfoColumn(
                            context: context,
                            skin: skin,
                            item: slide.item,
                            eyebrow: slide.eyebrow,
                            logoUrl: slideLogo,
                            wide: wide,
                            onPhoto: !skin.isLight,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            if (widget.showMobileHeader)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildMobileTopBar(),
              ),

            if (wide && widget.featured.length > 1) ...[
              Positioned(
                left: 14,
                top: 0,
                bottom: 0,
                child: Center(
                  child: ExcludeFocus(
                    excluding: !_hovered,
                    child: IgnorePointer(
                      ignoring: !_hovered,
                      child: AnimatedOpacity(
                        opacity: _hovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 180),
                        child: PressableScale(
                          onTap: () => _select(
                              (_active - 1 + widget.featured.length) % widget.featured.length),
                          child: GlassSurface(
                            borderRadius: 20,
                            blur: 18,
                            color: skin.isLight ? const Color(0xCCFFFFFF) : const Color(0x66141418),
                            borderColor: skin.isLight ? skin.border : Colors.transparent,
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.chevron_left_rounded,
                              size: 22,
                              color: skin.isLight ? skin.fg : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 14,
                top: 0,
                bottom: 0,
                child: Center(
                  child: ExcludeFocus(
                    excluding: !_hovered,
                    child: IgnorePointer(
                      ignoring: !_hovered,
                      child: AnimatedOpacity(
                        opacity: _hovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 180),
                        child: PressableScale(
                          onTap: () => _select((_active + 1) % widget.featured.length),
                          child: GlassSurface(
                            borderRadius: 20,
                            blur: 18,
                            color: skin.isLight ? const Color(0xCCFFFFFF) : const Color(0x66141418),
                            borderColor: skin.isLight ? skin.border : Colors.transparent,
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              size: 22,
                              color: skin.isLight ? skin.fg : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],

            if (widget.featured.length > 1)
              Positioned(
                right: padX,
                left: wide ? null : padX,
                bottom: wide ? 40 : 10,
                child: wide
                    ? _buildBorderlessPreviewStrip(
                        skin,
                        onLightSurface: skin.isLight,
                        maxWidth: fullBleedStripMaxW,
                      )
                    : _buildCapsuleDots(skin: skin, onLightSurface: skin.isLight),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeroTitleText extends StatelessWidget {
  const _HeroTitleText({
    required this.text,
    required this.wide,
    this.color = Colors.white,
  });
  final String text;
  final bool wide;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: skin.applyHeadlineMood(
        TextStyle(
          color: color,
          fontSize: wide ? 42 : 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          height: 1.08,
        ),
      ),
    );
  }
}
