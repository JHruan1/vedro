import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/badge_strip.dart';
import '../widgets/horizontal_rail.dart';
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
        _selectedSourceId = _item.mediaSources.first.id;
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

  @override
  Widget build(BuildContext context) {
    final bgUrl = _item.backdropImageTag != null
        ? widget.appState.buildImageUrl(_item.id, type: 'Backdrop', tag: _item.backdropImageTag, maxWidth: 1600)
        : '';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(_item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (bgUrl.isNotEmpty)
                    Image.network(bgUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x3307090F), VedroTheme.bg],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BadgeStrip(badges: [
                    if (_item.productionYear != null) '${_item.productionYear}',
                    if (_item.communityRating != null) '★ ${_item.communityRating!.toStringAsFixed(1)}',
                    if (_item.officialRating != null) _item.officialRating!,
                    ..._item.inferredBadges,
                  ]),
                  const SizedBox(height: 16),
                  // Action row
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      if (_item.isPlayable)
                        FilledButton.icon(
                          onPressed: () => _play(_item, sourceId: _selectedSourceId),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(_item.playbackPositionTicks > 0 ? '继续播放 (DirectPlay)' : '立即播放 (DirectPlay)'),
                        )
                      else if (_episodes.isNotEmpty)
                        FilledButton.icon(
                          onPressed: () => _play(_episodes.first),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text('播放 ${_episodes.first.episodeCode ?? '第 1 集'}'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await widget.appState.toggleFavorite(_item);
                          await _loadDetails();
                        },
                        icon: Icon(_item.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: _item.isFavorite ? Colors.pinkAccent : null),
                        label: Text(_item.isFavorite ? '已收藏' : '收藏'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await widget.appState.togglePlayed(_item);
                          await _loadDetails();
                        },
                        icon: Icon(_item.played ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded),
                        label: Text(_item.played ? '已观看' : '标记已看'),
                      ),
                    ],
                  ),
                  // Multi-version selector (perfect for embygo provider-ID merged local/cloud versions!)
                  if (_item.mediaSources.length > 1) ...[
                    const SizedBox(height: 20),
                    const Text('版本选择（支持 embygo 多版本合并）',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 8),
                    ..._item.mediaSources.map((src) {
                      final selected = src.id == _selectedSourceId;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                            color: selected ? VedroTheme.accent : VedroTheme.textSecondary,
                          ),
                          onTap: () => setState(() => _selectedSourceId = src.id),
                          title: Text(src.displayLabel, style: const TextStyle(fontSize: 13.5)),
                          subtitle: Text(
                            '容器: ${src.container?.toUpperCase() ?? '-'} • DirectPlay: ${src.supportsDirectPlay ? '支持' : '否'}',
                            style: const TextStyle(color: VedroTheme.textSecondary, fontSize: 12),
                          ),
                        ),
                      );
                    }),
                  ],
                  if (_item.overview != null && _item.overview!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      _item.overview!,
                      style: const TextStyle(color: VedroTheme.textSecondary, height: 1.55),
                    ),
                  ],
                  if (_seasons.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 8,
                      children: _seasons
                          .map((s) => ChoiceChip(
                                label: Text(s.name),
                                selected: s.id == _selectedSeasonId,
                                onSelected: (_) => _loadEpisodes(s.id),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    ..._episodes.map((ep) => Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: VedroTheme.surfaceElevated,
                              child: Text(ep.episodeCode ?? '${ep.indexNumber ?? ''}'),
                            ),
                            title: Text(ep.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: ep.overview != null
                                ? Text(ep.overview!, maxLines: 2, overflow: TextOverflow.ellipsis)
                                : null,
                            trailing: IconButton(
                              icon: const Icon(Icons.play_circle_fill_rounded, color: VedroTheme.accent, size: 32),
                              onPressed: () => _play(ep),
                            ),
                            onTap: () => _play(ep),
                          ),
                        )),
                  ],
                  if (_item.people.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text('演职员', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 86,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _item.people.take(15).length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, idx) {
                          final p = _item.people[idx];
                          return Container(
                            width: 160,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: VedroTheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: VedroTheme.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(p.role ?? p.type ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: VedroTheme.textSecondary, fontSize: 12)),
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
                title: '相似推荐',
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
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}
