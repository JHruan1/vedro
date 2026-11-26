import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/home_layout_sheet.dart';
import '../widgets/horizontal_rail.dart';
import '../widgets/media_card.dart';
import '../widgets/server_card_grid.dart';
import '../widgets/vedro_artwork.dart';
import '../widgets/vedro_ui.dart';

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
  final VoidCallback onOpenServerHub;
  final void Function([String? initialUrl]) onOpenAddServer;
  final VoidCallback onOpenSettings;
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
    for (final entry in app.latestByLibrary) {
      final lib = MediaItemModel.fromJson(entry['library'] as Map<String, dynamic>);
      final items = ((entry['items'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MediaItemModel.fromJson);
      for (final i in items) {
        pool.add((item: i, eyebrow: '最新加入 · ${lib.name}'));
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

    final showHero = app.showHomeHero && skin.heroStyle != 'compact_minimal';
    final featured = showHero
        ? _pickFeatured()
        : const <({MediaItemModel item, String eyebrow})>[];
    final caps = app.capabilities;
    final resumeIds = app.resume.map((e) => e.id).toSet();
    final nextItems = app.nextUp.where((e) => !resumeIds.contains(e.id)).toList();

    final latestMap = <String, List<MediaItemModel>>{};
    for (final entry in app.latestByLibrary) {
      final lib = MediaItemModel.fromJson(entry['library'] as Map<String, dynamic>);
      final items = ((entry['items'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MediaItemModel.fromJson)
          .toList();
      latestMap[lib.id] = items;
    }

    final libCardW = wide ? 276.0 : 228.0;
    final libRailH = (libCardW / (16 / 9)) + 48;

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
                  onItemLongPress: caps?.supportsHideFromResume == true
                      ? (item) => _confirmHideFromResume(context, item)
                      : null,
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
                ),
              ),
            );
          }
          break;
        case 'latest':
          for (final entry in app.latestByLibrary) {
            final lib = MediaItemModel.fromJson(entry['library'] as Map<String, dynamic>);
            final items = ((entry['items'] as List<dynamic>?) ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(MediaItemModel.fromJson)
                .toList();
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
        slivers: [
          if (featured.isNotEmpty)
            SliverToBoxAdapter(
              child: _CinemaHeroBanner(
                featured: featured,
                appState: app,
                scrollOffset: _scrollOffset,
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
                height: wide ? widget.topNavClearance : MediaQuery.paddingOf(context).top + 16,
              ),
            ),

          if (app.remoteBannerMessage != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(wide ? 32 : 20, 16, wide ? 32 : 20, 0),
                child: GlassSurface(
                  borderRadius: 12,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                    ],
                  ),
                ),
              ),
            ),

          ...dynamicSectionSlivers,

          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(wide ? 32 : 20, 32, wide ? 32 : 20, wide ? 48 : 112),
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

  void _confirmHideFromResume(BuildContext context, MediaItemModel item) {
    final skin = VedroSkin.of(context);
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
              style: TextStyle(
                color: skin.fg,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '从「继续观看」移除，保留已同步的播放进度。',
              style: TextStyle(color: skin.fg3, fontSize: 13),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 44,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: skin.surface3,
                  foregroundColor: skin.fg,
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

/// SenPlayer / Forward Home Server Hub shown on startup when no server is active yet.
class _ServerWelcomeHub extends StatelessWidget {
  const _ServerWelcomeHub({
    required this.appState,
    required this.wide,
    required this.onOpenAddServer,
    this.onOpenLocalMedia,
    required this.onOpenServerHub,
    required this.onOpenSettings,
  });

  final VedroAppState appState;
  final bool wide;
  final void Function([String? initialUrl]) onOpenAddServer;
  final VoidCallback? onOpenLocalMedia;
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
    required this.scrollOffset,
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
  final double scrollOffset;
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
  int _active = 0;
  bool _paused = false;
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
    super.dispose();
  }

  void _armTimer() {
    _autoTimer?.cancel();
    if (widget.featured.length < 2 || _paused) return;
    _autoTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      setState(() => _active = (_active + 1) % widget.featured.length);
      _syncDynamicHeroColor();
      _armTimer();
    });
  }

  void _select(int index) {
    setState(() => _active = index);
    _syncDynamicHeroColor();
    _armTimer();
  }

  /// Borderless floating preview thumbnails (ZERO white border boxes!) + sleek active indicator bar.
  Widget _buildBorderlessPreviewStrip(VedroSkin skin, {bool onLightSurface = false}) {
    final barActiveColor = skin.ctaStyle == 'contrast'
        ? (onLightSurface ? skin.fg : Colors.white)
        : skin.accent;
    return Row(
      key: const ValueKey('hero-preview-strip'),
      mainAxisSize: MainAxisSize.min,
      children: List.generate(widget.featured.length, (i) {
        final active = i == _active;
        final entry = widget.featured[i];
        return Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
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
                    width: 92,
                    height: 52,
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
                  width: active ? 28 : 8,
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
        return GestureDetector(
          onTap: () => _select(i),
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
          if (logoUrl != null && skin.preferClearLogo)
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
                  GestureDetector(
                    onTap: widget.onGenreTap == null ? null : () => widget.onGenreTap!(g),
                    child: MouseRegion(
                      cursor: widget.onGenreTap != null
                          ? SystemMouseCursors.click
                          : MouseCursor.defer,
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
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Text(
                item.cleanOverview,
                maxLines: wide ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 14,
                  height: 1.55,
                ),
              ),
            ),
          ],
          const SizedBox(height: 22),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PressableScale(
                onTap: () => widget.onPlay(item),
                hoverScale: 1.03,
                pressScale: 0.96,
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 26),
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
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                        child: const Text(
                          '详情',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 22),
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
                            fontSize: 14.5,
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
    final padX = wide ? 32.0 : 20.0;
    final current = widget.featured[_active];
    final item = current.item;
    final logoUrl = widget.appState.logoArtUrl(item);

    // -------------------------------------------------------------------------
    // Layout Mode B: Criterion / Kinfolk 2-Column Editorial Split Showcase
    // -------------------------------------------------------------------------
    if (wide && skin.heroStyle == 'split_showcase') {
      final cardR = skin.cardRadius.clamp(8.0, 24.0);
      return MouseRegion(
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
        child: Padding(
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
                  child: Column(
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
                        _buildBorderlessPreviewStrip(skin, onLightSurface: skin.isLight),
                      ],
                    ],
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
      final stageH = (size.height * (wide ? 0.58 : 0.48)).clamp(360.0, 580.0);
      return MouseRegion(
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showMobileHeader) _buildMobileTopBar(),
            Padding(
              key: const ValueKey('hero-framed-stage'),
              padding: EdgeInsets.fromLTRB(
                padX,
                wide ? widget.topNavClearance + 8 : 6,
                padX,
                8,
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
                    for (var i = 0; i < widget.featured.length; i++)
                      AnimatedOpacity(
                        opacity: i == _active ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 520),
                        curve: Curves.easeOutCubic,
                        child: VedroArtwork(
                          item: widget.featured[i].item,
                          appState: widget.appState,
                          isHero: true,
                          alignment: const Alignment(0, -0.45),
                          showInitials: false,
                        ),
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
                      left: wide ? 34 : 20,
                      right: wide ? size.width * 0.34 : 20,
                      bottom: wide ? 32 : 34,
                      child: _buildHeroInfoColumn(
                        context: context,
                        skin: skin,
                        item: item,
                        eyebrow: current.eyebrow,
                        logoUrl: logoUrl,
                        wide: wide,
                        onPhoto: !skin.isLight,
                      ),
                    ),
                    if (widget.featured.length > 1)
                      Positioned(
                        right: wide ? 28 : 20,
                        left: wide ? null : 20,
                        bottom: wide ? 26 : 12,
                        child: wide
                            ? _buildBorderlessPreviewStrip(skin, onLightSurface: skin.isLight)
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
    // - Overscanned parallax (`top: -96, bottom: -48`) so scrolling NEVER exposes top edge!
    // - Subpixel bottom canvas seal (`stop: 0.95 -> 1.0` + `bottom: -2` seal) so ZERO 1px line leaks!
    // - Pure borderless floating preview thumbnails (ZERO white frames!)
    // -------------------------------------------------------------------------
    final heroH = (size.height * (wide ? 0.72 : 0.60)).clamp(430.0, 740.0);
    final canvasColor = skin.canvas;
    final parallaxDy = (widget.scrollOffset * 0.22).clamp(-40.0, 84.0);

    return MouseRegion(
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
      child: SizedBox(
        key: const ValueKey('hero-full-bleed'),
        height: heroH,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    top: -96,
                    left: 0,
                    right: 0,
                    bottom: -48,
                    child: Transform.translate(
                      offset: Offset(0, parallaxDy),
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
                                alignment: const Alignment(0, -0.50),
                                showInitials: false,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
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
                            canvasColor.withValues(alpha: 0.92),
                            canvasColor.withValues(alpha: 0.62),
                            canvasColor.withValues(alpha: 0.14),
                            Colors.transparent,
                          ]
                        : const [
                            Color(0xDC0B0B0D),
                            Color(0x780B0B0D),
                            Color(0x140B0B0D),
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
                  stops: const [0.0, 0.24, 0.56, 0.84, 0.95, 1.0],
                  colors: skin.isLight
                      ? [
                          canvasColor.withValues(alpha: 0.42),
                          Colors.transparent,
                          canvasColor.withValues(alpha: 0.46),
                          canvasColor.withValues(alpha: 0.88),
                          canvasColor,
                          canvasColor,
                        ]
                      : [
                          const Color(0x660B0B0D),
                          Colors.transparent,
                          const Color(0x5E0B0B0D),
                          Color.lerp(const Color(0xD80B0B0D), canvasColor, 0.55)!,
                          canvasColor,
                          canvasColor,
                        ],
                ),
              ),
            ),

            // Subpixel anti-bleed bottom seal eliminating 1px rasterization seam on scroll!
            if (skin.backdropMode == 'solid')
              Positioned(
                left: 0,
                right: 0,
                bottom: -2,
                height: 5,
                child: ColoredBox(color: canvasColor),
              ),

            if (widget.showMobileHeader)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildMobileTopBar(),
              ),

            Positioned(
              left: padX,
              right: wide ? size.width * 0.36 : padX,
              bottom: wide ? 44 : 42,
              child: _buildHeroInfoColumn(
                context: context,
                skin: skin,
                item: item,
                eyebrow: current.eyebrow,
                logoUrl: logoUrl,
                wide: wide,
                onPhoto: !skin.isLight,
              ),
            ),

            if (wide && widget.featured.length > 1) ...[
              Positioned(
                left: 14,
                top: 0,
                bottom: 0,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _hovered ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: PressableScale(
                      onTap: () =>
                          _select((_active - 1 + widget.featured.length) % widget.featured.length),
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
              Positioned(
                right: 14,
                top: 0,
                bottom: 0,
                child: Center(
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
            ],

            if (widget.featured.length > 1)
              Positioned(
                right: padX,
                left: wide ? null : padX,
                bottom: wide ? 40 : 16,
                child: wide
                    ? _buildBorderlessPreviewStrip(skin, onLightSurface: skin.isLight)
                    : _buildCapsuleDots(skin: skin),
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
          fontSize: wide ? 42 : 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.9,
          height: 1.08,
        ),
      ),
    );
  }
}
