import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/models.dart';
import '../core/platform/native_playback_channel.dart';
import '../core/theme/vedro_skin.dart';
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
  int _selectedSourceIndex = 0;
  int _selectedSeriesVersionIndex = 0;
  int? _selectedAudioIndex;
  int? _selectedSubtitleIndex;
  String? _localExternalSubPath;
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
        if (_selectedSourceIndex >= _item.mediaSources.length) {
          _selectedSourceIndex = 0;
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

  List<ResolvedMediaVersion> get _resolvedPlayableVersions =>
      MediaSourceModel.resolveVersions(_item.mediaSources);

  MediaSourceModel? get _activeSource {
    final vers = _resolvedPlayableVersions;
    if (vers.isEmpty) return null;
    final idx = _selectedSourceIndex.clamp(0, vers.length - 1);
    return vers[idx].source;
  }

  /// Collect representative multi-version sources for a Series from the episode with the most versions.
  List<MediaSourceModel> get _seriesSampleSources {
    if (!_item.isSeries || _episodes.isEmpty) return const [];
    List<MediaSourceModel> best = const [];
    for (final ep in _episodes) {
      if (ep.mediaSources.length > best.length) {
        best = ep.mediaSources;
      }
    }
    return best;
  }

  List<ResolvedMediaVersion> get _resolvedSeriesVersions =>
      MediaSourceModel.resolveVersions(_seriesSampleSources);

  MediaSourceModel? _matchingSourceForEpisode(MediaItemModel ep) {
    if (ep.mediaSources.isEmpty) return null;
    if (ep.mediaSources.length == 1) return ep.mediaSources.first;
    final sampleVers = _resolvedSeriesVersions;
    if (sampleVers.isEmpty) return ep.mediaSources.first;
    final chosen = sampleVers[_selectedSeriesVersionIndex.clamp(0, sampleVers.length - 1)];
    final epVers = MediaSourceModel.resolveVersions(ep.mediaSources);

    // 1. Exact directory + release signature match across episodes
    for (final ev in epVers) {
      if (ev.seriesMatchSignature == chosen.seriesMatchSignature) {
        return ev.source;
      }
    }

    // 2. Token overlap on disambiguated title + signature
    final keyTokens = '${chosen.seriesMatchSignature} ${chosen.displayTitle}'
        .toLowerCase()
        .split(RegExp(r'[\s._\-·/|:\[\]]+'))
        .where((t) => t.length >= 2)
        .toSet();
    ResolvedMediaVersion? best;
    var bestScore = 0;
    for (final ev in epVers) {
      final sTokens = '${ev.seriesMatchSignature} ${ev.displayTitle}'
          .toLowerCase()
          .split(RegExp(r'[\s._\-·/|:\[\]]+'))
          .where((t) => t.length >= 2)
          .toSet();
      final score = keyTokens.intersection(sTokens).length;
      if (score > bestScore) {
        bestScore = score;
        best = ev;
      }
    }
    if (best != null && bestScore > 0) return best.source;

    // 3. Deterministic slot fallback
    return ep.mediaSources[_selectedSeriesVersionIndex.clamp(0, ep.mediaSources.length - 1)];
  }

  String? _matchingSourceIdForEpisode(MediaItemModel ep) =>
      _matchingSourceForEpisode(ep)?.id;

  Future<void> _pickExternalSubtitleForDetail() async {
    final picked = await NativePlaybackChannel.pickFiles(
      extensions: NativePlaybackChannel.subtitleExtensions.toList(),
      title: '选择外挂字幕文件 (.srt / .ass / .ssa / .vtt)',
    );
    if (picked.isNotEmpty) {
      if (mounted) {
        setState(() {
          _localExternalSubPath = picked.first;
          if (_selectedSubtitleIndex == -1) _selectedSubtitleIndex = null;
        });
      }
      return;
    }
    if (!mounted) return;
    final isDesktop = !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    if (!isDesktop) {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('挂载本地外挂字幕'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: '/path/to/subtitle.ass'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
          ],
        ),
      );
      final p = ctrl.text.trim();
      ctrl.dispose();
      if (ok == true && p.isNotEmpty && mounted) {
        setState(() {
          _localExternalSubPath = p;
          if (_selectedSubtitleIndex == -1) _selectedSubtitleIndex = null;
        });
      }
    }
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
    final resolved = MediaSourceModel.resolveVersions(target.mediaSources);
    if (resolved.isEmpty) {
      _openItemDetail(target);
      return;
    }
    final matchedSrc = _matchingSourceForEpisode(target);
    var activeIdx = resolved.indexWhere((r) => identical(r.source, matchedSrc));
    if (activeIdx < 0) {
      activeIdx = _selectedSeriesVersionIndex.clamp(0, resolved.length - 1);
    }
    final skin = VedroSkin.of(context);
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
                  '选择片源版本 (${resolved.length})',
                  style: TextStyle(
                    color: skin.fg,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${target.episodeCode ?? ''} ${target.displayName}'.trim(),
                  style: TextStyle(color: skin.fg2, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < resolved.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _VersionOptionTile(
                version: resolved[i],
                totalCount: resolved.length,
                selected: i == activeIdx,
                accent: skin.accent,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _selectedSeriesVersionIndex = i);
                  _play(target, sourceId: resolved[i].source.id);
                },
              ),
            ),
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
        initialAudioStreamIndex: _selectedAudioIndex,
        initialSubtitleStreamIndex: _selectedSubtitleIndex,
        initialExternalSubtitlePath: _localExternalSubPath,
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
    return _matchingSourceForEpisode(target);
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
        mediaSourceId: source?.id ?? (target.id == _item.id ? _activeSource?.id : null),
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
    final resolved = MediaSourceModel.resolveVersions(target.mediaSources);
    if (resolved.isEmpty) return;
    final dq = widget.appState.meQuota?.downloadQuota;
    final activeIdx = _selectedSourceIndex.clamp(0, resolved.length - 1);
    final skin = VedroSkin.of(context);

    showGlassSheet<void>(
      context: context,
      builder: (ctx) => ListView(
        key: const ValueKey('detail-version-download-sheet'),
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
        children: [
          Row(
            children: [
              Icon(Icons.download_rounded, size: 19, color: skin.fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '选择下载版本 (${resolved.length})',
                  style: TextStyle(color: skin.fg, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, color: skin.fg2, size: 19),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < resolved.length; i++) ...[
            Builder(
              builder: (_) {
                final ver = resolved[i];
                final s = ver.source;
                final existing = widget.appState.findDownloadForItem(target.id, mediaSourceId: s.id);
                final alreadyDone = existing != null && existing.status == 'completed';
                final inProgress = existing != null && existing.isActive;
                final tooLarge = dq != null &&
                    dq.enabled &&
                    !dq.adminExempt &&
                    s.size != null &&
                    s.size! > 0 &&
                    !dq.canFitBytes(s.size);
                final selected = i == activeIdx;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: selected ? skin.surface3 : skin.surface2,
                      borderRadius: BorderRadius.circular(skin.cardRadius.clamp(8.0, 16.0)),
                      border: skin.cardBorder(selected: selected),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ver.displayTitle,
                                style: TextStyle(
                                  color: skin.fg,
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
                                        color: tooLarge ? const Color(0xFFEF4444) : skin.fg2,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  if (s.container != null && s.container!.isNotEmpty)
                                    Text(
                                      s.container!.toUpperCase(),
                                      style: TextStyle(color: skin.fg3, fontSize: 12),
                                    ),
                                  if (s.bitrate != null && s.bitrate! > 0)
                                    Text(
                                      '${(s.bitrate! / 1000000).toStringAsFixed(1)} Mbps',
                                      style: TextStyle(color: skin.fg3, fontSize: 12),
                                    ),
                                  if (tooLarge)
                                    const Text(
                                      '余额不足',
                                      style: TextStyle(
                                        color: Color(0xFFEF4444),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  if (alreadyDone)
                                    const Text(
                                      '已下载',
                                      style: TextStyle(
                                        color: Color(0xFF10B981),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  else if (inProgress)
                                    Text(
                                      '下载队列中',
                                      style: TextStyle(
                                        color: skin.accent,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: alreadyDone ? skin.surface3 : skin.activePillBg,
                            foregroundColor: alreadyDone ? skin.fg : skin.activePillFg,
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                            minimumSize: const Size(0, 34),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(skin.radiusForPill(34)),
                            ),
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
              },
            ),
          ],
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
        initialVersionIndex: _selectedSeriesVersionIndex,
        appState: widget.appState,
      ),
    );
  }

  void _openMoreSheet() {
    final playable = _resolveDownloadTarget();
    final canDownload = widget.appState.canDownloadItem(playable);
    final skin = VedroSkin.of(context);
    showGlassSheet<void>(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('更多操作', style: TextStyle(color: skin.fg, fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          if (playable != null) ...[
            ListTile(
              leading: Icon(Icons.subtitles_outlined, color: skin.fg2),
              title: Text('挂载本地外挂字幕 (.srt / .ass)', style: TextStyle(color: skin.fg, fontSize: 14)),
              subtitle: Text(
                _localExternalSubPath != null
                    ? '已选：${_localExternalSubPath!.split(Platform.pathSeparator).last}'
                    : '开播时自动加载指定本地字幕文件',
                style: TextStyle(color: skin.fg3, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickExternalSubtitleForDetail();
              },
            ),
            ListTile(
              leading: Icon(Icons.open_in_new_rounded, color: skin.fg2),
              title: Text('使用外部播放器打开', style: TextStyle(color: skin.fg, fontSize: 14)),
              subtitle: Text('IINA / Infuse / MPV / VLC', style: TextStyle(color: skin.fg3, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _launchExternal(playable, sourceId: _resolveDownloadSource(playable)?.id ?? _activeSource?.id);
              },
            ),
            if (canDownload)
              ListTile(
                leading: Icon(Icons.download_rounded, color: skin.fg2),
                title: Text(
                  _item.isSeries
                      ? '批量下载剧集（选集与版本）'
                      : (_item.mediaSources.length > 1 ? '离线下载到本地（选择版本）' : '离线下载到本地'),
                  style: TextStyle(color: skin.fg, fontSize: 14),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _startDownload();
                },
              ),
          ],
          if (_item.type != 'Person')
            ListTile(
              leading: Icon(Icons.playlist_add_rounded, color: skin.fg2),
              title: Text('加入片单', style: TextStyle(color: skin.fg, fontSize: 14)),
              onTap: () {
                Navigator.pop(ctx);
                _openPlaylistSheet();
              },
            ),
          if (widget.appState.prefs.isAiReady && _item.cleanOverview.isNotEmpty)
            ListTile(
              leading: Icon(Icons.auto_awesome_rounded, color: skin.fg2),
              title: Text(
                _translatedOverview != null ? '还原原始简介' : 'AI 翻译简介',
                style: TextStyle(color: skin.fg, fontSize: 14),
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
    final skin = VedroSkin.of(context);
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 820;
    final ultraWide = size.width >= 1080;
    final padX = wide ? 44.0 : 20.0;
    final isMac = !kIsWeb && Platform.isMacOS;
    final topSafe = MediaQuery.paddingOf(context).top;
    final logoUrl = _item.type == 'Episode' ? null : widget.appState.logoArtUrl(_item);
    final src = _activeSource;
    final accent = skin.accent;
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

    final playableVersions = _resolvedPlayableVersions;
    final seriesVersions = _resolvedSeriesVersions;
    if (_selectedSeriesVersionIndex >= seriesVersions.length && seriesVersions.isNotEmpty) {
      _selectedSeriesVersionIndex = 0;
    }
    final activeSeriesEpSource =
        nextEpToPlay != null ? _matchingSourceForEpisode(nextEpToPlay) : null;

    final isEpisodeWithStill = _item.type == 'Episode' && _item.primaryImageTag != null;
    final coverW = _item.type == 'Person'
        ? (wide ? 156.0 : 104.0)
        : isEpisodeWithStill
            ? (wide ? 260.0 : 148.0)
            : (wide ? 188.0 : 112.0);
    final coverAspect = _item.type == 'Person'
        ? 1.0
        : (isEpisodeWithStill ? 16 / 9 : 2 / 3);

    // Editorial eyebrow (Studio + Type)
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
            sourceId: _activeSource?.id,
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
            color: skin.fg,
            onTap: () => _play(_item, sourceId: _activeSource?.id, fromBeginning: true),
          ),
        if (_item.type != 'Person')
          (
            key: null,
            icon: Icons.check_rounded,
            label: _item.played ? '已看' : '标已看',
            tooltip: _item.played ? '已看（点击取消）' : '标为已看',
            active: _item.played,
            color: _item.played ? accent : skin.fg,
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
          color: _item.isFavorite ? VedroTheme.danger : skin.fg,
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
            color: localReady ? const Color(0xFF10B981) : skin.fg,
            onTap: localReady
                ? () => _play(downloadTarget ?? _item, localPath: dlTask.filePath)
                : _startDownload,
          ),
        (
          key: null,
          icon: Icons.more_horiz_rounded,
          label: '更多',
          tooltip: '更多（字幕挂载 / 外部播放器 / 片单 / AI 翻译）',
          active: false,
          color: skin.fg,
          onTap: _openMoreSheet,
        ),
      ];

      return LayoutBuilder(
        builder: (ctx, constraints) {
          final singleLine = constraints.maxWidth >= 460;
          if (singleLine) {
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
                              backgroundColor: skin.fg.withValues(alpha: 0.16),
                              color: skin.ctaStyle == 'contrast' ? skin.fg : accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '已看 ${(playProgress * 100).round()}%',
                          style: TextStyle(
                            color: skin.fg2,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          }

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
                            backgroundColor: skin.fg.withValues(alpha: 0.16),
                            color: skin.ctaStyle == 'contrast' ? skin.fg : accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '已观看 ${(playProgress * 100).round()}%',
                        style: TextStyle(
                          color: skin.fg2,
                          fontSize: 11.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
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
                                : skin.subtleChipBg,
                            borderRadius: BorderRadius.circular(skin.cardRadius.clamp(8.0, 14.0)),
                            border: skin.frameStyle == 'borderless'
                                ? null
                                : Border.all(color: skin.border, width: 0.7),
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
                                  color: actions[i].active ? actions[i].color : skin.fg2,
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
              style: TextStyle(
                color: skin.fg,
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
              collapsedLines: 3,
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

    final dotFacts = <Widget>[];
    void addDotFact(Widget w) {
      if (dotFacts.isNotEmpty) {
        dotFacts.add(Text(
          ' · ',
          style: TextStyle(color: skin.fg3, fontSize: 13.5),
        ));
      }
      dotFacts.add(w);
    }

    if (premiere.isNotEmpty) {
      addDotFact(Text(
        premiere,
        style: TextStyle(
          color: skin.fg2,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ));
    } else if (_item.productionYear != null) {
      addDotFact(Text(
        '${_item.productionYear}',
        style: TextStyle(
          color: skin.fg2,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
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
              style: TextStyle(
                color: skin.fg2,
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
        style: TextStyle(color: skin.fg2, fontSize: 13.5),
      ));
    }

    if (!_item.isFolderish && fmtDurationTicks(_item.runTimeTicks).isNotEmpty) {
      addDotFact(Text(
        fmtDurationTicks(_item.runTimeTicks),
        style: TextStyle(color: skin.fg2, fontSize: 13.5),
      ));
    } else if (_item.isSeries && fmtDurationTicks(_item.runTimeTicks).isNotEmpty) {
      addDotFact(Text(
        '单集 ${fmtDurationTicks(_item.runTimeTicks)}',
        style: TextStyle(color: skin.fg3, fontSize: 13.5),
      ));
    }

    if (_item.productionLocations.isNotEmpty) {
      addDotFact(Text(
        _item.productionLocations.take(2).join(' / '),
        style: TextStyle(color: skin.fg3, fontSize: 13.5),
      ));
    }

    final heroCreditRows = <(String role, String names)>[
      if (directors.isNotEmpty) ('导演', directors.take(2).join('、')),
      if (castNames.isNotEmpty) ('主演', castNames.join('、')),
      if (_item.studios.isNotEmpty) ('出品', _item.studios.take(2).join('、')),
      if (statusLabel.isNotEmpty) ('状态', statusLabel),
    ];

    final posterRadius = widget.appState.prefs.effectiveCardRadius(skin);
    Widget coverCard = GestureDetector(
      onTap: _openPosterLightbox,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          key: const ValueKey('detail-poster-cover'),
          width: coverW,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(posterRadius),
            color: skin.surface2,
            boxShadow: skin.posterShadow(hovered: true),
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(posterRadius),
            border: skin.cardBorder(hovered: false),
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

    final c = skin.canvas;
    final heroVertStops = skin.isLight
        ? const [0.0, 0.24, 0.54, 0.82, 1.0]
        : const [0.0, 0.22, 0.56, 0.84, 1.0];
    final heroVertColors = skin.isLight
        ? [
            c.withValues(alpha: 0.58),
            c.withValues(alpha: 0.68),
            c.withValues(alpha: 0.89),
            c.withValues(alpha: 0.98),
            c,
          ]
        : [
            c.withValues(alpha: 0.35),
            c.withValues(alpha: 0.10),
            c.withValues(alpha: 0.64),
            c.withValues(alpha: 0.92),
            c,
          ];

    return Scaffold(
      backgroundColor: skin.canvas,
      body: VedroSkinCanvas(
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                // 1. Seamless Full-Stage Immersive Hero dissolving smoothly into active skin canvas
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
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                      stops: const [0.0, 0.55, 1.0],
                                      colors: [
                                        c.withValues(alpha: skin.isLight ? 0.86 : 0.78),
                                        c.withValues(alpha: skin.isLight ? 0.55 : 0.40),
                                        c.withValues(alpha: skin.isLight ? 0.25 : 0.22),
                                      ],
                                    ),
                                  ),
                                ),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    stops: heroVertStops,
                                    colors: heroVertColors,
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
                                            style: TextStyle(
                                              color: skin.ctaStyle == 'contrast' ? skin.fg3 : skin.accent,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.6,
                                            ),
                                          ),
                                        ),

                                      if (wide && logoUrl != null && !skin.isLight)
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
                                          style: TextStyle(
                                            color: skin.fg3,
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
                                                      size: 15.5, color: Color(0xFFF59E0B)),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    _item.communityRating!.toStringAsFixed(1),
                                                    style: TextStyle(
                                                      color: skin.fg,
                                                      fontSize: 13.5,
                                                      fontWeight: FontWeight.w700,
                                                      fontFeatures: const [FontFeature.tabularFigures()],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            if (_item.criticRating != null &&
                                                _item.criticRating! > 0)
                                              Text(
                                                '${_item.criticRating!.round()}% 好评',
                                                style: TextStyle(
                                                  color: skin.fg2,
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                  fontFeatures: const [FontFeature.tabularFigures()],
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
                                                    style: TextStyle(
                                                      color: skin.fg3,
                                                      fontSize: 12.5,
                                                      fontWeight: FontWeight.w500,
                                                      height: 1.45,
                                                    ),
                                                  ),
                                                  TextSpan(
                                                    text: heroCreditRows[i].$2,
                                                    style: TextStyle(
                                                      color: skin.fg2,
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

                // 2. Body Content: Strictly Single-Select Version Grid + Always-Visible Audio & Subtitle Selector!
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_item.isPlayable || _item.isSeries) ...[
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: padX),
                          child: _TracksPanel(
                            isSeries: _item.isSeries,
                            versions: _item.isSeries ? seriesVersions : playableVersions,
                            selectedVersionIndex: _item.isSeries
                                ? _selectedSeriesVersionIndex
                                : _selectedSourceIndex,
                            activeStreamSource: _item.isSeries ? activeSeriesEpSource : src,
                            selectedAudioIndex: _selectedAudioIndex,
                            selectedSubtitleIndex: _selectedSubtitleIndex,
                            localExternalSubPath: _localExternalSubPath,
                            appState: widget.appState,
                            onSelectVersionIndex: (idx) => setState(() {
                              if (_item.isSeries) {
                                _selectedSeriesVersionIndex = idx;
                              } else {
                                _selectedSourceIndex = idx;
                              }
                              _selectedAudioIndex = null;
                              if (_selectedSubtitleIndex != -1) {
                                _selectedSubtitleIndex = null;
                              }
                            }),
                            onSelectAudio: (idx) => setState(() => _selectedAudioIndex = idx),
                            onSelectSubtitle: (idx) => setState(() {
                              _selectedSubtitleIndex = idx;
                              if (idx != null) _localExternalSubPath = null;
                            }),
                            onPickExternalSubtitle: _pickExternalSubtitleForDetail,
                            onClearExternalSubtitle: () =>
                                setState(() => _localExternalSubPath = null),
                          ),
                        ),
                        const SizedBox(height: 30),
                      ],

                      // 2c. TV Series Seasons & Scalable Episode Selector
                      if (_seasons.isNotEmpty) ...[
                        _buildEpisodeSection(
                          wide: wide,
                          padX: padX,
                          accent: accent,
                          nextEpToPlay: nextEpToPlay,
                        ),
                        const SizedBox(height: 34),
                      ],

                      // 2d. Circular Cast & Crew Medallions
                      if (_item.people.isNotEmpty) ...[
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: padX),
                          child: Row(
                            children: [
                              Text(
                                '演职人员',
                                style: skin.applyHeadlineMood(
                                  TextStyle(
                                    color: skin.fg,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.4,
                                  ),
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
                                    style: TextStyle(color: skin.fg3, fontSize: 13),
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
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: skin.surface2,
                                        boxShadow: skin.posterShadow(),
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
                                      style: TextStyle(
                                        color: skin.fg,
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
                                      style: TextStyle(color: skin.fg3, fontSize: 11.5),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 28),
                      ],

                      // 2e. Chapters Strip
                      if (_item.chapters.isNotEmpty && _item.isPlayable) ...[
                        _ChaptersSection(
                          chapters: _item.chapters,
                          padX: padX,
                          accent: accent,
                          onSelectChapter: (ticks) => _play(
                            _item,
                            sourceId: _activeSource?.id,
                            startPositionTicks: ticks,
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ],
                  ),
                ),

                // 3. Related Recommendations Rail
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

                // 4. Editorial Information & Technical Specs Footer
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
                            style: skin.applyHeadlineMood(
                              TextStyle(
                                color: skin.fg,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                              ),
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
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: skin.fg2),
                        ),
                      ),
                    ),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 56)),
              ],
            ),

            // Floating frosted Back Pill
            Positioned(
              top: topSafe + 12,
              left: isMac ? 82 : (padX - 4),
              child: PressableScale(
                onTap: () => Navigator.of(context).pop(),
                hoverScale: 1.04,
                pressScale: 0.92,
                child: GlassSurface(
                  borderRadius: skin.radiusForPill(36),
                  blur: 24,
                  color: skin.glass,
                  borderColor: skin.borderStrong,
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7.5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_ios_new_rounded, size: 13.5, color: skin.fg),
                      const SizedBox(width: 4),
                      Text(
                        '返回',
                        style: TextStyle(color: skin.fg, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
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
    final skin = VedroSkin.of(context);
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
                            color: skin.surface2,
                            borderRadius: BorderRadius.circular(skin.radiusForPill(38)),
                            border: skin.frameStyle == 'borderless'
                                ? null
                                : Border.all(color: skin.border, width: 0.7),
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
                                      color: active ? skin.activePillBg : Colors.transparent,
                                      borderRadius: BorderRadius.circular(skin.radiusForPill(32)),
                                    ),
                                    child: Text(
                                      s.name,
                                      style: TextStyle(
                                        color: active ? skin.activePillFg : skin.fg2,
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
                            style: skin.applyHeadlineMood(
                              TextStyle(
                                color: skin.fg,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '共 ${_episodes.length} 集',
                            style: TextStyle(
                              color: skin.fg3,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              fontFeatures: const [FontFeature.tabularFigures()],
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
                            style: TextStyle(
                              color: skin.fg3,
                              fontSize: 12.5,
                              fontFeatures: const [FontFeature.tabularFigures()],
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
                                color: skin.surface2,
                                borderRadius: BorderRadius.circular(skin.radiusForPill(32)),
                                border: skin.frameStyle == 'borderless'
                                    ? null
                                    : Border.all(color: skin.border, width: 0.7),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.arrow_downward_rounded, size: 14, color: skin.fg),
                                  const SizedBox(width: 5),
                                  Text(
                                    '批量下载',
                                    style: TextStyle(
                                      color: skin.fg,
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
                              color: skin.surface2,
                              borderRadius: BorderRadius.circular(skin.radiusForPill(32)),
                              border: skin.frameStyle == 'borderless'
                                  ? null
                                  : Border.all(color: skin.border, width: 0.7),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _episodeDescending
                                      ? Icons.arrow_upward_rounded
                                      : Icons.arrow_downward_rounded,
                                  size: 13.5,
                                  color: skin.fg2,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _episodeDescending ? '倒序' : '正序',
                                  style: TextStyle(
                                    color: skin.fg2,
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
                            color: skin.surface2,
                            borderRadius: BorderRadius.circular(skin.radiusForPill(32)),
                            border: skin.frameStyle == 'borderless'
                                ? null
                                : Border.all(color: skin.border, width: 0.7),
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
                    style: TextStyle(
                      color: skin.fg2,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ],

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
                                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: active ? skin.activePillBg : skin.surface2,
                                        borderRadius: BorderRadius.circular(skin.radiusForPill(32)),
                                        border: (!active && skin.frameStyle != 'borderless')
                                            ? Border.all(color: skin.border, width: 0.7)
                                            : null,
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '$firstNum-$lastNum',
                                        style: TextStyle(
                                          color: active ? skin.activePillFg : skin.fg2,
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
                        style: TextStyle(color: skin.fg, fontSize: 12.5),
                        decoration: InputDecoration(
                          hintText: '跳集 / 搜集名',
                          hintStyle: TextStyle(color: skin.fg3, fontSize: 12),
                          prefixIcon: Icon(Icons.search_rounded, size: 15, color: skin.fg3),
                          prefixIconConstraints: const BoxConstraints(minWidth: 30),
                          suffixIcon: _episodeFilterQuery.isNotEmpty
                              ? IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: Icon(Icons.cancel_rounded, size: 14, color: skin.fg3),
                                  onPressed: () {
                                    _episodeJumpCtrl.clear();
                                    setState(() => _episodeFilterQuery = '');
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          fillColor: skin.surface2,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(skin.radiusForPill(32)),
                            borderSide: BorderSide(color: skin.border, width: 0.7),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(skin.radiusForPill(32)),
                            borderSide: skin.frameStyle == 'borderless'
                                ? BorderSide.none
                                : BorderSide(color: skin.border, width: 0.7),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(skin.radiusForPill(32)),
                            borderSide: BorderSide(color: skin.accent, width: 1),
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
            child: Text('没有匹配的分集', style: TextStyle(color: skin.fg3, fontSize: 13)),
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
                final tileR = skin.cardRadius.clamp(6.0, 12.0);
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
                                ? skin.activePillBg
                                : (ep.played
                                    ? skin.surface.withValues(alpha: 0.65)
                                    : skin.surface),
                            borderRadius: BorderRadius.circular(tileR),
                            border: isNext ? null : skin.cardBorder(),
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
                                          ? skin.activePillFg
                                          : (ep.played ? skin.fg3 : skin.fg),
                                      fontSize: wide ? 14 : 13,
                                      fontWeight: isNext ? FontWeight.w700 : FontWeight.w600,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ),
                              ),
                              if (ep.played && !isNext)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Icon(Icons.check_rounded, size: 11, color: skin.fg3),
                                )
                              else if (ep.versionCount > 1)
                                Positioned(
                                  top: 3,
                                  right: 5,
                                  child: Text(
                                    '${ep.versionCount}×',
                                    style: TextStyle(
                                      color: isNext ? skin.activePillFg : skin.fg3,
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
                                    color: isNext ? skin.activePillFg : accent,
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
    final skin = VedroSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2.5),
      decoration: BoxDecoration(
        color: skin.subtleChipBg,
        borderRadius: BorderRadius.circular(4.5),
        border: skin.frameStyle == 'neon'
            ? Border.all(color: skin.accent.withValues(alpha: 0.35), width: 0.6)
            : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: skin.fg,
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
    final skin = VedroSkin.of(context);
    final isSquareish = skin.pillRadius < 20;
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
          shape: isSquareish ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: isSquareish ? BorderRadius.circular(skin.pillRadius) : null,
          color: widget.active
              ? widget.color.withValues(alpha: 0.20)
              : (_hovered ? skin.subtleChipHoverBg : skin.subtleChipBg),
          border: skin.frameStyle == 'borderless'
              ? null
              : Border.all(color: _hovered ? skin.borderStrong : skin.border, width: 0.8),
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
    final skin = VedroSkin.of(context);
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
              color: active ? skin.activePillBg : Colors.transparent,
              borderRadius: BorderRadius.circular(skin.radiusForPill(26)),
            ),
            child: Icon(
              icon,
              size: 14.5,
              color: active ? skin.activePillFg : skin.fg3,
            ),
          ),
        ),
      ),
    );
  }
}

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
    final skin = VedroSkin.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: padX),
          child: Text(
            '章节导览 (${chapters.length})',
            style: skin.applyHeadlineMood(
              TextStyle(
                color: skin.fg,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
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
                      color: skin.surface,
                      borderRadius: BorderRadius.circular(skin.cardRadius.clamp(6.0, 14.0)),
                      border: skin.cardBorder(),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          ts,
                          style: TextStyle(
                            color: skin.fg3,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          style: TextStyle(
                            color: skin.fg,
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
    final skin = VedroSkin.of(context);
    final style = TextStyle(
      color: skin.isLight ? skin.fg2 : skin.fg.withValues(alpha: 0.88),
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
                          style: TextStyle(
                            color: skin.fg,
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

    final skin = VedroSkin.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: skin.surface,
        borderRadius: BorderRadius.circular(skin.cardRadius.clamp(8.0, 22.0)),
        border: skin.cardBorder(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '影片资料与 NFO 信息',
            style: skin.applyHeadlineMood(
              TextStyle(
                color: skin.fg,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
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
                            style: TextStyle(
                              color: skin.fg3,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 3),
                          SelectableText(
                            f.$2,
                            style: TextStyle(
                              color: skin.fg,
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
            Text('标签', style: TextStyle(color: skin.fg3, fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: item.tags.take(24).map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    color: skin.surface2,
                    borderRadius: BorderRadius.circular(skin.radiusForPill(28)),
                  ),
                  child: Text(
                    '# $tag',
                    style: TextStyle(color: skin.fg2, fontSize: 12),
                  ),
                );
              }).toList(),
            ),
          ],
          if (item.remoteTrailers.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('官方预告片', style: TextStyle(color: skin.fg3, fontSize: 12, fontWeight: FontWeight.w500)),
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
                      color: skin.surface2,
                      borderRadius: BorderRadius.circular(skin.radiusForPill(32)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_circle_outline_rounded, size: 15, color: skin.fg),
                        const SizedBox(width: 5),
                        Text(label, style: TextStyle(color: skin.fg, fontSize: 12.5)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          if (links.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('资料索引', style: TextStyle(color: skin.fg3, fontSize: 12, fontWeight: FontWeight.w500)),
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
                      color: skin.surface2,
                      borderRadius: BorderRadius.circular(skin.radiusForPill(32)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayId,
                          style: TextStyle(
                            color: skin.fg,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (url != null) ...[
                          const SizedBox(width: 5),
                          Icon(Icons.arrow_outward_rounded, size: 12.5, color: skin.fg3),
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
    final skin = VedroSkin.of(context);
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
        color: skin.surface,
        borderRadius: BorderRadius.circular(skin.cardRadius.clamp(8.0, 22.0)),
        border: skin.cardBorder(),
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
              Text(
                '技术规格',
                style: skin.applyHeadlineMood(
                  TextStyle(
                    color: skin.fg,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (source.container != null && source.container!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: skin.surface2,
                    borderRadius: BorderRadius.circular(skin.radiusForPill(24)),
                  ),
                  child: Text(
                    [
                      source.container!.toUpperCase(),
                      if (fmtFileSize(source.size).isNotEmpty) fmtFileSize(source.size),
                      if ((source.bitrate ?? 0) > 0)
                        '${(source.bitrate! / 1000000).toStringAsFixed(1)} Mbps',
                    ].join(' · '),
                    style: TextStyle(
                      color: skin.fg2,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
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
            Text('媒体路径', style: TextStyle(color: skin.fg3, fontSize: 11.5)),
            const SizedBox(height: 3),
            SelectableText(
              filePath,
              style: TextStyle(
                color: skin.fg2,
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
    final skin = VedroSkin.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: skin.fg3, fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                line,
                style: TextStyle(
                  color: skin.fg,
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()],
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
    final skin = VedroSkin.of(context);
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: skin.applyHeadlineMood(
        TextStyle(
          color: skin.fg,
          fontSize: wide ? 40 : 26,
          fontWeight: FontWeight.w700,
          letterSpacing: wide ? -0.9 : -0.6,
          height: 1.1,
        ),
      ),
    );
  }
}

/// Skin-adaptive Primary Play CTA button (supports contrast, accent, dual-tone gradient, and outline styles).
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
    final skin = VedroSkin.of(context);
    final h = fullWidth ? 50.0 : 46.0;
    final r = fullWidth ? skin.cardRadius.clamp(6.0, 16.0) : skin.radiusForPill(h);
    return PressableScale(
      onTap: onTap,
      hoverScale: fullWidth ? 1.015 : 1.03,
      pressScale: 0.96,
      child: Container(
        height: h,
        width: fullWidth ? double.infinity : null,
        constraints: fullWidth
            ? const BoxConstraints(minHeight: 50)
            : const BoxConstraints(minWidth: 152, maxWidth: 296),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: skin.primaryCtaBg,
          gradient: skin.primaryCtaGradient,
          borderRadius: BorderRadius.circular(r),
          border: skin.primaryCtaBorder,
          boxShadow: skin.primaryCtaShadow,
        ),
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_arrow_rounded, size: 23, color: skin.primaryCtaFg),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: skin.primaryCtaFg,
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
    final skin = VedroSkin.of(context);
    final ep = widget.episode;
    final hasProgress = ep.resumeProgress > 0.01;
    final airDate = fmtIsoDate(ep.premiereDate);
    final dur = fmtDurationTicks(ep.runTimeTicks);
    final epOverview = ep.cleanOverview;
    final cardR = widget.appState.prefs.effectiveCardRadius(skin);

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
                  borderRadius: BorderRadius.circular(cardR),
                  color: skin.surface2,
                  boxShadow: skin.posterShadow(hovered: _hovered),
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(cardR),
                  border: skin.cardBorder(hovered: _hovered),
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
                    IgnorePointer(
                      ignoring: !_hovered,
                      child: AnimatedOpacity(
                        opacity: _hovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 160),
                        child: Center(
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: skin.primaryCtaBg,
                              gradient: skin.primaryCtaGradient,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              size: 24,
                              color: skin.primaryCtaFg,
                            ),
                          ),
                        ),
                      ),
                    ),
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
                            color: skin.ctaStyle == 'contrast' ? Colors.white : skin.accent,
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
                    style: TextStyle(
                      color: skin.fg3,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                const Spacer(),
                if (ep.played)
                  Icon(Icons.check_circle_rounded, size: 13.5, color: skin.fg3),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              ep.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: skin.fg,
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
                style: TextStyle(color: skin.fg2, fontSize: 12, height: 1.42),
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
              style: TextStyle(
                color: skin.fg3,
                fontSize: 11.5,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Strictly single-select Version Option Card with smart disambiguated title & compact index pill.
class _VersionOptionTile extends StatelessWidget {
  const _VersionOptionTile({
    super.key,
    required this.version,
    required this.totalCount,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final ResolvedMediaVersion version;
  final int totalCount;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final source = version.source;
    final video = source.videoStreams.isNotEmpty ? source.videoStreams.first : null;
    final tags = <String>[
      if (version.folderBadge != null && version.folderBadge!.isNotEmpty) version.folderBadge!,
      if (video != null && video.height != null) '${video.height}p',
      if (video?.codec != null && video!.codec!.isNotEmpty) video.codec!.toUpperCase(),
      if (source.container != null && source.container!.isNotEmpty) source.container!.toUpperCase(),
      if (fmtFileSize(source.size).isNotEmpty) fmtFileSize(source.size),
      if ((source.bitrate ?? 0) > 0) '${(source.bitrate! / 1000000).toStringAsFixed(1)} Mbps',
      if (source.audioStreams.isNotEmpty) '${source.audioStreams.length} 音轨',
      if (source.subtitleStreams.isNotEmpty) '${source.subtitleStreams.length} 字幕',
    ];
    final compact = totalCount >= 4;
    final r = skin.cardRadius.clamp(6.0, 16.0);

    return PressableScale(
      onTap: onTap,
      hoverScale: 1.01,
      pressScale: 0.98,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: VedroTheme.easeOut,
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 13 : 16,
          vertical: compact ? 10.5 : 13,
        ),
        decoration: BoxDecoration(
          color: selected ? skin.surface2 : skin.surface,
          borderRadius: BorderRadius.circular(r),
          border: skin.cardBorder(selected: selected),
          boxShadow: selected && skin.isLight
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (totalCount > 2) ...[
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? skin.activePillBg : skin.subtleChipBg,
                  borderRadius: BorderRadius.circular(skin.radiusForPill(24)),
                ),
                child: Text(
                  '${version.index + 1}',
                  style: TextStyle(
                    color: selected ? skin.activePillFg : skin.fg3,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    version.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? skin.fg : skin.fg2,
                      fontSize: compact ? 13 : 13.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      tags.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: skin.fg3,
                        fontSize: 11.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: skin.activePillBg,
                  borderRadius: BorderRadius.circular(skin.radiusForPill(20)),
                ),
                child: Text(
                  '当前',
                  style: TextStyle(
                    color: skin.activePillFg,
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

/// Unified, Always-Available Version + Audio + Subtitle Control Deck for Movies, Episodes, AND Series!
/// - Strictly single-selects version by integer index (never highlights >1 version even when 4+ share Name/Id)
/// - Always surfaces Audio & Subtitle selection (real probed tracks when available, or language priority + local .srt/.ass mount when unprobed on embygo!)
class _TracksPanel extends StatelessWidget {
  const _TracksPanel({
    required this.isSeries,
    required this.versions,
    required this.selectedVersionIndex,
    required this.activeStreamSource,
    required this.selectedAudioIndex,
    required this.selectedSubtitleIndex,
    required this.localExternalSubPath,
    required this.appState,
    required this.onSelectVersionIndex,
    required this.onSelectAudio,
    required this.onSelectSubtitle,
    required this.onPickExternalSubtitle,
    required this.onClearExternalSubtitle,
  });

  final bool isSeries;
  final List<ResolvedMediaVersion> versions;
  final int selectedVersionIndex;
  final MediaSourceModel? activeStreamSource;
  final int? selectedAudioIndex;
  final int? selectedSubtitleIndex;
  final String? localExternalSubPath;
  final VedroAppState appState;
  final ValueChanged<int> onSelectVersionIndex;
  final ValueChanged<int?> onSelectAudio;
  final ValueChanged<int?> onSelectSubtitle;
  final VoidCallback onPickExternalSubtitle;
  final VoidCallback onClearExternalSubtitle;

  void _openAllTracksSheet({
    required BuildContext context,
    required String title,
    required List<MediaStreamModel> tracks,
    required int? selectedIndex,
    required ValueChanged<int?> onSelect,
    bool allowOff = false,
  }) {
    final skin = VedroSkin.of(context);
    showGlassSheet<void>(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(
              '$title (${tracks.length})',
              style: TextStyle(color: skin.fg, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          ListTile(
            dense: true,
            title: Text('默认自动', style: TextStyle(color: skin.fg, fontSize: 13.5)),
            trailing: selectedIndex == null ? Icon(Icons.check_rounded, size: 18, color: skin.accent) : null,
            onTap: () {
              Navigator.pop(ctx);
              onSelect(null);
            },
          ),
          if (allowOff)
            ListTile(
              dense: true,
              title: Text('关闭字幕', style: TextStyle(color: skin.fg, fontSize: 13.5)),
              trailing: selectedIndex == -1 ? Icon(Icons.check_rounded, size: 18, color: skin.accent) : null,
              onTap: () {
                Navigator.pop(ctx);
                onSelect(-1);
              },
            ),
          for (final t in tracks)
            ListTile(
              dense: true,
              title: Text(t.label, style: TextStyle(color: skin.fg, fontSize: 13.5)),
              subtitle: Text(t.detailedSpec, style: TextStyle(color: skin.fg3, fontSize: 11.5)),
              trailing: selectedIndex == t.index
                  ? Icon(Icons.check_rounded, size: 18, color: skin.accent)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                onSelect(t.index);
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final prefs = appState.prefs;
    final safeVerIdx = versions.isEmpty
        ? 0
        : selectedVersionIndex.clamp(0, versions.length - 1);
    final streamSrc = activeStreamSource ??
        (versions.isNotEmpty ? versions[safeVerIdx].source : null);
    final audios = streamSrc?.audioStreams ?? const <MediaStreamModel>[];
    final subs = streamSrc?.subtitleStreams ?? const <MediaStreamModel>[];
    final extFileName = localExternalSubPath?.trim().isNotEmpty == true
        ? localExternalSubPath!.replaceAll('\\', '/').split('/').last
        : null;

    const audioLangOptions = <(String code, String label)>[
      ('auto', '原声自动'),
      ('zh', '中文 / 国语'),
      ('ja', '日语'),
      ('yue', '粤语'),
      ('en', '英语'),
    ];

    const subLangOptions = <(String code, String label)>[
      ('zh', '简体中文'),
      ('zh-Hant', '繁体中文'),
      ('en', '英语 / 双语'),
      ('ja', '日语'),
      ('off', '关闭字幕'),
    ];

    return Column(
      key: const ValueKey('detail-version-selector'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (versions.length > 1) ...[
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                isSeries
                    ? '选择剧集片源版本 (${versions.length})'
                    : '选择片源版本 (${versions.length})',
                style: TextStyle(
                  color: skin.fg2,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
              if (versions.length > 3)
                Text(
                  '已智能识别目录与编码差异',
                  style: TextStyle(color: skin.fg3, fontSize: 11.5),
                ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (ctx, c) {
              final cols = (versions.length >= 4 && c.maxWidth >= 980)
                  ? 3
                  : (c.maxWidth >= 640 ? 2 : 1);
              const gap = 10.0;
              final cardW = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: 9,
                children: [
                  for (var i = 0; i < versions.length; i++)
                    SizedBox(
                      width: cardW,
                      child: _VersionOptionTile(
                        key: ValueKey('${isSeries ? 'series' : 'movie'}-version-card-$i'),
                        version: versions[i],
                        totalCount: versions.length,
                        selected: i == safeVerIdx,
                        accent: skin.accent,
                        onTap: () => onSelectVersionIndex(i),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
        ],

        // Always-Visible Audio & Subtitle Selector Container
        Container(
          key: const ValueKey('detail-audio-subtitle-panel'),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
          decoration: BoxDecoration(
            color: skin.surface,
            borderRadius: BorderRadius.circular(skin.cardRadius.clamp(8.0, 18.0)),
            border: skin.cardBorder(),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.subtitles_outlined, size: 15.5, color: skin.accent),
                      const SizedBox(width: 6),
                      Text(
                        '音轨与字幕',
                        style: TextStyle(
                          color: skin.fg,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (audios.isEmpty && subs.isEmpty)
                    Text(
                      '开播自动按偏好匹配内封/外挂轨道 · 也可挂载本地字幕',
                      style: TextStyle(color: skin.fg3, fontSize: 11.5),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // 1. Audio Track / Preferred Audio Language Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 10),
                    child: SizedBox(
                      width: 42,
                      child: Text(
                        audios.isNotEmpty ? '音轨' : '配音',
                        style: TextStyle(
                          color: skin.fg3,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: audios.isNotEmpty
                          ? [
                              _TrackChoiceChip(
                                label: '默认',
                                selected: selectedAudioIndex == null,
                                onTap: () => onSelectAudio(null),
                              ),
                              ...audios.take(6).map((a) {
                                final on = selectedAudioIndex == a.index;
                                return _TrackChoiceChip(
                                  label: a.label,
                                  selected: on,
                                  onTap: () => onSelectAudio(on ? null : a.index),
                                );
                              }),
                              if (audios.length > 6)
                                _TrackChoiceChip(
                                  label: '全部 ${audios.length} 条音轨 ▾',
                                  selected: selectedAudioIndex != null &&
                                      !audios.take(6).any((a) => a.index == selectedAudioIndex),
                                  onTap: () => _openAllTracksSheet(
                                    context: context,
                                    title: '选择音轨',
                                    tracks: audios,
                                    selectedIndex: selectedAudioIndex,
                                    onSelect: onSelectAudio,
                                  ),
                                ),
                            ]
                          : audioLangOptions.map((opt) {
                              final on = prefs.preferredAudioLang == opt.$1;
                              return _TrackChoiceChip(
                                label: opt.$2,
                                selected: on,
                                onTap: () => appState.updatePrefs(
                                  prefs.copyWith(preferredAudioLang: opt.$1),
                                ),
                              );
                            }).toList(),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // 2. Subtitle Stream / Preferred Subtitle Language + External Subtitle File Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 10),
                    child: SizedBox(
                      width: 42,
                      child: Text(
                        '字幕',
                        style: TextStyle(
                          color: skin.fg3,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        if (subs.isNotEmpty) ...[
                          _TrackChoiceChip(
                            label: '默认',
                            selected: selectedSubtitleIndex == null && extFileName == null,
                            onTap: () => onSelectSubtitle(null),
                          ),
                          _TrackChoiceChip(
                            label: '关闭字幕',
                            selected: selectedSubtitleIndex == -1 && extFileName == null,
                            onTap: () => onSelectSubtitle(-1),
                          ),
                          ...subs.take(8).map((s) {
                            final on = selectedSubtitleIndex == s.index && extFileName == null;
                            return _TrackChoiceChip(
                              label: s.label,
                              selected: on,
                              onTap: () => onSelectSubtitle(on ? null : s.index),
                            );
                          }),
                          if (subs.length > 8)
                            _TrackChoiceChip(
                              label: '全部 ${subs.length} 条字幕 ▾',
                              selected: extFileName == null &&
                                  selectedSubtitleIndex != null &&
                                  selectedSubtitleIndex != -1 &&
                                  !subs.take(8).any((s) => s.index == selectedSubtitleIndex),
                              onTap: () => _openAllTracksSheet(
                                context: context,
                                title: '选择字幕轨道',
                                tracks: subs,
                                selectedIndex: selectedSubtitleIndex,
                                onSelect: onSelectSubtitle,
                                allowOff: true,
                              ),
                            ),
                        ] else ...[
                          for (final opt in subLangOptions)
                            _TrackChoiceChip(
                              label: opt.$2,
                              selected: extFileName == null &&
                                  ((opt.$1 == 'off' &&
                                          (selectedSubtitleIndex == -1 ||
                                              prefs.preferredSubLang == 'off')) ||
                                      (opt.$1 != 'off' &&
                                          selectedSubtitleIndex != -1 &&
                                          prefs.preferredSubLang == opt.$1)),
                              onTap: () {
                                onSelectSubtitle(opt.$1 == 'off' ? -1 : null);
                                appState.updatePrefs(prefs.copyWith(preferredSubLang: opt.$1));
                              },
                            ),
                        ],

                        if (extFileName != null)
                          _TrackChoiceChip(
                            label: '外挂: $extFileName ×',
                            selected: true,
                            onTap: onClearExternalSubtitle,
                          ),

                        _TrackChoiceChip(
                          key: const ValueKey('detail-mount-local-sub-btn'),
                          label: '+ 本地字幕',
                          icon: Icons.upload_file_rounded,
                          selected: false,
                          onTap: onPickExternalSubtitle,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrackChoiceChip extends StatelessWidget {
  const _TrackChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return PressableScale(
      onTap: onTap,
      hoverScale: 1.02,
      pressScale: 0.96,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: VedroTheme.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12.5, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? skin.activePillBg : skin.surface2,
          borderRadius: BorderRadius.circular(skin.radiusForPill(30)),
          border: (!selected && skin.frameStyle == 'neon')
              ? Border.all(color: skin.border, width: 0.7)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 13.5,
                color: selected ? skin.activePillFg : skin.fg2,
              ),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? skin.activePillFg : skin.fg2,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
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
    final skin = VedroSkin.of(context);
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
            color: _hovered ? skin.surface2 : skin.surface,
            borderRadius: BorderRadius.circular(skin.cardRadius.clamp(8.0, 18.0)),
            border: skin.cardBorder(hovered: _hovered),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 164,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(skin.cardRadius.clamp(6.0, 12.0)),
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
                                color: skin.ctaStyle == 'contrast' ? Colors.white : skin.accent,
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
                            style: TextStyle(
                              color: skin.fg,
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
                                  color: skin.surface2,
                                  borderRadius: BorderRadius.circular(skin.radiusForPill(20)),
                                ),
                                child: Text(
                                  '${ep.versionCount} 版本',
                                  style: TextStyle(
                                    color: skin.fg,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (ep.played)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(Icons.check_circle_rounded, size: 16, color: skin.fg3),
                          ),
                        Tooltip(
                          message: '查看本集详情与媒体规格',
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.more_horiz_rounded, size: 18, color: skin.fg3),
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
                      style: TextStyle(
                        color: skin.fg3,
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (epOverview.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        epOverview,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: skin.fg2,
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

/// Scalable Multi-Episode & Multi-Version Batch Download Picker (strictly single-selects version by index!).
class _BatchDownloadDialog extends StatefulWidget {
  const _BatchDownloadDialog({
    required this.series,
    required this.seasons,
    required this.initialSeasonId,
    required this.initialEpisodes,
    required this.initialVersionIndex,
    required this.appState,
  });

  final MediaItemModel series;
  final List<MediaItemModel> seasons;
  final String? initialSeasonId;
  final List<MediaItemModel> initialEpisodes;
  final int initialVersionIndex;
  final VedroAppState appState;

  @override
  State<_BatchDownloadDialog> createState() => _BatchDownloadDialogState();
}

class _BatchDownloadDialogState extends State<_BatchDownloadDialog> {
  String? _seasonId;
  late List<MediaItemModel> _episodes;
  final Map<String, List<MediaItemModel>> _seasonCache = {};
  final Map<String, MediaItemModel> _selectedById = {};
  int _versionIndex = 0;
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
    _versionIndex = widget.initialVersionIndex;
    _ensureDefaultVersion();
  }

  List<ResolvedMediaVersion> get _availableVersions {
    List<MediaSourceModel> best = const [];
    for (final ep in _episodes) {
      if (ep.mediaSources.length > best.length) {
        best = ep.mediaSources;
      }
    }
    return MediaSourceModel.resolveVersions(best);
  }

  void _ensureDefaultVersion() {
    final vers = _availableVersions;
    if (vers.isEmpty) {
      _versionIndex = 0;
      return;
    }
    if (_versionIndex < 0 || _versionIndex >= vers.length) {
      _versionIndex = 0;
    }
  }

  MediaSourceModel? _resolveSourceFor(MediaItemModel ep) {
    if (ep.mediaSources.isEmpty) return null;
    if (ep.mediaSources.length == 1) return ep.mediaSources.first;
    final vers = _availableVersions;
    if (vers.isEmpty) return ep.mediaSources.first;
    final chosen = vers[_versionIndex.clamp(0, vers.length - 1)];
    final epVers = MediaSourceModel.resolveVersions(ep.mediaSources);
    for (final ev in epVers) {
      if (ev.seriesMatchSignature == chosen.seriesMatchSignature) return ev.source;
    }
    return ep.mediaSources[_versionIndex.clamp(0, ep.mediaSources.length - 1)];
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
      final vers = _availableVersions;
      final chosenLabel = vers.isNotEmpty
          ? vers[_versionIndex.clamp(0, vers.length - 1)].displayTitle
          : null;
      final batch = ordered.map((ep) {
        final src = _resolveSourceFor(ep);
        return (
          item: ep,
          mediaSourceId: src?.id,
          versionLabel: chosenLabel ?? src?.name ?? src?.container?.toUpperCase(),
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
    final skin = VedroSkin.of(context);
    final versions = _availableVersions;
    final safeVerIdx = versions.isEmpty ? 0 : _versionIndex.clamp(0, versions.length - 1);
    final totalBytes = _selectedTotalBytes;

    final chunkSize = _episodes.length >= 400 ? 100 : 50;
    final rangeCount = _episodes.isEmpty ? 0 : ((_episodes.length - 1) ~/ chunkSize) + 1;
    final safeRangeIdx = rangeCount == 0 ? 0 : _rangeIdx.clamp(0, rangeCount - 1);
    final start = safeRangeIdx * chunkSize;
    final end = (start + chunkSize).clamp(0, _episodes.length);
    final visibleEps = rangeCount > 1 ? _episodes.sublist(start, end) : _episodes;

    return Dialog(
      key: const ValueKey('detail-batch-download-dialog'),
      backgroundColor: skin.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(skin.cardRadius.clamp(12.0, 22.0)),
        side: BorderSide(color: skin.borderStrong, width: 0.9),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.arrow_downward_rounded, size: 19, color: skin.fg),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '选择下载剧集与版本 · ${widget.series.displayName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: skin.fg,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: skin.fg2),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

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
                          color: active ? skin.activePillBg : skin.surface2,
                          borderRadius: BorderRadius.circular(skin.radiusForPill(36)),
                        ),
                        child: Text(
                          s.name,
                          style: TextStyle(
                            color: active ? skin.activePillFg : skin.fg2,
                            fontSize: 12.5,
                            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

            if (versions.length > 1) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '下载版本 (${versions.length})',
                      style: TextStyle(color: skin.fg3, fontSize: 11.5, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (var i = 0; i < versions.length; i++)
                          GestureDetector(
                            onTap: () => setState(() => _versionIndex = i),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
                              decoration: BoxDecoration(
                                color: i == safeVerIdx ? skin.activePillBg : skin.surface2,
                                borderRadius: BorderRadius.circular(skin.radiusForPill(30)),
                              ),
                              child: Text(
                                versions[i].displayTitle,
                                style: TextStyle(
                                  color: i == safeVerIdx ? skin.activePillFg : skin.fg2,
                                  fontSize: 12,
                                  fontWeight: i == safeVerIdx ? FontWeight.w600 : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

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
                                  color: active ? skin.activePillBg : skin.surface2,
                                  borderRadius: BorderRadius.circular(skin.radiusForPill(28)),
                                ),
                                child: Text(
                                  '$firstNum-$lastNum',
                                  style: TextStyle(
                                    color: active ? skin.activePillFg : skin.fg2,
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
                      foregroundColor: skin.fg,
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
                      foregroundColor: skin.fg2,
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
                        foregroundColor: skin.fg3,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () => setState(() => _selectedById.clear()),
                      child: const Text('清空', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            Expanded(
              child: _loadingSeason
                  ? Center(
                      child: CircularProgressIndicator(strokeWidth: 2, color: skin.fg2),
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
                              color: checked ? skin.surface3 : skin.surface2,
                              borderRadius: BorderRadius.circular(skin.cardRadius.clamp(6.0, 12.0)),
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
                                      ? const Color(0xFF10B981)
                                      : (checked ? skin.accent : skin.fg3),
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
                                          color: disabled ? skin.fg3 : skin.fg,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (src != null && (src.name?.isNotEmpty == true))
                                        Text(
                                          src.name!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: skin.fg3, fontSize: 11),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (done)
                                  const Text(
                                    '已下载',
                                    style: TextStyle(
                                      color: Color(0xFF10B981),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                else if (active)
                                  Text(
                                    '队列中',
                                    style: TextStyle(
                                      color: skin.accent,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                else if (sizeText.isNotEmpty)
                                  Text(
                                    sizeText,
                                    style: TextStyle(
                                      color: skin.fg2,
                                      fontSize: 12,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedById.isEmpty
                          ? '请勾选需要下载的剧集'
                          : '已选 ${_selectedById.length} 集${totalBytes > 0 ? ' · 共 ${fmtQuotaBytes(totalBytes)}' : ''}',
                      style: TextStyle(
                        color: skin.fg,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: skin.primaryCtaBg,
                      foregroundColor: skin.primaryCtaFg,
                      disabledBackgroundColor: skin.surface3,
                      disabledForegroundColor: skin.fg3,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(skin.radiusForPill(42)),
                      ),
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
