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
import '../widgets/windows_immersive_frame.dart';
import 'home_screen.dart' show showMediaItemContextSheet;
import 'library_screen.dart';
import 'player_screen.dart';

part 'detail/detail_batch_download_dialog.dart';
part 'detail/detail_body.dart';
part 'detail/detail_components.dart';
part 'detail/detail_episode_widgets.dart';
part 'detail/detail_episodes_section.dart';
part 'detail/detail_tracks_panel.dart';

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
    if (!mounted) return;
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
    final isDesktop = PlatformPerfProfile.isDesktop;
    if (!isDesktop) {
      final p = await showDialog<String>(
        context: context,
        builder: (ctx) => VedroControllerScope<TextEditingController>(
          create: () => TextEditingController(),
          dispose: (c) => c.dispose(),
          builder: (ctx, ctrl) => AlertDialog(
            title: const Text('挂载本地外挂字幕'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: '/path/to/subtitle.ass'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('确定'),
              ),
            ],
          ),
        ),
      );
      if (p != null && p.isNotEmpty && mounted) {
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

  void _setDetailState(VoidCallback fn) => setState(fn);
}
