import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/horizontal_rail.dart';
import '../widgets/media_card.dart';
import '../widgets/vedro_artwork.dart';
import '../widgets/vedro_ui.dart';
import 'player_screen.dart';

/// SenPlayer / Forward / Apple TV+ style Detail Screen:
/// - Full-bleed parallax backdrop + desktop floating 2:3 Hero poster beside title block
/// - Real transparent Title Logo, original title, metadata facts, hairline source chips
/// - Inline Version & Audio/Subtitle track preview card right below the hero
/// - Tall 2:3 clickable Cast & Crew portraits -> Person filmography browser
/// - Apple sliding segmented season selector + rich 16:9 episode rows
class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.item,
    required this.appState,
    this.heroTag,
  });

  final MediaItemModel item;
  final VedroAppState appState;
  final String? heroTag;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late MediaItemModel _item;
  List<MediaItemModel> _similar = [];
  List<MediaSegmentModel> _segments = [];
  List<MediaItemModel> _seasons = [];
  List<MediaItemModel> _episodes = [];
  List<MediaItemModel> _personCredits = [];
  String? _selectedSeasonId;
  String? _selectedSourceId;
  bool _loading = true;
  bool _overviewExpanded = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _loading = true);
    try {
      if (_item.type == 'Person') {
        final cRes = await widget.appState.core.invoke('get_person_credits', {
          'person_id': _item.id,
        }) as Map<String, dynamic>;
        _personCredits = ((cRes['Items'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MediaItemModel.fromJson)
            .toList();
      } else {
        final res = await widget.appState.core.invoke('get_item', {'item_id': _item.id})
            as Map<String, dynamic>;
        _item = MediaItemModel.fromJson(res['item'] as Map<String, dynamic>);
        _similar = ((res['similar'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MediaItemModel.fromJson)
            .toList();
        _segments = ((res['segments'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MediaSegmentModel.fromJson)
            .toList();
        if (_item.mediaSources.isNotEmpty) {
          _selectedSourceId ??= _item.mediaSources.first.id;
        }
        if (_item.isSeries) {
          final sRes = await widget.appState.core.invoke('get_seasons', {'series_id': _item.id})
              as Map<String, dynamic>;
          _seasons = ((sRes['Items'] as List<dynamic>?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(MediaItemModel.fromJson)
              .toList();
          if (_seasons.isNotEmpty) {
            _selectedSeasonId = _seasons.first.id;
            await _loadEpisodes(_seasons.first.id);
          }
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadEpisodes(String seasonId) async {
    final eRes = await widget.appState.core.invoke('get_episodes', {
      'series_id': _item.id,
      'season_id': seasonId,
      'limit': 200,
    }) as Map<String, dynamic>;
    if (!mounted) return;
    setState(() {
      _selectedSeasonId = seasonId;
      _episodes = ((eRes['Items'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MediaItemModel.fromJson)
          .toList();
    });
  }

  MediaSourceModel? get _activeSource {
    if (_item.mediaSources.isEmpty) return null;
    for (final s in _item.mediaSources) {
      if (s.id == _selectedSourceId) return s;
    }
    return _item.mediaSources.first;
  }

  void _play(MediaItemModel target, {String? sourceId, bool fromBeginning = false}) {
    final playTarget = fromBeginning && target.playbackPositionTicks > 0
        ? MediaItemModel(
            id: target.id,
            name: target.name,
            type: target.type,
            seriesId: target.seriesId,
            seriesName: target.seriesName,
            parentIndexNumber: target.parentIndexNumber,
            indexNumber: target.indexNumber,
            runTimeTicks: target.runTimeTicks,
            playbackPositionTicks: 0,
            mediaSources: target.mediaSources,
          )
        : target;

    Navigator.of(context).push(
      vedroRoute(PlayerScreen(
        item: playTarget,
        appState: widget.appState,
        mediaSourceId: sourceId,
        playlistEpisodes: _episodes.isNotEmpty ? _episodes : null,
        segments: target.id == _item.id ? _segments : null,
      )),
    );
  }

  Future<void> _openPlaylistSheet() async {
    await widget.appState.refreshPlaylists();
    if (!mounted) return;
    showGlassSheet<void>(
      context: context,
      builder: (ctx) {
        final lists = widget.appState.playlists;
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '加入片单',
                style: TextStyle(color: VedroTheme.fg, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            if (lists.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无片单，请先在片单页新建', style: TextStyle(color: VedroTheme.fg3, fontSize: 13)),
              )
            else
              ...lists.map((pl) => ListTile(
                    leading: const Icon(Icons.bookmark_outline_rounded, color: VedroTheme.fg2),
                    title: Text(pl.name, style: const TextStyle(color: VedroTheme.fg, fontSize: 14)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await widget.appState.core.invoke('add_to_playlist', {
                        'playlist_id': pl.id,
                        'item_ids': [_item.id],
                      });
                    },
                  )),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 820;
    final padX = wide ? 40.0 : 20.0;
    final heroH = (size.height * (wide ? 0.72 : 0.56)).clamp(400.0, 720.0);
    final logoUrl = _item.type == 'Episode' ? null : widget.appState.logoArtUrl(_item);
    final src = _activeSource;

    final facts = <String>[
      if (_item.productionYear != null) '${_item.productionYear}',
      if (_item.communityRating != null) '★ ${_item.communityRating!.toStringAsFixed(1)}',
      if (!_item.isFolderish && fmtDurationTicks(_item.runTimeTicks).isNotEmpty)
        fmtDurationTicks(_item.runTimeTicks),
      if (_item.isSeries && (_item.childCount ?? 0) > 0) '${_item.childCount} 季',
      if (_item.isFolderish && (_item.recursiveItemCount ?? 0) > 0) '${_item.recursiveItemCount} 集',
      if (_item.officialRating != null) _item.officialRating!,
      ..._item.genres.take(3),
    ];

    final specChips = <String>[
      ..._item.inferredBadges,
      if (src != null) ...src.factChips.where((c) => !_item.inferredBadges.contains(c)),
    ].take(6).toList();

    Widget desktopPoster = Container(
      width: _item.type == 'Episode' ? 320 : 210,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x28FFFFFF), width: 0.8),
        boxShadow: const [
          BoxShadow(color: Color(0xAA000000), blurRadius: 36, offset: Offset(0, 18)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: _item.type == 'Episode' ? 16 / 9 : 2 / 3,
        child: VedroArtwork(
          item: _item,
          appState: widget.appState,
          landscape: _item.type == 'Episode',
          width: _item.type == 'Episode' ? 800 : 480,
        ),
      ),
    );
    if (widget.heroTag != null) {
      desktopPoster = Hero(tag: widget.heroTag!, child: desktopPoster);
    }

    return Scaffold(
      backgroundColor: VedroTheme.canvas,
      body: CustomScrollView(
        slivers: [
          // Full-bleed cinema Hero with back pill
          SliverToBoxAdapter(
            child: SizedBox(
              height: heroH,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VedroArtwork(
                    item: _item,
                    appState: widget.appState,
                    isHero: true,
                    alignment: const Alignment(0, -0.55),
                    showInitials: false,
                  ),
                  if (wide)
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          stops: [0.0, 0.55, 1.0],
                          colors: [Color(0xCC0B0B0D), Color(0x550B0B0D), Colors.transparent],
                        ),
                      ),
                    ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.0, 0.28, 0.72, 1.0],
                        colors: [
                          Color(0x660B0B0D),
                          Colors.transparent,
                          Color(0xBF0B0B0D),
                          VedroTheme.canvas,
                        ],
                      ),
                    ),
                  ),
                  // Floating glass back button (clears macOS traffic lights cleanly)
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + (!kIsWeb && Platform.isMacOS ? 34 : 14),
                    left: padX - 4,
                    child: PressableScale(
                      onTap: () => Navigator.of(context).pop(),
                      hoverScale: 1.05,
                      pressScale: 0.92,
                      child: GlassSurface(
                        borderRadius: 20,
                        blur: 22,
                        color: const Color(0x66141417),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back_ios_new_rounded, size: 15, color: Colors.white),
                            SizedBox(width: 5),
                            Text('返回', style: TextStyle(color: Colors.white, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Hero foreground: floating 2:3 Poster + Title & Actions
                  Positioned(
                    left: padX,
                    right: padX,
                    bottom: 24,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (wide) ...[
                          desktopPoster,
                          const SizedBox(width: 34),
                        ],
                        Expanded(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_item.type == 'Episode' && _item.seriesName != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text(
                                      '${_item.seriesName} · ${_item.episodeCode ?? ''}',
                                      style: const TextStyle(color: Color(0xB8FFFFFF), fontSize: 13),
                                    ),
                                  ),
                                if (logoUrl != null)
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxHeight: wide ? 96 : 68,
                                      maxWidth: wide ? 420 : 280,
                                    ),
                                    child: Image.network(
                                      logoUrl,
                                      fit: BoxFit.contain,
                                      alignment: Alignment.centerLeft,
                                      errorBuilder: (_, __, ___) => Text(
                                        _item.displayName,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: wide ? 36 : 26,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.7,
                                          height: 1.1,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  Text(
                                    _item.displayName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: wide ? 36 : 26,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.7,
                                      height: 1.1,
                                    ),
                                  ),
                                if (_item.originalTitle != null &&
                                    _item.originalTitle != _item.name) ...[
                                  const SizedBox(height: 5),
                                  Text(
                                    _item.originalTitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 13.5),
                                  ),
                                ],
                                if (facts.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    facts.join('  ·  '),
                                    style: const TextStyle(
                                      color: Color(0xD4FFFFFF),
                                      fontSize: 13.5,
                                      fontFeatures: [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ],
                                if (specChips.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  SpecGlyphRow(specs: specChips),
                                ],
                                const SizedBox(height: 20),
                                // Action pills
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (_item.isPlayable)
                                      _WhitePlayButton(
                                        label: _item.playbackPositionTicks > 0
                                            ? '继续 ${fmtDurationTicks(_item.playbackPositionTicks)}'
                                            : '播放',
                                        onTap: () => _play(_item, sourceId: _selectedSourceId),
                                      )
                                    else if (_episodes.isNotEmpty)
                                      _WhitePlayButton(
                                        label: '播放 ${_episodes.first.episodeCode ?? '第 1 集'}',
                                        onTap: () => _play(_episodes.first),
                                      ),
                                    if (_item.isPlayable && _item.playbackPositionTicks > 0)
                                      _GlassActionPill(
                                        icon: Icons.replay_rounded,
                                        label: '从头播放',
                                        onTap: () => _play(
                                          _item,
                                          sourceId: _selectedSourceId,
                                          fromBeginning: true,
                                        ),
                                      ),
                                    if (_item.type != 'Person')
                                      _GlassActionPill(
                                        icon: _item.played
                                            ? Icons.check_circle_rounded
                                            : Icons.check_circle_outline_rounded,
                                        label: _item.played ? '已看' : '标为已看',
                                        onTap: () async {
                                          await widget.appState.togglePlayed(_item);
                                          await _loadDetails();
                                        },
                                      ),
                                    _GlassActionPill(
                                      icon: _item.isFavorite
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      iconColor: _item.isFavorite ? VedroTheme.danger : Colors.white,
                                      label: _item.isFavorite ? '已收藏' : '收藏',
                                      onTap: () async {
                                        await widget.appState.toggleFavorite(_item);
                                        await _loadDetails();
                                      },
                                    ),
                                    if (_item.type != 'Person')
                                      _GlassActionPill(
                                        icon: Icons.playlist_add_rounded,
                                        label: '片单',
                                        onTap: _openPlaylistSheet,
                                      ),
                                  ],
                                ),
                              ],
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

          // Main detail content below hero
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(padX, 12, padX, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_item.overview != null && _item.overview!.isNotEmpty) ...[
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _item.overview!,
                            maxLines: _overviewExpanded ? null : 3,
                            overflow: _overviewExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: VedroTheme.fg2,
                              fontSize: 14.5,
                              height: 1.65,
                            ),
                          ),
                          if (_item.overview!.length > 130)
                            GestureDetector(
                              onTap: () => setState(() => _overviewExpanded = !_overviewExpanded),
                              child: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  _overviewExpanded ? '收起' : '展开全部',
                                  style: const TextStyle(
                                    color: VedroTheme.fg,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],

                  // Inline Versions & Audio/Subtitle Tracks card (for playable items)
                  if (_item.isPlayable && _item.mediaSources.isNotEmpty) ...[
                    _TracksPanel(
                      sources: _item.mediaSources,
                      selectedId: _selectedSourceId,
                      onSelect: (id) => setState(() => _selectedSourceId = id),
                    ),
                    const SizedBox(height: 30),
                  ],

                  // TV Series Seasons & Episodes
                  if (_seasons.isNotEmpty) ...[
                    Row(
                      children: [
                        const Text(
                          '剧集',
                          style: TextStyle(
                            color: VedroTheme.fg,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${_episodes.length} 集',
                          style: const TextStyle(color: VedroTheme.fg3, fontSize: 13),
                        ),
                      ],
                    ),
                    if (_seasons.length > 1) ...[
                      const SizedBox(height: 14),
                      VedroSegmentedControl<String>(
                        items: _seasons.map((s) => (s.id, s.name)).toList(),
                        selected: _selectedSeasonId ?? _seasons.first.id,
                        onSelected: _loadEpisodes,
                      ),
                    ],
                    const SizedBox(height: 16),
                    ..._episodes.map((ep) => _EpisodeRow(
                          episode: ep,
                          appState: widget.appState,
                          onTap: () => _play(ep),
                        )),
                    const SizedBox(height: 24),
                  ],

                  // Person Credits grid (when viewing an actor/director)
                  if (_item.type == 'Person' && _personCredits.isNotEmpty) ...[
                    Text(
                      '参与作品 (${_personCredits.length})',
                      style: const TextStyle(
                        color: VedroTheme.fg,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 20,
                      children: _personCredits
                          .map((c) => MediaCard(
                                item: c,
                                appState: widget.appState,
                                width: wide ? 156 : 112,
                                onTap: () => Navigator.of(context).push(
                                  vedroRoute(DetailScreen(item: c, appState: widget.appState)),
                                ),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 28),
                  ],

                  // Cast & Crew tall 2:3 portraits (clickable -> Person filmography!)
                  if (_item.people.isNotEmpty) ...[
                    const Text(
                      '演员与主创',
                      style: TextStyle(
                        color: VedroTheme.fg,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 226,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _item.people.take(20).length,
                        separatorBuilder: (_, __) => const SizedBox(width: 14),
                        itemBuilder: (_, idx) {
                          final p = _item.people[idx];
                          final avatarUrl = p.primaryImageTag != null
                              ? widget.appState.buildImageUrl(
                                  p.id,
                                  type: 'Primary',
                                  tag: p.primaryImageTag,
                                  maxWidth: 280,
                                )
                              : '';
                          return SizedBox(
                            width: 118,
                            child: PressableScale(
                              onTap: () => Navigator.of(context).push(
                                vedroRoute(DetailScreen(
                                  item: MediaItemModel(
                                    id: p.id,
                                    name: p.name,
                                    type: 'Person',
                                    primaryImageTag: p.primaryImageTag,
                                  ),
                                  appState: widget.appState,
                                )),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AspectRatio(
                                    aspectRatio: 2 / 3,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: VedroTheme.line, width: 0.7),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          GeneratedArt(seed: p.id, label: p.name),
                                          if (avatarUrl.isNotEmpty)
                                            FadeNetworkImage(url: avatarUrl),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: VedroTheme.fg,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if ((p.role ?? p.type ?? '').isNotEmpty)
                                    Text(
                                      p.role ?? p.type ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: VedroTheme.fg3, fontSize: 11.5),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          if (_similar.isNotEmpty)
            SliverToBoxAdapter(
              child: HorizontalMediaRail(
                title: '相关推荐',
                items: _similar,
                appState: widget.appState,
                onItemTap: (other) => Navigator.of(context).push(
                  vedroRoute(DetailScreen(item: other, appState: widget.appState)),
                ),
              ),
            ),

          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: VedroTheme.fg2),
                  ),
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 56)),
        ],
      ),
    );
  }
}

class _WhitePlayButton extends StatelessWidget {
  const _WhitePlayButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      hoverScale: 1.03,
      pressScale: 0.96,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(color: Color(0x45000000), blurRadius: 16, offset: Offset(0, 6)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_arrow_rounded, size: 22, color: VedroTheme.canvas),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: VedroTheme.canvas,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassActionPill extends StatelessWidget {
  const _GlassActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      hoverScale: 1.03,
      pressScale: 0.96,
      child: GlassSurface(
        borderRadius: 12,
        blur: 22,
        color: const Color(0x5222232A),
        borderColor: const Color(0x32FFFFFF),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: iconColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TracksPanel extends StatelessWidget {
  const _TracksPanel({
    required this.sources,
    required this.selectedId,
    required this.onSelect,
  });

  final List<MediaSourceModel> sources;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final active = sources.firstWhere(
      (s) => s.id == selectedId,
      orElse: () => sources.first,
    );
    final audios = active.audioStreams;
    final subs = active.subtitleStreams;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: VedroTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VedroTheme.line, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sources.length > 1) ...[
            Text(
              '版本 (${sources.length})',
              style: const TextStyle(color: VedroTheme.fg2, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: sources.map((s) {
                final on = s.id == active.id;
                return PressableScale(
                  onTap: () => onSelect(s.id),
                  hoverScale: 1.02,
                  pressScale: 0.97,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: on ? VedroTheme.accentSoft : VedroTheme.surface2,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: on ? VedroTheme.accent.withValues(alpha: 0.6) : VedroTheme.line,
                        width: 0.9,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.name?.isNotEmpty == true ? s.name! : (s.container?.toUpperCase() ?? '原画'),
                          style: TextStyle(
                            color: on ? VedroTheme.fg : VedroTheme.fg2,
                            fontSize: 13.5,
                            fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            if (s.container != null) s.container!.toUpperCase(),
                            if (fmtFileSize(s.size).isNotEmpty) fmtFileSize(s.size),
                            if (s.subtitleStreams.isNotEmpty) '${s.subtitleStreams.length} 条字幕',
                          ].join(' · '),
                          style: const TextStyle(color: VedroTheme.fg3, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ] else
            Text(
              active.displayLabel,
              style: const TextStyle(color: VedroTheme.fg, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          if (audios.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              '音轨 (${audios.length})',
              style: const TextStyle(color: VedroTheme.fg3, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: audios
                  .map((a) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: VedroTheme.surface2,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: VedroTheme.line, width: 0.6),
                        ),
                        child: Text(a.label, style: const TextStyle(color: VedroTheme.fg2, fontSize: 12)),
                      ))
                  .toList(),
            ),
          ],
          if (subs.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              '字幕 (${subs.length})',
              style: const TextStyle(color: VedroTheme.fg3, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: subs
                  .take(12)
                  .map((s) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: VedroTheme.surface2,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: VedroTheme.line, width: 0.6),
                        ),
                        child: Text(s.label, style: const TextStyle(color: VedroTheme.fg2, fontSize: 12)),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _EpisodeRow extends StatefulWidget {
  const _EpisodeRow({
    required this.episode,
    required this.appState,
    required this.onTap,
  });

  final MediaItemModel episode;
  final VedroAppState appState;
  final VoidCallback onTap;

  @override
  State<_EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends State<_EpisodeRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ep = widget.episode;
    final dur = fmtDurationTicks(ep.runTimeTicks);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PressableScale(
        onTap: widget.onTap,
        onHoverChanged: (v) => setState(() => _hovered = v),
        hoverScale: 1.008,
        pressScale: 0.985,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _hovered ? VedroTheme.surface2 : VedroTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovered ? VedroTheme.lineStrong : VedroTheme.line,
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 148,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        VedroArtwork(
                          item: ep,
                          appState: widget.appState,
                          landscape: true,
                          width: 420,
                        ),
                        if (ep.resumeProgress > 0.01)
                          Positioned(
                            left: 6,
                            right: 6,
                            bottom: 6,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: ep.resumeProgress,
                                minHeight: 2.5,
                                backgroundColor: const Color(0x45FFFFFF),
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            [
                              if (ep.indexNumber != null) '${ep.indexNumber}.',
                              ep.displayName,
                            ].join(' '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: VedroTheme.fg,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (dur.isNotEmpty)
                          Text(
                            dur,
                            style: const TextStyle(color: VedroTheme.fg3, fontSize: 12),
                          ),
                      ],
                    ),
                    if (ep.overview != null && ep.overview!.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        ep.overview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: VedroTheme.fg3,
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                ep.played ? Icons.check_circle_rounded : Icons.play_arrow_rounded,
                size: 22,
                color: _hovered ? VedroTheme.fg : VedroTheme.fg3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
