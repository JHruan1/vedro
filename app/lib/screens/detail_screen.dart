import 'dart:io';
import 'dart:ui';

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

/// AfuseKt 3.4 / Infuse / Apple TV+ caliber Cinema Detail Screen:
/// - Full-page adaptive ambient backdrop canvas dissolving smoothly behind all sections
/// - Progress-filled primary Play pill + sleek circular action buttons (no cluttered text walls)
/// - Bold Tagline + HTML-cleaned high-contrast Overview + AI Translate + clickable underlined Genres
/// - Series Seasons with underline tabs + Horizontal 16:9 Episode Cards (toggleable to vertical list)
/// - Compact rounded-square Cast & Crew portraits with Director label right-aligned on header
/// - Live Offline Download status & direct local playback + External Player launcher
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
  bool _overviewExpanded = false;
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
        .take(2)
        .toList();

    final specChips = showSpecs
        ? <String>[
            ..._item.inferredBadges,
            if (src != null) ...src.factChips.where((c) => !_item.inferredBadges.contains(c)),
          ].take(5).toList()
        : const <String>[];

    final backdropArt = widget.appState.backdropArt(_item, width: 1920);
    final heroMinH = (size.height * (wide ? 0.56 : 0.46)).clamp(350.0, 560.0);

    return Scaffold(
      backgroundColor: VedroTheme.canvas,
      body: Stack(
        children: [
          // Adaptive full-page atmospheric ambient backdrop behind the entire page (AfuseKt 3.4 style!)
          if (backdropArt != null)
            Positioned.fill(
              child: IgnorePointer(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
                  child: Opacity(
                    opacity: 0.24,
                    child: FadeNetworkImage(url: backdropArt.url, fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.45, 1.0],
                    colors: [
                      Colors.transparent,
                      VedroTheme.canvas.withValues(alpha: 0.78),
                      VedroTheme.canvas.withValues(alpha: 0.94),
                    ],
                  ),
                ),
              ),
            ),
          ),

          CustomScrollView(
            slivers: [
              // Crisp Top Cinema Hero
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
                                    stops: [0.0, 0.52, 0.85, 1.0],
                                    colors: [
                                      Color(0xDE0B0B0D),
                                      Color(0x940B0B0D),
                                      Color(0x280B0B0D),
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
                                  stops: [0.0, 0.28, 0.65, 1.0],
                                  colors: [
                                    Color(0x780B0B0D),
                                    Colors.transparent,
                                    Color(0xB80B0B0D),
                                    Color(0xEE0B0B0D),
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
                          topSafe + (wide ? 110 : 120),
                          padX,
                          24,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 780),
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

                              // Transparent Title Logo or bold Display Title
                              if (logoUrl != null)
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: wide ? 96 : 72,
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
                                  style: const TextStyle(color: Color(0xB8FFFFFF), fontSize: 13.5),
                                ),
                              ],

                              const SizedBox(height: 12),

                              // Compact AfuseKt Metadata Line (★ Rating · [PG] · Year · Duration · Specs · Clickable Genres)
                              Wrap(
                                spacing: 10,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (_item.communityRating != null)
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
                                  if (_item.officialRating != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(color: const Color(0x66FFFFFF), width: 0.9),
                                      ),
                                      child: Text(
                                        _item.officialRating!,
                                        style: const TextStyle(
                                          color: Color(0xE8FFFFFF),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  if (_item.productionYear != null)
                                    Text(
                                      '${_item.productionYear}',
                                      style: const TextStyle(color: Color(0xE8FFFFFF), fontSize: 13.5),
                                    ),
                                  if (!_item.isFolderish && fmtDurationTicks(_item.runTimeTicks).isNotEmpty)
                                    Text(
                                      fmtDurationTicks(_item.runTimeTicks),
                                      style: const TextStyle(color: Color(0xE8FFFFFF), fontSize: 13.5),
                                    ),
                                  if (_item.isSeries && (_item.childCount ?? 0) > 0)
                                    Text(
                                      '共 ${_item.childCount} 季${(_item.recursiveItemCount ?? 0) > 0 ? ' · ${_item.recursiveItemCount} 集' : ''}',
                                      style: const TextStyle(color: Color(0xE8FFFFFF), fontSize: 13.5),
                                    ),
                                  for (final g in _item.genres.take(5))
                                    GestureDetector(
                                      onTap: widget.onGenreTap == null ? null : () => widget.onGenreTap!(g),
                                      child: MouseRegion(
                                        cursor: widget.onGenreTap != null
                                            ? SystemMouseCursors.click
                                            : MouseCursor.defer,
                                        child: Text(
                                          g,
                                          style: TextStyle(
                                            color: const Color(0xE0FFFFFF),
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

                              // Tagline + Crystal-clear Overview right in the primary hero reading zone!
                              if (tagline != null) ...[
                                const SizedBox(height: 16),
                                Text(
                                  tagline,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                              ],
                              if (overviewText.isNotEmpty) ...[
                                SizedBox(height: tagline != null ? 6 : 14),
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
                                      color: Color(0xF0F1F2F6),
                                      fontSize: 14.5,
                                      height: 1.7,
                                      letterSpacing: 0.1,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 14,
                                  children: [
                                    if (overviewText.length > 96)
                                      GestureDetector(
                                        onTap: () => setState(() => _overviewExpanded = !_overviewExpanded),
                                        child: Text(
                                          _overviewExpanded ? '收起' : '展开全部',
                                          style: TextStyle(
                                            color: accent,
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
                                            Icon(Icons.auto_awesome_rounded, size: 13.5, color: accent),
                                            const SizedBox(width: 4),
                                            Text(
                                              _translating
                                                  ? 'AI 翻译中…'
                                                  : (_translatedOverview != null ? '显示原文' : 'AI 翻译简介'),
                                              style: TextStyle(
                                                color: accent,
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

                              // AfuseKt Signature Row: Progress-Filled Primary Play Pill + Clean Circular Icon Buttons!
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
                                              : '播放'),
                                      progress: _item.resumeProgress,
                                      accent: accent,
                                      onTap: () => _play(
                                        _item,
                                        sourceId: _selectedSourceId,
                                        localPath: localReady ? dlTask.filePath : null,
                                      ),
                                    )
                                  else if (_episodes.isNotEmpty)
                                    _ProgressPlayPill(
                                      label: '播放 ${_episodes.first.episodeCode ?? '第 1 集'}',
                                      progress: _episodes.first.resumeProgress,
                                      accent: accent,
                                      onTap: () => _play(_episodes.first),
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

              // Body Sections over Ambient Canvas
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(padX, 8, padX, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // TV Series Seasons & Horizontal 16:9 Episode Cards (AfuseKt 9_ref.png style!)
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
                                            fontSize: 15.5,
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
                              '${_episodes.length} 集',
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
                            height: wide ? 214 : 186,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              clipBehavior: Clip.none,
                              itemCount: _episodes.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 14),
                              itemBuilder: (_, idx) => _EpisodeHorizontalCard(
                                episode: _episodes[idx],
                                appState: widget.appState,
                                width: wide ? 246 : 206,
                                accent: accent,
                                onTap: () => _play(_episodes[idx]),
                              ),
                            ),
                          )
                        else
                          ..._episodes.map((ep) => _EpisodeRow(
                                episode: ep,
                                appState: widget.appState,
                                onTap: () => _play(ep),
                              )),
                        const SizedBox(height: 28),
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

                      // Compact Rounded-Square Cast & Crew with right-aligned Director (AfuseKt 3_wide1 / 7_ref style!)
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
                                '导演: ${directors.join(' · ')}',
                                style: const TextStyle(color: Color(0xC8FFFFFF), fontSize: 13),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 144,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            clipBehavior: Clip.none,
                            itemCount: _item.people.take(24).length,
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
                                  onTap: () => Navigator.of(context).push(
                                    vedroRoute(DetailScreen(
                                      item: MediaItemModel(
                                        id: p.id,
                                        name: p.name,
                                        type: 'Person',
                                        primaryImageTag: p.primaryImageTag,
                                      ),
                                      appState: widget.appState,
                                      onGenreTap: widget.onGenreTap,
                                    )),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 84,
                                        height: 84,
                                        foregroundDecoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: const Color(0x28FFFFFF), width: 0.8),
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
                                        (p.role ?? '').isNotEmpty ? p.role! : p.name,
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
                                        (p.role ?? '').isNotEmpty ? p.name : (p.type ?? ''),
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
                        const SizedBox(height: 16),
                      ],

                      // Person Credits Grid
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
                                    onTap: () => Navigator.of(context).push(
                                      vedroRoute(DetailScreen(
                                        item: c,
                                        appState: widget.appState,
                                        onGenreTap: widget.onGenreTap,
                                      )),
                                    ),
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
                    onItemTap: (other) => Navigator.of(context).push(
                      vedroRoute(DetailScreen(
                        item: other,
                        appState: widget.appState,
                        onGenreTap: widget.onGenreTap,
                      )),
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

          // Persistent floating glass Back Pill aligned beside macOS traffic lights
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

/// AfuseKt signature wide Play Pill with built-in resume progress shading.
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
          color: const Color(0xF5FFFFFF),
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(color: Color(0x45000000), blurRadius: 16, offset: Offset(0, 6)),
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
        child: GlassSurface(
          borderRadius: 22,
          blur: 22,
          color: active ? accent.withValues(alpha: 0.28) : const Color(0x661C1D24),
          borderColor: active ? accent.withValues(alpha: 0.7) : const Color(0x30FFFFFF),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 20, color: active ? accent : iconColor),
          ),
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
  });

  final MediaItemModel episode;
  final VedroAppState appState;
  final double width;
  final Color accent;
  final VoidCallback onTap;

  @override
  State<_EpisodeHorizontalCard> createState() => _EpisodeHorizontalCardState();
}

class _EpisodeHorizontalCardState extends State<_EpisodeHorizontalCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ep = widget.episode;
    final hasProgress = ep.resumeProgress > 0.01;
    return SizedBox(
      width: widget.width,
      child: PressableScale(
        onTap: widget.onTap,
        onHoverChanged: (v) => setState(() => _hovered = v),
        hoverScale: 1.022,
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
                        : (hasProgress ? widget.accent.withValues(alpha: 0.8) : VedroTheme.line),
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
                    if (ep.played)
                      const Positioned(
                        top: 7,
                        right: 7,
                        child: CircleAvatar(
                          radius: 10,
                          backgroundColor: Color(0xAA0B0B0D),
                          child: Icon(Icons.check_rounded, size: 12, color: Colors.white),
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
                fontWeight: FontWeight.w500,
              ),
            ),
            if (fmtDurationTicks(ep.runTimeTicks).isNotEmpty)
              Text(
                fmtDurationTicks(ep.runTimeTicks),
                style: const TextStyle(color: VedroTheme.fg3, fontSize: 11.5),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xAA141418),
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
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
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
                            fontSize: 13,
                            fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (s.container != null) s.container!.toUpperCase(),
                            if (fmtFileSize(s.size).isNotEmpty) fmtFileSize(s.size),
                            if (s.subtitleStreams.isNotEmpty) '${s.subtitleStreams.length} 条字幕',
                          ].join(' · '),
                          style: const TextStyle(color: VedroTheme.fg3, fontSize: 11.5),
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
              style: const TextStyle(color: VedroTheme.fg, fontSize: 13.5, fontWeight: FontWeight.w500),
            ),
          if (audios.isNotEmpty) ...[
            const SizedBox(height: 12),
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5.5),
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
                        fontSize: 12,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          if (subs.isNotEmpty) ...[
            const SizedBox(height: 12),
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5.5),
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
                        fontSize: 12,
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
      padding: const EdgeInsets.only(bottom: 10),
      child: PressableScale(
        onTap: widget.onTap,
        onHoverChanged: (v) => setState(() => _hovered = v),
        hoverScale: 1.006,
        pressScale: 0.985,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _hovered ? VedroTheme.surface2 : const Color(0xAA141418),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: _hovered ? VedroTheme.lineStrong : VedroTheme.line,
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 152,
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
              const SizedBox(width: 15),
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
                      const SizedBox(height: 5),
                      Text(
                        epOverview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFB8BAC4),
                          fontSize: 12.5,
                          height: 1.48,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                ep.played ? Icons.check_circle_rounded : Icons.play_arrow_rounded,
                size: 21,
                color: _hovered ? VedroTheme.fg : VedroTheme.fg3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
