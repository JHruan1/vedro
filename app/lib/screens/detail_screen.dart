import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/horizontal_rail.dart';
import '../widgets/media_card.dart';
import '../widgets/vedro_artwork.dart';
import '../widgets/vedro_ui.dart';
import 'player_screen.dart';

/// Apple TV+ / Infuse / AfuseKt caliber Cinema Detail Screen:
/// - Seamless full-bleed Hero backdrop smoothly dissolving into solid OLED canvas (no muddy wash or seam)
/// - Exact TextPainter-measured expandable overview (never shows "展开全部" when text fits)
/// - High-contrast solid elevated Version / Audio / Subtitle selector panel
/// - Rich Series Seasons with 16:9 Episode Cards (air date, rating, 2-line overview, per-episode detail)
/// - Complete NFO Metadata & External Provider Links (TMDB / IMDb / TVDB / Studios / Tags / Crew / Dates)
/// - Full Media Technical Specs card (Video / Audio / Subtitle streams, bitrate, size, filename)
class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.item,
    required this.appState,
    this.heroTag,
    this.onGenreTap,
  });

  final MediaItemModel item;
  final VedroAppState appState;
  final String? heroTag;
  final ValueChanged<String>? onGenreTap;

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
  bool _episodeListVertical = false;
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

  void _play(MediaItemModel target, {String? sourceId, bool fromBeginning = false, String? localPath}) {
    if (localPath == null && widget.appState.prefs.externalPlayer != 'builtin') {
      _launchExternal(target, sourceId: sourceId);
      return;
    }
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
        localFilePath: localPath,
      )),
    );
  }

  void _openItemDetail(MediaItemModel other) {
    Navigator.of(context).push(
      vedroRoute(DetailScreen(
        item: other,
        appState: widget.appState,
        onGenreTap: widget.onGenreTap,
      )),
    );
  }

  Future<void> _launchExternal(MediaItemModel target, {String? sourceId, String? player}) async {
    try {
      final msg = await widget.appState.launchExternalPlayer(
        target,
        mediaSourceId: sourceId,
        playerOverride: player,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('外部播放器失败：$e')));
      }
    }
  }

  Future<void> _translateOverview() async {
    final text = _item.cleanOverview;
    if (text.isEmpty || _translating) return;
    setState(() => _translating = true);
    try {
      final translated = await widget.appState.translateText(text);
      if (mounted) {
        setState(() => _translatedOverview = translated);
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
        content: Text('已加入下载队列：${target.cardTitle}（设置 → 下载管理）'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _openMoreSheet() {
    final playable = _item.isPlayable ? _item : (_episodes.isNotEmpty ? _episodes.first : null);
    showGlassSheet<void>(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('更多操作', style: TextStyle(color: VedroTheme.fg, fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          if (playable != null) ...[
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded, color: VedroTheme.fg2),
              title: const Text('使用外部播放器打开', style: TextStyle(color: VedroTheme.fg, fontSize: 14)),
              subtitle: const Text('IINA / Infuse / MPV / VLC', style: TextStyle(color: VedroTheme.fg3, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _launchExternal(playable, sourceId: _selectedSourceId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded, color: VedroTheme.fg2),
              title: const Text('离线下载到本地', style: TextStyle(color: VedroTheme.fg, fontSize: 14)),
              onTap: () {
                Navigator.pop(ctx);
                _startDownload();
              },
            ),
          ],
          if (_item.type != 'Person')
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded, color: VedroTheme.fg2),
              title: const Text('加入片单', style: TextStyle(color: VedroTheme.fg, fontSize: 14)),
              onTap: () {
                Navigator.pop(ctx);
                _openPlaylistSheet();
              },
            ),
          if (widget.appState.prefs.isAiReady && _item.cleanOverview.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.auto_awesome_rounded, color: VedroTheme.fg2),
              title: Text(
                _translatedOverview != null ? '还原原始简介' : 'AI 翻译简介',
                style: const TextStyle(color: VedroTheme.fg, fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(ctx);
                if (_translatedOverview != null) {
                  setState(() => _translatedOverview = null);
                } else {
                  _translateOverview();
                }
              },
            ),
        ],
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

  String _localizeStatus(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    switch (raw.trim().toLowerCase()) {
      case 'continuing':
      case 'returning series':
        return '连载中';
      case 'ended':
        return '已完结';
      default:
        return raw.trim();
    }
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
    final accent = Theme.of(context).colorScheme.secondary;
    final showSpecs = widget.appState.prefs.showSpecBadges;
    final overviewText = _translatedOverview?.isNotEmpty == true
        ? _translatedOverview!
        : _item.cleanOverview;
    final tagline = _item.taglines.isNotEmpty ? _item.taglines.first : null;
    final dlTask = widget.appState.findDownloadForItem(_item.id);
    final localReady = dlTask != null && dlTask.status == 'completed' && dlTask.filePath.isNotEmpty;

    final directors = _item.people
        .where((p) => (p.type ?? '').toLowerCase() == 'director')
        .map((p) => p.name)
        .toList();
    final statusLabel = _localizeStatus(_item.status);
    final premiere = fmtIsoDate(_item.premiereDate);

    // Aggregate specs from current item or first episode if Series
    final sampleMediaItem = _item.isPlayable
        ? _item
        : (_episodes.isNotEmpty ? _episodes.first : null);
    final specChips = showSpecs
        ? <String>[
            ..._item.inferredBadges,
            if (src != null) ...src.factChips.where((c) => !_item.inferredBadges.contains(c)),
            if (!_item.isPlayable && sampleMediaItem != null)
              ...sampleMediaItem.inferredBadges.where((c) => !_item.inferredBadges.contains(c)),
          ].take(6).toList()
        : const <String>[];

    // Pick next unwatched episode for Series main Play CTA
    MediaItemModel? nextEpToPlay;
    if (_episodes.isNotEmpty) {
      nextEpToPlay = _episodes.firstWhere(
        (e) => e.resumeProgress > 0.01,
        orElse: () => _episodes.firstWhere(
          (e) => !e.played,
          orElse: () => _episodes.first,
        ),
      );
    }

    final heroMinH = (size.height * (wide ? 0.56 : 0.44)).clamp(340.0, 540.0);

    return Scaffold(
      backgroundColor: VedroTheme.canvas,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Clean Seamless Cinema Hero (dissolves cleanly to solid VedroTheme.canvas — zero seam!)
              SliverToBoxAdapter(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: heroMinH),
                  child: Stack(
                    children: [
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
                                    stops: [0.0, 0.48, 0.78, 1.0],
                                    colors: [
                                      Color(0xF00B0B0D),
                                      Color(0xBA0B0B0D),
                                      Color(0x400B0B0D),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  stops: [0.0, 0.22, 0.60, 0.88, 1.0],
                                  colors: [
                                    Color(0x880B0B0D),
                                    Color(0x180B0B0D),
                                    Color(0xB80B0B0D),
                                    Color(0xF50B0B0D),
                                    VedroTheme.canvas,
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Foreground Hero Content
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          padX,
                          topSafe + (wide ? 96 : 112),
                          padX,
                          24,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 820),
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
                                      color: Color(0xE0FFFFFF),
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),

                              // Title Logo or Display Headline
                              if (logoUrl != null)
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: wide ? 92 : 70,
                                    maxWidth: wide ? 440 : 300,
                                  ),
                                  child: Image.network(
                                    logoUrl,
                                    fit: BoxFit.contain,
                                    alignment: Alignment.centerLeft,
                                    errorBuilder: (_, __, ___) => _TitleHeadline(_item.displayName, wide),
                                  ),
                                )
                              else
                                _TitleHeadline(_item.displayName, wide),

                              if (_item.originalTitle != null &&
                                  _item.originalTitle != _item.name) ...[
                                const SizedBox(height: 5),
                                Text(
                                  _item.originalTitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Color(0xBDFFFFFF), fontSize: 13.5),
                                ),
                              ],

                              const SizedBox(height: 12),

                              // Rich NFO Metadata Strip
                              Wrap(
                                spacing: 10,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (_item.communityRating != null && _item.communityRating! > 0)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFBBF24)),
                                        const SizedBox(width: 3),
                                        Text(
                                          _item.communityRating!.toStringAsFixed(1),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            fontFeatures: [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (_item.criticRating != null && _item.criticRating! > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0x22FB7185),
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(color: const Color(0x55FB7185), width: 0.7),
                                      ),
                                      child: Text(
                                        '媒体 ${_item.criticRating!.round()}%',
                                        style: const TextStyle(
                                          color: Color(0xFFFDA4AF),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          fontFeatures: [FontFeature.tabularFigures()],
                                        ),
                                      ),
                                    ),
                                  if (_item.officialRating != null && _item.officialRating!.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0x18FFFFFF),
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(color: const Color(0x58FFFFFF), width: 0.8),
                                      ),
                                      child: Text(
                                        _item.officialRating!,
                                        style: const TextStyle(
                                          color: Color(0xF0FFFFFF),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  if (statusLabel.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: statusLabel == '连载中'
                                            ? const Color(0x2634D399)
                                            : const Color(0x1CFFFFFF),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Text(
                                        statusLabel,
                                        style: TextStyle(
                                          color: statusLabel == '连载中'
                                              ? const Color(0xFF34D399)
                                              : const Color(0xD8FFFFFF),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  if (premiere.isNotEmpty)
                                    Text(
                                      premiere,
                                      style: const TextStyle(
                                        color: Color(0xEBFFFFFF),
                                        fontSize: 13.5,
                                        fontFeatures: [FontFeature.tabularFigures()],
                                      ),
                                    )
                                  else if (_item.productionYear != null)
                                    Text(
                                      '${_item.productionYear}',
                                      style: const TextStyle(color: Color(0xEBFFFFFF), fontSize: 13.5),
                                    ),
                                  if (!_item.isFolderish && fmtDurationTicks(_item.runTimeTicks).isNotEmpty)
                                    Text(
                                      fmtDurationTicks(_item.runTimeTicks),
                                      style: const TextStyle(color: Color(0xEBFFFFFF), fontSize: 13.5),
                                    ),
                                  if (_item.isSeries) ...[
                                    if (_seasons.isNotEmpty || (_item.childCount ?? 0) > 0)
                                      Text(
                                        '共 ${_seasons.isNotEmpty ? _seasons.length : _item.childCount} 季${(_item.recursiveItemCount ?? 0) > 0 ? ' · ${_item.recursiveItemCount} 集' : ''}',
                                        style: const TextStyle(color: Color(0xEBFFFFFF), fontSize: 13.5),
                                      ),
                                    if (fmtDurationTicks(_item.runTimeTicks).isNotEmpty)
                                      Text(
                                        '单集约 ${fmtDurationTicks(_item.runTimeTicks)}',
                                        style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 13),
                                      ),
                                  ],
                                  if (_item.productionLocations.isNotEmpty)
                                    Text(
                                      _item.productionLocations.take(2).join(' / '),
                                      style: const TextStyle(color: Color(0xD8FFFFFF), fontSize: 13),
                                    ),
                                  for (final g in _item.genres.take(6))
                                    GestureDetector(
                                      onTap: widget.onGenreTap == null ? null : () => widget.onGenreTap!(g),
                                      child: MouseRegion(
                                        cursor: widget.onGenreTap != null
                                            ? SystemMouseCursors.click
                                            : MouseCursor.defer,
                                        child: Text(
                                          g,
                                          style: TextStyle(
                                            color: const Color(0xE8FFFFFF),
                                            fontSize: 13.5,
                                            decoration: widget.onGenreTap != null
                                                ? TextDecoration.underline
                                                : TextDecoration.none,
                                            decorationColor: const Color(0x77FFFFFF),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),

                              if (specChips.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                SpecGlyphRow(specs: specChips),
                              ],

                              if (tagline != null) ...[
                                const SizedBox(height: 14),
                                Text(
                                  tagline,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                              ],

                              // Exact TextPainter-measured overview: NEVER shows "展开全部" when short!
                              if (overviewText.isNotEmpty) ...[
                                SizedBox(height: tagline != null ? 6 : 14),
                                _ExpandableOverview(
                                  text: overviewText,
                                  collapsedLines: wide ? 4 : 3,
                                  accent: accent,
                                  aiReady: widget.appState.prefs.isAiReady,
                                  translating: _translating,
                                  isTranslated: _translatedOverview != null,
                                  onTranslateToggle: _translatedOverview != null
                                      ? () => setState(() => _translatedOverview = null)
                                      : _translateOverview,
                                ),
                              ],

                              const SizedBox(height: 22),

                              // Primary Play Pill + Circular Action Buttons
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (_item.isPlayable)
                                    _ProgressPlayPill(
                                      label: localReady
                                          ? '播放离线缓存'
                                          : (_item.playbackPositionTicks > 0
                                              ? '继续 ${fmtDurationTicks(_item.playbackPositionTicks)}'
                                              : '立即播放'),
                                      progress: _item.resumeProgress,
                                      accent: accent,
                                      onTap: () => _play(
                                        _item,
                                        sourceId: _selectedSourceId,
                                        localPath: localReady ? dlTask.filePath : null,
                                      ),
                                    )
                                  else if (nextEpToPlay != null)
                                    _ProgressPlayPill(
                                      label: nextEpToPlay.resumeProgress > 0.01
                                          ? '继续 ${nextEpToPlay.episodeCode ?? nextEpToPlay.displayName}'
                                          : '播放 ${nextEpToPlay.episodeCode ?? '第 1 集'}',
                                      progress: nextEpToPlay.resumeProgress,
                                      accent: accent,
                                      onTap: () => _play(nextEpToPlay!),
                                    ),

                                  if (_item.isPlayable && _item.playbackPositionTicks > 0)
                                    _CircleActionButton(
                                      icon: Icons.replay_rounded,
                                      tooltip: '从头播放',
                                      onTap: () => _play(
                                        _item,
                                        sourceId: _selectedSourceId,
                                        fromBeginning: true,
                                      ),
                                    ),
                                  if (_item.type != 'Person')
                                    _CircleActionButton(
                                      icon: _item.played
                                          ? Icons.check_circle_rounded
                                          : Icons.check_circle_outline_rounded,
                                      active: _item.played,
                                      tooltip: _item.played ? '已看（点击取消）' : '标为已看',
                                      onTap: () async {
                                        await widget.appState.togglePlayed(_item);
                                        await _loadDetails();
                                      },
                                    ),
                                  _CircleActionButton(
                                    icon: _item.isFavorite
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    iconColor: _item.isFavorite ? VedroTheme.danger : Colors.white,
                                    tooltip: _item.isFavorite ? '取消收藏' : '收藏',
                                    onTap: () async {
                                      await widget.appState.toggleFavorite(_item);
                                      await _loadDetails();
                                    },
                                  ),
                                  if (_item.isPlayable || _episodes.isNotEmpty)
                                    _CircleActionButton(
                                      icon: localReady
                                          ? Icons.download_done_rounded
                                          : Icons.download_rounded,
                                      iconColor: localReady ? const Color(0xFF34D399) : Colors.white,
                                      tooltip: localReady ? '已离线下载' : '离线下载',
                                      onTap: localReady
                                          ? () => _play(_item, localPath: dlTask.filePath)
                                          : _startDownload,
                                    ),
                                  _CircleActionButton(
                                    icon: Icons.more_horiz_rounded,
                                    tooltip: '更多（外部播放器 / 片单 / AI 翻译）',
                                    onTap: _openMoreSheet,
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

              // Body Content on Pure Deep OLED Canvas (razor-sharp contrast)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(padX, 6, padX, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. High-Contrast Version / Audio / Subtitle Selector (for Movies & Episodes)
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

                      // 2. TV Series Seasons & Rich Episode Cards
                      if (_seasons.isNotEmpty) ...[
                        Row(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: _seasons.map((s) {
                                    final active = s.id == (_selectedSeasonId ?? _seasons.first.id);
                                    return GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => _loadEpisodes(s.id),
                                      child: Container(
                                        margin: const EdgeInsets.only(right: 22),
                                        padding: const EdgeInsets.only(bottom: 8),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            bottom: BorderSide(
                                              color: active ? accent : Colors.transparent,
                                              width: 2.5,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          s.name,
                                          style: TextStyle(
                                            color: active ? Colors.white : VedroTheme.fg3,
                                            fontSize: 16,
                                            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                            Text(
                              '共 ${_episodes.length} 集',
                              style: const TextStyle(color: VedroTheme.fg3, fontSize: 12.5),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: _episodeListVertical ? '切换横向卡片' : '切换详情列表',
                              icon: Icon(
                                _episodeListVertical
                                    ? Icons.view_carousel_outlined
                                    : Icons.view_agenda_outlined,
                                size: 19,
                                color: VedroTheme.fg2,
                              ),
                              onPressed: () =>
                                  setState(() => _episodeListVertical = !_episodeListVertical),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (!_episodeListVertical)
                          SizedBox(
                            height: wide ? 268 : 232,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              clipBehavior: Clip.none,
                              itemCount: _episodes.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 14),
                              itemBuilder: (_, idx) => _EpisodeHorizontalCard(
                                episode: _episodes[idx],
                                appState: widget.appState,
                                width: wide ? 264 : 216,
                                accent: accent,
                                onTap: () => _play(_episodes[idx]),
                                onOpenDetail: () => _openItemDetail(_episodes[idx]),
                              ),
                            ),
                          )
                        else
                          ..._episodes.map((ep) => _EpisodeRow(
                                episode: ep,
                                appState: widget.appState,
                                onTap: () => _play(ep),
                                onOpenDetail: () => _openItemDetail(ep),
                              )),
                        const SizedBox(height: 28),
                      ],

                      // 3. Cast & Crew Rail
                      if (_item.people.isNotEmpty) ...[
                        Row(
                          children: [
                            const Text(
                              '演职人员',
                              style: TextStyle(
                                color: VedroTheme.fg,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const Spacer(),
                            if (directors.isNotEmpty)
                              Text(
                                '导演：${directors.take(2).join(' · ')}',
                                style: const TextStyle(color: VedroTheme.fg2, fontSize: 13),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 144,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            clipBehavior: Clip.none,
                            itemCount: _item.people.take(28).length,
                            separatorBuilder: (_, __) => const SizedBox(width: 14),
                            itemBuilder: (_, idx) {
                              final p = _item.people[idx];
                              final avatarUrl = p.primaryImageTag != null
                                  ? widget.appState.buildImageUrl(
                                      p.id,
                                      type: 'Primary',
                                      tag: p.primaryImageTag,
                                      maxWidth: 240,
                                    )
                                  : '';
                              return SizedBox(
                                width: 88,
                                child: PressableScale(
                                  onTap: () => _openItemDetail(MediaItemModel(
                                    id: p.id,
                                    name: p.name,
                                    type: 'Person',
                                    primaryImageTag: p.primaryImageTag,
                                  )),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 84,
                                        height: 84,
                                        foregroundDecoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: const Color(0x26FFFFFF), width: 0.8),
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(14),
                                          color: VedroTheme.surface2,
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            GeneratedArt(seed: p.id, label: p.name),
                                            if (avatarUrl.isNotEmpty)
                                              FadeNetworkImage(
                                                url: avatarUrl,
                                                alignment: const Alignment(0, -0.35),
                                              ),
                                          ],
                                        ),
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
                                        (p.role ?? '').isNotEmpty ? p.role! : (p.type ?? ''),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: VedroTheme.fg3, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 28),
                      ],

                      // 4. Complete NFO Metadata & External Provider Links (shown for Series, Movies & Episodes!)
                      if (_item.type != 'Person') ...[
                        _NfoMetadataSection(
                          item: _item,
                          seasonsCount: _seasons.isNotEmpty ? _seasons.length : _item.childCount,
                          episodesCount: _item.recursiveItemCount ?? (_episodes.isNotEmpty ? _episodes.length : null),
                          statusLabel: statusLabel,
                          appState: widget.appState,
                          onGenreTap: widget.onGenreTap,
                        ),
                        const SizedBox(height: 24),
                      ],

                      // 5. Full Media File Technical Specs (for playable items)
                      if (src != null) ...[
                        _MediaSpecsSection(source: src, itemPath: _item.path),
                        const SizedBox(height: 24),
                      ],

                      // 6. Person Credits Grid
                      if (_item.type == 'Person' && _personCredits.isNotEmpty) ...[
                        Text(
                          '参与作品 (${_personCredits.length})',
                          style: const TextStyle(
                            color: VedroTheme.fg,
                            fontSize: 19,
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
                                    width: wide ? 152 : 110,
                                    onTap: () => _openItemDetail(c),
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 24),
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
                    onItemTap: _openItemDetail,
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

          // Floating glass Back Pill aligned beside macOS traffic lights
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
                color: const Color(0x88141418),
                borderColor: const Color(0x32FFFFFF),
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: Colors.white),
                    SizedBox(width: 5),
                    Text(
                      '返回',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Measures real rendered line overflow via TextPainter so "展开全部" NEVER appears on short text!
class _ExpandableOverview extends StatefulWidget {
  const _ExpandableOverview({
    required this.text,
    required this.collapsedLines,
    required this.accent,
    required this.aiReady,
    required this.translating,
    required this.isTranslated,
    required this.onTranslateToggle,
  });

  final String text;
  final int collapsedLines;
  final Color accent;
  final bool aiReady;
  final bool translating;
  final bool isTranslated;
  final VoidCallback onTranslateToggle;

  @override
  State<_ExpandableOverview> createState() => _ExpandableOverviewState();
}

class _ExpandableOverviewState extends State<_ExpandableOverview> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: Color(0xF0F1F2F6),
      fontSize: 14.5,
      height: 1.72,
      letterSpacing: 0.1,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: widget.collapsedLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topLeft,
              child: Text(
                widget.text,
                maxLines: _expanded ? null : widget.collapsedLines,
                overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                style: style,
              ),
            ),
            if (overflows || widget.aiReady) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 14,
                children: [
                  if (overflows)
                    GestureDetector(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Text(
                          _expanded ? '收起简介' : '展开全部',
                          style: TextStyle(
                            color: widget.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  if (widget.aiReady)
                    GestureDetector(
                      onTap: widget.onTranslateToggle,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome_rounded, size: 13.5, color: widget.accent),
                            const SizedBox(width: 4),
                            Text(
                              widget.translating
                                  ? 'AI 翻译中…'
                                  : (widget.isTranslated ? '显示原文' : 'AI 翻译简介'),
                              style: TextStyle(
                                color: widget.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Complete Apple TV+ / Infuse style NFO Metadata Section (displays every present NFO field cleanly).
class _NfoMetadataSection extends StatelessWidget {
  const _NfoMetadataSection({
    required this.item,
    required this.seasonsCount,
    required this.episodesCount,
    required this.statusLabel,
    required this.appState,
    this.onGenreTap,
  });

  final MediaItemModel item;
  final int? seasonsCount;
  final int? episodesCount;
  final String statusLabel;
  final VedroAppState appState;
  final ValueChanged<String>? onGenreTap;

  @override
  Widget build(BuildContext context) {
    final directors = item.people
        .where((p) => (p.type ?? '').toLowerCase() == 'director')
        .map((p) => p.name)
        .toList();
    final writers = item.people
        .where((p) => (p.type ?? '').toLowerCase() == 'writer')
        .map((p) => p.name)
        .toList();
    final producers = item.people
        .where((p) => (p.type ?? '').toLowerCase() == 'producer')
        .map((p) => p.name)
        .toList();

    final facts = <(String label, String value)>[
      if (item.originalTitle != null && item.originalTitle!.trim().isNotEmpty)
        ('原名', item.originalTitle!.trim()),
      if (fmtIsoDate(item.premiereDate).isNotEmpty)
        (item.isSeries ? '首播日期' : '上映日期', fmtIsoDate(item.premiereDate)),
      if (fmtIsoDate(item.endDate).isNotEmpty) ('完结日期', fmtIsoDate(item.endDate)),
      if (statusLabel.isNotEmpty) ('连载状态', statusLabel),
      if (item.isSeries && ((seasonsCount ?? 0) > 0 || (episodesCount ?? 0) > 0))
        (
          '季数 / 集数',
          [
            if ((seasonsCount ?? 0) > 0) '$seasonsCount 季',
            if ((episodesCount ?? 0) > 0) '$episodesCount 集',
          ].join(' · '),
        ),
      if (fmtDurationTicks(item.runTimeTicks).isNotEmpty)
        (item.isSeries ? '单集时长' : '片长', fmtDurationTicks(item.runTimeTicks)),
      if (item.officialRating != null && item.officialRating!.trim().isNotEmpty)
        ('内容分级', item.officialRating!.trim()),
      if (item.communityRating != null && item.communityRating! > 0)
        ('社区评分', '${item.communityRating!.toStringAsFixed(1)} / 10'),
      if (item.criticRating != null && item.criticRating! > 0)
        ('媒体好评率', '${item.criticRating!.round()}%'),
      if (item.productionLocations.isNotEmpty)
        ('制片国家 / 地区', item.productionLocations.join('、')),
      if (item.studios.isNotEmpty) ('出品方 / 电视网', item.studios.join('、')),
      if (item.airDays.isNotEmpty || (item.airTime ?? '').isNotEmpty)
        ('播出时段', [...item.airDays, if ((item.airTime ?? '').isNotEmpty) item.airTime!].join(' ')),
      if (directors.isNotEmpty) ('导演', directors.take(4).join('、')),
      if (writers.isNotEmpty) ('编剧', writers.take(4).join('、')),
      if (producers.isNotEmpty) ('制片人', producers.take(4).join('、')),
      if (fmtIsoDate(item.dateCreated).isNotEmpty) ('入库日期', fmtIsoDate(item.dateCreated)),
      if ((item.sourceFolderCount ?? 0) > 1) ('合并源目录', '${item.sourceFolderCount} 个来源文件夹'),
    ];

    // Build clickable external links from ExternalUrls + ProviderIds (TMDB / IMDb / TVDB / Douban)
    final links = <(String label, String? url, String displayId)>[];
    final seenProviders = <String>{};
    for (final ext in item.externalUrls) {
      if (ext.name.isNotEmpty && ext.url.isNotEmpty) {
        seenProviders.add(ext.name.toLowerCase());
        links.add((ext.name, ext.url, ext.name));
      }
    }
    item.providerIds.forEach((rawKey, rawVal) {
      final k = rawKey.trim();
      final v = rawVal.trim();
      if (k.isEmpty || v.isEmpty) return;
      final lower = k.toLowerCase();
      if (seenProviders.contains(lower)) return;
      String? url;
      String label = k.toUpperCase();
      if (lower == 'tmdb') {
        label = 'TMDB';
        url = item.isSeries
            ? 'https://www.themoviedb.org/tv/$v'
            : 'https://www.themoviedb.org/movie/$v';
      } else if (lower == 'imdb') {
        label = 'IMDb';
        url = 'https://www.imdb.com/title/$v/';
      } else if (lower == 'tvdb') {
        label = 'TVDB';
        url = 'https://thetvdb.com/dereferrer/series/$v';
      } else if (lower == 'douban') {
        label = '豆瓣';
        url = 'https://movie.douban.com/subject/$v/';
      }
      links.add((label, url, '$label: $v'));
    });

    if (facts.isEmpty && item.tags.isEmpty && links.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF13141A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1DFFFFFF), width: 0.85),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 17, color: VedroTheme.fg2),
              SizedBox(width: 8),
              Text(
                '影片资料与 NFO 信息',
                style: TextStyle(
                  color: VedroTheme.fg,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final cols = constraints.maxWidth >= 720 ? 3 : (constraints.maxWidth >= 420 ? 2 : 1);
                const gap = 16.0;
                final cellW = (constraints.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: 14,
                  children: facts.map((f) {
                    return SizedBox(
                      width: cellW,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.$1,
                            style: const TextStyle(
                              color: VedroTheme.fg3,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 3),
                          SelectableText(
                            f.$2,
                            style: const TextStyle(
                              color: VedroTheme.fg,
                              fontSize: 13.5,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
          if (item.tags.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
            const Text('NFO 标签', style: TextStyle(color: VedroTheme.fg3, fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: item.tags.take(24).map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D1F27),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x1EFFFFFF), width: 0.7),
                  ),
                  child: Text(
                    '# $tag',
                    style: const TextStyle(color: VedroTheme.fg2, fontSize: 12),
                  ),
                );
              }).toList(),
            ),
          ],
          if (links.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
            const Text('外部资料索引', style: TextStyle(color: VedroTheme.fg3, fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: links.map((entry) {
                final (label, url, displayId) = entry;
                return PressableScale(
                  onTap: () {
                    if (url != null) {
                      appState.openExternalUrl(url);
                    } else {
                      Clipboard.setData(ClipboardData(text: displayId));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已复制 $displayId')),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1E28),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: const Color(0x28FFFFFF), width: 0.7),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayId,
                          style: const TextStyle(
                            color: VedroTheme.fg,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (url != null) ...[
                          const SizedBox(width: 5),
                          const Icon(Icons.open_in_new_rounded, size: 12.5, color: VedroTheme.fg3),
                        ],
                      ],
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

class _MediaSpecsSection extends StatelessWidget {
  const _MediaSpecsSection({required this.source, this.itemPath});
  final MediaSourceModel source;
  final String? itemPath;

  @override
  Widget build(BuildContext context) {
    final videos = source.videoStreams;
    final audios = source.audioStreams;
    final subs = source.subtitleStreams;
    final filePath = source.path?.isNotEmpty == true ? source.path : itemPath;

    final hasAnything = videos.isNotEmpty ||
        audios.isNotEmpty ||
        subs.isNotEmpty ||
        (filePath != null && filePath.isNotEmpty) ||
        (source.size ?? 0) > 0;
    if (!hasAnything) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF13141A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1DFFFFFF), width: 0.85),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.memory_rounded, size: 17, color: VedroTheme.fg2),
              const SizedBox(width: 8),
              const Text(
                '媒体文件规格',
                style: TextStyle(color: VedroTheme.fg, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (source.container != null && source.container!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0x18FFFFFF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    [
                      source.container!.toUpperCase(),
                      if (fmtFileSize(source.size).isNotEmpty) fmtFileSize(source.size),
                      if ((source.bitrate ?? 0) > 0)
                        '${(source.bitrate! / 1000000).toStringAsFixed(1)} Mbps',
                    ].join(' · '),
                    style: const TextStyle(
                      color: VedroTheme.fg2,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (videos.isNotEmpty)
            _SpecGroup('视频流', videos.map((v) => v.detailedSpec).toList()),
          if (audios.isNotEmpty)
            _SpecGroup('音频流 (${audios.length})', audios.map((a) => a.detailedSpec).toList()),
          if (subs.isNotEmpty)
            _SpecGroup('字幕流 (${subs.length})', subs.take(12).map((s) => s.detailedSpec).toList()),
          if (filePath != null && filePath.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('文件路径', style: TextStyle(color: VedroTheme.fg3, fontSize: 11.5)),
            const SizedBox(height: 3),
            SelectableText(
              filePath,
              style: const TextStyle(
                color: VedroTheme.fg2,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SpecGroup extends StatelessWidget {
  const _SpecGroup(this.label, this.lines);
  final String label;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: VedroTheme.fg3, fontSize: 11.5, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                line,
                style: const TextStyle(
                  color: VedroTheme.fg,
                  fontSize: 13,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TitleHeadline extends StatelessWidget {
  const _TitleHeadline(this.text, this.wide);
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
        fontSize: wide ? 36 : 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.7,
        height: 1.12,
      ),
    );
  }
}

class _ProgressPlayPill extends StatelessWidget {
  const _ProgressPlayPill({
    required this.label,
    required this.progress,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final double progress;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      hoverScale: 1.03,
      pressScale: 0.96,
      child: Container(
        height: 44,
        constraints: const BoxConstraints(minWidth: 168),
        decoration: BoxDecoration(
          color: const Color(0xF8FFFFFF),
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(color: Color(0x55000000), blurRadius: 18, offset: Offset(0, 6)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (progress > 0.02)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress.clamp(0.08, 1.0),
                  child: Container(color: accent.withValues(alpha: 0.28)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
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
          ],
        ),
      ),
    );
  }
}

class _CircleActionButton extends StatelessWidget {
  const _CircleActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return Tooltip(
      message: tooltip,
      child: PressableScale(
        onTap: onTap,
        hoverScale: 1.06,
        pressScale: 0.92,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? accent.withValues(alpha: 0.28) : const Color(0xCC181920),
            border: Border.all(
              color: active ? accent.withValues(alpha: 0.8) : const Color(0x36FFFFFF),
              width: 0.9,
            ),
          ),
          child: Icon(icon, size: 20, color: active ? accent : iconColor),
        ),
      ),
    );
  }
}

class _EpisodeHorizontalCard extends StatefulWidget {
  const _EpisodeHorizontalCard({
    required this.episode,
    required this.appState,
    required this.width,
    required this.accent,
    required this.onTap,
    required this.onOpenDetail,
  });

  final MediaItemModel episode;
  final VedroAppState appState;
  final double width;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onOpenDetail;

  @override
  State<_EpisodeHorizontalCard> createState() => _EpisodeHorizontalCardState();
}

class _EpisodeHorizontalCardState extends State<_EpisodeHorizontalCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ep = widget.episode;
    final hasProgress = ep.resumeProgress > 0.01;
    final airDate = fmtIsoDate(ep.premiereDate);
    final dur = fmtDurationTicks(ep.runTimeTicks);
    final epOverview = ep.cleanOverview;

    return SizedBox(
      width: widget.width,
      child: PressableScale(
        onTap: widget.onTap,
        onHoverChanged: (v) => setState(() => _hovered = v),
        hoverScale: 1.02,
        pressScale: 0.97,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: VedroTheme.surface2,
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _hovered
                        ? Colors.white
                        : (hasProgress ? widget.accent.withValues(alpha: 0.85) : VedroTheme.line),
                    width: _hovered || hasProgress ? 1.5 : 0.8,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    VedroArtwork(
                      item: ep,
                      appState: widget.appState,
                      landscape: true,
                      width: 480,
                    ),
                    // Top-left episode number pill
                    if (ep.indexNumber != null)
                      Positioned(
                        top: 7,
                        left: 7,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xC00B0B0D),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'E${ep.indexNumber!.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                    // Top-right Episode Detail / Specs button
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (ep.played)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: CircleAvatar(
                                radius: 10,
                                backgroundColor: Color(0xC00B0B0D),
                                child: Icon(Icons.check_rounded, size: 12, color: Colors.white),
                              ),
                            ),
                          Tooltip(
                            message: '本集详情 / 版本 / 规格',
                            child: GestureDetector(
                              onTap: widget.onOpenDetail,
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: const Color(0xC00B0B0D),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0x38FFFFFF), width: 0.6),
                                ),
                                child: const Icon(Icons.info_outline_rounded, size: 13, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasProgress)
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 7,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: ep.resumeProgress,
                            minHeight: 3,
                            backgroundColor: const Color(0x45FFFFFF),
                            color: widget.accent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${ep.indexNumber != null ? '${ep.indexNumber}. ' : ''}${ep.displayName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hasProgress ? widget.accent : VedroTheme.fg,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (airDate.isNotEmpty) airDate,
                if (dur.isNotEmpty) dur,
                if (ep.communityRating != null && ep.communityRating! > 0)
                  '★ ${ep.communityRating!.toStringAsFixed(1)}',
                if (ep.versionCount > 1) '${ep.versionCount} 版本',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: VedroTheme.fg3,
                fontSize: 11.5,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            if (epOverview.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                epOverview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: VedroTheme.fg2, fontSize: 12, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Crystal-clear high-contrast Version / Audio / Subtitle selector panel.
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
        color: const Color(0xFF14151C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x26FFFFFF), width: 0.9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sources.length > 1) ...[
            Row(
              children: [
                const Icon(Icons.layers_outlined, size: 16, color: VedroTheme.fg2),
                const SizedBox(width: 7),
                Text(
                  '选择片源版本 (${sources.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: sources.map((s) {
                final on = s.id == active.id;
                final subMeta = [
                  if (s.container != null && s.container!.isNotEmpty) s.container!.toUpperCase(),
                  if (fmtFileSize(s.size).isNotEmpty) fmtFileSize(s.size),
                  if ((s.bitrate ?? 0) > 0) '${(s.bitrate! / 1000000).toStringAsFixed(1)} Mbps',
                  if (s.subtitleStreams.isNotEmpty) '${s.subtitleStreams.length} 字幕',
                ].join(' · ');
                return PressableScale(
                  onTap: () => onSelectSource(s.id),
                  hoverScale: 1.015,
                  pressScale: 0.97,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: on ? accent.withValues(alpha: 0.22) : const Color(0xFF1E2029),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: on ? accent : const Color(0x2EFFFFFF),
                        width: on ? 1.4 : 0.85,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (on) ...[
                          Icon(Icons.check_circle_rounded, size: 16, color: accent),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                s.name?.isNotEmpty == true ? s.name! : (s.container?.toUpperCase() ?? '原画'),
                                style: TextStyle(
                                  color: on ? Colors.white : const Color(0xFFE5E7EE),
                                  fontSize: 13.5,
                                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                                ),
                              ),
                              if (subMeta.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  subMeta,
                                  style: TextStyle(
                                    color: on ? const Color(0xDCE6EBF5) : const Color(0xFF9EA2B0),
                                    fontSize: 11.5,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ] else
            Row(
              children: [
                const Icon(Icons.high_quality_outlined, size: 16, color: VedroTheme.fg2),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    active.displayLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),

          if (audios.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              '音轨 (${audios.length})',
              style: const TextStyle(color: Color(0xFFB5B9C6), fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: audios.map((a) {
                final on = selectedAudioIndex == a.index;
                return GestureDetector(
                  onTap: () => onSelectAudio(on ? null : a.index),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6.5),
                      decoration: BoxDecoration(
                        color: on ? accent.withValues(alpha: 0.22) : const Color(0xFF1E2029),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: on ? accent : const Color(0x28FFFFFF),
                          width: on ? 1.2 : 0.8,
                        ),
                      ),
                      child: Text(
                        a.label,
                        style: TextStyle(
                          color: on ? Colors.white : const Color(0xFFDCE0EA),
                          fontSize: 12.5,
                          fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                        ),
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
              style: const TextStyle(color: Color(0xFFB5B9C6), fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: subs.take(16).map((s) {
                final on = selectedSubtitleIndex == s.index;
                return GestureDetector(
                  onTap: () => onSelectSubtitle(on ? null : s.index),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6.5),
                      decoration: BoxDecoration(
                        color: on ? accent.withValues(alpha: 0.22) : const Color(0xFF1E2029),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: on ? accent : const Color(0x28FFFFFF),
                          width: on ? 1.2 : 0.8,
                        ),
                      ),
                      child: Text(
                        s.label,
                        style: TextStyle(
                          color: on ? Colors.white : const Color(0xFFDCE0EA),
                          fontSize: 12.5,
                          fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                        ),
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
    required this.onOpenDetail,
  });

  final MediaItemModel episode;
  final VedroAppState appState;
  final VoidCallback onTap;
  final VoidCallback onOpenDetail;

  @override
  State<_EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends State<_EpisodeRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ep = widget.episode;
    final dur = fmtDurationTicks(ep.runTimeTicks);
    final airDate = fmtIsoDate(ep.premiereDate);
    final epOverview = ep.cleanOverview;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PressableScale(
        onTap: widget.onTap,
        onHoverChanged: (v) => setState(() => _hovered = v),
        hoverScale: 1.006,
        pressScale: 0.985,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF1B1C24) : const Color(0xFF13141A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovered ? VedroTheme.lineStrong : const Color(0x1CFFFFFF),
              width: 0.8,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 164,
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
                        if (ep.played)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF34D399)),
                          ),
                        Tooltip(
                          message: '查看本集详情与媒体规格',
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.info_outline_rounded, size: 18, color: VedroTheme.fg3),
                            onPressed: widget.onOpenDetail,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (airDate.isNotEmpty) airDate,
                        if (dur.isNotEmpty) dur,
                        if (ep.communityRating != null && ep.communityRating! > 0)
                          '★ ${ep.communityRating!.toStringAsFixed(1)}',
                        if (ep.versionCount > 1) '${ep.versionCount} 个版本',
                      ].join(' · '),
                      style: const TextStyle(
                        color: VedroTheme.fg3,
                        fontSize: 12,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (epOverview.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        epOverview,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: VedroTheme.fg2,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
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
}
