import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/models.dart';
import '../core/platform/native_playback_channel.dart';
import '../core/platform/platform_perf.dart';
import '../core/theme/display_profile.dart';
import '../core/theme/dynamic_color_engine.dart';
import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/horizontal_rail.dart';
import '../widgets/media_card.dart';
import '../widgets/vedro_artwork.dart';
import '../widgets/vedro_ui.dart';
import 'home_screen.dart' show showMediaItemContextSheet;
import 'library_screen.dart';
import 'player_screen.dart';

/// Apple TV+ / Infuse / AfuseKt caliber Cinema Detail Screen:
/// - Seamless full-bleed Hero backdrop smoothly dissolving into solid OLED canvas (no muddy wash or seam)
/// - Exact TextPainter-measured expandable overview (never shows "展开全部" when text fits)
/// - High-contrast solid elevated Version / Audio / Subtitle selector panel
/// - Rich Series Seasons with 16:9 Episode Cards (air date, rating, 2-line overview, per-episode detail)
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
  List<MediaItemModel> _collectionItems = [];
  List<MediaItemModel> _personCredits = [];
  MediaItemModel? _seriesNextUp;
  String? _selectedSeasonId;
  int _selectedSourceIndex = 0;
  int _selectedSeriesVersionIndex = 0;
  bool _loading = true;
  String? _loadError;
  Future<void>? _loadFuture;
  int _episodesGen = 0;
  String? _lastChromeSig;
  VedroSkin? _cachedDetailSkin;
  ThemeData? _cachedDetailTheme;
  String _episodeViewMode = 'cards'; // 'grid' | 'cards' | 'list'
  bool _episodeModeUserChosen = false;
  bool _episodeDescending = false;
  int _episodeRangeIndex = 0;
  bool _episodeSearchOpen = false;
  final TextEditingController _episodeJumpCtrl = TextEditingController();
  final FocusNode _episodeSearchFocus = FocusNode();
  String _episodeFilterQuery = '';
  String? _translatedOverview;
  bool _translating = false;
  DateTime? _lastDownloadTapAt;
  final Map<String, int?> _audioIndexByVer = {};
  final Map<String, int?> _subIndexByVer = {};
  final Map<String, String> _audioLangByVer = {};
  final Map<String, String> _subLangByVer = {};
  final Map<String, String?> _extSubByVer = {};
  Color? _detailMonetSeed;

  void _refreshDetailMonetSeed() {
    if (_item.type == 'Person') return;
    final artUrl = widget.appState.backdropArt(_item, width: 320)?.url ??
        widget.appState.posterArtUrl(_item, width: 320);
    final cached = DynamicColorEngine.cachedForUrl(artUrl);
    final initial = cached ?? DynamicColorEngine.seedForIdentity(_item.id, _item.name);
    if (_detailMonetSeed != initial && mounted) {
      setState(() => _detailMonetSeed = initial);
    } else {
      _detailMonetSeed ??= initial;
    }
    if (cached == null && artUrl != null && artUrl.isNotEmpty) {
      final targetId = _item.id;
      DynamicColorEngine.extractFromImageUrl(artUrl).then((extracted) {
        if (extracted != null && mounted && _item.id == targetId) {
          setState(() => _detailMonetSeed = extracted);
        }
      });
    }
  }

  String get _activeVersionStateKey {
    if (_item.isSeries) {
      final vers = _resolvedSeriesVersions;
      if (vers.isEmpty) return 'series_v0';
      final idx = _selectedSeriesVersionIndex.clamp(0, vers.length - 1);
      final id = vers[idx].source.id;
      return 'series_${idx}_${id.isEmpty ? vers[idx].seriesMatchSignature : id}';
    }
    final vers = _resolvedPlayableVersions;
    if (vers.isEmpty) return 'movie_v0';
    final idx = _selectedSourceIndex.clamp(0, vers.length - 1);
    final id = vers[idx].source.id;
    return 'movie_${idx}_${id.isEmpty ? "slot_$idx" : id}';
  }

  int? get _selectedAudioIndex => _audioIndexByVer[_activeVersionStateKey];
  set _selectedAudioIndex(int? v) => _audioIndexByVer[_activeVersionStateKey] = v;

  int? get _selectedSubtitleIndex => _subIndexByVer[_activeVersionStateKey];
  set _selectedSubtitleIndex(int? v) => _subIndexByVer[_activeVersionStateKey] = v;

  String? get _localExternalSubPath => _extSubByVer[_activeVersionStateKey];
  set _localExternalSubPath(String? v) => _extSubByVer[_activeVersionStateKey] = v;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _refreshDetailMonetSeed();
    widget.appState.addListener(_onAppStateChanged);
    _loadFuture = _loadDetails();
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
    _episodeSearchFocus.dispose();
    final restoreSkin = widget.appState.prefs.activeSkinFor(
      dynamicSeedOverride: widget.appState.dynamicPageSeedColor,
    );
    NativePlaybackChannel.syncWindowChrome(
      isLight: restoreSkin.isLight,
      canvasArgb: restoreSkin.canvas.toARGB32(),
      fgArgb: restoreSkin.fg.toARGB32(),
    );
    super.dispose();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      if (_item.type == 'Person') {
        final cRes = await widget.appState.core.invoke('get_person_credits', {
          'person_id': _item.id,
        }) as Map<String, dynamic>;
        if (!mounted) return;
        _personCredits = ((cRes['Items'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MediaItemModel.fromJson)
            .toList();
      } else if (_item.isSeries) {
        // Fetch item metadata, seasons, and NextUp in parallel to halve Series DetailScreen TTFP
        // and land directly on the active/resumed season (skipping Season 0 Specials unless only S0 exists).
        final results = await Future.wait<dynamic>([
          widget.appState.core.invoke('get_item', {'item_id': _item.id}),
          widget.appState.core.invoke('get_seasons', {'series_id': _item.id}),
          widget.appState.getNextUpForSeries(_item.id).catchError((_) => null),
        ]);
        if (!mounted) return;
        final res = results[0] as Map<String, dynamic>;
        final sRes = results[1] as Map<String, dynamic>;
        final nextUpEp = results[2] as MediaItemModel?;
        _item = MediaItemModel.fromJson(res['item'] as Map<String, dynamic>);
        _similar = ((res['similar'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MediaItemModel.fromJson)
            .toList();
        _segments = ((res['segments'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MediaSegmentModel.fromJson)
            .toList();
        _seriesNextUp = nextUpEp;
        _refreshDetailMonetSeed();
        _seasons = ((sRes['Items'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MediaItemModel.fromJson)
            .toList();
        if (_seasons.isNotEmpty) {
          MediaItemModel preferredSeason = _seasons.first;
          // 1. Prefer the season referenced by NextUp / Resume
          if (nextUpEp != null) {
            final byId = nextUpEp.seasonId != null
                ? _seasons.where((s) => s.id == nextUpEp.seasonId)
                : const Iterable<MediaItemModel>.empty();
            if (byId.isNotEmpty) {
              preferredSeason = byId.first;
            } else if (nextUpEp.parentIndexNumber != null) {
              final byIdx = _seasons.where((s) => s.indexNumber == nextUpEp.parentIndexNumber);
              if (byIdx.isNotEmpty) preferredSeason = byIdx.first;
            }
          } else {
            // 2. Skip Season 0 (Specials) when regular seasons exist
            final regular = _seasons.where((s) => (s.indexNumber ?? 1) >= 1);
            if (regular.isNotEmpty) preferredSeason = regular.first;
          }
          _selectedSeasonId = preferredSeason.id;
          await _loadEpisodes(preferredSeason.id);
        }
      } else if (_item.type == 'BoxSet' || _item.type == 'Folder') {
        final results = await Future.wait<dynamic>([
          widget.appState.core.invoke('get_item', {'item_id': _item.id}),
          widget.appState.core.invoke('get_items', {
            'ParentId': _item.id,
            'Recursive': false,
            'SortBy': 'SortName',
            'SortOrder': 'Ascending',
            'Limit': 500,
          }),
        ]);
        if (!mounted) return;
        final res = results[0] as Map<String, dynamic>;
        final cRes = results[1] as Map<String, dynamic>;
        _item = MediaItemModel.fromJson(res['item'] as Map<String, dynamic>);
        _similar = ((res['similar'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MediaItemModel.fromJson)
            .toList();
        _collectionItems = ((cRes['Items'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MediaItemModel.fromJson)
            .toList();
        _refreshDetailMonetSeed();
      } else {
        final res = await widget.appState.core.invoke('get_item', {'item_id': _item.id})
            as Map<String, dynamic>;
        if (!mounted) return;
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
        _refreshDetailMonetSeed();
      }
    } catch (e) {
      if (mounted) {
        _loadError = VedroErrorFormatter.friendly(e);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadEpisodes(String seasonId) async {
    final gen = ++_episodesGen;
    try {
      final eRes = await widget.appState.core.invoke('get_episodes', {
        'series_id': _item.id,
        'season_id': seasonId,
        'limit': 5000,
      }) as Map<String, dynamic>;
      if (!mounted || gen != _episodesGen) return;
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
    } catch (e) {
      if (!mounted || gen != _episodesGen) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载分集失败：${VedroErrorFormatter.friendly(e)}')),
      );
    }
  }

  /// Silent background refresh after returning from PlayerScreen so newly played versions
  /// immediately surface their real embedded audio & subtitle tracks with 0 extra cloud probes!
  Future<void> _refreshAfterPlayback() async {
    if (!mounted || _item.type == 'Person') return;
    try {
      final res = await widget.appState.core.invoke('get_item', {'item_id': _item.id})
          as Map<String, dynamic>;
      if (!mounted) return;
      final refreshedItem = MediaItemModel.fromJson(res['item'] as Map<String, dynamic>);
      List<MediaItemModel>? refreshedEps;
      if (_item.isSeries && _selectedSeasonId != null) {
        final eRes = await widget.appState.core.invoke('get_episodes', {
          'series_id': _item.id,
          'season_id': _selectedSeasonId,
          'limit': 5000,
        }) as Map<String, dynamic>;
        refreshedEps = ((eRes['Items'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MediaItemModel.fromJson)
            .toList();
      }
      if (!mounted) return;
      setState(() {
        _item = refreshedItem;
        if (refreshedEps != null) _episodes = refreshedEps;
      });
    } catch (_) {}
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
    MediaItemModel? bestEp;
    for (final ep in _episodes) {
      if (bestEp == null || ep.mediaSources.length > bestEp.mediaSources.length) {
        bestEp = ep;
      }
    }
    return bestEp?.mediaSources ?? const [];
  }

  List<ResolvedMediaVersion> get _resolvedSeriesVersions =>
      MediaSourceModel.resolveVersions(_seriesSampleSources, stripEpisodePrefix: true);

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
              child: InkWell(
                autofocus: i == activeIdx,
                borderRadius: BorderRadius.circular(skin.cardRadius.clamp(10.0, 16.0)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _selectedSeriesVersionIndex = i);
                  _play(target, sourceId: resolved[i].source.id);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: i == activeIdx
                        ? skin.accent.withValues(alpha: 0.14)
                        : skin.subtleChipBg,
                    borderRadius: BorderRadius.circular(skin.cardRadius.clamp(10.0, 16.0)),
                    border: Border.all(
                      color: i == activeIdx ? skin.accent : skin.border,
                      width: i == activeIdx ? 1.1 : 0.7,
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: i == activeIdx
                            ? Icon(Icons.check_rounded, size: 17, color: skin.accent)
                            : null,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              resolved[i].displayTitle,
                              style: TextStyle(
                                color: skin.fg,
                                fontSize: 13.5,
                                fontWeight: i == activeIdx ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                            if (fmtFileSize(resolved[i].source.size).isNotEmpty ||
                                (resolved[i].folderBadge?.isNotEmpty ?? false)) ...[
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (fmtFileSize(resolved[i].source.size).isNotEmpty)
                                    fmtFileSize(resolved[i].source.size),
                                  if (resolved[i].folderBadge?.isNotEmpty ?? false)
                                    resolved[i].folderBadge!,
                                ].join(' · '),
                                style: TextStyle(color: skin.fg3, fontSize: 11.5),
                              ),
                            ],
                          ],
                        ),
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
                    child: Image.network(
                      posterUrl,
                      cacheWidth: 1600,
                      filterQuality: FilterQuality.medium,
                      fit: BoxFit.contain,
                    ),
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

  Future<void> _play(
    MediaItemModel target, {
    String? sourceId,
    bool fromBeginning = false,
    int? startPositionTicks,
    String? localPath,
  }) async {
    if (localPath == null && widget.appState.prefs.externalPlayer != 'builtin') {
      await _launchExternal(target, sourceId: sourceId);
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
            chapters: target.chapters,
          )
        : target;

    final verKey = _activeVersionStateKey;
    final verAudioLang = _audioLangByVer[verKey];
    final verSubLang = _subLangByVer[verKey];

    await Navigator.of(context).push(
      vedroRoute(PlayerScreen(
        item: playTarget,
        appState: widget.appState,
        mediaSourceId: sourceId,
        playlistEpisodes: _episodes.isNotEmpty ? _episodes : null,
        segments: target.id == _item.id ? _segments : null,
        initialAudioStreamIndex: _selectedAudioIndex,
        initialSubtitleStreamIndex: _selectedSubtitleIndex,
        initialExternalSubtitlePath: _localExternalSubPath,
        preferredAudioLangOverride: verAudioLang,
        preferredSubLangOverride: verSubLang,
        localFilePath: localPath,
      )),
    );
    await _refreshAfterPlayback();
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

  void _openStudio(String studio) {
    Navigator.of(context).push(
      vedroRoute(LibraryScreen(
        appState: widget.appState,
        initialStudio: studio,
        onItemTap: _openItemDetail,
        onQuickPlay: (item) {
          if (item.isPlayable) {
            _play(item);
          } else {
            _openItemDetail(item);
          }
        },
        standalone: true,
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
              autofocus: true,
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
        final sheetSkin = VedroSkin.of(ctx);
        final lists = widget.appState.playlists;
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '加入片单',
                style: TextStyle(color: sheetSkin.fg, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            if (lists.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('暂无片单，请先在片单页新建', style: TextStyle(color: sheetSkin.fg3, fontSize: 13)),
              )
            else
              for (var i = 0; i < lists.length; i++)
                ListTile(
                  autofocus: i == 0,
                  leading: Icon(Icons.bookmark_outline_rounded, color: sheetSkin.fg2),
                  title: Text(lists[i].name, style: TextStyle(color: sheetSkin.fg, fontSize: 14)),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(ctx);
                    try {
                      await widget.appState.core.invoke('add_to_playlist', {
                        'playlist_id': lists[i].id,
                        'item_ids': [_item.id],
                      });
                      messenger.showSnackBar(
                        SnackBar(content: Text('已加入片单「${lists[i].name}」')),
                      );
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('加入片单失败：${VedroErrorFormatter.friendly(e)}')),
                      );
                    }
                  },
                ),
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
    final prefs = widget.appState.prefs;
    if (prefs.dynamicMonet && _detailMonetSeed != null) {
      final sysBrightness = View.of(context).platformDispatcher.platformBrightness;
      final dynSkin = prefs.activeSkinFor(
        systemBrightness: sysBrightness,
        dynamicSeedOverride: _detailMonetSeed,
      );
      if (_cachedDetailTheme == null || _cachedDetailSkin != dynSkin) {
        _cachedDetailTheme = VedroTheme.fromSkin(dynSkin);
        _cachedDetailSkin = dynSkin;
      }
      return Theme(
        data: _cachedDetailTheme!,
        child: Builder(builder: _buildThemedDetail),
      );
    }
    return _buildThemedDetail(context);
  }

  Widget _buildThemedDetail(BuildContext context) {
    final skin = VedroSkin.of(context);
    final detailOverlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: skin.isLight ? Brightness.dark : Brightness.light,
      statusBarBrightness: skin.isLight ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: skin.isLight ? Brightness.dark : Brightness.light,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    );
    final chromeSig = '${skin.isLight}|${skin.canvas.toARGB32()}|${skin.fg.toARGB32()}';
    if (_lastChromeSig != chromeSig) {
      _lastChromeSig = chromeSig;
      NativePlaybackChannel.syncWindowChrome(
        isLight: skin.isLight,
        canvasArgb: skin.canvas.toARGB32(),
        fgArgb: skin.fg.toARGB32(),
      );
    }
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
    final hasOverviewSlot =
        (_item.taglines.isNotEmpty) || overviewText.isNotEmpty || (_loading && _item.type != 'Person');
    final tagline = _item.taglines.isNotEmpty ? _item.taglines.first : null;
    final downloadTarget = _resolveDownloadTarget();
    final canDownload = widget.appState.canDownloadItem(downloadTarget ?? _item);

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

    // Pick next unwatched episode for Series main Play CTA (preferring server NextUp when present)
    MediaItemModel? nextEpToPlay;
    if (_episodes.isNotEmpty) {
      if (_seriesNextUp != null) {
        final match = _episodes.where((e) => e.id == _seriesNextUp!.id);
        if (match.isNotEmpty) nextEpToPlay = match.first;
      }
      nextEpToPlay ??= _episodes.firstWhere(
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
    final activeEffSource = _item.isSeries ? activeSeriesEpSource : src;
    final hasKnownEmbeddedStreams = activeEffSource != null &&
        (activeEffSource.audioStreams.isNotEmpty || activeEffSource.videoStreams.isNotEmpty);

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
      return ListenableBuilder(
        listenable: widget.appState.downloadsTickNotifier,
        builder: (context, _) {
          final liveDlTask =
              widget.appState.findDownloadForItem(downloadTarget?.id ?? _item.id);
          final liveLocalReady = liveDlTask != null &&
              liveDlTask.status == 'completed' &&
              liveDlTask.filePath.isNotEmpty;
          // Keep Play CTA visible from Frame 0 for both Movies AND Series so buttons NEVER pop in late!
          final hasPrimaryPlay = _item.isPlayable || _item.isSeries;
          final String playLabel = _item.isPlayable
              ? (liveLocalReady
                  ? '播放离线缓存'
                  : (_item.playbackPositionTicks > 0
                      ? '继续播放 ${fmtDurationTicks(_item.playbackPositionTicks)}'
                      : '播放'))
              : (nextEpToPlay != null
                  ? (nextEpToPlay.resumeProgress > 0.01
                      ? '继续观看 ${nextEpToPlay.episodeCode ?? nextEpToPlay.displayName}'
                      : '播放 ${nextEpToPlay.episodeCode ?? '第 1 集'}')
                  : '播放 S01E01');
          final double playProgress =
              _item.isPlayable ? _item.resumeProgress : (nextEpToPlay?.resumeProgress ?? 0.0);
          Future<void> onPrimaryPlay() async {
            if (_item.isPlayable) {
              _play(
                _item,
                sourceId: _activeSource?.id,
                localPath: liveLocalReady ? liveDlTask.filePath : null,
              );
              return;
            }
            if (nextEpToPlay == null && _loadFuture != null) {
              await _loadFuture;
            }
            if (!mounted) return;
            final resolvedEp = nextEpToPlay ??
                (_episodes.isNotEmpty
                    ? _episodes.firstWhere(
                        (e) => e.resumeProgress > 0.01,
                        orElse: () => _episodes.firstWhere(
                          (e) => !e.played,
                          orElse: () => _episodes.first,
                        ),
                      )
                    : null);
            if (resolvedEp != null) {
              _play(
                resolvedEp,
                sourceId: _matchingSourceIdForEpisode(resolvedEp),
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
            if (liveLocalReady || canDownload)
              (
                key: const ValueKey('detail-download-button'),
                icon: liveLocalReady ? Icons.download_done_rounded : Icons.arrow_downward_rounded,
                label: liveLocalReady ? '已缓存' : (_item.isSeries ? '下载' : '缓存'),
                tooltip: liveLocalReady ? '播放已缓存文件' : '离线下载',
                active: liveLocalReady,
                color: liveLocalReady ? const Color(0xFF10B981) : skin.fg,
                onTap: liveLocalReady
                    ? () => _play(downloadTarget ?? _item, localPath: liveDlTask.filePath)
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
                          autofocus: PlatformPerfProfile.isTv,
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
                      autofocus: PlatformPerfProfile.isTv,
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
                                borderRadius:
                                    BorderRadius.circular(skin.cardRadius.clamp(8.0, 14.0)),
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
            )
          else if (_loading && _item.type != 'Person')
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  VedroShimmer(width: 440, height: 14, borderRadius: 4),
                  SizedBox(height: 8),
                  VedroShimmer(width: 300, height: 14, borderRadius: 4),
                ],
              ),
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
        PressableScale(
          onTap: widget.onGenreTap == null ? null : () => widget.onGenreTap!(g),
          borderRadius: BorderRadius.circular(6),
          hoverScale: 1.04,
          pressScale: 0.96,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
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

    for (final studio in _item.studios.take(2)) {
      addDotFact(
        PressableScale(
          onTap: () => _openStudio(studio),
          borderRadius: BorderRadius.circular(6),
          hoverScale: 1.04,
          pressScale: 0.96,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            child: Text(
              studio,
              style: TextStyle(
                color: skin.accent,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    final heroCreditRows = <(String role, String names)>[
      if (directors.isNotEmpty) ('导演', directors.take(2).join('、')),
      if (castNames.isNotEmpty) ('主演', castNames.join('、')),
      if (_item.studios.isNotEmpty) ('出品', _item.studios.take(2).join('、')),
      if (statusLabel.isNotEmpty) ('状态', statusLabel),
    ];

    final posterRadius = widget.appState.prefs.effectiveCardRadius(skin);
    Widget coverCard = RepaintBoundary(
      child: PressableScale(
        onTap: _openPosterLightbox,
        borderRadius: BorderRadius.circular(posterRadius),
        hoverScale: 1.02,
        pressScale: 0.97,
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
              displayWidth: coverW,
            ),
          ),
        ),
      ),
    );
    if (widget.heroTag != null) {
      coverCard = Hero(tag: widget.heroTag!, child: coverCard);
    }

    final c = skin.canvas;
    // Always dissolve smoothly into solid `skin.canvas` so the Hero image is NEVER stacked a second time!
    final endCanvas = c;
    final heroVertStops = skin.isLight
        ? const [0.0, 0.24, 0.54, 0.82, 0.95, 1.0]
        : const [0.0, 0.22, 0.56, 0.84, 0.95, 1.0];
    final heroVertColors = skin.isLight
        ? [
            c.withValues(alpha: 0.48),
            c.withValues(alpha: 0.56),
            c.withValues(alpha: 0.89),
            endCanvas,
            endCanvas,
            endCanvas,
          ]
        : [
            c.withValues(alpha: 0.30),
            c.withValues(alpha: 0.08),
            c.withValues(alpha: 0.64),
            c.withValues(alpha: 0.92),
            endCanvas,
            endCanvas,
          ];

    final isCenteredEditorial = skin.detailLayout == 'centered_editorial';
    final isJellyfinGlass = skin.detailLayout == 'jellyfin_glass';

    Widget buildHeroBodyContent() {
      if (isCenteredEditorial) {
        return Column(
          key: const ValueKey('detail-centered-editorial-hero'),
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            coverCard,
            const SizedBox(height: 22),
            if (eyebrowText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  eyebrowText.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: skin.ctaStyle == 'contrast' ? skin.fg3 : skin.accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.9,
                  ),
                ),
              ),
            if (logoUrl != null && skin.preferClearLogo && !skin.isLight)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: wide ? 82 : 60,
                  maxWidth: wide ? 420 : 280,
                ),
                child: Image.network(
                  logoUrl,
                  cacheWidth: 640,
                  filterQuality: FilterQuality.medium,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      _TitleHeadline(_item.displayName, wide, centered: true),
                ),
              )
            else
              _TitleHeadline(_item.displayName, wide, centered: true),
            if (_item.originalTitle != null && _item.originalTitle != _item.name) ...[
              const SizedBox(height: 4),
              Text(
                _item.originalTitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: skin.fg3, fontSize: 13.5),
              ),
            ],
            if (dotFacts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
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
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (_item.communityRating != null && _item.communityRating! > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded, size: 15.5, color: Color(0xFFF59E0B)),
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
                  if (_item.officialRating != null && _item.officialRating!.isNotEmpty)
                    _AppleMicroBadge(_item.officialRating!),
                  if (statusLabel.isNotEmpty) _AppleMicroBadge(statusLabel),
                  if (specChips.isNotEmpty) SpecGlyphRow(specs: specChips),
                ],
              ),
            ],
            if (hasOverviewSlot) ...[
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: buildOverviewBlock(),
              ),
            ],
            const SizedBox(height: 22),
            Center(child: buildActionRow()),
          ],
        );
      }

      final standardContent = Column(
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
                    if (wide && logoUrl != null && skin.preferClearLogo && !skin.isLight)
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: 74,
                          maxWidth: 400,
                        ),
                        child: Image.network(
                          logoUrl,
                          cacheWidth: 640,
                          filterQuality: FilterQuality.medium,
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
                      if (hasOverviewSlot) ...[
                        const SizedBox(height: 14),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 680),
                          child: buildOverviewBlock(),
                        ),
                      ],
                      const SizedBox(height: 22),
                      buildActionRow(),
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
            buildActionRow(),
            if (hasOverviewSlot) ...[
              const SizedBox(height: 16),
              buildOverviewBlock(),
            ],
          ],
        ],
      );

      if (isJellyfinGlass) {
        return GlassSurface(
          key: const ValueKey('detail-jellyfin-glass-hero'),
          borderRadius: skin.cardRadius.clamp(10.0, 24.0),
          blur: 28,
          color: skin.panelSurface,
          borderColor: skin.borderStrong,
          padding: EdgeInsets.all(wide ? 26 : 18),
          child: standardContent,
        );
      }
      return standardContent;
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: detailOverlay,
      child: Scaffold(
      backgroundColor: skin.canvas,
      body: VedroSkinCanvas(
        suppressTopOrb: true,
        child: Stack(
          children: [
            CustomScrollView(
              cacheExtent: PlatformPerfProfile.scrollCacheExtent,
              slivers: [
                // 1. Seamless Full-Stage Hero adapting to `detailLayout` (`apple_immersive` | `jellyfin_glass` | `centered_editorial`)
                SliverToBoxAdapter(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
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
                                if (wide && !isCenteredEditorial)
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
                      ),
                      if (skin.backdropMode == 'solid_clean')
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: -2,
                          height: 5,
                          child: ColoredBox(color: c),
                        ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          padX,
                          wide ? (topSafe + (isJellyfinGlass ? 112 : 144)) : (topSafe + 108),
                          padX,
                          wide ? 32 : 24,
                        ),
                        child: buildHeroBodyContent(),
                      ),
                    ],
                  ),
                ),

                // 2. Body Content: Strictly Single-Select Version Grid + Version-Following Audio & Subtitle Selector!
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_loadError != null && !_loading)
                        Padding(
                          padding: EdgeInsets.fromLTRB(padX, 0, padX, 18),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: VedroTheme.danger.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: VedroTheme.danger.withValues(alpha: 0.30),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    size: 18, color: VedroTheme.danger),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '加载详情失败：$_loadError',
                                    style: TextStyle(color: skin.fg, fontSize: 13),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: _loadDetails,
                                  child: const Text('重试'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_item.isPlayable || _item.isSeries) ...[
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: padX),
                          child: _TracksPanel(
                            isSeries: _item.isSeries,
                            isLoading: _loading,
                            expectedVersionCount: _item.versionCount,
                            versions: _item.isSeries ? seriesVersions : playableVersions,
                            selectedVersionIndex: _item.isSeries
                                ? _selectedSeriesVersionIndex
                                : _selectedSourceIndex,
                            activeStreamSource: activeEffSource,
                            hasKnownEmbeddedStreams: hasKnownEmbeddedStreams,
                            selectedAudioIndex: _selectedAudioIndex,
                            selectedSubtitleIndex: _selectedSubtitleIndex,
                            preferredAudioLangOverride: _audioLangByVer[_activeVersionStateKey],
                            preferredSubLangOverride: _subLangByVer[_activeVersionStateKey],
                            localExternalSubPath: _localExternalSubPath,
                            appState: widget.appState,
                            onSelectVersionIndex: (idx) {
                              setState(() {
                                if (_item.isSeries) {
                                  _selectedSeriesVersionIndex = idx;
                                } else {
                                  _selectedSourceIndex = idx;
                                }
                              });
                            },
                            onSelectAudio: (idx) => setState(() => _selectedAudioIndex = idx),
                            onSelectSubtitle: (idx) => setState(() {
                              _selectedSubtitleIndex = idx;
                              if (idx != null) _localExternalSubPath = null;
                            }),
                            onSelectVersionAudioLang: (lang) => setState(() {
                              _audioLangByVer[_activeVersionStateKey] = lang;
                            }),
                            onSelectVersionSubLang: (lang) => setState(() {
                              _subLangByVer[_activeVersionStateKey] = lang;
                              _selectedSubtitleIndex = lang == 'off' ? -1 : null;
                            }),
                            onPickExternalSubtitle: _pickExternalSubtitleForDetail,
                            onClearExternalSubtitle: () =>
                                setState(() => _localExternalSubPath = null),
                          ),
                        ),
                        const SizedBox(height: 30),
                      ],

                      // 2c. TV Series Seasons & Scalable Episode Selector (pre-sized skeleton while loading -> 0 CLS!)
                      if (_seasons.isNotEmpty) ...[
                        _buildEpisodeSection(
                          wide: wide,
                          padX: padX,
                          accent: accent,
                          nextEpToPlay: nextEpToPlay,
                        ),
                        const SizedBox(height: 34),
                      ] else if (_loading && _item.isSeries) ...[
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: padX),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  VedroShimmer(width: 96, height: 34, borderRadius: 999),
                                  Spacer(),
                                  VedroShimmer(width: 72, height: 34, borderRadius: 999),
                                ],
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                height: wide ? 298 : 258,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: 4,
                                  separatorBuilder: (_, __) => const SizedBox(width: 16),
                                  itemBuilder: (_, __) => SizedBox(
                                    width: wide ? 284 : 232,
                                    child: const Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        VedroShimmer(aspectRatio: 16 / 9, borderRadius: 12),
                                        SizedBox(height: 10),
                                        VedroShimmer(width: 140, height: 14, borderRadius: 4),
                                        SizedBox(height: 6),
                                        VedroShimmer(width: 96, height: 11, borderRadius: 4),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 34),
                      ],

                      // 2d. Skin-Adaptive Cast & Crew (`circle_medallion` | `portrait_card` | `compact_pill`)
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
                          height: skin.castStyle == 'portrait_card'
                              ? 242
                              : (skin.castStyle == 'compact_pill' ? 68 : 152),
                          padX: padX,
                          paddleCenterY: skin.castStyle == 'portrait_card'
                              ? 84
                              : (skin.castStyle == 'compact_pill' ? 28 : 48),
                          spacing: skin.castStyle == 'compact_pill' ? 10 : 16,
                          itemCount: _item.people.take(36).length,
                          itemBuilder: (_, idx) {
                            final p = _item.people[idx];
                            final avatarUrl = p.primaryImageTag != null
                                ? widget.appState.buildImageUrl(
                                    p.id,
                                    type: 'Primary',
                                    tag: p.primaryImageTag,
                                    maxWidth: 320,
                                  )
                                : '';
                            final roleLabel = (p.role ?? '').trim().isNotEmpty
                                ? p.role!.trim()
                                : localizePersonRole(p.type);
                            void openPerson() => _openItemDetail(MediaItemModel(
                                  id: p.id,
                                  name: p.name,
                                  type: 'Person',
                                  primaryImageTag: p.primaryImageTag,
                                ));

                            if (skin.castStyle == 'portrait_card') {
                              final cardR = skin.cardRadius.clamp(6.0, 16.0);
                              return RepaintBoundary(
                                child: SizedBox(
                                width: 114,
                                child: PressableScale(
                                  onTap: openPerson,
                                  hoverScale: 1.03,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      AspectRatio(
                                        aspectRatio: 2 / 3,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: skin.surface2,
                                            borderRadius: BorderRadius.circular(cardR),
                                            boxShadow: skin.posterShadow(),
                                          ),
                                          foregroundDecoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(cardR),
                                            border: skin.cardBorder(),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: avatarUrl.isNotEmpty
                                              ? FadeNetworkImage(
                                                  url: avatarUrl,
                                                  cacheWidth: 260,
                                                  alignment: const Alignment(0, -0.3),
                                                  placeholder: GeneratedArt(
                                                    seed: p.id,
                                                    label: p.name,
                                                  ),
                                                )
                                              : GeneratedArt(seed: p.id, label: p.name),
                                        ),
                                      ),
                                      const SizedBox(height: 7),
                                      Text(
                                        p.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: skin.fg,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        roleLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: skin.fg3, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              );
                            }

                            if (skin.castStyle == 'compact_pill') {
                              final pillR = skin.radiusForPill(52);
                              return RepaintBoundary(
                                child: PressableScale(
                                onTap: openPerson,
                                hoverScale: 1.02,
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(7, 6, 14, 6),
                                  decoration: BoxDecoration(
                                    color: skin.panelSurface,
                                    borderRadius: BorderRadius.circular(pillR),
                                    border: skin.cardBorder(),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: skin.surface2,
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: avatarUrl.isNotEmpty
                                            ? FadeNetworkImage(
                                                url: avatarUrl,
                                                cacheWidth: 120,
                                                placeholder: GeneratedArt(
                                                  seed: p.id,
                                                  label: p.name,
                                                ),
                                              )
                                            : GeneratedArt(seed: p.id, label: p.name),
                                      ),
                                      const SizedBox(width: 10),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 140),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              p.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: skin.fg,
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              roleLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(color: skin.fg3, fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              );
                            }

                            return RepaintBoundary(
                              child: SizedBox(
                              width: 90,
                              child: PressableScale(
                                onTap: openPerson,
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
                                      child: avatarUrl.isNotEmpty
                                          ? FadeNetworkImage(
                                              url: avatarUrl,
                                              cacheWidth: 220,
                                              alignment: const Alignment(0, -0.35),
                                              placeholder: GeneratedArt(
                                                seed: p.id,
                                                label: p.name,
                                              ),
                                            )
                                          : GeneratedArt(seed: p.id, label: p.name),
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

                // 3. BoxSet / Folder Child Items (lazy SliverGrid.builder)
                if ((_item.type == 'BoxSet' || _item.type == 'Folder') &&
                    _collectionItems.isNotEmpty)
                  ..._buildLazyPosterGridSlivers(
                    title: _item.type == 'BoxSet'
                        ? '合集内容 (${_collectionItems.length})'
                        : '文件夹内容 (${_collectionItems.length})',
                    items: _collectionItems,
                    padX: padX,
                    wide: wide,
                    skin: skin,
                  ),

                // 4. Related Recommendations Rail
                if (_similar.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: HorizontalMediaRail(
                        title: '相关推荐',
                        items: _similar,
                        appState: widget.appState,
                        onItemTap: _openItemDetail,
                        onItemQuickPlay: (it) => it.isPlayable ? _play(it) : _openItemDetail(it),
                        onItemLongPress: (it) => showMediaItemContextSheet(
                          context: context,
                          item: it,
                          appState: widget.appState,
                          onOpenDetail: () => _openItemDetail(it),
                          onQuickPlay: it.isPlayable ? () => _play(it) : null,
                        ),
                      ),
                    ),
                  ),

                // 5. Person Filmography (lazy SliverGrid.builder — smooth even for 200+ credits!)
                if (_item.type == 'Person' && _personCredits.isNotEmpty)
                  ..._buildLazyPosterGridSlivers(
                    title: '参与作品 (${_personCredits.length})',
                    items: _personCredits,
                    padX: padX,
                    wide: wide,
                    skin: skin,
                  ),

                if (_loading &&
                    (_item.type == 'Person' ||
                        _item.type == 'BoxSet' ||
                        _item.type == 'Folder'))
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

            // Subtle Top Chrome Scrim so scrolled content melts cleanly under glass buttons
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topSafe + 58,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        skin.canvas.withValues(alpha: skin.isLight ? 0.62 : 0.56),
                        skin.canvas.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Floating iOS Glass Top Chrome (Back + Mobile Quick More)
            Positioned(
              top: topSafe + 10,
              left: isMac ? 82 : (padX - 4),
              child: PressableScale(
                onTap: () => Navigator.of(context).pop(),
                hoverScale: 1.05,
                pressScale: 0.92,
                child: GlassSurface(
                  borderRadius: 999,
                  blur: 26,
                  color: skin.glass,
                  borderColor: skin.borderStrong,
                  padding: wide
                      ? const EdgeInsets.symmetric(horizontal: 13, vertical: 7.5)
                      : const EdgeInsets.all(9.5),
                  child: wide
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back_ios_new_rounded, size: 13.5, color: skin.fg),
                            const SizedBox(width: 4),
                            Text(
                              '返回',
                              style: TextStyle(
                                color: skin.fg,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      : Icon(Icons.arrow_back_ios_new_rounded, size: 17, color: skin.fg),
                ),
              ),
            ),
            if (!wide && _item.type != 'Person')
              Positioned(
                top: topSafe + 10,
                right: padX - 4,
                child: PressableScale(
                  onTap: _openMoreSheet,
                  hoverScale: 1.05,
                  pressScale: 0.92,
                  child: GlassSurface(
                    borderRadius: 999,
                    blur: 26,
                    color: skin.glass,
                    borderColor: skin.borderStrong,
                    padding: const EdgeInsets.all(9.5),
                    child: Icon(CupertinoIcons.ellipsis, size: 18, color: skin.fg),
                  ),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }

  List<Widget> _buildLazyPosterGridSlivers({
    required String title,
    required List<MediaItemModel> items,
    required double padX,
    required bool wide,
    required VedroSkin skin,
  }) {
    final metrics = DisplayMetricsProfile.of(context);
    final prefs = widget.appState.prefs;
    final gridGap = prefs.cardGap(wide);
    final effectiveStyle =
        (skin.cardStyle == 'hover_reveal' && metrics.isTouchPrimary)
            ? 'overlay_poster'
            : skin.cardStyle;
    final showBelowCaption = effectiveStyle != 'overlay_poster' &&
        effectiveStyle != 'hover_reveal' &&
        effectiveStyle != 'minimal_clean';
    final textScaler = MediaQuery.textScalerOf(context);
    final screenW = MediaQuery.sizeOf(context).width;
    final availW = (screenW - padX * 2).clamp(140.0, 8000.0);
    final gridLayout = PosterCardLayout.forGrid(
      profile: metrics,
      availableWidth: availW,
      density: prefs.listDensity,
      scale: prefs.posterScale,
      aspectRatio: 2 / 3,
      showBelowCaption: showBelowCaption,
      crossSpacing: gridGap,
      textScaler: textScaler,
    );
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(padX, 0, padX, 16),
          child: Text(
            title,
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
      ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(padX, 0, padX, 28),
        sliver: SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: gridLayout.columns,
            mainAxisSpacing: gridLayout.mainSpacing,
            crossAxisSpacing: gridLayout.crossSpacing,
            mainAxisExtent: gridLayout.cardHeight,
          ),
          itemCount: items.length,
          itemBuilder: (_, idx) {
            final c = items[idx];
            return MediaCard(
              item: c,
              appState: widget.appState,
              width: gridLayout.cardWidth,
              onTap: () => _openItemDetail(c),
              onQuickPlay: c.isPlayable ? () => _play(c) : null,
              onLongPress: () => showMediaItemContextSheet(
                context: context,
                item: c,
                appState: widget.appState,
                onOpenDetail: () => _openItemDetail(c),
                onQuickPlay: c.isPlayable ? () => _play(c) : null,
              ),
            );
          },
        ),
      ),
    ];
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
    final rawSeasonOverview = activeSeason?.cleanOverview ?? '';
    // Hide season overview when it merely duplicates the series overview right above!
    final seasonOverview = (rawSeasonOverview.isNotEmpty &&
            rawSeasonOverview.trim() != _item.cleanOverview.trim())
        ? rawSeasonOverview
        : '';

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
    final searchActive = _episodeSearchOpen || _episodeFilterQuery.isNotEmpty;
    final canBatchDownload = widget.appState.canDownloadItem(_resolveDownloadTarget());

    final pillBg = skin.isLight
        ? Colors.black.withValues(alpha: 0.055)
        : Colors.white.withValues(alpha: 0.09);
    final pillBorder = skin.isLight
        ? Border.all(color: skin.border, width: 0.7)
        : Border.all(color: Colors.white.withValues(alpha: 0.12), width: 0.75);

    Widget buildToolCircle({
      Key? key,
      required IconData icon,
      required String tooltip,
      required VoidCallback onTap,
      bool highlighted = false,
      String? wideLabel,
    }) {
      return Tooltip(
        message: tooltip,
        child: PressableScale(
          key: key,
          onTap: onTap,
          hoverScale: 1.03,
          pressScale: 0.94,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 34,
            width: wideLabel != null ? null : 34,
            padding: wideLabel != null
                ? const EdgeInsets.symmetric(horizontal: 11)
                : EdgeInsets.zero,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: highlighted
                  ? skin.accent.withValues(alpha: skin.isLight ? 0.14 : 0.22)
                  : pillBg,
              borderRadius: BorderRadius.circular(999),
              border: highlighted
                  ? Border.all(color: skin.accent.withValues(alpha: 0.55), width: 0.9)
                  : pillBorder,
            ),
            child: wideLabel != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 14, color: highlighted ? skin.accent : skin.fg2),
                      const SizedBox(width: 5),
                      Text(
                        wideLabel,
                        style: TextStyle(
                          color: highlighted ? skin.accent : skin.fg,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  )
                : Icon(icon, size: 15.5, color: highlighted ? skin.accent : skin.fg2),
          ),
        ),
      );
    }

    final viewModeLabel = switch (_episodeViewMode) {
      'grid' => '宫格',
      'cards' => '剧照',
      _ => '列表',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: padX),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Responsive iOS Header: Season Picker + Uniform 34px Controls (wraps cleanly on 360px phones)
              LayoutBuilder(
                builder: (context, headerConstraints) {
                  final seasonSelector = _seasons.length > 1
                      ? VedroPullDownButton<String>(
                          key: const ValueKey('detail-season-dropdown'),
                          height: 34,
                          displayLabelOverride:
                              '${activeSeason?.name ?? _seasons.first.name} · ${_episodes.length} 集',
                          value: _selectedSeasonId ?? _seasons.first.id,
                          items: _seasons
                              .map(
                                (s) => VedroDropdownItem<String>(
                                  value: s.id,
                                  label: s.name,
                                  subtitle: s.childCount != null && s.childCount! > 0
                                      ? '共 ${s.childCount} 集'
                                      : null,
                                  itemKey: ValueKey('season-option-${s.id}'),
                                ),
                              )
                              .toList(),
                          onChanged: _loadEpisodes,
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Flexible(
                              child: Text(
                                _seasons.first.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: skin.applyHeadlineMood(
                                  TextStyle(
                                    color: skin.fg,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '共 ${_episodes.length} 集',
                              style: TextStyle(
                                color: skin.fg3,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        );
                  final controls = Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (_episodes.length > 12)
                        buildToolCircle(
                          key: const ValueKey('detail-episode-search-toggle'),
                          icon: CupertinoIcons.search,
                          tooltip: '搜集名 / 跳集',
                          highlighted: searchActive,
                          onTap: () {
                            setState(() {
                              if (searchActive) {
                                _episodeSearchOpen = false;
                                _episodeJumpCtrl.clear();
                                _episodeFilterQuery = '';
                              } else {
                                _episodeSearchOpen = true;
                              }
                            });
                            if (_episodeSearchOpen) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) _episodeSearchFocus.requestFocus();
                              });
                            }
                          },
                        ),
                      buildToolCircle(
                        key: const ValueKey('detail-episode-sort-btn'),
                        icon: CupertinoIcons.arrow_up_arrow_down,
                        tooltip: _episodeDescending ? '当前倒序（点击切正序）' : '当前正序（点击切倒序）',
                        highlighted: _episodeDescending,
                        wideLabel: wide ? (_episodeDescending ? '倒序' : '正序') : null,
                        onTap: () => setState(() {
                          _episodeDescending = !_episodeDescending;
                          _episodeRangeIndex = 0;
                        }),
                      ),
                      if (canBatchDownload)
                        buildToolCircle(
                          key: const ValueKey('detail-batch-download-btn'),
                          icon: CupertinoIcons.arrow_down_to_line,
                          tooltip: '批量下载选集',
                          wideLabel: wide ? '批量下载' : null,
                          onTap: _openBatchDownloadDialog,
                        ),
                      VedroPullDownButton<String>(
                        key: const ValueKey('detail-episode-view-dropdown'),
                        height: 34,
                        displayLabelOverride: viewModeLabel,
                        value: _episodeViewMode,
                        items: const [
                          VedroDropdownItem(value: 'list', label: '列表视图'),
                          VedroDropdownItem(value: 'cards', label: '横向剧照'),
                          VedroDropdownItem(value: 'grid', label: '选集宫格'),
                        ],
                        onChanged: (mode) => setState(() {
                          _episodeViewMode = mode;
                          _episodeModeUserChosen = true;
                        }),
                      ),
                    ],
                  );
                  if (headerConstraints.maxWidth < 300) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        seasonSelector,
                        const SizedBox(height: 8),
                        controls,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: seasonSelector,
                        ),
                      ),
                      const SizedBox(width: 8),
                      controls,
                    ],
                  );
                },
              ),

              // Expandable Full-Width iOS Search Bar (Never truncates range pills!)
              AnimatedSize(
                duration: const Duration(milliseconds: 190),
                curve: VedroTheme.easeOut,
                child: searchActive
                    ? Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 36,
                                child: TextField(
                                  controller: _episodeJumpCtrl,
                                  focusNode: _episodeSearchFocus,
                                  onChanged: (v) => setState(() {
                                    _episodeFilterQuery = v;
                                    _episodeRangeIndex = 0;
                                  }),
                                  style: TextStyle(color: skin.fg, fontSize: 13.5),
                                  decoration: InputDecoration(
                                    hintText: '输入集数或分集标题定位…',
                                    hintStyle: TextStyle(color: skin.fg3, fontSize: 13),
                                    prefixIcon:
                                        Icon(CupertinoIcons.search, size: 16, color: skin.fg3),
                                    prefixIconConstraints: const BoxConstraints(minWidth: 36),
                                    suffixIcon: _episodeFilterQuery.isNotEmpty
                                        ? IconButton(
                                            padding: EdgeInsets.zero,
                                            icon: Icon(
                                              CupertinoIcons.clear_circled_solid,
                                              size: 16,
                                              color: skin.fg3,
                                            ),
                                            onPressed: () {
                                              _episodeJumpCtrl.clear();
                                              setState(() => _episodeFilterQuery = '');
                                            },
                                          )
                                        : null,
                                    contentPadding:
                                        const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                    filled: true,
                                    fillColor: pillBg,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(999),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(999),
                                      borderSide: BorderSide(
                                        color: skin.isLight
                                            ? skin.border
                                            : Colors.white.withValues(alpha: 0.12),
                                        width: 0.75,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(999),
                                      borderSide: BorderSide(color: skin.accent, width: 1.1),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            PressableScale(
                              onTap: () {
                                _episodeJumpCtrl.clear();
                                _episodeSearchFocus.unfocus();
                                setState(() {
                                  _episodeFilterQuery = '';
                                  _episodeSearchOpen = false;
                                });
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                child: Text(
                                  '取消',
                                  style: TextStyle(
                                    color: skin.accent,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
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
            ],
          ),
        ),

        // Full-Width Edge-to-Edge Episode Range Strip (Zero Clipping!)
        if (rangeCount > 1 && query.isEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 32,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: ListView.separated(
                padding: EdgeInsets.symmetric(horizontal: padX),
                scrollDirection: Axis.horizontal,
                itemCount: rangeCount,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, rIdx) {
                  final rStart = rIdx * chunkSize;
                  final rEnd = (rStart + chunkSize).clamp(0, filtered.length);
                  final firstNum = filtered[rStart].indexNumber ?? (rStart + 1);
                  final lastNum = filtered[rEnd - 1].indexNumber ?? rEnd;
                  final active = rIdx == safeRangeIdx;
                  return PressableScale(
                    onTap: () => setState(() => _episodeRangeIndex = rIdx),
                    borderRadius: BorderRadius.circular(999),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: active ? skin.activePillBg : pillBg,
                        borderRadius: BorderRadius.circular(999),
                        border: active ? null : pillBorder,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$firstNum-$lastNum',
                        style: TextStyle(
                          color: active ? skin.activePillFg : skin.fg2,
                          fontSize: 12,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],

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
                              else if (widget.appState.prefs.showMultiVersionBadge &&
                                  ep.versionCount > 1)
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
              final season = _activeSeason;
              final fallback = (season != null &&
                      widget.appState.wideArt(season) != null &&
                      widget.appState.wideArt(_item)?.isPoster != false)
                  ? season
                  : _item;
              return _EpisodeHorizontalCard(
                episode: ep,
                seriesFallback: fallback,
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
              children: visibleEps.map((ep) {
                final season = _activeSeason;
                final fallback = (season != null &&
                        widget.appState.wideArt(season) != null &&
                        widget.appState.wideArt(_item)?.isPoster != false)
                    ? season
                    : _item;
                return _EpisodeRow(
                  episode: ep,
                  seriesFallback: fallback,
                  appState: widget.appState,
                  onTap: () => _play(ep, sourceId: _matchingSourceIdForEpisode(ep)),
                  onOpenDetail: () => _openItemDetail(ep),
                  onPickVersion:
                      ep.versionCount > 1 ? () => _openEpisodeVersionSheet(ep) : null,
                );
              }).toList(),
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
        tp.dispose();

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
                    PressableScale(
                      onTap: () => setState(() => _expanded = !_expanded),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                    PressableScale(
                      onTap: widget.onTranslateToggle,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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

class _TitleHeadline extends StatelessWidget {
  const _TitleHeadline(this.text, this.wide, {this.centered = false});
  final String text;
  final bool wide;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return Text(
      text,
      maxLines: 2,
      textAlign: centered ? TextAlign.center : TextAlign.start,
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
    this.autofocus = false,
  });

  final String label;
  final double progress;
  final Color accent;
  final VoidCallback onTap;
  final bool fullWidth;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final h = fullWidth ? 50.0 : 46.0;
    final r = fullWidth ? skin.cardRadius.clamp(6.0, 16.0) : skin.radiusForPill(h);
    return PressableScale(
      onTap: onTap,
      autofocus: autofocus,
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

    return RepaintBoundary(
      child: SizedBox(
      width: widget.width,
      child: PressableScale(
        onTap: widget.onTap,
        onLongPress: widget.onPickVersion ?? widget.onOpenDetail,
        onSecondaryTap: widget.onPickVersion ?? widget.onOpenDetail,
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
                      displayWidth: widget.width,
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
                              child: PressableScale(
                                onTap: widget.onPickVersion,
                                borderRadius: BorderRadius.circular(10),
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
                          PressableScale(
                            onTap: widget.onOpenDetail,
                            borderRadius: BorderRadius.circular(12),
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
    ),
    );
  }
}

/// Unified iOS-Caliber Pull-Down Selector Bar (`下拉框`) for Version, Audio, and Subtitle on `DetailScreen`.
/// - Strictly single-selects version by integer index (never highlights >1 version even when 4+ share Name/Id)
/// - Passively reflects version-specific tracks & filename traits with ZERO cloud-drive API probes
/// - Adapts cleanly to 320px–430px portrait phones (stacked full-width Version + 2-column Audio/Subtitle) and wide desktops.
class _TracksPanel extends StatelessWidget {
  const _TracksPanel({
    required this.isSeries,
    this.isLoading = false,
    this.expectedVersionCount = 1,
    required this.versions,
    required this.selectedVersionIndex,
    required this.activeStreamSource,
    this.hasKnownEmbeddedStreams = false,
    required this.selectedAudioIndex,
    required this.selectedSubtitleIndex,
    this.preferredAudioLangOverride,
    this.preferredSubLangOverride,
    required this.localExternalSubPath,
    required this.appState,
    required this.onSelectVersionIndex,
    required this.onSelectAudio,
    required this.onSelectSubtitle,
    required this.onSelectVersionAudioLang,
    required this.onSelectVersionSubLang,
    required this.onPickExternalSubtitle,
    required this.onClearExternalSubtitle,
  });

  final bool isSeries;
  final bool isLoading;
  final int expectedVersionCount;
  final List<ResolvedMediaVersion> versions;
  final int selectedVersionIndex;
  final MediaSourceModel? activeStreamSource;
  final bool hasKnownEmbeddedStreams;
  final int? selectedAudioIndex;
  final int? selectedSubtitleIndex;
  final String? preferredAudioLangOverride;
  final String? preferredSubLangOverride;
  final String? localExternalSubPath;
  final VedroAppState appState;
  final ValueChanged<int> onSelectVersionIndex;
  final ValueChanged<int?> onSelectAudio;
  final ValueChanged<int?> onSelectSubtitle;
  final ValueChanged<String> onSelectVersionAudioLang;
  final ValueChanged<String> onSelectVersionSubLang;
  final VoidCallback onPickExternalSubtitle;
  final VoidCallback onClearExternalSubtitle;

  String? _inferPassiveAudioTrait(MediaSourceModel? src, ResolvedMediaVersion? ver) {
    if (src == null) return null;
    final raw = '${ver?.displayTitle ?? ''} ${ver?.folderBadge ?? ''} ${src.name ?? ''} ${src.path ?? ''}'
        .toLowerCase();
    if (raw.contains('国粤英')) return '国粤英多音轨';
    if (raw.contains('国粤') || (raw.contains('mandarin') && raw.contains('cantonese'))) {
      return '国粤双语';
    }
    if (raw.contains('国英')) return '国英双语';
    if (raw.contains('台配') || raw.contains('国配') || raw.contains('国语')) return '国语配音';
    if (raw.contains('粤语') || raw.contains('粤配') || raw.contains('cantonese')) return '粤语配音';
    if (raw.contains('日语音轨') || raw.contains('双语') || raw.contains('dual')) return '多音轨封装';
    return null;
  }

  String? _inferPassiveSubtitleTrait(MediaSourceModel? src, ResolvedMediaVersion? ver) {
    if (src == null) return null;
    final raw = '${ver?.displayTitle ?? ''} ${ver?.folderBadge ?? ''} ${src.name ?? ''} ${src.path ?? ''}'
        .toLowerCase();
    if (raw.contains('特效') || raw.contains('ass')) return 'ASS 特效字幕';
    if (raw.contains('简繁英') || raw.contains('中英')) return '中英双语字幕';
    if (raw.contains('简繁') || raw.contains('chs') || raw.contains('cht')) return '内封中文字幕';
    if (raw.contains('sup') || raw.contains('pgs')) return '原盘图形字幕';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final safeVerIdx = versions.isEmpty
        ? 0
        : selectedVersionIndex.clamp(0, versions.length - 1);
    final activeVer = versions.isNotEmpty ? versions[safeVerIdx] : null;
    final streamSrc = activeStreamSource ?? activeVer?.source;
    final audios = streamSrc?.audioStreams ?? const <MediaStreamModel>[];
    final subs = streamSrc?.subtitleStreams ?? const <MediaStreamModel>[];
    final passiveAudio = _inferPassiveAudioTrait(streamSrc, activeVer);
    final passiveSub = _inferPassiveSubtitleTrait(streamSrc, activeVer);
    final extFileName = localExternalSubPath?.trim().isNotEmpty == true
        ? localExternalSubPath!.replaceAll('\\', '/').split('/').last
        : null;
    final hasAnyRealTracks =
        audios.isNotEmpty || subs.isNotEmpty || hasKnownEmbeddedStreams || extFileName != null;

    if (isLoading && versions.isEmpty) {
      if (isSeries && expectedVersionCount <= 1) {
        return const SizedBox.shrink();
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final compactMobile = constraints.maxWidth < 560;
          if (compactMobile) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const VedroShimmer(height: 36, borderRadius: 999),
                if (!isSeries) ...[
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Expanded(child: VedroShimmer(height: 36, borderRadius: 999)),
                      SizedBox(width: 8),
                      Expanded(child: VedroShimmer(height: 36, borderRadius: 999)),
                    ],
                  ),
                ],
              ],
            );
          }
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              const VedroShimmer(width: 168, height: 36, borderRadius: 999),
              if (!isSeries) ...[
                const VedroShimmer(width: 142, height: 36, borderRadius: 999),
                const VedroShimmer(width: 142, height: 36, borderRadius: 999),
              ],
            ],
          );
        },
      );
    }

    if (versions.length <= 1 && isSeries && !hasAnyRealTracks) {
      return const SizedBox.shrink();
    }

    final showVersionDropdown = versions.length > 1 || (!isSeries && versions.isNotEmpty);
    final showTrackDropdowns = !isSeries || hasAnyRealTracks;

    // 1. Version Pull-Down Items
    final versionItems = <VedroDropdownItem<int>>[
      for (var i = 0; i < versions.length; i++)
        () {
          final v = versions[i];
          final src = v.source;
          final video = src.videoStreams.isNotEmpty ? src.videoStreams.first : null;
          final res = video?.height != null
              ? (video!.height! >= 2160 ? '4K' : '${video.height}p')
              : '';
          final sz = fmtFileSize(src.size);
          final cont = (src.container ?? '').trim().toUpperCase();
          final sub = <String>[
            if (res.isNotEmpty && !v.displayTitle.toUpperCase().contains(res)) res,
            if (sz.isNotEmpty) sz,
            if (cont.isNotEmpty) cont,
          ].join(' · ');
          return VedroDropdownItem<int>(
            value: i,
            label: v.displayTitle,
            subtitle: sub.isEmpty ? null : sub,
            itemKey: ValueKey('${isSeries ? 'series' : 'movie'}-version-item-$i'),
          );
        }(),
    ];

    // 2. Audio Pull-Down Items & Active Label
    String audioButtonLabel = passiveAudio ?? '默认音轨';
    if (selectedAudioIndex != null) {
      final match = audios.where((a) => a.index == selectedAudioIndex);
      if (match.isNotEmpty) audioButtonLabel = match.first.label;
    } else if (audios.isNotEmpty) {
      audioButtonLabel = audios.first.label;
    }

    final audioItems = <VedroDropdownItem<int?>>[
      VedroDropdownItem<int?>(
        value: null,
        label: '默认音轨',
        subtitle: audios.isNotEmpty ? audios.first.detailedSpec : passiveAudio,
        itemKey: const ValueKey('detail-audio-default-item'),
      ),
      for (final a in audios)
        VedroDropdownItem<int?>(
          value: a.index,
          label: a.label,
          subtitle: a.detailedSpec,
          itemKey: ValueKey('detail-audio-item-${a.index}'),
        ),
    ];

    // 3. Subtitle Pull-Down Items & Active Label
    String subtitleButtonLabel;
    if (extFileName != null) {
      subtitleButtonLabel = extFileName;
    } else if (selectedSubtitleIndex == -1) {
      subtitleButtonLabel = '关闭字幕';
    } else if (selectedSubtitleIndex != null) {
      final match = subs.where((s) => s.index == selectedSubtitleIndex);
      subtitleButtonLabel = match.isNotEmpty ? match.first.label : '默认字幕';
    } else if (subs.isNotEmpty) {
      subtitleButtonLabel = subs.first.label;
    } else if (hasKnownEmbeddedStreams) {
      subtitleButtonLabel = '无内封字幕';
    } else {
      subtitleButtonLabel = passiveSub ?? '默认字幕';
    }

    final subtitleItems = <VedroDropdownItem<int?>>[
      VedroDropdownItem<int?>(
        value: null,
        label: (hasKnownEmbeddedStreams && subs.isEmpty) ? '无内封字幕' : '默认字幕',
        subtitle: subs.isNotEmpty ? subs.first.detailedSpec : passiveSub,
        itemKey: const ValueKey('detail-subtitle-default-item'),
      ),
      const VedroDropdownItem<int?>(
        value: -1,
        label: '关闭字幕',
        itemKey: ValueKey('detail-subtitle-off-item'),
      ),
      for (final s in subs)
        VedroDropdownItem<int?>(
          value: s.index,
          label: s.label,
          subtitle: s.detailedSpec,
          itemKey: ValueKey('detail-subtitle-item-${s.index}'),
        ),
      if (extFileName != null)
        VedroDropdownItem<int?>(
          value: -998,
          label: '移除外挂字幕',
          subtitle: extFileName,
          icon: Icons.close_rounded,
          isDestructive: true,
          itemKey: const ValueKey('detail-clear-local-sub-btn'),
          onTapOverride: onClearExternalSubtitle,
        ),
      if (!isSeries)
        VedroDropdownItem<int?>(
          value: -999,
          label: '挂载本地字幕文件…',
          icon: Icons.upload_file_rounded,
          itemKey: const ValueKey('detail-mount-local-sub-btn'),
          onTapOverride: onPickExternalSubtitle,
        ),
    ];

    return LayoutBuilder(
      key: const ValueKey('detail-version-selector'),
      builder: (context, constraints) {
        final compactMobile = constraints.maxWidth < 560;

        Widget buildVersionBtn({required bool expanded}) => VedroPullDownButton<int>(
              key: const ValueKey('detail-version-dropdown'),
              prefixLabel: versions.length > 1 ? '版本 · ${versions.length}' : '版本',
              value: safeVerIdx,
              items: versionItems,
              expanded: expanded,
              menuMaxWidth: 380,
              onChanged: onSelectVersionIndex,
            );

        Widget buildAudioBtn({required bool expanded}) => VedroPullDownButton<int?>(
              key: const ValueKey('detail-audio-dropdown'),
              prefixLabel: '音轨',
              displayLabelOverride: audioButtonLabel,
              value: selectedAudioIndex,
              items: audioItems,
              expanded: expanded,
              onChanged: onSelectAudio,
            );

        Widget buildSubBtn({required bool expanded}) => VedroPullDownButton<int?>(
              key: const ValueKey('detail-subtitle-dropdown'),
              prefixLabel: '字幕',
              displayLabelOverride: subtitleButtonLabel,
              value: extFileName != null ? -997 : selectedSubtitleIndex,
              items: subtitleItems,
              expanded: expanded,
              onChanged: (val) {
                if (val == -997) return;
                onSelectSubtitle(val);
              },
            );

        if (compactMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showVersionDropdown) buildVersionBtn(expanded: true),
              if (showVersionDropdown && showTrackDropdowns) const SizedBox(height: 8),
              if (showTrackDropdowns)
                KeyedSubtree(
                  key: const ValueKey('detail-audio-subtitle-panel'),
                  child: Row(
                    children: [
                      Expanded(child: buildAudioBtn(expanded: true)),
                      const SizedBox(width: 8),
                      Expanded(child: buildSubBtn(expanded: true)),
                    ],
                  ),
                ),
            ],
          );
        }

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (showVersionDropdown) buildVersionBtn(expanded: false),
            if (showTrackDropdowns)
              KeyedSubtree(
                key: const ValueKey('detail-audio-subtitle-panel'),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    buildAudioBtn(expanded: false),
                    buildSubBtn(expanded: false),
                  ],
                ),
              ),
          ],
        );
      },
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
    final screenW = MediaQuery.sizeOf(context).width;
    final isMobile = screenW < 580;
    final thumbW = isMobile ? 116.0 : 162.0;

    final rawTitle = ep.displayName.trim();
    final alreadyHasNum = ep.indexNumber != null &&
        RegExp('^第\\s*${ep.indexNumber}\\s*[集话]|^${ep.indexNumber}[.、\\s]')
            .hasMatch(rawTitle);
    final headlineText = (ep.indexNumber != null && !alreadyHasNum)
        ? '${ep.indexNumber}. $rawTitle'
        : (rawTitle.isNotEmpty
            ? rawTitle
            : (ep.indexNumber != null ? '第 ${ep.indexNumber} 集' : '未命名分集'));

    final metaParts = <String>[
      if (dur.isNotEmpty) dur,
      if (airDate.isNotEmpty) airDate,
      if (ep.communityRating != null && ep.communityRating! > 0)
        '★ ${ep.communityRating!.toStringAsFixed(1)}',
    ];

    return RepaintBoundary(
      child: Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PressableScale(
        onTap: widget.onTap,
        onLongPress: widget.onPickVersion ?? widget.onOpenDetail,
        onSecondaryTap: widget.onPickVersion ?? widget.onOpenDetail,
        onHoverChanged: (v) => setState(() => _hovered = v),
        hoverScale: 1.006,
        pressScale: 0.985,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.all(isMobile ? 10 : 12),
          decoration: BoxDecoration(
            color: skin.unifiedTileColor(hovered: _hovered),
            borderRadius: BorderRadius.circular(skin.cardRadius.clamp(10.0, 18.0)),
            border: skin.cardBorder(hovered: _hovered),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: thumbW,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(skin.cardRadius.clamp(6.0, 11.0)),
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
                          displayWidth: thumbW,
                        ),
                        if (ep.indexNumber != null)
                          Positioned(
                            left: 5,
                            bottom: ep.resumeProgress > 0.01 ? 8 : 5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xB8090B10),
                                borderRadius: BorderRadius.circular(4.5),
                              ),
                              child: Text(
                                'EP ${ep.indexNumber!.toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ),
                        if (ep.played)
                          Positioned(
                            top: 5,
                            right: 5,
                            child: Container(
                              width: 17,
                              height: 17,
                              decoration: const BoxDecoration(
                                color: Color(0xB8090B10),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: const Icon(Icons.check_rounded, size: 11, color: Colors.white),
                            ),
                          ),
                        if (ep.resumeProgress > 0.01)
                          Positioned(
                            left: 5,
                            right: 5,
                            bottom: 4,
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
              SizedBox(width: isMobile ? 12 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Line 1: 100% Dedicated to Episode Number + Title (NEVER covered by version pills!)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            headlineText,
                            maxLines: isMobile ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ep.played ? skin.fg2 : skin.fg,
                              fontSize: isMobile ? 14.5 : 15,
                              fontWeight: FontWeight.w600,
                              height: 1.28,
                              letterSpacing: -0.15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        PressableScale(
                          onTap: widget.onOpenDetail,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 1, 2, 4),
                            child: Icon(CupertinoIcons.ellipsis, size: 16, color: skin.fg3),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Line 2: Metadata + Clean Clickable Version Pill (When Multi-Version)
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (metaParts.isNotEmpty)
                          Text(
                            metaParts.join(' · '),
                            style: TextStyle(
                              color: skin.fg3,
                              fontSize: 11.5,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        if (widget.onPickVersion != null)
                          PressableScale(
                            onTap: widget.onPickVersion,
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: skin.accent.withValues(alpha: skin.isLight ? 0.12 : 0.18),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${ep.versionCount} 版本',
                                    style: TextStyle(
                                      color: skin.isLight ? skin.accent : Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 12,
                                    color: skin.isLight ? skin.accent : Colors.white70,
                                  ),
                                ],
                              ),
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
                        style: TextStyle(
                          color: skin.fg2,
                          fontSize: 12.5,
                          height: 1.44,
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
    return MediaSourceModel.resolveVersions(best, stripEpisodePrefix: true);
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
                ? '已加入下载队列：$added 集（支持 HTTP Range 断点续传，设置 → 下载与缓存）'
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
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: (MediaQuery.sizeOf(context).height * 0.86).clamp(360.0, 720.0),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
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

            Expanded(
              child: CustomScrollView(
                slivers: [
                  if (widget.seasons.length > 1)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          itemCount: widget.seasons.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, idx) {
                            final s = widget.seasons[idx];
                            final active = s.id == _seasonId;
                            return PressableScale(
                              onTap: () => _selectSeason(s.id),
                              borderRadius: BorderRadius.circular(skin.radiusForPill(36)),
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
                    ),

                  if (versions.length > 1)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
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
                                  PressableScale(
                                    onTap: () => setState(() => _versionIndex = i),
                                    borderRadius: BorderRadius.circular(skin.radiusForPill(30)),
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
                    ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
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
                                    return PressableScale(
                                      onTap: () => setState(() => _rangeIdx = rIdx),
                                      borderRadius: BorderRadius.circular(skin.radiusForPill(28)),
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
                  ),

                  if (_loadingSeason)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2, color: skin.fg2),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      sliver: SliverList.separated(
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
                ],
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
