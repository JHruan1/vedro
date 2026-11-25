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

/// Infuse / Forward / Apple TV+ caliber cinema Detail Screen:
/// - Non-clipping responsive Hero with dual-layer high-contrast cinema scrim
/// - Aligned macOS titlebar back pill (`top: 12, left: 82`)
/// - Crystal-clear HTML-cleaned Synopsis right beside Poster + structured metadata strip
/// - Optional 1-click AI Translation of Synopsis when AI Service is configured
/// - Interactive Version / Audio / Subtitle track pre-selection + Offline Download
/// - Clickable Cast & Crew portraits -> Person filmography, Segmented Seasons & Episodes
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
  int? _selectedAudioIndex;
  int? _selectedSubtitleIndex;
  bool _loading = true;
  bool _overviewExpanded = false;
  String? _translatedOverview;
  bool _translating = false;

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
        initialAudioStreamIndex: target.id == _item.id ? _selectedAudioIndex : null,
        initialSubtitleStreamIndex: target.id == _item.id ? _selectedSubtitleIndex : null,
      )),
    );
  }

  Future<void> _translateOverview() async {
    final text = _item.cleanOverview;
    if (text.isEmpty || _translating) return;
    setState(() => _translating = true);
    try {
      final translated = await widget.appState.translateText(text);
      if (mounted) {
        setState(() {
          _translatedOverview = translated;
          _overviewExpanded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  Future<void> _startDownload() async {
    final target = _item.isPlayable
        ? _item
        : (_episodes.isNotEmpty ? _episodes.first : null);
    if (target == null) return;
    await widget.appState.enqueueDownload(target, mediaSourceId: _selectedSourceId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已加入下载队列：${target.cardTitle}（可在「设置 → 下载管理」查看）'),
        duration: const Duration(seconds: 3),
      ),
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
    final padX = wide ? 44.0 : 20.0;
    final isMac = !kIsWeb && Platform.isMacOS;
    final topSafe = MediaQuery.paddingOf(context).top;
    final logoUrl = _item.type == 'Episode' ? null : widget.appState.logoArtUrl(_item);
    final src = _activeSource;
    final showSpecs = widget.appState.prefs.showSpecBadges;
    final overviewText = _translatedOverview?.isNotEmpty == true
        ? _translatedOverview!
        : _item.cleanOverview;

    final directors = _item.people
        .where((p) => (p.type ?? '').toLowerCase() == 'director')
        .map((p) => p.name)
        .take(3)
        .toList();

    final facts = <String>[
      if (_item.productionYear != null) '${_item.productionYear}',
      if (_item.communityRating != null) '★ ${_item.communityRating!.toStringAsFixed(1)}',
      if (!_item.isFolderish && fmtDurationTicks(_item.runTimeTicks).isNotEmpty)
        fmtDurationTicks(_item.runTimeTicks),
      if (_item.isSeries && (_item.childCount ?? 0) > 0) '${_item.childCount} 季',
      if (_item.isFolderish && (_item.recursiveItemCount ?? 0) > 0) '${_item.recursiveItemCount} 集',
      if (_item.officialRating != null) _item.officialRating!,
      ..._item.genres.take(4),
    ];

    final specChips = showSpecs
        ? <String>[
            ..._item.inferredBadges,
            if (src != null) ...src.factChips.where((c) => !_item.inferredBadges.contains(c)),
          ].take(6).toList()
        : const <String>[];

    Widget desktopPoster = Container(
      width: _item.type == 'Episode' ? 320 : 214,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Color(0xCC000000), blurRadius: 38, offset: Offset(0, 18)),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x30FFFFFF), width: 0.9),
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

    final heroMinH = (size.height * (wide ? 0.62 : 0.50)).clamp(380.0, 620.0);

    return Scaffold(
      backgroundColor: VedroTheme.canvas,
      body: CustomScrollView(
        slivers: [
          // Full-bleed responsive cinema Hero (never clips or collides with back bar)
          SliverToBoxAdapter(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: heroMinH),
              child: Stack(
                children: [
                  // Backdrop image + heavy dual-layer cinema scrim
                  Positioned.fill(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        VedroArtwork(
                          item: _item,
                          appState: widget.appState,
                          isHero: true,
                          alignment: const Alignment(0, -0.35),
                          showInitials: false,
                        ),
                        if (wide)
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                stops: [0.0, 0.52, 0.85, 1.0],
                                colors: [
                                  Color(0xE80B0B0D),
                                  Color(0xA60B0B0D),
                                  Color(0x380B0B0D),
                                  Color(0x140B0B0D),
                                ],
                              ),
                            ),
                          ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: [0.0, 0.22, 0.55, 0.84, 1.0],
                              colors: [
                                Color(0x880B0B0D),
                                Color(0x280B0B0D),
                                Color(0x990B0B0D),
                                Color(0xEB0B0B0D),
                                VedroTheme.canvas,
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Foreground content naturally flows with safe padding
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      padX,
                      topSafe + (wide ? 120 : 108),
                      padX,
                      28,
                    ),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (wide) ...[
                            desktopPoster,
                            const SizedBox(width: 36),
                          ],
                          Expanded(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 740),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_item.type == 'Episode' && _item.seriesName != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Text(
                                        '${_item.seriesName} · ${_item.episodeCode ?? ''}',
                                        style: const TextStyle(
                                          color: Color(0xD8FFFFFF),
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  if (logoUrl != null)
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxHeight: wide ? 92 : 64,
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
                                            height: 1.12,
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
                                        height: 1.12,
                                      ),
                                    ),
                                  if (_item.originalTitle != null &&
                                      _item.originalTitle != _item.name) ...[
                                    const SizedBox(height: 5),
                                    Text(
                                      _item.originalTitle!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xB8FFFFFF),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                  if (facts.isNotEmpty) ...[
                                    const SizedBox(height: 11),
                                    Text(
                                      facts.join('  ·  '),
                                      style: const TextStyle(
                                        color: Color(0xE8FFFFFF),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        fontFeatures: [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ],
                                  if (specChips.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    SpecGlyphRow(specs: specChips),
                                  ],
                                  // Crystal-clear high-contrast Synopsis right inside the Hero on desktop!
                                  if (overviewText.isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    AnimatedSize(
                                      duration: const Duration(milliseconds: 220),
                                      curve: Curves.easeOutCubic,
                                      alignment: Alignment.topLeft,
                                      child: Text(
                                        overviewText,
                                        maxLines: _overviewExpanded ? null : (wide ? 4 : 3),
                                        overflow: _overviewExpanded
                                            ? TextOverflow.visible
                                            : TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xEBECECF0),
                                          fontSize: 15,
                                          height: 1.72,
                                          letterSpacing: 0.1,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 14,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        if (overviewText.length > 100)
                                          GestureDetector(
                                            onTap: () => setState(
                                              () => _overviewExpanded = !_overviewExpanded,
                                            ),
                                            child: Text(
                                              _overviewExpanded ? '收起简介' : '展开全部简介',
                                              style: TextStyle(
                                                color: Theme.of(context).colorScheme.secondary,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        if (widget.appState.prefs.isAiReady)
                                          GestureDetector(
                                            onTap: _translatedOverview != null
                                                ? () => setState(() => _translatedOverview = null)
                                                : _translateOverview,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.auto_awesome_rounded,
                                                  size: 14,
                                                  color: Theme.of(context).colorScheme.secondary,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _translating
                                                      ? 'AI 翻译中…'
                                                      : (_translatedOverview != null
                                                          ? '显示原文'
                                                          : 'AI 翻译简介'),
                                                  style: TextStyle(
                                                    color: Theme.of(context).colorScheme.secondary,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 22),
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
                                      if (_item.isPlayable || _episodes.isNotEmpty)
                                        _GlassActionPill(
                                          icon: Icons.download_rounded,
                                          label: '下载',
                                          onTap: _startDownload,
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
                  ),

                  // Floating glass back button cleanly aligned with macOS traffic lights
                  Positioned(
                    top: topSafe + 12,
                    left: isMac ? 82 : (padX - 4),
                    child: PressableScale(
                      onTap: () => Navigator.of(context).pop(),
                      hoverScale: 1.04,
                      pressScale: 0.92,
                      child: GlassSurface(
                        borderRadius: 18,
                        blur: 22,
                        color: const Color(0x6E141417),
                        borderColor: const Color(0x2EFFFFFF),
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: Colors.white),
                            SizedBox(width: 5),
                            Text(
                              '返回',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Main detail body below hero
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(padX, 8, padX, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Structured metadata facts strip (Director / Studio / Tags)
                  if (directors.isNotEmpty || _item.studios.isNotEmpty || _item.tags.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        color: VedroTheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: VedroTheme.line, width: 0.8),
                      ),
                      child: Wrap(
                        spacing: 28,
                        runSpacing: 12,
                        children: [
                          if (directors.isNotEmpty)
                            _MetaFact(label: '导演', value: directors.join(' / ')),
                          if (_item.studios.isNotEmpty)
                            _MetaFact(label: '出品', value: _item.studios.take(3).join(' / ')),
                          if (_item.officialRating != null)
                            _MetaFact(label: '分级', value: _item.officialRating!),
                          if (_item.tags.isNotEmpty)
                            _MetaFact(label: '标签', value: _item.tags.take(5).join(' · ')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Interactive Versions & Audio/Subtitle Tracks card (for playable items)
                  if (_item.isPlayable && _item.mediaSources.isNotEmpty) ...[
                    _TracksPanel(
                      sources: _item.mediaSources,
                      selectedId: _selectedSourceId,
                      selectedAudioIndex: _selectedAudioIndex,
                      selectedSubtitleIndex: _selectedSubtitleIndex,
                      onSelectSource: (id) => setState(() {
                        _selectedSourceId = id;
                        _selectedAudioIndex = null;
                        _selectedSubtitleIndex = null;
                      }),
                      onSelectAudio: (idx) => setState(() => _selectedAudioIndex = idx),
                      onSelectSubtitle: (idx) => setState(() => _selectedSubtitleIndex = idx),
                    ),
                    const SizedBox(height: 28),
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

                  // Person Credits grid
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

                  // Cast & Crew tall 2:3 portraits
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
                      height: 230,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
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
                                      foregroundDecoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: VedroTheme.line, width: 0.8),
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
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

class _MetaFact extends StatelessWidget {
  const _MetaFact({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: VedroTheme.fg3,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: VedroTheme.fg,
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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
        color: const Color(0x661C1D24),
        borderColor: const Color(0x34FFFFFF),
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
    required this.selectedAudioIndex,
    required this.selectedSubtitleIndex,
    required this.onSelectSource,
    required this.onSelectAudio,
    required this.onSelectSubtitle,
  });

  final List<MediaSourceModel> sources;
  final String? selectedId;
  final int? selectedAudioIndex;
  final int? selectedSubtitleIndex;
  final ValueChanged<String> onSelectSource;
  final ValueChanged<int?> onSelectAudio;
  final ValueChanged<int?> onSelectSubtitle;

  @override
  Widget build(BuildContext context) {
    final active = sources.firstWhere(
      (s) => s.id == selectedId,
      orElse: () => sources.first,
    );
    final audios = active.audioStreams;
    final subs = active.subtitleStreams;
    final accent = Theme.of(context).colorScheme.secondary;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: VedroTheme.surface,
        borderRadius: BorderRadius.circular(14),
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
                  onTap: () => onSelectSource(s.id),
                  hoverScale: 1.02,
                  pressScale: 0.97,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: on ? accent.withValues(alpha: 0.16) : VedroTheme.surface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: on ? accent.withValues(alpha: 0.65) : VedroTheme.line,
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
              children: audios.map((a) {
                final on = selectedAudioIndex == a.index;
                return GestureDetector(
                  onTap: () => onSelectAudio(on ? null : a.index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: on ? accent.withValues(alpha: 0.16) : VedroTheme.surface2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: on ? accent.withValues(alpha: 0.65) : VedroTheme.line,
                        width: 0.7,
                      ),
                    ),
                    child: Text(
                      a.label,
                      style: TextStyle(
                        color: on ? VedroTheme.fg : VedroTheme.fg2,
                        fontSize: 12.5,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              }).toList(),
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
              children: subs.take(14).map((s) {
                final on = selectedSubtitleIndex == s.index;
                return GestureDetector(
                  onTap: () => onSelectSubtitle(on ? null : s.index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: on ? accent.withValues(alpha: 0.16) : VedroTheme.surface2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: on ? accent.withValues(alpha: 0.65) : VedroTheme.line,
                        width: 0.7,
                      ),
                    ),
                    child: Text(
                      s.label,
                      style: TextStyle(
                        color: on ? VedroTheme.fg : VedroTheme.fg2,
                        fontSize: 12.5,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              }).toList(),
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
    final epOverview = ep.cleanOverview;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PressableScale(
        onTap: widget.onTap,
        onHoverChanged: (v) => setState(() => _hovered = v),
        hoverScale: 1.006,
        pressScale: 0.985,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(11),
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
                width: 158,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    foregroundDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: VedroTheme.line, width: 0.6),
                    ),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(9)),
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
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (dur.isNotEmpty)
                          Text(
                            dur,
                            style: const TextStyle(
                              color: VedroTheme.fg2,
                              fontSize: 12,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                      ],
                    ),
                    if (epOverview.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        epOverview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFB8BAC4),
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
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
