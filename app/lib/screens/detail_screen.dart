import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/horizontal_rail.dart';
import '../widgets/vedro_ui.dart';
import 'player_screen.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.item, required this.appState});

  final MediaItemModel item;
  final VedroAppState appState;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late MediaItemModel _item;
  List<MediaItemModel> _similar = [];
  List<MediaItemModel> _seasons = [];
  List<MediaItemModel> _episodes = [];
  String? _selectedSeasonId;
  String? _selectedSourceId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _loading = true);
    try {
      final res = await widget.appState.core.invoke('get_item', {'item_id': _item.id})
          as Map<String, dynamic>;
      _item = MediaItemModel.fromJson(res['item'] as Map<String, dynamic>);
      _similar = ((res['similar'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MediaItemModel.fromJson)
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

  void _play(MediaItemModel target, {String? sourceId}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          item: target,
          appState: widget.appState,
          mediaSourceId: sourceId,
        ),
      ),
    );
  }

  void _openVersionPicker() {
    showGlassSheet<void>(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(
              '选择版本',
              style: TextStyle(
                color: VedroTheme.fg,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 6),
          ..._item.mediaSources.map((src) {
            final selected = src.id == _selectedSourceId;
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() => _selectedSourceId = src.id);
                Navigator.pop(ctx);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? const Color(0x16FFFFFF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            src.displayLabel,
                            style: const TextStyle(
                              color: VedroTheme.fg,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (src.container != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              src.container!.toUpperCase(),
                              style: const TextStyle(color: VedroTheme.fg3, fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (selected)
                      const Icon(Icons.check_rounded, size: 18, color: VedroTheme.accent),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgUrl = _item.backdropImageTag != null
        ? widget.appState.buildImageUrl(
            _item.id,
            type: 'Backdrop',
            tag: _item.backdropImageTag,
            maxWidth: 1920,
          )
        : (_item.primaryImageTag != null
            ? widget.appState.buildImageUrl(
                _item.id,
                type: 'Primary',
                tag: _item.primaryImageTag,
                maxWidth: 1200,
              )
            : '');

    final runtimeMins =
        _item.runTimeTicks != null && _item.runTimeTicks! > 0 ? _item.runTimeTicks! ~/ 600000000 : null;
    final metaLine = [
      if (_item.productionYear != null) '${_item.productionYear}',
      if (runtimeMins != null) '$runtimeMins 分钟',
      if (_item.communityRating != null) '★ ${_item.communityRating!.toStringAsFixed(1)}',
      if (_item.officialRating != null) _item.officialRating!,
      if (_item.genres.isNotEmpty) _item.genres.take(3).join(' / '),
    ].join('  ·  ');

    return Scaffold(
      backgroundColor: VedroTheme.canvas,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 340,
            pinned: true,
            backgroundColor: VedroTheme.canvas,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: PressableScale(
                onTap: () => Navigator.of(context).pop(),
                child: GlassSurface(
                  borderRadius: 20,
                  blur: 18,
                  color: const Color(0x66141417),
                  child: const Center(
                    child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: VedroTheme.fg),
                  ),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
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
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.0, 0.45, 1.0],
                        colors: [
                          Color(0x550B0B0D),
                          Color(0x280B0B0D),
                          VedroTheme.canvas,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _item.name,
                    style: const TextStyle(
                      color: VedroTheme.fg,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.7,
                      height: 1.15,
                    ),
                  ),
                  if (metaLine.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      metaLine,
                      style: const TextStyle(color: VedroTheme.fg2, fontSize: 13.5),
                    ),
                  ],
                  if (_item.inferredBadges.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SpecGlyphRow(specs: _item.inferredBadges),
                  ],
                  const SizedBox(height: 20),

                  // Action bar
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (_item.isPlayable)
                        PressableScale(
                          onTap: () => _play(_item, sourceId: _selectedSourceId),
                          child: Container(
                            height: 42,
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            decoration: BoxDecoration(
                              color: VedroTheme.fg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.play_arrow_rounded, size: 20, color: VedroTheme.canvas),
                                const SizedBox(width: 5),
                                Text(
                                  _item.playbackPositionTicks > 0 ? '继续播放' : '播放',
                                  style: const TextStyle(
                                    color: VedroTheme.canvas,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (_episodes.isNotEmpty)
                        PressableScale(
                          onTap: () => _play(_episodes.first),
                          child: Container(
                            height: 42,
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            decoration: BoxDecoration(
                              color: VedroTheme.fg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.play_arrow_rounded, size: 20, color: VedroTheme.canvas),
                                const SizedBox(width: 5),
                                Text(
                                  '播放 ${_episodes.first.episodeCode ?? '第 1 集'}',
                                  style: const TextStyle(
                                    color: VedroTheme.canvas,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      _SubtleActionPill(
                        icon: _item.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        iconColor: _item.isFavorite ? VedroTheme.danger : VedroTheme.fg2,
                        label: _item.isFavorite ? '已收藏' : '收藏',
                        onTap: () async {
                          await widget.appState.toggleFavorite(_item);
                          await _loadDetails();
                        },
                      ),
                      _SubtleActionPill(
                        icon: _item.played ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                        iconColor: _item.played ? VedroTheme.fg : VedroTheme.fg2,
                        label: _item.played ? '已看' : '标为已看',
                        onTap: () async {
                          await widget.appState.togglePlayed(_item);
                          await _loadDetails();
                        },
                      ),
                      if (_item.mediaSources.length > 1)
                        _SubtleActionPill(
                          icon: Icons.layers_outlined,
                          iconColor: VedroTheme.fg2,
                          label: '版本 (${_item.mediaSources.length})',
                          onTap: _openVersionPicker,
                        ),
                    ],
                  ),

                  if (_item.overview != null && _item.overview!.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 740),
                      child: Text(
                        _item.overview!,
                        style: const TextStyle(
                          color: VedroTheme.fg2,
                          fontSize: 14,
                          height: 1.62,
                        ),
                      ),
                    ),
                  ],

                  if (_seasons.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _seasons.map((s) {
                          final active = s.id == _selectedSeasonId;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: PressableScale(
                              onTap: () => _loadEpisodes(s.id),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: active ? VedroTheme.fg : VedroTheme.surface2,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: active ? VedroTheme.fg : VedroTheme.line,
                                    width: 0.7,
                                  ),
                                ),
                                child: Text(
                                  s.name,
                                  style: TextStyle(
                                    color: active ? VedroTheme.canvas : VedroTheme.fg2,
                                    fontSize: 13,
                                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ..._episodes.map((ep) => _EpisodeRow(
                          episode: ep,
                          appState: widget.appState,
                          onTap: () => _play(ep),
                        )),
                  ],

                  if (_item.people.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    const Text(
                      '演职员',
                      style: TextStyle(
                        color: VedroTheme.fg,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 112,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _item.people.take(18).length,
                        separatorBuilder: (_, __) => const SizedBox(width: 14),
                        itemBuilder: (_, idx) {
                          final p = _item.people[idx];
                          final avatarUrl = p.primaryImageTag != null
                              ? widget.appState.buildImageUrl(
                                  p.id,
                                  type: 'Primary',
                                  tag: p.primaryImageTag,
                                  maxWidth: 160,
                                )
                              : '';
                          return SizedBox(
                            width: 82,
                            child: Column(
                              children: [
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: VedroTheme.surface2,
                                    border: Border.all(color: VedroTheme.line, width: 0.7),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: avatarUrl.isNotEmpty
                                      ? Image.network(
                                          avatarUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => _InitialsAvatar(name: p.name),
                                        )
                                      : _InitialsAvatar(name: p.name),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: VedroTheme.fg,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  p.role ?? p.type ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: VedroTheme.fg3, fontSize: 11),
                                ),
                              ],
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
                  MaterialPageRoute(
                    builder: (_) => DetailScreen(item: other, appState: widget.appState),
                  ),
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

          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
      ),
    );
  }
}

class _SubtleActionPill extends StatelessWidget {
  const _SubtleActionPill({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: VedroTheme.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: VedroTheme.line, width: 0.7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: iconColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: VedroTheme.fg,
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

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.episode,
    required this.appState,
    required this.onTap,
  });

  final MediaItemModel episode;
  final VedroAppState appState;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final thumbUrl = episode.primaryImageTag != null
        ? appState.buildImageUrl(
            episode.id,
            type: 'Primary',
            tag: episode.primaryImageTag,
            maxWidth: 420,
          )
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PressableScale(
        onTap: onTap,
        hoverScale: 1.01,
        pressScale: 0.985,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: VedroTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: VedroTheme.line, width: 0.6),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 128,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    decoration: BoxDecoration(
                      color: VedroTheme.surface2,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (thumbUrl.isNotEmpty)
                          Image.network(
                            thumbUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.play_arrow_rounded, color: VedroTheme.fg3),
                            ),
                          )
                        else
                          const Center(
                            child: Icon(Icons.play_arrow_rounded, color: VedroTheme.fg3),
                          ),
                        if (episode.resumeProgress > 0.01)
                          Positioned(
                            left: 6,
                            right: 6,
                            bottom: 6,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: episode.resumeProgress,
                                minHeight: 2.5,
                                backgroundColor: const Color(0x44FFFFFF),
                                color: VedroTheme.fg,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        if (episode.indexNumber != null) '${episode.indexNumber}.',
                        episode.name,
                      ].join(' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VedroTheme.fg,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (episode.overview != null && episode.overview!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        episode.overview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: VedroTheme.fg3,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.play_arrow_rounded, size: 22, color: VedroTheme.fg2),
            ],
          ),
        ),
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isNotEmpty ? name.trim().substring(0, 1).toUpperCase() : '?';
    return Center(
      child: Text(
        letter,
        style: const TextStyle(
          color: VedroTheme.fg2,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
