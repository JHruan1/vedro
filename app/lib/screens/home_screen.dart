import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/horizontal_rail.dart';
import '../widgets/vedro_ui.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.appState,
    required this.onItemTap,
    required this.onLibraryTap,
  });

  final VedroAppState appState;
  final void Function(MediaItemModel) onItemTap;
  final void Function(MediaItemModel) onLibraryTap;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _heroCtrl = PageController();
  int _heroPage = 0;

  @override
  void dispose() {
    _heroCtrl.dispose();
    super.dispose();
  }

  void _quickPlay(MediaItemModel item) {
    if (item.isPlayable) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(item: item, appState: widget.appState),
        ),
      );
    } else {
      widget.onItemTap(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    final heroItems = (appState.popular.isNotEmpty
            ? appState.popular
            : (appState.latestByLibrary.isNotEmpty
                ? ((appState.latestByLibrary.first['items'] as List<dynamic>? ?? const [])
                    .whereType<Map<String, dynamic>>()
                    .map(MediaItemModel.fromJson)
                    .toList())
                : const <MediaItemModel>[]))
        .take(5)
        .toList();

    final caps = appState.capabilities;
    final serverTitle = caps?.serverName.isNotEmpty == true ? caps!.serverName : 'Vedro';
    final wide = MediaQuery.sizeOf(context).width >= 820;

    return RefreshIndicator(
      color: VedroTheme.fg,
      backgroundColor: VedroTheme.surface2,
      onRefresh: appState.refreshHome,
      child: CustomScrollView(
        slivers: [
          if (heroItems.isNotEmpty)
            SliverToBoxAdapter(
              child: _CinemaHeroCarousel(
                items: heroItems,
                serverTitle: serverTitle,
                appState: appState,
                controller: _heroCtrl,
                currentPage: _heroPage,
                onPageChanged: (i) => setState(() => _heroPage = i),
                onPlay: _quickPlay,
                onDetail: widget.onItemTap,
                onRefresh: appState.refreshHome,
              ),
            )
          else
            SliverAppBar(
              floating: true,
              title: Text(serverTitle),
              actions: [
                IconButton(
                  tooltip: '刷新',
                  icon: const Icon(Icons.refresh_rounded, size: 20, color: VedroTheme.fg2),
                  onPressed: appState.refreshHome,
                ),
              ],
            ),

          if (appState.remoteBannerMessage != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                child: GlassSurface(
                  borderRadius: 12,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.cast_connected_rounded, size: 16, color: VedroTheme.fg2),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          appState.remoteBannerMessage!,
                          style: const TextStyle(color: VedroTheme.fg, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (appState.views.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: appState.views.map((lib) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: PressableScale(
                          onTap: () => widget.onLibraryTap(lib),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: VedroTheme.surface2,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: VedroTheme.line, width: 0.7),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  lib.collectionType == 'tvshows'
                                      ? Icons.tv_rounded
                                      : Icons.movie_outlined,
                                  size: 15,
                                  color: VedroTheme.fg2,
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  lib.name,
                                  style: const TextStyle(
                                    color: VedroTheme.fg,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),

          SliverToBoxAdapter(
            child: HorizontalMediaRail(
              title: '继续观看',
              items: appState.resume,
              appState: appState,
              landscape: true,
              onItemTap: widget.onItemTap,
              onItemLongPress: caps?.supportsHideFromResume == true
                  ? (item) => _confirmHideFromResume(context, item)
                  : null,
            ),
          ),

          SliverToBoxAdapter(
            child: HorizontalMediaRail(
              title: '下一集',
              items: appState.nextUp,
              appState: appState,
              landscape: true,
              onItemTap: widget.onItemTap,
            ),
          ),

          if (appState.popular.length > 1)
            SliverToBoxAdapter(
              child: HorizontalMediaRail(
                title: '热门',
                items: appState.popular,
                appState: appState,
                onItemTap: widget.onItemTap,
              ),
            ),

          SliverToBoxAdapter(
            child: HorizontalMediaRail(
              title: '为你推荐',
              items: appState.suggestions,
              appState: appState,
              onItemTap: widget.onItemTap,
            ),
          ),

          ...appState.latestByLibrary.map((entry) {
            final lib = MediaItemModel.fromJson(entry['library'] as Map<String, dynamic>);
            final items = ((entry['items'] as List<dynamic>?) ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(MediaItemModel.fromJson)
                .toList();
            return SliverToBoxAdapter(
              child: HorizontalMediaRail(
                title: '最近添加 · ${lib.name}',
                items: items,
                appState: appState,
                onItemTap: widget.onItemTap,
                onSeeAll: () => widget.onLibraryTap(lib),
              ),
            );
          }),

          SliverToBoxAdapter(child: SizedBox(height: wide ? 44 : 104)),
        ],
      ),
    );
  }

  void _confirmHideFromResume(BuildContext context, MediaItemModel item) {
    showGlassSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              item.name,
              style: const TextStyle(
                color: VedroTheme.fg,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '从「继续观看」移除，保留已同步的播放进度。',
              style: TextStyle(color: VedroTheme.fg3, fontSize: 13),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 44,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: VedroTheme.surface3,
                  foregroundColor: VedroTheme.fg,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  widget.appState.hideFromResume(item.id);
                },
                child: const Text('从继续观看移除'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CinemaHeroCarousel extends StatelessWidget {
  const _CinemaHeroCarousel({
    required this.items,
    required this.serverTitle,
    required this.appState,
    required this.controller,
    required this.currentPage,
    required this.onPageChanged,
    required this.onPlay,
    required this.onDetail,
    required this.onRefresh,
  });

  final List<MediaItemModel> items;
  final String serverTitle;
  final VedroAppState appState;
  final PageController controller;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final void Function(MediaItemModel) onPlay;
  final void Function(MediaItemModel) onDetail;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.sizeOf(context).height;
    final heroHeight = (screenH * 0.56).clamp(340.0, 500.0);

    return SizedBox(
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: controller,
            onPageChanged: onPageChanged,
            itemCount: items.length,
            itemBuilder: (_, idx) {
              final item = items[idx];
              final bgUrl = item.backdropImageTag != null
                  ? appState.buildImageUrl(
                      item.id,
                      type: 'Backdrop',
                      tag: item.backdropImageTag,
                      maxWidth: 1920,
                    )
                  : (item.primaryImageTag != null
                      ? appState.buildImageUrl(
                          item.id,
                          type: 'Primary',
                          tag: item.primaryImageTag,
                          maxWidth: 1200,
                        )
                      : '');

              final meta = [
                if (item.productionYear != null) '${item.productionYear}',
                if (item.communityRating != null) item.communityRating!.toStringAsFixed(1),
                if (item.genres.isNotEmpty) item.genres.take(2).join(' / '),
              ].join('  ·  ');

              return Stack(
                fit: StackFit.expand,
                children: [
                  if (bgUrl.isNotEmpty)
                    Image.network(
                      bgUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: VedroTheme.surface),
                    )
                  else
                    Container(color: VedroTheme.surface),
                  // Top & bottom cinema vignette blending seamlessly into obsidian canvas
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.0, 0.28, 0.72, 1.0],
                        colors: [
                          Color(0x990B0B0D),
                          Color(0x180B0B0D),
                          Color(0xB80B0B0D),
                          VedroTheme.canvas,
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 24,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: VedroTheme.fg,
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.7,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (meta.isNotEmpty)
                                Text(
                                  meta,
                                  style: const TextStyle(color: VedroTheme.fg2, fontSize: 13),
                                ),
                              SpecGlyphRow(specs: item.inferredBadges.take(3).toList()),
                            ],
                          ),
                          if (item.overview != null && item.overview!.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              item.overview!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: VedroTheme.fg2,
                                fontSize: 13.5,
                                height: 1.45,
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              PressableScale(
                                onTap: () => onPlay(item),
                                child: Container(
                                  height: 40,
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                  decoration: BoxDecoration(
                                    color: VedroTheme.fg,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.play_arrow_rounded, size: 20, color: VedroTheme.canvas),
                                      SizedBox(width: 4),
                                      Text(
                                        '播放',
                                        style: TextStyle(
                                          color: VedroTheme.canvas,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              PressableScale(
                                onTap: () => onDetail(item),
                                child: GlassSurface(
                                  borderRadius: 10,
                                  blur: 20,
                                  color: const Color(0x55222228),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  child: const Text(
                                    '详情',
                                    style: TextStyle(
                                      color: VedroTheme.fg,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          // Quiet floating header bar over the hero
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 16, 8),
                child: Row(
                  children: [
                    Text(
                      serverTitle,
                      style: const TextStyle(
                        color: VedroTheme.fg,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const Spacer(),
                    PressableScale(
                      onTap: onRefresh,
                      child: GlassSurface(
                        borderRadius: 20,
                        blur: 18,
                        color: const Color(0x4D141417),
                        padding: const EdgeInsets.all(8),
                        child: const Icon(Icons.refresh_rounded, size: 18, color: VedroTheme.fg),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Minimal carousel dots
          if (items.length > 1)
            Positioned(
              right: 24,
              bottom: 30,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(items.length, (i) {
                  final active = i == currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.only(left: 5),
                    width: active ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active ? VedroTheme.fg : const Color(0x52FFFFFF),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}
