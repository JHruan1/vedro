import 'dart:async';
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
  String? _selectedSeriesVersionKey;
  int? _selectedAudioIndex;
  int? _selectedSubtitleIndex;
  bool _loading = true;
  String _episodeViewMode = 'cards'; // 'grid' | 'cards' | 'list'
  bool _episodeModeUserChosen = false;
  bool _episodeDescending = false;
  int _episodeRangeIndex = 0;
  final TextEditingController _episodeJumpCtrl = TextEditingController();
  String _episodeFilterQuery = '';
  String? _translatedOverview;
  bool _translating = false;
  DateTime? _lastDownloadTapAt;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    widget.appState.addListener(_onAppStateChanged);
    _loadDetails();
    if (widget.appState.capabilities?.isEmbyGo == true) {
      unawaited(widget.appState.refreshMeQuota());
    }
  }

  void _onAppStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant DetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appState != widget.appState) {
      oldWidget.appState.removeListener(_onAppStateChanged);
      widget.appState.addListener(_onAppStateChanged);
    }
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onAppStateChanged);
    _episodeJumpCtrl.dispose();
    super.dispose();
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
      'limit': 5000,
    }) as Map<String, dynamic>;
    if (!mounted) return;
    final loaded = ((eRes['Items'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MediaItemModel.fromJson)
        .toList();

    // Auto-select compact numbered grid when a season has >= 24 episodes (e.g. long-running anime)
    final chunkSize = loaded.length >= 400 ? 100 : 50;
    var initialRange = 0;
    if (loaded.length > chunkSize) {
      var targetIdx = loaded.indexWhere((e) => e.resumeProgress > 0.01);
      if (targetIdx < 0) targetIdx = loaded.indexWhere((e) => !e.played);
      if (targetIdx >= 0) initialRange = targetIdx ~/ chunkSize;
    }

    setState(() {
      _selectedSeasonId = seasonId;
      _episodes = loaded;
      _episodeRangeIndex = initialRange;
      _episodeFilterQuery = '';
      _episodeJumpCtrl.clear();
      if (!_episodeModeUserChosen) {
        _episodeViewMode = loaded.length >= 24 ? 'grid' : 'cards';
      }
    });
  }

  MediaItemModel? get _activeSeason {
    if (_seasons.isEmpty) return null;
    for (final s in _seasons) {
      if (s.id == _selectedSeasonId) return s;
    }
    return _seasons.first;
  }

  MediaSourceModel? get _activeSource {
    if (_item.mediaSources.isEmpty) return null;
    for (final s in _item.mediaSources) {
      if (s.id == _selectedSourceId) return s;
    }
    return _item.mediaSources.first;
  }

  /// Build a stable human-readable version key for matching sources across episodes of a Series.
  String _sourceVersionKey(MediaSourceModel s) {
    final name = (s.name ?? '').trim();
    if (name.isNotEmpty) return name;
    final parts = <String>[
      if (s.videoStreams.isNotEmpty && s.videoStreams.first.height != null)
        '${s.videoStreams.first.height}p',
      if (s.container != null && s.container!.isNotEmpty) s.container!.toUpperCase(),
    ];
    return parts.isNotEmpty ? parts.join(' · ') : s.id;
  }

  /// Collect representative multi-version sources for a Series from its loaded episodes.
  List<MediaSourceModel> get _seriesSampleSources {
    if (!_item.isSeries) return const [];
    for (final ep in _episodes) {
      if (ep.mediaSources.length > 1) return ep.mediaSources;
    }
    return const [];
  }

  String? _matchingSourceIdForEpisode(MediaItemModel ep) {
    if (ep.mediaSources.length <= 1) return null;
    final key = _selectedSeriesVersionKey;
    if (key == null || key.isEmpty) return ep.mediaSources.first.id;
    for (final s in ep.mediaSources) {
      if (_sourceVersionKey(s) == key) return s.id;
    }
    // Fuzzy match on resolution/codec tokens when filenames differ per episode (e.g. S01E01 vs S01E02)
    final keyTokens = key.toLowerCase().split(RegExp(r'[\s._\-·/]+')).where((t) => t.length >= 2).toSet();
    MediaSourceModel? best;
    var bestScore = 0;
    for (final s in ep.mediaSources) {
      final sTokens = _sourceVersionKey(s)
          .toLowerCase()
          .split(RegExp(r'[\s._\-·/]+'))
          .where((t) => t.length >= 2)
          .toSet();
      final score = keyTokens.intersection(sTokens).length;
      if (score > bestScore) {
        bestScore = score;
        best = s;
      }
    }
    return best?.id ?? ep.mediaSources.first.id;
  }

  Future<void> _openEpisodeVersionSheet(MediaItemModel ep) async {
    var target = ep;
    if (target.mediaSources.length <= 1 && target.versionCount > 1) {
      try {
        final res = await widget.appState.core.invoke('get_item', {'item_id': ep.id})
            as Map<String, dynamic>;
        target = MediaItemModel.fromJson(res['item'] as Map<String, dynamic>);
      } catch (_) {}
    }
    if (!mounted) return;
    final sources = target.mediaSources;
    if (sources.isEmpty) {
      _openItemDetail(target);
      return;
    }
    final activeId = _matchingSourceIdForEpisode(target) ?? sources.first.id;
    final accent = Theme.of(context).colorScheme.secondary;
    showGlassSheet<void>(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '选择片源版本 (${sources.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${target.episodeCode ?? ''} ${target.displayName}'.trim(),
                  style: const TextStyle(color: VedroTheme.fg2, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...sources.map((s) {
            final on = s.id == activeId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _VersionOptionTile(
                source: s,
                selected: on,
                accent: accent,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _selectedSeriesVersionKey = _sourceVersionKey(s));
                  _play(target, sourceId: s.id);
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  void _openPosterLightbox() {
    final posterUrl = widget.appState.posterArtUrl(_item, width: 1200);
    if (posterUrl == null || posterUrl.isEmpty) return;
    showDialog<void>(
      context: context,
      barrierColor: const Color(0xDE000000),
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 3.0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(posterUrl, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(ctx).top + 16,
              right: 20,
              child: IconButton(
                style: IconButton.styleFrom(backgroundColor: const Color(0xCC181A24)),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _play(
    MediaItemModel target, {
    String? sourceId,
    bool fromBeginning = false,
    int? startPositionTicks,
    String? localPath,
  }) {
    if (localPath == null && widget.appState.prefs.externalPlayer != 'builtin') {
      _launchExternal(target, sourceId: sourceId);
      return;
    }
    final overrideTicks = startPositionTicks ?? (fromBeginning ? 0 : null);
    final playTarget = overrideTicks != null
        ? MediaItemModel(
            id: target.id,
            name: target.name,
            type: target.type,
            seriesId: target.seriesId,
            seriesName: target.seriesName,
            parentIndexNumber: target.parentIndexNumber,
            indexNumber: target.indexNumber,
            runTimeTicks: target.runTimeTicks,
            playbackPositionTicks: overrideTicks,
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

  MediaItemModel? _resolveDownloadTarget() {
    if (_item.isPlayable) return _item;
    if (_episodes.isEmpty) return null;
    return _episodes.firstWhere(
      (e) => e.resumeProgress > 0.01,
      orElse: () => _episodes.firstWhere(
        (e) => !e.played,
        orElse: () => _episodes.first,
      ),
    );
  }

  MediaSourceModel? _resolveDownloadSource(MediaItemModel? target) {
    if (target == null) return null;
    if (target.id == _item.id) return _activeSource;
    if (target.mediaSources.isEmpty) return null;
    final matchedId = _matchingSourceIdForEpisode(target);
    if (matchedId != null) {
      for (final s in target.mediaSources) {
        if (s.id == matchedId) return s;
      }
    }
    return target.mediaSources.first;
  }

  Future<void> _startDownload() async {
    // 1. Series -> open multi-episode + multi-version Batch Download Picker!
    if (_item.isSeries) {
      await _openBatchDownloadDialog();
      return;
    }

    // 2. Movie / Episode with multiple versions -> open Version Download Picker!
    if (_item.isPlayable && _item.mediaSources.length > 1) {
      _openVersionDownloadSheet(_item);
      return;
    }

    final target = _resolveDownloadTarget();
    if (target == null || !widget.appState.canDownloadItem(target)) return;
    await _enqueueSingleDownload(target, _resolveDownloadSource(target));
  }

  Future<void> _enqueueSingleDownload(MediaItemModel target, MediaSourceModel? source) async {
    if (!widget.appState.canDownloadItem(target)) return;
    final now = DateTime.now();
    if (_lastDownloadTapAt != null &&
        now.difference(_lastDownloadTapAt!) < const Duration(milliseconds: 2500)) {
      return;
    }
    _lastDownloadTapAt = now;

    try {
      await widget.appState.enqueueDownload(
        target,
        mediaSourceId: source?.id ?? (target.id == _item.id ? _selectedSourceId : null),
        versionLabel: source?.name ?? source?.container?.toUpperCase(),
        expectedBytes: source?.size,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已加入下载队列（支持断点续传）：${target.cardTitle}'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF991B1B),
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
            style: const TextStyle(color: Colors.white),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _openVersionDownloadSheet(MediaItemModel target) {
    if (!widget.appState.canDownloadItem(target)) return;
    final sources = target.mediaSources;
    if (sources.isEmpty) return;
    final dq = widget.appState.meQuota?.downloadQuota;

    showGlassSheet<void>(
      context: context,
      builder: (ctx) => ListView(
        key: const ValueKey('detail-version-download-sheet'),
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
        children: [
          Row(
            children: [
              const Icon(Icons.download_rounded, size: 19, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '选择下载版本 (${sources.length})',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, color: VedroTheme.fg2, size: 19),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...sources.map((s) {
            final existing = widget.appState.findDownloadForItem(target.id, mediaSourceId: s.id);
            final alreadyDone = existing != null && existing.status == 'completed';
            final inProgress = existing != null && existing.isActive;
            final tooLarge = dq != null &&
                dq.enabled &&
                !dq.adminExempt &&
                s.size != null &&
                s.size! > 0 &&
                !dq.canFitBytes(s.size);
            final selected = s.id == _selectedSourceId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFF222228) : const Color(0xFF18181C),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (s.name?.trim().isNotEmpty == true)
                                ? s.name!.trim()
                                : (s.container?.toUpperCase() ?? '原画版本'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              if (fmtFileSize(s.size).isNotEmpty)
                                Text(
                                  fmtFileSize(s.size),
                                  style: TextStyle(
                                    color: tooLarge ? const Color(0xFFFCA5A5) : VedroTheme.fg2,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              if (s.container != null && s.container!.isNotEmpty)
                                Text(
                                  s.container!.toUpperCase(),
                                  style: const TextStyle(color: VedroTheme.fg3, fontSize: 12),
                                ),
                              if (s.bitrate != null && s.bitrate! > 0)
                                Text(
                                  '${(s.bitrate! / 1000000).toStringAsFixed(1)} Mbps',
                                  style: const TextStyle(color: VedroTheme.fg3, fontSize: 12),
                                ),
                              if (tooLarge)
                                const Text(
                                  '余额不足',
                                  style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 11.5, fontWeight: FontWeight.w600),
                                ),
                              if (alreadyDone)
                                const Text(
                                  '已下载',
                                  style: TextStyle(color: Color(0xFF34D399), fontSize: 11.5, fontWeight: FontWeight.w600),
                                )
                              else if (inProgress)
                                const Text(
                                  '下载队列中',
                                  style: TextStyle(color: Color(0xFF60A5FA), fontSize: 11.5, fontWeight: FontWeight.w600),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: alreadyDone ? const Color(0xFF28282E) : Colors.white,
                        foregroundColor: alreadyDone ? Colors.white : VedroTheme.canvas,
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                        minimumSize: const Size(0, 34),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                      ),
                      onPressed: (tooLarge || inProgress)
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              if (alreadyDone && existing.filePath.isNotEmpty) {
                                _play(target, localPath: existing.filePath);
                              } else {
                                _enqueueSingleDownload(target, s);
                              }
                            },
                      child: Text(
                        alreadyDone ? '播放' : (inProgress ? '队列中' : '下载'),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _openBatchDownloadDialog() async {
    final target = _resolveDownloadTarget();
    if (!widget.appState.canDownloadItem(target)) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _BatchDownloadDialog(
        series: _item,
        seasons: _seasons,
        initialSeasonId: _selectedSeasonId ?? (_seasons.isNotEmpty ? _seasons.first.id : null),
        initialEpisodes: _episodes,
        initialVersionKey: _selectedSeriesVersionKey,
        appState: widget.appState,
        sourceVersionKeyOf: _sourceVersionKey,
      ),
    );
  }

  void _openMoreSheet() {
    final playable = _resolveDownloadTarget();
    final canDownload = widget.appState.canDownloadItem(playable);
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
                _launchExternal(playable, sourceId: _resolveDownloadSource(playable)?.id ?? _selectedSourceId);
              },
            ),
            if (canDownload)
              ListTile(
                leading: const Icon(Icons.download_rounded, color: VedroTheme.fg2),
                title: Text(
                  _item.isSeries
                      ? '批量下载剧集（选集与版本）'
                      : (_item.mediaSources.length > 1 ? '离线下载到本地（选择版本）' : '离线下载到本地'),
                  style: const TextStyle(color: VedroTheme.fg, fontSize: 14),
                ),
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
    final ultraWide = size.width >= 1080;
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
    final downloadTarget = _resolveDownloadTarget();
    final canDownload = widget.appState.canDownloadItem(downloadTarget);
    final dlTask = widget.appState.findDownloadForItem(downloadTarget?.id ?? _item.id);
    final localReady = dlTask != null && dlTask.status == 'completed' && dlTask.filePath.isNotEmpty;

    final directors = _item.people
        .where((p) => (p.type ?? '').toLowerCase() == 'director')
        .map((p) => p.name)
        .toList();
    final castNames = _item.people
        .where((p) => (p.type ?? '').toLowerCase() == 'actor')
        .map((p) => p.name)
        .take(4)
        .toList();
    final statusLabel = _localizeStatus(_item.status);
    final premiere = fmtIsoDate(_item.premiereDate);

    // Aggregate clean specs from current item or first episode if Series
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

    final seriesSources = _seriesSampleSources;
    if (seriesSources.length > 1 && _selectedSeriesVersionKey == null) {
      _selectedSeriesVersionKey = _sourceVersionKey(seriesSources.first);
    }

    final isEpisodeWithStill = _item.type == 'Episode' && _item.primaryImageTag != null;
    final coverW = _item.type == 'Person'
        ? (wide ? 156.0 : 104.0)
        : isEpisodeWithStill
            ? (wide ? 260.0 : 148.0)
            : (wide ? 188.0 : 112.0);
    final coverAspect = _item.type == 'Person'
        ? 1.0
        : (isEpisodeWithStill ? 16 / 9 : 2 / 3);

    // Editorial eyebrow (Studio + Type, Apple TV+ style)
    final typeWord = _item.isSeries
        ? '剧集'
        : (_item.type == 'Movie' ? '电影' : (_item.type == 'Episode' ? '单集' : ''));
    final eyebrowParts = <String>[
      if (_item.type == 'Episode' && _item.seriesName != null) _item.seriesName!,
      if (_item.type == 'Episode' && _item.episodeCode != null) _item.episodeCode!,
      if (_item.type != 'Episode' && _item.studios.isNotEmpty) _item.studios.first,
      if (_item.type != 'Episode' && typeWord.isNotEmpty) typeWord,
    ];
    final eyebrowText = eyebrowParts.join(' · ');

    Widget buildActionRow() {
      final hasPrimaryPlay = _item.isPlayable || nextEpToPlay != null;
      final String playLabel = _item.isPlayable
          ? (localReady
              ? '播放离线缓存'
              : (_item.playbackPositionTicks > 0
                  ? '继续播放 ${fmtDurationTicks(_item.playbackPositionTicks)}'
                  : '播放'))
          : (nextEpToPlay != null
              ? (nextEpToPlay.resumeProgress > 0.01
                  ? '继续观看 ${nextEpToPlay.episodeCode ?? nextEpToPlay.displayName}'
                  : '播放 ${nextEpToPlay.episodeCode ?? '第 1 集'}')
              : '播放');
      final double playProgress =
          _item.isPlayable ? _item.resumeProgress : (nextEpToPlay?.resumeProgress ?? 0.0);
      void onPrimaryPlay() {
        if (_item.isPlayable) {
          _play(
            _item,
            sourceId: _selectedSourceId,
            localPath: localReady ? dlTask.filePath : null,
          );
        } else if (nextEpToPlay != null) {
          _play(
            nextEpToPlay,
            sourceId: _matchingSourceIdForEpisode(nextEpToPlay),
          );
        }
      }

      final actions = <({
        Key? key,
        IconData icon,
        String label,
        String tooltip,
        bool active,
        Color color,
        VoidCallback onTap,
      })>[
        if (_item.isPlayable && _item.playbackPositionTicks > 0)
          (
            key: null,
            icon: Icons.replay_rounded,
            label: '从头',
            tooltip: '从头播放',
            active: false,
            color: Colors.white,
            onTap: () => _play(_item, sourceId: _selectedSourceId, fromBeginning: true),
          ),
        if (_item.type != 'Person')
          (
            key: null,
            icon: _item.played ? Icons.check_rounded : Icons.check_rounded,
            label: _item.played ? '已看' : '标已看',
            tooltip: _item.played ? '已看（点击取消）' : '标为已看',
            active: _item.played,
            color: _item.played ? accent : Colors.white,
            onTap: () async {
              await widget.appState.togglePlayed(_item);
              await _loadDetails();
            },
          ),
        (
          key: null,
          icon: _item.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          label: _item.isFavorite ? '已收藏' : '收藏',
          tooltip: _item.isFavorite ? '取消收藏' : '收藏',
          active: _item.isFavorite,
          color: _item.isFavorite ? VedroTheme.danger : Colors.white,
          onTap: () async {
            await widget.appState.toggleFavorite(_item);
            await _loadDetails();
          },
        ),
        if (localReady || canDownload)
          (
            key: const ValueKey('detail-download-button'),
            icon: localReady ? Icons.download_done_rounded : Icons.arrow_downward_rounded,
            label: localReady ? '已缓存' : (_item.isSeries ? '下载' : '缓存'),
            tooltip: localReady ? '播放已缓存文件' : '离线下载',
            active: localReady,
            color: localReady ? const Color(0xFF34D399) : Colors.white,
            onTap: localReady
                ? () => _play(downloadTarget ?? _item, localPath: dlTask.filePath)
                : _startDownload,
          ),
        (
          key: null,
          icon: Icons.more_horiz_rounded,
          label: '更多',
          tooltip: '更多（外部播放器 / 片单 / AI 翻译）',
          active: false,
          color: Colors.white,
          onTap: _openMoreSheet,
        ),
      ];

      return LayoutBuilder(
        builder: (ctx, constraints) {
          final singleLine = constraints.maxWidth >= 460;
          if (singleLine) {
            // Apple TV+ Desktop / iPad Action Row:
            // Pure solid white Play capsule + individual borderless frosted circular buttons (zero weird vertical lines!)
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (hasPrimaryPlay)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _ProgressPlayPill(
                      label: playLabel,
                      progress: playProgress,
                      accent: accent,
                      onTap: onPrimaryPlay,
                    ),
                  ),
                for (var i = 0; i < actions.length; i++)
                  KeyedSubtree(
                    key: actions[i].key,
                    child: Tooltip(
                      message: actions[i].tooltip,
                      child: _AppleCircleActionButton(
                        icon: actions[i].icon,
                        active: actions[i].active,
                        color: actions[i].color,
                        onTap: actions[i].onTap,
                      ),
                    ),
                  ),
                if (playProgress > 0.02)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 64,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: playProgress.clamp(0.04, 1.0),
                              minHeight: 3,
                              backgroundColor: const Color(0x24FFFFFF),
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '已看 ${(playProgress * 100).round()}%',
                          style: const TextStyle(
                            color: Color(0xFFA1A1AA),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          }

          // iOS & Android Portrait: Full-width solid white Play CTA + 4 separate borderless frosted action tiles
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasPrimaryPlay) ...[
                _ProgressPlayPill(
                  label: playLabel,
                  progress: playProgress,
                  accent: accent,
                  fullWidth: true,
                  onTap: onPrimaryPlay,
                ),
                if (playProgress > 0.02) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: playProgress.clamp(0.04, 1.0),
                            minHeight: 2.5,
                            backgroundColor: const Color(0x22FFFFFF),
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '已观看 ${(playProgress * 100).round()}%',
                        style: const TextStyle(
                          color: Color(0xFFA1A1AA),
                          fontSize: 11.5,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      key: actions[i].key,
                      child: PressableScale(
                        onTap: actions[i].onTap,
                        hoverScale: 1.03,
                        pressScale: 0.93,
                        child: Container(
                          height: 54,
                          decoration: BoxDecoration(
                            color: actions[i].active
                                ? actions[i].color.withValues(alpha: 0.18)
                                : const Color(0x14FFFFFF),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(actions[i].icon, size: 19, color: actions[i].color),
                              const SizedBox(height: 3),
                              Text(
                                actions[i].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: actions[i].active
                                      ? actions[i].color
                                      : const Color(0xFFD4D4DA),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      );
    }

    Widget buildOverviewBlock() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tagline != null) ...[
            Text(
              tagline,
              style: const TextStyle(
                color: Color(0xFFE5E5EA),
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 6),
          ],
          if (overviewText.isNotEmpty)
            _ExpandableOverview(
              text: overviewText,
              collapsedLines: wide ? 3 : 3,
              accent: accent,
              aiReady: widget.appState.prefs.isAiReady,
              translating: _translating,
              isTranslated: _translatedOverview != null,
              onTranslateToggle: _translatedOverview != null
                  ? () => setState(() => _translatedOverview = null)
                  : _translateOverview,
            ),
        ],
      );
    }

    // Build clean dot-separated Apple TV+ editorial fact widgets (zero underlines!)
    final dotFacts = <Widget>[];
    void addDotFact(Widget w) {
      if (dotFacts.isNotEmpty) {
        dotFacts.add(const Text(
          ' · ',
          style: TextStyle(color: Color(0xFF71717A), fontSize: 13.5),
        ));
      }
      dotFacts.add(w);
    }

    if (premiere.isNotEmpty) {
      addDotFact(Text(
        premiere,
        style: const TextStyle(
          color: Color(0xFFD4D4DA),
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ));
    } else if (_item.productionYear != null) {
      addDotFact(Text(
        '${_item.productionYear}',
        style: const TextStyle(
          color: Color(0xFFD4D4DA),
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ));
    }

    for (final g in _item.genres.take(4)) {
      addDotFact(
        GestureDetector(
          onTap: widget.onGenreTap == null ? null : () => widget.onGenreTap!(g),
          child: MouseRegion(
            cursor: widget.onGenreTap != null ? SystemMouseCursors.click : MouseCursor.defer,
            child: Text(
              g,
              style: const TextStyle(
                color: Color(0xFFD4D4DA),
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    if (_item.isSeries && (_seasons.isNotEmpty || (_item.childCount ?? 0) > 0)) {
      addDotFact(Text(
        '共 ${_seasons.isNotEmpty ? _seasons.length : _item.childCount} 季${(_item.recursiveItemCount ?? 0) > 0 ? ' ${_item.recursiveItemCount} 集' : ''}',
        style: const TextStyle(color: Color(0xFFD4D4DA), fontSize: 13.5),
      ));
    }

    if (!_item.isFolderish && fmtDurationTicks(_item.runTimeTicks).isNotEmpty) {
      addDotFact(Text(
        fmtDurationTicks(_item.runTimeTicks),
        style: const TextStyle(color: Color(0xFFD4D4DA), fontSize: 13.5),
      ));
    } else if (_item.isSeries && fmtDurationTicks(_item.runTimeTicks).isNotEmpty) {
      addDotFact(Text(
        '单集 ${fmtDurationTicks(_item.runTimeTicks)}',
        style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 13.5),
      ));
    }

    if (_item.productionLocations.isNotEmpty) {
      addDotFact(Text(
        _item.productionLocations.take(2).join(' / '),
        style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 13.5),
      ));
    }

    // Apple TV+ Right-Side Editorial Credits Column (for wide macOS / desktop windows)
    final heroCreditRows = <(String role, String names)>[
      if (directors.isNotEmpty) ('导演', directors.take(2).join('、')),
      if (castNames.isNotEmpty) ('主演', castNames.join('、')),
      if (_item.studios.isNotEmpty) ('出品', _item.studios.take(2).join('、')),
      if (statusLabel.isNotEmpty) ('状态', statusLabel),
    ];

    Widget coverCard = GestureDetector(
      onTap: _openPosterLightbox,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          key: const ValueKey('detail-poster-cover'),
          width: coverW,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(wide ? 14 : 12),
            color: VedroTheme.surface2,
            boxShadow: const [
              BoxShadow(
                color: Color(0xCC000000),
                blurRadius: 38,
                offset: Offset(0, 16),
              ),
            ],
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(wide ? 14 : 12),
            border: Border.all(color: const Color(0x20FFFFFF), width: 0.6),
          ),
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: coverAspect,
            child: VedroArtwork(
              item: _item,
              appState: widget.appState,
              landscape: isEpisodeWithStill,
              width: 600,
            ),
          ),
        ),
      ),
    );
    if (widget.heroTag != null) {
      coverCard = Hero(tag: widget.heroTag!, child: coverCard);
    }

    return Scaffold(
      backgroundColor: VedroTheme.canvas,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // 1. Seamless Full-Stage Apple TV+ Immersive Hero (Positioned.fill -> ZERO horizontal cut-off seam!)
              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRect(
                        key: const ValueKey('detail-backdrop-banner'),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            VedroArtwork(
                              item: _item,
                              appState: widget.appState,
                              isHero: true,
                              alignment: const Alignment(0, -0.32),
                              showInitials: false,
                            ),
                            if (wide)
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    stops: [0.0, 0.55, 1.0],
                                    colors: [
                                      Color(0xC809090B),
                                      Color(0x6609090B),
                                      Color(0x3809090B),
                                    ],
                                  ),
                                ),
                              ),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  stops: [0.0, 0.22, 0.56, 0.84, 1.0],
                                  colors: [
                                    Color(0x5809090B),
                                    Color(0x1809090B),
                                    Color(0x9E09090B),
                                    Color(0xEB09090B),
                                    VedroTheme.canvas,
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        padX,
                        wide ? (topSafe + 148) : (topSafe + 118),
                        padX,
                        wide ? 32 : 24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: wide ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              coverCard,
                              SizedBox(width: wide ? 32 : 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (eyebrowText.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 6),
                                        child: Text(
                                          eyebrowText.toUpperCase(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFFA1A1AA),
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.6,
                                          ),
                                        ),
                                      ),

                                    if (wide && logoUrl != null)
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxHeight: 74,
                                          maxWidth: 400,
                                        ),
                                        child: Image.network(
                                          logoUrl,
                                          fit: BoxFit.contain,
                                          alignment: Alignment.centerLeft,
                                          errorBuilder: (_, __, ___) =>
                                              _TitleHeadline(_item.displayName, wide),
                                        ),
                                      )
                                    else
                                      _TitleHeadline(_item.displayName, wide),

                                    if (_item.originalTitle != null &&
                                        _item.originalTitle != _item.name) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        _item.originalTitle!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF98989F),
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ],

                                    if (dotFacts.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Wrap(
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        runSpacing: 4,
                                        children: dotFacts,
                                      ),
                                    ],

                                    // Monochrome Apple TV+ Ratings + Certification + Technical Badges
                                    if ((_item.communityRating ?? 0) > 0 ||
                                        (_item.criticRating ?? 0) > 0 ||
                                        (_item.officialRating?.isNotEmpty == true) ||
                                        statusLabel.isNotEmpty ||
                                        specChips.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          if (_item.communityRating != null &&
                                              _item.communityRating! > 0)
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.star_rounded,
                                                    size: 15.5, color: Color(0xFFFBBF24)),
                                                const SizedBox(width: 3),
                                                Text(
                                                  _item.communityRating!.toStringAsFixed(1),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13.5,
                                                    fontWeight: FontWeight.w700,
                                                    fontFeatures: [FontFeature.tabularFigures()],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          if (_item.criticRating != null &&
                                              _item.criticRating! > 0)
                                            Text(
                                              '${_item.criticRating!.round()}% 好评',
                                              style: const TextStyle(
                                                color: Color(0xFFD4D4DA),
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w600,
                                                fontFeatures: [FontFeature.tabularFigures()],
                                              ),
                                            ),
                                          if (_item.officialRating != null &&
                                              _item.officialRating!.isNotEmpty)
                                            _AppleMicroBadge(_item.officialRating!),
                                          if (statusLabel.isNotEmpty && !ultraWide)
                                            _AppleMicroBadge(statusLabel),
                                          if (specChips.isNotEmpty) SpecGlyphRow(specs: specChips),
                                        ],
                                      ),
                                    ],

                                    if (wide) ...[
                                      if (tagline != null || overviewText.isNotEmpty) ...[
                                        const SizedBox(height: 14),
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 680),
                                          child: buildOverviewBlock(),
                                        ),
                                      ],
                                      const SizedBox(height: 22),
                                      VedroStaggeredEntrance(
                                        index: 1,
                                        reduceMotion: widget.appState.prefs.reduceMotion,
                                        child: buildActionRow(),
                                      ),
                                    ],
                                  ],
                                ),
                              ),

                              // Apple TV+ Desktop Right-Side Editorial Credits Column
                              if (ultraWide && heroCreditRows.isNotEmpty) ...[
                                const SizedBox(width: 36),
                                SizedBox(
                                  width: 228,
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        for (var i = 0; i < heroCreditRows.length; i++) ...[
                                          if (i > 0) const SizedBox(height: 10),
                                          Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: '${heroCreditRows[i].$1}  ',
                                                  style: const TextStyle(
                                                    color: Color(0xFF71717A),
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w500,
                                                    height: 1.45,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: heroCreditRows[i].$2,
                                                  style: const TextStyle(
                                                    color: Color(0xFFD4D4DA),
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w500,
                                                    height: 1.45,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),

                          if (!wide) ...[
                            const SizedBox(height: 20),
                            VedroStaggeredEntrance(
                              index: 1,
                              reduceMotion: widget.appState.prefs.reduceMotion,
                              child: buildActionRow(),
                            ),
                            if (tagline != null || overviewText.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              buildOverviewBlock(),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Body Content on Deep Obsidian Canvas (zero heavy admin boxes or weird lines)
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 2a. Compact Apple Version / Audio / Subtitle Selector (Movies & Episodes)
                    if (_item.isPlayable && _item.mediaSources.isNotEmpty) ...[
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: padX),
                        child: _TracksPanel(
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
                      ),
                      const SizedBox(height: 32),
                    ],

                    // 2b. Compact Apple Series Version Cards (when episodes have multiple versions)
                    if (_item.isSeries && seriesSources.length > 1) ...[
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: padX),
                        child: Column(
                          key: const ValueKey('detail-version-selector'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '选择剧集片源版本 (${seriesSources.length})',
                              style: const TextStyle(
                                color: VedroTheme.fg2,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.1,
                              ),
                            ),
                            const SizedBox(height: 10),
                            LayoutBuilder(
                              builder: (ctx, c) {
                                final twoCol = c.maxWidth >= 680;
                                final cardW = twoCol ? (c.maxWidth - 12) / 2 : c.maxWidth;
                                return Wrap(
                                  spacing: 12,
                                  runSpacing: 10,
                                  children: seriesSources.map((s) {
                                    final vKey = _sourceVersionKey(s);
                                    final on = vKey == _selectedSeriesVersionKey;
                                    return SizedBox(
                                      width: cardW,
                                      child: _VersionOptionTile(
                                        source: s,
                                        selected: on,
                                        accent: accent,
                                        onTap: () => setState(() => _selectedSeriesVersionKey = vKey),
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],

                    // 2c. TV Series Seasons & Scalable Episode Selector (full-bleed horizontal cards!)
                    if (_seasons.isNotEmpty) ...[
                      _buildEpisodeSection(
                        wide: wide,
                        padX: padX,
                        accent: accent,
                        nextEpToPlay: nextEpToPlay,
                      ),
                      const SizedBox(height: 34),
                    ],

                    // 2d. Apple TV+ Circular Cast & Crew Medallions
                    if (_item.people.isNotEmpty) ...[
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: padX),
                        child: Row(
                          children: [
                            const Text(
                              '演职人员',
                              style: TextStyle(
                                color: VedroTheme.fg,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                              ),
                            ),
                            if (directors.isNotEmpty && !ultraWide) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '导演：${directors.take(2).join(' · ')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(color: VedroTheme.fg3, fontSize: 13),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SmoothHorizontalStrip(
                        height: 152,
                        padX: padX,
                        paddleCenterY: 48,
                        spacing: 18,
                        itemCount: _item.people.take(36).length,
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
                          final roleLabel = (p.role ?? '').trim().isNotEmpty
                              ? p.role!.trim()
                              : localizePersonRole(p.type);
                          return SizedBox(
                            width: 90,
                            child: PressableScale(
                              onTap: () => _openItemDetail(MediaItemModel(
                                id: p.id,
                                name: p.name,
                                type: 'Person',
                                primaryImageTag: p.primaryImageTag,
                              )),
                              hoverScale: 1.04,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 86,
                                    height: 86,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: VedroTheme.surface2,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Color(0x66000000),
                                          blurRadius: 16,
                                          offset: Offset(0, 6),
                                        ),
                                      ],
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
                                  const SizedBox(height: 8),
                                  Text(
                                    p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: VedroTheme.fg,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    roleLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: VedroTheme.fg3, fontSize: 11.5),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 28),
                    ],

                    // 2e. Borderless Chapters Strip
                    if (_item.chapters.isNotEmpty && _item.isPlayable) ...[
                      _ChaptersSection(
                        chapters: _item.chapters,
                        padX: padX,
                        accent: accent,
                        onSelectChapter: (ticks) => _play(
                          _item,
                          sourceId: _selectedSourceId,
                          startPositionTicks: ticks,
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ],
                ),
              ),

              // 3. Related Recommendations Rail (placed ABOVE the "关于" footer, exact Apple TV+ order!)
              if (_similar.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: HorizontalMediaRail(
                      title: '相关推荐',
                      items: _similar,
                      appState: widget.appState,
                      onItemTap: _openItemDetail,
                    ),
                  ),
                ),

              // 4. Apple TV+ Editorial Information & Technical Specs Footer
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: padX),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_item.type != 'Person') ...[
                        _NfoMetadataSection(
                          item: _item,
                          seasonsCount: _seasons.isNotEmpty ? _seasons.length : _item.childCount,
                          episodesCount: _item.recursiveItemCount ??
                              (_episodes.isNotEmpty ? _episodes.length : null),
                          statusLabel: statusLabel,
                          appState: widget.appState,
                          onGenreTap: widget.onGenreTap,
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (src != null) ...[
                        _MediaSpecsSection(source: src, itemPath: _item.path),
                        const SizedBox(height: 20),
                      ],
                      if (_item.type == 'Person' && _personCredits.isNotEmpty) ...[
                        Text(
                          '参与作品 (${_personCredits.length})',
                          style: const TextStyle(
                            color: VedroTheme.fg,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
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

          // Floating borderless frosted Back Pill aligned beside macOS traffic lights / iOS Dynamic Island
          Positioned(
            top: topSafe + 12,
            left: isMac ? 82 : (padX - 4),
            child: PressableScale(
              onTap: () => Navigator.of(context).pop(),
              hoverScale: 1.04,
              pressScale: 0.92,
              child: GlassSurface(
                borderRadius: 20,
                blur: 24,
                color: const Color(0x66161619),
                borderColor: const Color(0x18FFFFFF),
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7.5),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_ios_new_rounded, size: 13.5, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      '返回',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
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

  /// Scalable Apple TV+ Season & Episode Picker supporting everything from 6-episode miniseries
  /// to 2,000+ episode anime (borderless capsules + full-bleed 16:9 stills + clean number keypad).
  Widget _buildEpisodeSection({
    required bool wide,
    required double padX,
    required Color accent,
    required MediaItemModel? nextEpToPlay,
  }) {
    final activeSeason = _activeSeason;
    final seasonOverview = activeSeason?.cleanOverview ?? '';

    final ordered = _episodeDescending ? _episodes.reversed.toList() : _episodes;
    final query = _episodeFilterQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? ordered
        : ordered.where((ep) {
            final numStr = '${ep.indexNumber ?? ''}';
            final codeStr = (ep.episodeCode ?? '').toLowerCase();
            return numStr == query ||
                numStr.contains(query) ||
                codeStr.contains(query) ||
                ep.displayName.toLowerCase().contains(query) ||
                ep.cleanOverview.toLowerCase().contains(query);
          }).toList();

    final chunkSize = filtered.length >= 400 ? 100 : 50;
    final rangeCount = filtered.isEmpty ? 0 : ((filtered.length - 1) ~/ chunkSize) + 1;
    final safeRangeIdx = rangeCount == 0 ? 0 : _episodeRangeIndex.clamp(0, rangeCount - 1);
    final rangeStart = safeRangeIdx * chunkSize;
    final rangeEnd = (rangeStart + chunkSize).clamp(0, filtered.length);
    final visibleEps =
        (query.isEmpty && rangeCount > 1) ? filtered.sublist(rangeStart, rangeEnd) : filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: padX),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                  if (_seasons.length > 1)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16161A),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: _seasons.map((s) {
                            final active = s.id == (_selectedSeasonId ?? _seasons.first.id);
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _loadEpisodes(s.id),
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  curve: VedroTheme.easeOut,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6.5),
                                  decoration: BoxDecoration(
                                    color: active ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(17),
                                  ),
                                  child: Text(
                                    s.name,
                                    style: TextStyle(
                                      color: active ? VedroTheme.canvas : VedroTheme.fg2,
                                      fontSize: 13.5,
                                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _seasons.first.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '共 ${_episodes.length} 集',
                          style: const TextStyle(
                            color: VedroTheme.fg3,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (_seasons.length > 1)
                        Text(
                          '共 ${_episodes.length} 集',
                          style: const TextStyle(
                            color: VedroTheme.fg3,
                            fontSize: 12.5,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      if (widget.appState.canDownloadItem(_resolveDownloadTarget()))
                        PressableScale(
                          key: const ValueKey('detail-batch-download-btn'),
                          onTap: _openBatchDownloadDialog,
                          child: Container(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1F),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.arrow_downward_rounded, size: 14, color: Colors.white),
                                SizedBox(width: 5),
                                Text(
                                  '批量下载',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      PressableScale(
                        onTap: () => setState(() {
                          _episodeDescending = !_episodeDescending;
                          _episodeRangeIndex = 0;
                        }),
                        child: Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 11),
                          decoration: BoxDecoration(
                            color: const Color(0xFF16161A),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _episodeDescending
                                    ? Icons.arrow_upward_rounded
                                    : Icons.arrow_downward_rounded,
                                size: 13.5,
                                color: VedroTheme.fg2,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _episodeDescending ? '倒序' : '正序',
                                style: const TextStyle(
                                  color: VedroTheme.fg2,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16161A),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _EpModeBtn(
                              icon: Icons.grid_view_rounded,
                              tooltip: '数字网格选集（适合多集/番剧）',
                              active: _episodeViewMode == 'grid',
                              onTap: () => setState(() {
                                _episodeViewMode = 'grid';
                                _episodeModeUserChosen = true;
                              }),
                            ),
                            _EpModeBtn(
                              icon: Icons.view_carousel_outlined,
                              tooltip: '横向剧照卡片',
                              active: _episodeViewMode == 'cards',
                              onTap: () => setState(() {
                                _episodeViewMode = 'cards';
                                _episodeModeUserChosen = true;
                              }),
                            ),
                            _EpModeBtn(
                              icon: Icons.view_agenda_outlined,
                              tooltip: '纵向图文列表',
                              active: _episodeViewMode == 'list',
                              onTap: () => setState(() {
                                _episodeViewMode = 'list';
                                _episodeModeUserChosen = true;
                              }),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                ),
              ),

              if (seasonOverview.isNotEmpty) ...[
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Text(
                    seasonOverview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VedroTheme.fg2,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ],

              // Range Chunk Capsules (1-50, 51-100...) + Quick Jump Search for long series
              if (_episodes.length > 24) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (rangeCount > 1 && query.isEmpty)
                      Expanded(
                        child: SizedBox(
                          height: 32,
                          child: ScrollConfiguration(
                            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: rangeCount,
                              separatorBuilder: (_, __) => const SizedBox(width: 7),
                              itemBuilder: (_, rIdx) {
                                final rStart = rIdx * chunkSize;
                                final rEnd = (rStart + chunkSize).clamp(0, filtered.length);
                                final firstNum = filtered[rStart].indexNumber ?? (rStart + 1);
                                final lastNum = filtered[rEnd - 1].indexNumber ?? rEnd;
                                final active = rIdx == safeRangeIdx;
                                return GestureDetector(
                                  onTap: () => setState(() => _episodeRangeIndex = rIdx),
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: Container(
                                      padding:
                                          const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: active ? Colors.white : const Color(0xFF16161A),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '$firstNum-$lastNum',
                                        style: TextStyle(
                                          color: active ? VedroTheme.canvas : VedroTheme.fg2,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          fontFeatures: const [FontFeature.tabularFigures()],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: wide ? 176 : 132,
                      height: 32,
                      child: TextField(
                        controller: _episodeJumpCtrl,
                        onChanged: (v) => setState(() {
                          _episodeFilterQuery = v;
                          _episodeRangeIndex = 0;
                        }),
                        style: const TextStyle(color: Colors.white, fontSize: 12.5),
                        decoration: InputDecoration(
                          hintText: '跳集 / 搜集名',
                          hintStyle: const TextStyle(color: VedroTheme.fg3, fontSize: 12),
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 15, color: VedroTheme.fg3),
                          prefixIconConstraints: const BoxConstraints(minWidth: 30),
                          suffixIcon: _episodeFilterQuery.isNotEmpty
                              ? IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.cancel_rounded,
                                      size: 14, color: VedroTheme.fg3),
                                  onPressed: () {
                                    _episodeJumpCtrl.clear();
                                    setState(() => _episodeFilterQuery = '');
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          fillColor: const Color(0xFF16161A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0x28FFFFFF), width: 1),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 14),

        if (visibleEps.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: padX, vertical: 20),
            child: const Text('没有匹配的分集', style: TextStyle(color: VedroTheme.fg3, fontSize: 13)),
          )
        else if (_episodeViewMode == 'grid')
          Padding(
            padding: EdgeInsets.symmetric(horizontal: padX),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tileW = wide ? 86.0 : 62.0;
                final cols = (constraints.maxWidth / (tileW + 8)).floor().clamp(4, 14);
                const gap = 8.0;
                final actualW = (constraints.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: visibleEps.map((ep) {
                    final isNext = nextEpToPlay?.id == ep.id;
                    final hasProg = ep.resumeProgress > 0.01;
                    final epNum = ep.indexNumber != null ? '${ep.indexNumber}' : ep.displayName;
                    final tip = [
                      '${ep.episodeCode ?? 'E$epNum'} ${ep.displayName}',
                      if (fmtDurationTicks(ep.runTimeTicks).isNotEmpty)
                        fmtDurationTicks(ep.runTimeTicks),
                      if (fmtIsoDate(ep.premiereDate).isNotEmpty) fmtIsoDate(ep.premiereDate),
                      if (ep.versionCount > 1) '${ep.versionCount} 版本（右键/长按选版本）',
                    ].join(' · ');
                    return Tooltip(
                      message: tip,
                      child: PressableScale(
                        onTap: () => _play(ep, sourceId: _matchingSourceIdForEpisode(ep)),
                        onLongPress: ep.versionCount > 1
                            ? () => _openEpisodeVersionSheet(ep)
                            : () => _openItemDetail(ep),
                        onSecondaryTap: ep.versionCount > 1
                            ? () => _openEpisodeVersionSheet(ep)
                            : () => _openItemDetail(ep),
                        hoverScale: 1.04,
                        pressScale: 0.94,
                        child: Container(
                          width: actualW,
                          height: wide ? 46 : 42,
                          decoration: BoxDecoration(
                            color: isNext
                                ? Colors.white
                                : (ep.played ? const Color(0xFF111114) : const Color(0xFF17171B)),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            children: [
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(
                                    epNum,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isNext
                                          ? VedroTheme.canvas
                                          : (ep.played ? const Color(0xFF63636B) : Colors.white),
                                      fontSize: wide ? 14 : 13,
                                      fontWeight: isNext ? FontWeight.w700 : FontWeight.w600,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ),
                              ),
                              if (ep.played && !isNext)
                                const Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Icon(Icons.check_rounded,
                                      size: 11, color: Color(0xFF6E6E77)),
                                )
                              else if (ep.versionCount > 1)
                                Positioned(
                                  top: 3,
                                  right: 5,
                                  child: Text(
                                    '${ep.versionCount}×',
                                    style: TextStyle(
                                      color: isNext ? VedroTheme.canvas : VedroTheme.fg3,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              if (hasProg)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  height: 3,
                                  child: LinearProgressIndicator(
                                    value: ep.resumeProgress,
                                    backgroundColor: Colors.transparent,
                                    color: isNext ? VedroTheme.canvas : accent,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          )
        else if (_episodeViewMode == 'cards')
          SmoothHorizontalStrip(
            height: wide ? 298 : 258,
            padX: padX,
            paddleCenterY: (wide ? 284 : 232) / (16 / 9) / 2 + 10,
            spacing: 16,
            itemCount: visibleEps.length,
            itemBuilder: (_, idx) {
              final ep = visibleEps[idx];
              return _EpisodeHorizontalCard(
                episode: ep,
                seriesFallback: _item,
                appState: widget.appState,
                width: wide ? 284 : 232,
                accent: accent,
                onTap: () => _play(ep, sourceId: _matchingSourceIdForEpisode(ep)),
                onOpenDetail: () => _openItemDetail(ep),
                onPickVersion: ep.versionCount > 1 ? () => _openEpisodeVersionSheet(ep) : null,
              );
            },
          )
        else
          Padding(
            padding: EdgeInsets.symmetric(horizontal: padX),
            child: Column(
              children: visibleEps
                  .map((ep) => _EpisodeRow(
                        episode: ep,
                        seriesFallback: _item,
                        appState: widget.appState,
                        onTap: () => _play(ep, sourceId: _matchingSourceIdForEpisode(ep)),
                        onOpenDetail: () => _openItemDetail(ep),
                        onPickVersion:
                            ep.versionCount > 1 ? () => _openEpisodeVersionSheet(ep) : null,
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}

class _AppleMicroBadge extends StatelessWidget {
  const _AppleMicroBadge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2.5),
      decoration: BoxDecoration(
        color: const Color(0x18FFFFFF),
        borderRadius: BorderRadius.circular(4.5),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFE5E5EA),
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _AppleCircleActionButton extends StatefulWidget {
  const _AppleCircleActionButton({
    required this.icon,
    required this.active,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_AppleCircleActionButton> createState() => _AppleCircleActionButtonState();
}

class _AppleCircleActionButtonState extends State<_AppleCircleActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: widget.onTap,
      onHoverChanged: (v) => setState(() => _hovered = v),
      hoverScale: 1.07,
      pressScale: 0.91,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: VedroTheme.easeOut,
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.active
              ? widget.color.withValues(alpha: 0.22)
              : (_hovered ? const Color(0x2BFFFFFF) : const Color(0x18FFFFFF)),
        ),
        child: Icon(widget.icon, size: 20, color: widget.color),
      ),
    );
  }
}

class _EpModeBtn extends StatelessWidget {
  const _EpModeBtn({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 30,
            height: 26,
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              icon,
              size: 14.5,
              color: active ? VedroTheme.canvas : VedroTheme.fg3,
            ),
          ),
        ),
      ),
    );
  }
}

/// Clean borderless Apple TV+ Chapters Strip.
class _ChaptersSection extends StatelessWidget {
  const _ChaptersSection({
    required this.chapters,
    required this.padX,
    required this.accent,
    required this.onSelectChapter,
  });

  final List<ChapterModel> chapters;
  final double padX;
  final Color accent;
  final ValueChanged<int> onSelectChapter;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: padX),
          child: Text(
            '章节导览 (${chapters.length})',
            style: const TextStyle(
              color: VedroTheme.fg,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 54,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: ListView.separated(
              padding: EdgeInsets.symmetric(horizontal: padX),
              scrollDirection: Axis.horizontal,
              itemCount: chapters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, idx) {
                final ch = chapters[idx];
                final title = ch.name.isNotEmpty ? ch.name : '第 ${idx + 1} 章';
                final ts = fmtTicksClock(ch.startPositionTicks);
                return PressableScale(
                  onTap: () => onSelectChapter(ch.startPositionTicks),
                  hoverScale: 1.03,
                  pressScale: 0.96,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          ts,
                          style: const TextStyle(
                            color: VedroTheme.fg3,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
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
      color: Color(0xFFDADAE0),
      fontSize: 14.5,
      height: 1.62,
      letterSpacing: 0.05,
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
              curve: VedroTheme.easeOut,
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
                          style: const TextStyle(
                            color: Colors.white,
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

/// Pure borderless Apple TV+ "关于 / 信息" Editorial Footer Section.
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
    final composers = item.people
        .where((p) => (p.type ?? '').toLowerCase() == 'composer')
        .map((p) => p.name)
        .toList();
    final creators = item.people
        .where((p) => (p.type ?? '').toLowerCase() == 'creator')
        .map((p) => p.name)
        .toList();
    final guests = item.people
        .where((p) => (p.type ?? '').toLowerCase().replaceAll(' ', '') == 'gueststar')
        .map((p) => p.name)
        .toList();

    final localizedAirDays = item.airDays.map(localizeAirDay).where((s) => s.isNotEmpty).toList();
    final sortNameClean = (item.sortName ?? '').trim();
    final showSortName = sortNameClean.isNotEmpty &&
        sortNameClean.toLowerCase() != item.name.trim().toLowerCase() &&
        sortNameClean.toLowerCase() != (item.originalTitle ?? '').trim().toLowerCase();

    final facts = <(String label, String value)>[
      if (item.originalTitle != null && item.originalTitle!.trim().isNotEmpty)
        ('原名', item.originalTitle!.trim()),
      if (showSortName) ('排序名', sortNameClean),
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
      if (item.aspectRatio != null && item.aspectRatio!.trim().isNotEmpty)
        ('画面比例', item.aspectRatio!.trim()),
      if (item.officialRating != null && item.officialRating!.trim().isNotEmpty)
        ('内容分级', item.officialRating!.trim()),
      if (item.customRating != null &&
          item.customRating!.trim().isNotEmpty &&
          item.customRating!.trim() != item.officialRating?.trim())
        ('自定义分级', item.customRating!.trim()),
      if (item.communityRating != null && item.communityRating! > 0)
        ('社区评分', '${item.communityRating!.toStringAsFixed(1)} / 10'),
      if (item.criticRating != null && item.criticRating! > 0)
        ('媒体好评率', '${item.criticRating!.round()}%'),
      if (item.awardSummary != null && item.awardSummary!.trim().isNotEmpty)
        ('获奖与提名', item.awardSummary!.trim()),
      if (fmtCurrencyUsd(item.budget).isNotEmpty) ('制作预算', fmtCurrencyUsd(item.budget)),
      if (fmtCurrencyUsd(item.revenue).isNotEmpty) ('全球票房', fmtCurrencyUsd(item.revenue)),
      if (item.productionLocations.isNotEmpty)
        ('制片国家 / 地区', item.productionLocations.join('、')),
      if (item.studios.isNotEmpty) ('出品方 / 电视网', item.studios.join('、')),
      if (localizedAirDays.isNotEmpty || (item.airTime ?? '').isNotEmpty)
        (
          '播出时段',
          [
            if (localizedAirDays.isNotEmpty) '每${localizedAirDays.join('、')}',
            if ((item.airTime ?? '').isNotEmpty) item.airTime!,
          ].join(' '),
        ),
      if (item.airsBeforeSeasonNumber != null)
        (
          '特别篇顺序',
          '第 ${item.airsBeforeSeasonNumber} 季${item.airsBeforeEpisodeNumber != null ? ' 第 ${item.airsBeforeEpisodeNumber} 集之前' : ' 之前'}',
        ),
      if (creators.isNotEmpty) ('主创', creators.take(4).join('、')),
      if (directors.isNotEmpty) ('导演', directors.take(4).join('、')),
      if (writers.isNotEmpty) ('编剧', writers.take(4).join('、')),
      if (producers.isNotEmpty) ('制片人', producers.take(4).join('、')),
      if (composers.isNotEmpty) ('配乐', composers.take(4).join('、')),
      if (guests.isNotEmpty) ('客串嘉宾', guests.take(6).join('、')),
      if (item.taglines.length > 1) ('更多标语', item.taglines.skip(1).join(' / ')),
      if (fmtIsoDate(item.dateCreated).isNotEmpty) ('入库日期', fmtIsoDate(item.dateCreated)),
      if ((item.sourceFolderCount ?? 0) > 1) ('合并源目录', '${item.sourceFolderCount} 个来源文件夹'),
    ];

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
      } else if (lower == 'bgm' || lower == 'bangumi') {
        label = 'Bangumi';
        url = 'https://bgm.tv/subject/$v';
      } else if (lower == 'anidb') {
        label = 'AniDB';
        url = 'https://anidb.net/anime/$v';
      } else if (lower == 'anilist') {
        label = 'AniList';
        url = 'https://anilist.co/anime/$v';
      } else if (lower == 'mal' || lower == 'myanimelist') {
        label = 'MAL';
        url = 'https://myanimelist.net/anime/$v';
      } else if (lower == 'trakt') {
        label = 'Trakt';
        url = item.isSeries ? 'https://trakt.tv/shows/$v' : 'https://trakt.tv/movies/$v';
      }
      links.add((label, url, '$label: $v'));
    });

    if (facts.isEmpty && item.tags.isEmpty && links.isEmpty && item.remoteTrailers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF121215),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '影片资料与 NFO 信息',
            style: TextStyle(
              color: VedroTheme.fg,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final cols =
                    constraints.maxWidth >= 720 ? 3 : (constraints.maxWidth >= 400 ? 2 : 1);
                const gap = 20.0;
                final cellW = (constraints.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: 16,
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
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 3),
                          SelectableText(
                            f.$2,
                            style: const TextStyle(
                              color: VedroTheme.fg,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
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
            const SizedBox(height: 20),
            const Text('标签', style: TextStyle(color: VedroTheme.fg3, fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: item.tags.take(24).map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B1B20),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '# $tag',
                    style: const TextStyle(color: VedroTheme.fg2, fontSize: 12),
                  ),
                );
              }).toList(),
            ),
          ],
          if (item.remoteTrailers.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('官方预告片', style: TextStyle(color: VedroTheme.fg3, fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: item.remoteTrailers.asMap().entries.map((entry) {
                final tr = entry.value;
                final label = tr.name.trim().isNotEmpty ? tr.name.trim() : '预告片 ${entry.key + 1}';
                return PressableScale(
                  onTap: () => appState.openExternalUrl(tr.url),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1B20),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_circle_outline_rounded, size: 15, color: Colors.white),
                        const SizedBox(width: 5),
                        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          if (links.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('资料索引', style: TextStyle(color: VedroTheme.fg3, fontSize: 12, fontWeight: FontWeight.w500)),
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1B20),
                      borderRadius: BorderRadius.circular(16),
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
                          const Icon(Icons.arrow_outward_rounded, size: 12.5, color: VedroTheme.fg3),
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF121215),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                '技术规格',
                style: TextStyle(
                  color: VedroTheme.fg,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              if (source.container != null && source.container!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B1B20),
                    borderRadius: BorderRadius.circular(12),
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
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (videos.isNotEmpty)
            _SpecGroup('视频', videos.map((v) => v.detailedSpec).toList()),
          if (audios.isNotEmpty)
            _SpecGroup('音频 (${audios.length})', audios.map((a) => a.detailedSpec).toList()),
          if (subs.isNotEmpty)
            _SpecGroup('字幕 (${subs.length})', subs.take(12).map((s) => s.detailedSpec).toList()),
          if (filePath != null && filePath.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('媒体路径', style: TextStyle(color: VedroTheme.fg3, fontSize: 11.5)),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: VedroTheme.fg3, fontSize: 12, fontWeight: FontWeight.w500)),
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
        fontSize: wide ? 40 : 26,
        fontWeight: FontWeight.w700,
        letterSpacing: wide ? -0.9 : -0.6,
        height: 1.1,
      ),
    );
  }
}

/// Pure solid-white Apple TV+ Play Capsule (zero half-blue split lines!).
class _ProgressPlayPill extends StatelessWidget {
  const _ProgressPlayPill({
    required this.label,
    required this.progress,
    required this.accent,
    required this.onTap,
    this.fullWidth = false,
  });

  final String label;
  final double progress;
  final Color accent;
  final VoidCallback onTap;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      hoverScale: fullWidth ? 1.015 : 1.03,
      pressScale: 0.96,
      child: Container(
        height: fullWidth ? 50 : 46,
        width: fullWidth ? double.infinity : null,
        constraints: fullWidth
            ? const BoxConstraints(minHeight: 50)
            : const BoxConstraints(minWidth: 152, maxWidth: 296),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(fullWidth ? 14 : 23),
          boxShadow: const [
            BoxShadow(color: Color(0x52000000), blurRadius: 22, offset: Offset(0, 8)),
          ],
        ),
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_arrow_rounded, size: 23, color: VedroTheme.canvas),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: VedroTheme.canvas,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeHorizontalCard extends StatefulWidget {
  const _EpisodeHorizontalCard({
    required this.episode,
    required this.seriesFallback,
    required this.appState,
    required this.width,
    required this.accent,
    required this.onTap,
    required this.onOpenDetail,
    this.onPickVersion,
  });

  final MediaItemModel episode;
  final MediaItemModel seriesFallback;
  final VedroAppState appState;
  final double width;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onOpenDetail;
  final VoidCallback? onPickVersion;

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
                duration: const Duration(milliseconds: 200),
                curve: VedroTheme.easeOut,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: VedroTheme.surface2,
                  boxShadow: [
                    BoxShadow(
                      color: _hovered ? const Color(0x88000000) : const Color(0x48000000),
                      blurRadius: _hovered ? 24 : 14,
                      offset: Offset(0, _hovered ? 10 : 6),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    VedroArtwork(
                      item: ep,
                      fallbackItem: widget.seriesFallback,
                      appState: widget.appState,
                      landscape: true,
                      width: 520,
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0.55, 1.0],
                          colors: [Colors.transparent, Color(0x99000000)],
                        ),
                      ),
                    ),
                    // Subtle hover play FAB in center
                    IgnorePointer(
                      ignoring: !_hovered,
                      child: AnimatedOpacity(
                        opacity: _hovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 160),
                        child: Center(
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: const BoxDecoration(
                              color: Color(0xEBFFFFFF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              size: 24,
                              color: VedroTheme.canvas,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Clean top-right actions (no borders!)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.onPickVersion != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 5),
                              child: GestureDetector(
                                onTap: widget.onPickVersion,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xB809090B),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${ep.versionCount} 版本',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          GestureDetector(
                            onTap: widget.onOpenDetail,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                color: Color(0xA609090B),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.more_horiz_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasProgress)
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 9,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: ep.resumeProgress,
                            minHeight: 3,
                            backgroundColor: const Color(0x45FFFFFF),
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                if (ep.indexNumber != null)
                  Text(
                    '第 ${ep.indexNumber} 集',
                    style: const TextStyle(
                      color: VedroTheme.fg3,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                const Spacer(),
                if (ep.played)
                  const Icon(Icons.check_circle_rounded, size: 13.5, color: VedroTheme.fg3),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              ep.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            if (epOverview.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                epOverview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: VedroTheme.fg2, fontSize: 12, height: 1.42),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              [
                if (dur.isNotEmpty) dur,
                if (airDate.isNotEmpty) airDate,
                if (ep.communityRating != null && ep.communityRating! > 0)
                  '★ ${ep.communityRating!.toStringAsFixed(1)}',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: VedroTheme.fg3,
                fontSize: 11.5,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Clean Apple Soft Surface card for selecting a media version (zero radio buttons or neon boxes!).
class _VersionOptionTile extends StatelessWidget {
  const _VersionOptionTile({
    required this.source,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final MediaSourceModel source;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = source.name?.isNotEmpty == true
        ? source.name!
        : (source.container?.toUpperCase() ?? '原画');
    final video = source.videoStreams.isNotEmpty ? source.videoStreams.first : null;
    final tags = <String>[
      if (video != null && video.height != null) '${video.height}p',
      if (video?.codec != null && video!.codec!.isNotEmpty) video.codec!.toUpperCase(),
      if (source.container != null && source.container!.isNotEmpty) source.container!.toUpperCase(),
      if (fmtFileSize(source.size).isNotEmpty) fmtFileSize(source.size),
      if ((source.bitrate ?? 0) > 0) '${(source.bitrate! / 1000000).toStringAsFixed(1)} Mbps',
      if (source.audioStreams.isNotEmpty) '${source.audioStreams.length} 音轨',
      if (source.subtitleStreams.isNotEmpty) '${source.subtitleStreams.length} 字幕',
    ];

    return PressableScale(
      onTap: onTap,
      hoverScale: 1.01,
      pressScale: 0.98,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: VedroTheme.easeOut,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF222228) : const Color(0xFF151518),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0x38FFFFFF) : Colors.transparent,
            width: 0.9,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFFD4D4DA),
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      tags.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VedroTheme.fg3,
                        fontSize: 12,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '当前',
                  style: TextStyle(
                    color: VedroTheme.canvas,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Borderless Infuse 8 / Apple TV+ Version, Audio & Subtitle selector section.
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

    if (sources.length <= 1 && audios.isEmpty && subs.isEmpty) {
      return const SizedBox.shrink(key: ValueKey('detail-version-selector'));
    }

    return Column(
      key: const ValueKey('detail-version-selector'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sources.length > 1) ...[
          Text(
            '选择片源版本 (${sources.length})',
            style: const TextStyle(
              color: VedroTheme.fg2,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (ctx, c) {
              final twoCol = c.maxWidth >= 680;
              final cardW = twoCol ? (c.maxWidth - 12) / 2 : c.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 10,
                children: sources.map((s) {
                  return SizedBox(
                    width: cardW,
                    child: _VersionOptionTile(
                      source: s,
                      selected: s.id == active.id,
                      accent: accent,
                      onTap: () => onSelectSource(s.id),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],

        if (audios.isNotEmpty) ...[
          if (sources.length > 1) const SizedBox(height: 18),
          Text(
            '音轨 (${audios.length})',
            style: const TextStyle(
              color: VedroTheme.fg3,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TrackChoiceChip(
                label: '默认',
                selected: selectedAudioIndex == null,
                onTap: () => onSelectAudio(null),
              ),
              ...audios.map((a) {
                final on = selectedAudioIndex == a.index;
                return _TrackChoiceChip(
                  label: a.label,
                  selected: on,
                  onTap: () => onSelectAudio(on ? null : a.index),
                );
              }),
            ],
          ),
        ],

        if (subs.isNotEmpty) ...[
          if (sources.length > 1 || audios.isNotEmpty) const SizedBox(height: 16),
          Text(
            '字幕 (${subs.length})',
            style: const TextStyle(
              color: VedroTheme.fg3,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TrackChoiceChip(
                label: '默认',
                selected: selectedSubtitleIndex == null,
                onTap: () => onSelectSubtitle(null),
              ),
              ...subs.take(16).map((s) {
                final on = selectedSubtitleIndex == s.index;
                return _TrackChoiceChip(
                  label: s.label,
                  selected: on,
                  onTap: () => onSelectSubtitle(on ? null : s.index),
                );
              }),
            ],
          ),
        ],
      ],
    );
  }
}

class _TrackChoiceChip extends StatelessWidget {
  const _TrackChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      hoverScale: 1.02,
      pressScale: 0.96,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: VedroTheme.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.white : const Color(0xFF16161A),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? VedroTheme.canvas : const Color(0xFFD4D4DA),
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _EpisodeRow extends StatefulWidget {
  const _EpisodeRow({
    required this.episode,
    required this.seriesFallback,
    required this.appState,
    required this.onTap,
    required this.onOpenDetail,
    this.onPickVersion,
  });

  final MediaItemModel episode;
  final MediaItemModel seriesFallback;
  final VedroAppState appState;
  final VoidCallback onTap;
  final VoidCallback onOpenDetail;
  final VoidCallback? onPickVersion;

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
            color: _hovered ? const Color(0xFF1C1C21) : const Color(0xFF131316),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 164,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        VedroArtwork(
                          item: ep,
                          fallbackItem: widget.seriesFallback,
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
                        if (widget.onPickVersion != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: GestureDetector(
                              onTap: widget.onPickVersion,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF222228),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${ep.versionCount} 版本',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (ep.played)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(Icons.check_circle_rounded,
                                size: 16, color: VedroTheme.fg3),
                          ),
                        Tooltip(
                          message: '查看本集详情与媒体规格',
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.more_horiz_rounded,
                                size: 18, color: VedroTheme.fg3),
                            onPressed: widget.onOpenDetail,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (dur.isNotEmpty) dur,
                        if (airDate.isNotEmpty) airDate,
                        if (ep.communityRating != null && ep.communityRating! > 0)
                          '★ ${ep.communityRating!.toStringAsFixed(1)}',
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

/// Scalable Multi-Episode & Multi-Version Batch Download Picker (supports 1,000+ episodes,
/// season switching, version selection, live EmbyGo download quota pre-check & Range queue).
class _BatchDownloadDialog extends StatefulWidget {
  const _BatchDownloadDialog({
    required this.series,
    required this.seasons,
    required this.initialSeasonId,
    required this.initialEpisodes,
    required this.initialVersionKey,
    required this.appState,
    required this.sourceVersionKeyOf,
  });

  final MediaItemModel series;
  final List<MediaItemModel> seasons;
  final String? initialSeasonId;
  final List<MediaItemModel> initialEpisodes;
  final String? initialVersionKey;
  final VedroAppState appState;
  final String Function(MediaSourceModel) sourceVersionKeyOf;

  @override
  State<_BatchDownloadDialog> createState() => _BatchDownloadDialogState();
}

class _BatchDownloadDialogState extends State<_BatchDownloadDialog> {
  String? _seasonId;
  late List<MediaItemModel> _episodes;
  final Map<String, List<MediaItemModel>> _seasonCache = {};
  final Map<String, MediaItemModel> _selectedById = {};
  String? _versionKey;
  int _rangeIdx = 0;
  bool _loadingSeason = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _seasonId = widget.initialSeasonId;
    _episodes = List<MediaItemModel>.from(widget.initialEpisodes);
    if (_seasonId != null) {
      _seasonCache[_seasonId!] = _episodes;
    }
    _versionKey = widget.initialVersionKey;
    _ensureDefaultVersion();
  }

  List<MediaSourceModel> get _availableVersions {
    final seen = <String, MediaSourceModel>{};
    for (final ep in _episodes) {
      for (final s in ep.mediaSources) {
        final k = widget.sourceVersionKeyOf(s);
        seen.putIfAbsent(k, () => s);
      }
    }
    return seen.values.toList();
  }

  void _ensureDefaultVersion() {
    final vers = _availableVersions;
    if (vers.isEmpty) return;
    if (_versionKey == null || !vers.any((v) => widget.sourceVersionKeyOf(v) == _versionKey)) {
      _versionKey = widget.sourceVersionKeyOf(vers.first);
    }
  }

  MediaSourceModel? _resolveSourceFor(MediaItemModel ep) {
    if (ep.mediaSources.isEmpty) return null;
    if (_versionKey != null) {
      for (final s in ep.mediaSources) {
        if (widget.sourceVersionKeyOf(s) == _versionKey) return s;
      }
    }
    return ep.mediaSources.first;
  }

  Future<void> _selectSeason(String seasonId) async {
    if (seasonId == _seasonId) return;
    setState(() {
      _seasonId = seasonId;
      _rangeIdx = 0;
    });
    if (_seasonCache.containsKey(seasonId)) {
      setState(() {
        _episodes = _seasonCache[seasonId]!;
        _ensureDefaultVersion();
      });
      return;
    }
    setState(() => _loadingSeason = true);
    try {
      final eRes = await widget.appState.core.invoke('get_episodes', {
        'series_id': widget.series.id,
        'season_id': seasonId,
        'limit': 5000,
      }) as Map<String, dynamic>;
      final loaded = ((eRes['Items'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MediaItemModel.fromJson)
          .toList();
      _seasonCache[seasonId] = loaded;
      if (mounted && _seasonId == seasonId) {
        setState(() {
          _episodes = loaded;
          _ensureDefaultVersion();
        });
      }
    } finally {
      if (mounted) setState(() => _loadingSeason = false);
    }
  }

  bool _isAlreadyQueuedOrDone(MediaItemModel ep) {
    final src = _resolveSourceFor(ep);
    final existing = widget.appState.findDownloadForItem(ep.id, mediaSourceId: src?.id);
    return existing != null && (existing.status == 'completed' || existing.isActive);
  }

  int get _selectedTotalBytes {
    var total = 0;
    for (final ep in _selectedById.values) {
      total += _resolveSourceFor(ep)?.size ?? 0;
    }
    return total;
  }

  Future<void> _submit() async {
    if (_selectedById.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final ordered = _selectedById.values.toList()
        ..sort((a, b) {
          final sa = a.parentIndexNumber ?? 0;
          final sb = b.parentIndexNumber ?? 0;
          if (sa != sb) return sa.compareTo(sb);
          return (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0);
        });
      final batch = ordered.map((ep) {
        final src = _resolveSourceFor(ep);
        return (
          item: ep,
          mediaSourceId: src?.id,
          versionLabel: src?.name ?? src?.container?.toUpperCase(),
          expectedBytes: src?.size,
        );
      }).toList();

      final added = await widget.appState.enqueueBatchDownloads(batch);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            added > 0
                ? '已加入下载队列：$added 集（支持 HTTP Range 断点续传，设置 → 下载管理）'
                : '所选剧集已在下载队列或已缓存',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF991B1B),
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
            style: const TextStyle(color: Colors.white),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final versions = _availableVersions;
    final totalBytes = _selectedTotalBytes;

    final chunkSize = _episodes.length >= 400 ? 100 : 50;
    final rangeCount = _episodes.isEmpty ? 0 : ((_episodes.length - 1) ~/ chunkSize) + 1;
    final safeRangeIdx = rangeCount == 0 ? 0 : _rangeIdx.clamp(0, rangeCount - 1);
    final start = safeRangeIdx * chunkSize;
    final end = (start + chunkSize).clamp(0, _episodes.length);
    final visibleEps = rangeCount > 1 ? _episodes.sublist(start, end) : _episodes;

    return Dialog(
      key: const ValueKey('detail-batch-download-dialog'),
      backgroundColor: const Color(0xFF141417),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0x18FFFFFF), width: 0.8),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.arrow_downward_rounded, size: 19, color: Colors.white),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '选择下载剧集与版本 · ${widget.series.displayName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: VedroTheme.fg2),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Season switcher (multi-season)
            if (widget.seasons.length > 1)
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  itemCount: widget.seasons.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, idx) {
                    final s = widget.seasons[idx];
                    final active = s.id == _seasonId;
                    return GestureDetector(
                      onTap: () => _selectSeason(s.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: active ? Colors.white : const Color(0xFF1E1E24),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          s.name,
                          style: TextStyle(
                            color: active ? VedroTheme.canvas : VedroTheme.fg2,
                            fontSize: 12.5,
                            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

            // Multi-version selector
            if (versions.length > 1) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '下载版本 (${versions.length})',
                      style: const TextStyle(color: VedroTheme.fg3, fontSize: 11.5, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: versions.map((v) {
                        final vKey = widget.sourceVersionKeyOf(v);
                        final active = vKey == _versionKey;
                        final label = (v.name?.trim().isNotEmpty == true)
                            ? v.name!.trim()
                            : (v.container?.toUpperCase() ?? '原画');
                        return GestureDetector(
                          onTap: () => setState(() => _versionKey = vKey),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
                            decoration: BoxDecoration(
                              color: active ? Colors.white : const Color(0xFF1E1E24),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: active ? VedroTheme.canvas : VedroTheme.fg2,
                                fontSize: 12,
                                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],

            // Range pills + Quick Select actions
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  if (rangeCount > 1)
                    Expanded(
                      child: SizedBox(
                        height: 30,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: rangeCount,
                          separatorBuilder: (_, __) => const SizedBox(width: 6),
                          itemBuilder: (_, rIdx) {
                            final rStart = rIdx * chunkSize;
                            final rEnd = (rStart + chunkSize).clamp(0, _episodes.length);
                            final firstNum = _episodes[rStart].indexNumber ?? (rStart + 1);
                            final lastNum = _episodes[rEnd - 1].indexNumber ?? rEnd;
                            final active = rIdx == safeRangeIdx;
                            return GestureDetector(
                              onTap: () => setState(() => _rangeIdx = rIdx),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: active ? Colors.white : const Color(0xFF1E1E24),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  '$firstNum-$lastNum',
                                  style: TextStyle(
                                    color: active ? VedroTheme.canvas : VedroTheme.fg2,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 8),
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () {
                      setState(() {
                        for (final ep in visibleEps) {
                          if (!_isAlreadyQueuedOrDone(ep)) {
                            _selectedById[ep.id] = ep;
                          }
                        }
                      });
                    },
                    child: Text(rangeCount > 1 ? '全选本段' : '全选', style: const TextStyle(fontSize: 12)),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: VedroTheme.fg2,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () {
                      setState(() {
                        for (final ep in visibleEps) {
                          if (!ep.played && !_isAlreadyQueuedOrDone(ep)) {
                            _selectedById[ep.id] = ep;
                          }
                        }
                      });
                    },
                    child: const Text('选未看', style: TextStyle(fontSize: 12)),
                  ),
                  if (_selectedById.isNotEmpty)
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: VedroTheme.fg3,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () => setState(() => _selectedById.clear()),
                      child: const Text('清空', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Episode list
            Expanded(
              child: _loadingSeason
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2, color: VedroTheme.fg2),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      itemCount: visibleEps.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, idx) {
                        final ep = visibleEps[idx];
                        final src = _resolveSourceFor(ep);
                        final existing =
                            widget.appState.findDownloadForItem(ep.id, mediaSourceId: src?.id);
                        final done = existing != null && existing.status == 'completed';
                        final active = existing != null && existing.isActive;
                        final disabled = done || active;
                        final checked = _selectedById.containsKey(ep.id);
                        final sizeText = fmtFileSize(src?.size);

                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: disabled
                              ? null
                              : () {
                                  setState(() {
                                    if (checked) {
                                      _selectedById.remove(ep.id);
                                    } else {
                                      _selectedById[ep.id] = ep;
                                    }
                                  });
                                },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10.5),
                            decoration: BoxDecoration(
                              color: checked
                                  ? const Color(0xFF25252C)
                                  : const Color(0xFF1A1A1E),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  done
                                      ? Icons.check_circle_rounded
                                      : (checked
                                          ? Icons.check_circle_rounded
                                          : Icons.radio_button_unchecked_rounded),
                                  size: 19,
                                  color: done
                                      ? const Color(0xFF34D399)
                                      : (checked ? Colors.white : VedroTheme.fg3),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${ep.episodeCode ?? 'E${ep.indexNumber ?? idx + 1}'} · ${ep.displayName}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: disabled ? VedroTheme.fg3 : Colors.white,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (src != null && (src.name?.isNotEmpty == true))
                                        Text(
                                          src.name!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: VedroTheme.fg3, fontSize: 11),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (done)
                                  const Text(
                                    '已下载',
                                    style: TextStyle(
                                      color: Color(0xFF34D399),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                else if (active)
                                  const Text(
                                    '队列中',
                                    style: TextStyle(
                                      color: Color(0xFF60A5FA),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                else if (sizeText.isNotEmpty)
                                  Text(
                                    sizeText,
                                    style: const TextStyle(
                                      color: VedroTheme.fg2,
                                      fontSize: 12,
                                      fontFeatures: [FontFeature.tabularFigures()],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Sticky Bottom Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedById.isEmpty
                          ? '请勾选需要下载的剧集'
                          : '已选 ${_selectedById.length} 集${totalBytes > 0 ? ' · 共 ${fmtQuotaBytes(totalBytes)}' : ''}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: VedroTheme.canvas,
                      disabledBackgroundColor: const Color(0xFF28282E),
                      disabledForegroundColor: VedroTheme.fg3,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    onPressed: (_selectedById.isEmpty || _submitting)
                        ? null
                        : _submit,
                    child: Text(
                      _submitting
                          ? '提交中…'
                          : '开始下载${_selectedById.isNotEmpty ? ' (${_selectedById.length})' : ''}',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
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
