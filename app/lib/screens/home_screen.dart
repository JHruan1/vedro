import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/horizontal_rail.dart';
import '../widgets/media_card.dart';
import '../widgets/vedro_artwork.dart';
import '../widgets/vedro_ui.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.appState,
    required this.onItemTap,
    required this.onQuickPlay,
    required this.onLibraryTap,
    this.onScrollChanged,
  });

  final VedroAppState appState;
  final void Function(MediaItemModel, {String? heroPrefix}) onItemTap;
  final void Function(MediaItemModel) onQuickPlay;
  final void Function(MediaItemModel) onLibraryTap;
  final ValueChanged<bool>? onScrollChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scrollCtrl = ScrollController();
  double _scrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    final offset = _scrollCtrl.offset;
    widget.onScrollChanged?.call(offset > 24);
    if ((offset - _scrollOffset).abs() >= 1.5 && offset < 720) {
      setState(() => _scrollOffset = offset);
    }
  }

  List<({MediaItemModel item, String eyebrow})> _pickFeatured() {
    final app = widget.appState;
    final pool = <({MediaItemModel item, String eyebrow})>[];
    if (app.popular.isNotEmpty) {
      for (final i in app.popular) {
        pool.add((item: i, eyebrow: i.type == 'Series' ? '热门剧集' : '热门电影'));
      }
    } else {
      for (final i in app.resume) {
        pool.add((item: i, eyebrow: '继续观看'));
      }
      for (final i in app.nextUp) {
        pool.add((item: i, eyebrow: '接下来播放'));
      }
      for (final entry in app.latestByLibrary) {
        final lib = MediaItemModel.fromJson(entry['library'] as Map<String, dynamic>);
        final items = ((entry['items'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MediaItemModel.fromJson);
        for (final i in items) {
          pool.add((item: i, eyebrow: '最新加入 · ${lib.name}'));
        }
      }
    }

    final seen = <String>{};
    final unique = <({MediaItemModel item, String eyebrow})>[];
    for (final entry in pool) {
      final key = entry.item.seriesId ?? entry.item.id;
      if (seen.add(key)) unique.add(entry);
    }
    // Prefer real widescreen backdrops over poster-only items
    final wideOnes = unique.where((e) => app.backdropArt(e.item)?.isPoster == false).toList();
    final rest = unique.where((e) => app.backdropArt(e.item)?.isPoster != false).toList();
    return [...wideOnes, ...rest].take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.appState;
    final wide = MediaQuery.sizeOf(context).width >= 820;

    // Immediate gorgeous animated shimmer while Home fetches in parallel!
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
              const Icon(Icons.cloud_off_rounded, size: 36, color: VedroTheme.fg3),
              const SizedBox(height: 14),
              Text(
                app.homeError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: VedroTheme.fg2, fontSize: 14),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: app.refreshHome,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final featured = _pickFeatured();
    final caps = app.capabilities;
    final resumeIds = app.resume.map((e) => e.id).toSet();
    final nextItems = app.nextUp.where((e) => !resumeIds.contains(e.id)).toList();

    // Map library ID -> latest items so LibraryCard gets a lush widescreen backdrop!
    final latestMap = <String, List<MediaItemModel>>{};
    for (final entry in app.latestByLibrary) {
      final lib = MediaItemModel.fromJson(entry['library'] as Map<String, dynamic>);
      final items = ((entry['items'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MediaItemModel.fromJson)
          .toList();
      latestMap[lib.id] = items;
    }

    final libCardW = wide ? 340.0 : 284.0;
    final libRailH = (libCardW / (16 / 9)) + 16;

    return RefreshIndicator(
      color: VedroTheme.fg,
      backgroundColor: VedroTheme.surface2,
      onRefresh: app.refreshHome,
      child: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          if (featured.isNotEmpty)
            SliverToBoxAdapter(
              child: _CinemaHeroBanner(
                featured: featured,
                appState: app,
                scrollOffset: _scrollOffset,
                showMobileHeader: !wide,
                onPlay: widget.onQuickPlay,
                onDetail: (item) => widget.onItemTap(item, heroPrefix: 'hero'),
                onRefresh: app.refreshHome,
              ),
            )
          else
            SliverToBoxAdapter(child: SizedBox(height: wide ? 78 : 24)),

          if (app.remoteBannerMessage != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(wide ? 32 : 20, 16, wide ? 32 : 20, 0),
                child: GlassSurface(
                  borderRadius: 12,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.cast_connected_rounded, size: 16, color: VedroTheme.fg2),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          app.remoteBannerMessage!,
                          style: const TextStyle(color: VedroTheme.fg, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Continue Watching (dedicated 16:9 ResumeCard with "继续" & remaining time)
          SliverToBoxAdapter(
            child: HorizontalMediaRail(
              title: '继续观看',
              items: app.resume,
              appState: app,
              isResume: true,
              onItemTap: (item) => widget.onItemTap(item),
              onItemQuickPlay: widget.onQuickPlay,
              onItemLongPress: caps?.supportsHideFromResume == true
                  ? (item) => _confirmHideFromResume(context, item)
                  : null,
            ),
          ),

          // Next Up episodes
          SliverToBoxAdapter(
            child: HorizontalMediaRail(
              title: '接下来播放',
              items: nextItems,
              appState: app,
              landscape: true,
              onItemTap: (item) => widget.onItemTap(item),
              onItemQuickPlay: widget.onQuickPlay,
            ),
          ),

          // Suggestions
          SliverToBoxAdapter(
            child: HorizontalMediaRail(
              title: '猜你喜欢',
              items: app.suggestions,
              appState: app,
              heroPrefix: 'sug',
              onItemTap: (item) => widget.onItemTap(item, heroPrefix: 'sug'),
              onItemQuickPlay: widget.onQuickPlay,
            ),
          ),

          // Cinematic 16:9 Media Library Tiles (just like Forward / embygo Web!)
          if (app.views.isNotEmpty)
            SliverToBoxAdapter(
              child: CustomHorizontalRail(
                title: '媒体库',
                height: libRailH,
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

          // Favorites rail
          SliverToBoxAdapter(
            child: HorizontalMediaRail(
              title: '我的收藏',
              items: app.favorites,
              appState: app,
              heroPrefix: 'fav',
              onItemTap: (item) => widget.onItemTap(item, heroPrefix: 'fav'),
              onItemQuickPlay: widget.onQuickPlay,
            ),
          ),

          // Recently Added per Library
          ...app.latestByLibrary.map((entry) {
            final lib = MediaItemModel.fromJson(entry['library'] as Map<String, dynamic>);
            final items = ((entry['items'] as List<dynamic>?) ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(MediaItemModel.fromJson)
                .toList();
            return SliverToBoxAdapter(
              child: HorizontalMediaRail(
                title: '最新加入 · ${lib.name}',
                items: items,
                appState: app,
                heroPrefix: 'lat-${lib.id}',
                onItemTap: (item) => widget.onItemTap(item, heroPrefix: 'lat-${lib.id}'),
                onItemQuickPlay: widget.onQuickPlay,
                onSeeAll: () => widget.onLibraryTap(lib),
              ),
            );
          }),

          SliverToBoxAdapter(child: SizedBox(height: wide ? 56 : 112)),
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
              item.cardTitle,
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

/// Apple TV+ / Forward / SenPlayer full-bleed cinema hero with auto-rotating crossfade,
/// subtle scroll parallax, real transparent Title Logo, and desktop 16:9 thumbnail switcher.
class _CinemaHeroBanner extends StatefulWidget {
  const _CinemaHeroBanner({
    required this.featured,
    required this.appState,
    required this.scrollOffset,
    required this.showMobileHeader,
    required this.onPlay,
    required this.onDetail,
    required this.onRefresh,
  });

  final List<({MediaItemModel item, String eyebrow})> featured;
  final VedroAppState appState;
  final double scrollOffset;
  final bool showMobileHeader;
  final void Function(MediaItemModel) onPlay;
  final void Function(MediaItemModel) onDetail;
  final VoidCallback onRefresh;

  @override
  State<_CinemaHeroBanner> createState() => _CinemaHeroBannerState();
}

class _CinemaHeroBannerState extends State<_CinemaHeroBanner> {
  int _active = 0;
  bool _paused = false;
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    _armTimer();
  }

  @override
  void didUpdateWidget(covariant _CinemaHeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_active >= widget.featured.length) {
      _active = 0;
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  void _armTimer() {
    _autoTimer?.cancel();
    if (widget.featured.length < 2 || _paused) return;
    _autoTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      setState(() => _active = (_active + 1) % widget.featured.length);
      _armTimer();
    });
  }

  void _select(int index) {
    setState(() => _active = index);
    _armTimer();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 820;
    final heroH = (size.height * (wide ? 0.72 : 0.60)).clamp(430.0, 740.0);
    final padX = wide ? 32.0 : 20.0;
    final current = widget.featured[_active];
    final item = current.item;
    final logoUrl = widget.appState.logoArtUrl(item);
    final serverName = widget.appState.capabilities?.serverName.isNotEmpty == true
        ? widget.appState.capabilities!.serverName
        : 'Vedro';

    final facts = <String>[
      if (item.type == 'Episode') item.cardSubtitle,
      if (item.productionYear != null) '${item.productionYear}',
      if (item.communityRating != null) '★ ${item.communityRating!.toStringAsFixed(1)}',
      ...item.genres.take(3),
    ];

    return MouseRegion(
      onEnter: (_) {
        _paused = true;
        _autoTimer?.cancel();
      },
      onExit: (_) {
        _paused = false;
        _armTimer();
      },
      child: SizedBox(
        height: heroH,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Crossfading full-bleed artwork with subtle vertical parallax
            ClipRect(
              child: Transform.translate(
                offset: Offset(0, widget.scrollOffset * 0.28),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    for (var i = 0; i < widget.featured.length; i++)
                      AnimatedOpacity(
                        opacity: i == _active ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 520),
                        curve: Curves.easeOutCubic,
                        child: VedroArtwork(
                          item: widget.featured[i].item,
                          appState: widget.appState,
                          isHero: true,
                          alignment: const Alignment(0, -0.55),
                          showInitials: false,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Left cinema wash for title legibility on wide screens
            if (wide)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    stops: [0.0, 0.52, 1.0],
                    colors: [Color(0xC80B0B0D), Color(0x520B0B0D), Colors.transparent],
                  ),
                ),
              ),

            // Bottom gradient fading seamlessly into obsidian canvas
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.25, 0.70, 1.0],
                  colors: [
                    Color(0x660B0B0D),
                    Colors.transparent,
                    Color(0xB30B0B0D),
                    VedroTheme.canvas,
                  ],
                ),
              ),
            ),

            // Mobile floating header
            if (widget.showMobileHeader)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 16, 8),
                    child: Row(
                      children: [
                        const VedroBrandMark(size: 26),
                        const SizedBox(width: 9),
                        Text(
                          serverName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const Spacer(),
                        PressableScale(
                          onTap: widget.onRefresh,
                          child: GlassSurface(
                            borderRadius: 18,
                            blur: 18,
                            color: const Color(0x52141417),
                            padding: const EdgeInsets.all(8),
                            child: const Icon(Icons.refresh_rounded, size: 17, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Bottom-left title block with smooth cross-slide transition
            Positioned(
              left: padX,
              right: wide ? size.width * 0.36 : padX,
              bottom: wide ? 44 : 42,
              child: AnimatedSwitcher(
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
                      current.eyebrow,
                      style: const TextStyle(
                        color: Color(0xC0FFFFFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (logoUrl != null)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: wide ? 104 : 74,
                          maxWidth: wide ? 420 : 280,
                        ),
                        child: Image.network(
                          logoUrl,
                          fit: BoxFit.contain,
                          alignment: Alignment.centerLeft,
                          errorBuilder: (_, __, ___) => _HeroTitleText(
                            text: item.cardTitle,
                            wide: wide,
                          ),
                        ),
                      )
                    else
                      _HeroTitleText(text: item.cardTitle, wide: wide),
                    if (facts.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        facts.join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xD4FFFFFF),
                          fontSize: 13.5,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                    if (item.overview != null && item.overview!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Text(
                          item.overview!,
                          maxLines: wide ? 3 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xBDFFFFFF),
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        PressableScale(
                          onTap: () => widget.onPlay(item),
                          hoverScale: 1.03,
                          pressScale: 0.96,
                          child: Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x45000000),
                                  blurRadius: 16,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.play_arrow_rounded, size: 22, color: VedroTheme.canvas),
                                SizedBox(width: 4),
                                Text(
                                  '播放',
                                  style: TextStyle(
                                    color: VedroTheme.canvas,
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
                          child: GlassSurface(
                            borderRadius: 12,
                            blur: 22,
                            color: const Color(0x5222232A),
                            borderColor: const Color(0x36FFFFFF),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.info_outline_rounded, size: 17, color: Colors.white),
                                SizedBox(width: 6),
                                Text(
                                  '详情',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Desktop 16:9 interactive thumbnail strip / Mobile expanding dots
            if (widget.featured.length > 1)
              Positioned(
                right: padX,
                left: wide ? null : padX,
                bottom: wide ? 46 : 16,
                child: wide
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(widget.featured.length, (i) {
                          final active = i == _active;
                          final entry = widget.featured[i];
                          return Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: PressableScale(
                              onTap: () => _select(i),
                              hoverScale: 1.05,
                              pressScale: 0.95,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: VedroTheme.easeOut,
                                width: 96,
                                height: 54,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: active ? Colors.white : const Color(0x30FFFFFF),
                                    width: active ? 2 : 0.8,
                                  ),
                                  boxShadow: active
                                      ? const [
                                          BoxShadow(
                                            color: Color(0x88000000),
                                            blurRadius: 14,
                                            offset: Offset(0, 6),
                                          ),
                                        ]
                                      : null,
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: AnimatedOpacity(
                                  opacity: active ? 1.0 : 0.52,
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
                          );
                        }),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(widget.featured.length, (i) {
                          final active = i == _active;
                          return GestureDetector(
                            onTap: () => _select(i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              curve: VedroTheme.easeOut,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: active ? 20 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: active ? Colors.white : const Color(0x60FFFFFF),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          );
                        }),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeroTitleText extends StatelessWidget {
  const _HeroTitleText({required this.text, required this.wide});
  final String text;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white,
        fontSize: wide ? 42 : 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.9,
        height: 1.08,
      ),
    );
  }
}
