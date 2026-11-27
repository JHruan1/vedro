import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/platform/platform_perf.dart';
import '../core/theme/display_profile.dart';
import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_scroll.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/media_card.dart';
import '../widgets/vedro_artwork.dart';
import '../widgets/vedro_ui.dart';
import '../widgets/windows_immersive_frame.dart';
import 'home_screen.dart' show showMediaItemContextSheet;

/// Infinite-paging library & facet browser (supports Library, Genre, Studio, Year, Favorites, Folders, Grid/List).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.appState,
    required this.onItemTap,
    this.onQuickPlay,
    this.onOpenAddServer,
    this.initialLibrary,
    this.initialGenreName,
    this.initialStudio,
    this.initialYear,
    this.initialOnlyFavorite = false,
    this.customTitle,
    this.topInset = 0,
    this.standalone = false,
  });

  final VedroAppState appState;
  final void Function(MediaItemModel) onItemTap;
  final void Function(MediaItemModel)? onQuickPlay;
  final void Function([String? initialUrl])? onOpenAddServer;
  final MediaItemModel? initialLibrary;
  final String? initialGenreName;
  final String? initialStudio;
  final int? initialYear;
  final bool initialOnlyFavorite;
  final String? customTitle;
  final double topInset;
  final bool standalone;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _scrollCtrl = VedroScrollController();
  MediaItemModel? _selectedLibrary;
  late String _sortBy;
  String _sortOrder = 'Descending';
  String _mediaTypeFilter = 'Movie,Series,Video,MusicVideo,BoxSet';
  bool _recursiveQuery = true;
  bool _userTypeOverride = false;
  String? _selectedGenreId;
  String? _selectedGenreName;
  String? _selectedStudio;
  int? _selectedYear;
  bool _onlyUnplayed = false;
  bool _onlyFavorite = false;
  bool _listViewMode = false;

  List<MediaItemModel> _items = [];
  List<Map<String, dynamic>> _genres = [];
  List<int> _years = [];
  int _total = 0;
  bool _loading = false;
  String? _loadError;
  int _requestGen = 0;
  static const int _pageSize = 60;

  static ({String types, bool recursive}) _defaultFilterForLibrary(MediaItemModel? lib) {
    if (lib == null) {
      return (types: 'Movie,Series,Video,MusicVideo,BoxSet', recursive: true);
    }
    if (lib.type == 'Folder' || lib.type == 'BoxSet') {
      return (types: '', recursive: false);
    }
    switch ((lib.collectionType ?? '').toLowerCase()) {
      case 'movies':
        return (types: 'Movie', recursive: true);
      case 'tvshows':
        return (types: 'Series', recursive: true);
      case 'boxsets':
        return (types: 'BoxSet', recursive: true);
      case 'musicvideos':
        return (types: 'MusicVideo', recursive: true);
      case 'homevideos':
        return (types: 'Video,Movie', recursive: true);
      case 'livetv':
        return (types: 'TvChannel,LiveTvChannel,Video', recursive: true);
      case 'folders':
        return (types: '', recursive: false);
      case 'mixed':
      default:
        return (types: 'Movie,Series,Video,MusicVideo,BoxSet', recursive: true);
    }
  }

  void _applyLibraryDefaults(MediaItemModel? lib) {
    final defaults = _defaultFilterForLibrary(lib);
    _mediaTypeFilter = defaults.types;
    _recursiveQuery = defaults.recursive;
    _userTypeOverride = false;
  }

  bool get _isFolderDrilldown =>
      _selectedLibrary != null &&
      (_selectedLibrary!.type == 'Folder' ||
          _selectedLibrary!.type == 'BoxSet' ||
          (_selectedLibrary!.collectionType ?? '').toLowerCase() == 'folders');

  void _handleItemTap(MediaItemModel item) {
    if (item.type == 'Folder') {
      Navigator.of(context).push(
        vedroRoute(LibraryScreen(
          appState: widget.appState,
          initialLibrary: item,
          onItemTap: widget.onItemTap,
          onQuickPlay: widget.onQuickPlay,
          standalone: true,
        )),
      );
      return;
    }
    widget.onItemTap(item);
  }

  @override
  void initState() {
    super.initState();
    _sortBy = widget.appState.prefs.defaultSort;
    _selectedGenreName = widget.initialGenreName;
    _selectedStudio = widget.initialStudio;
    _selectedYear = widget.initialYear;
    _onlyFavorite = widget.initialOnlyFavorite;
    if (widget.initialGenreName == null &&
        widget.initialStudio == null &&
        widget.initialYear == null &&
        !widget.initialOnlyFavorite) {
      _selectedLibrary = widget.initialLibrary ??
          (widget.appState.views.isNotEmpty ? widget.appState.views.first : null);
    } else {
      _selectedLibrary = widget.initialLibrary;
    }
    _applyLibraryDefaults(_selectedLibrary);
    _scrollCtrl.addListener(_onScroll);
    if (widget.appState.isSignedIn) {
      _loadFiltersAndReset();
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 500 &&
        !_loading &&
        _items.length < _total) {
      _loadPage(_items.length, gen: _requestGen);
    }
  }

  Future<void> _loadFiltersAndReset() async {
    final gen = ++_requestGen;
    setState(() {
      _items = [];
      _total = 0;
      _loadError = null;
      _loading = true;
    });
    final filtersFuture = widget.appState.core.invoke('get_filters', {
      if (_selectedLibrary != null) 'parent_id': _selectedLibrary!.id,
    }).catchError((_) => <String, dynamic>{});
    final itemsFuture = _fetchPageData(0);

    try {
      final results = await Future.wait<dynamic>([filtersFuture, itemsFuture]);
      if (!mounted || gen != _requestGen) return;
      final f = results[0] as Map<String, dynamic>;
      final page = results[1] as ({List<MediaItemModel> items, int total});
      setState(() {
        _genres = ((f['Genres'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();
        _years = ((f['Years'] as List<dynamic>?) ?? const [])
            .map((e) => int.tryParse(e.toString()))
            .whereType<int>()
            .toList()
          ..sort((a, b) => b.compareTo(a));
        _items = page.items;
        _total = page.total;
        _loadError = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _requestGen) return;
      setState(() {
        _loadError = VedroErrorFormatter.friendly(e);
        _loading = false;
      });
    }
  }

  Future<({List<MediaItemModel> items, int total})> _fetchPageData(int startIndex) async {
    final res = await widget.appState.core.invoke('get_items', {
      if (_selectedLibrary != null) 'ParentId': _selectedLibrary!.id,
      if (_mediaTypeFilter.isNotEmpty) 'IncludeItemTypes': _mediaTypeFilter,
      'Recursive': _recursiveQuery,
      'SortBy': _sortBy,
      'SortOrder': _sortOrder,
      'StartIndex': startIndex,
      'Limit': _pageSize,
      if (_selectedGenreId != null) 'GenreIds': _selectedGenreId,
      if (_selectedGenreName != null && _selectedGenreId == null) 'Genres': _selectedGenreName,
      if (_selectedStudio != null && _selectedStudio!.isNotEmpty) 'Studios': _selectedStudio,
      if (_selectedYear != null) 'Years': '$_selectedYear',
      if (_onlyUnplayed) 'IsPlayed': false,
      if (_onlyFavorite) 'IsFavorite': true,
    }) as Map<String, dynamic>;
    final fetched = ((res['Items'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MediaItemModel.fromJson)
        .toList();
    final total = (res['TotalRecordCount'] as num?)?.toInt() ?? (startIndex + fetched.length);
    return (items: fetched, total: total);
  }

  Future<void> _resetAndLoad() async {
    final gen = ++_requestGen;
    setState(() {
      _items = [];
      _total = 0;
      _loadError = null;
      _loading = false;
    });
    await _loadPage(0, gen: gen);
  }

  Future<void> _loadPage(int startIndex, {required int gen}) async {
    if (_loading && gen == _requestGen) return;
    setState(() {
      _loading = true;
      if (startIndex == 0) _loadError = null;
    });
    try {
      final page = await _fetchPageData(startIndex);
      if (!mounted || gen != _requestGen) return;
      setState(() {
        if (startIndex == 0) {
          _items = page.items;
        } else {
          _items.addAll(page.items);
        }
        _total = page.total;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted || gen != _requestGen) return;
      setState(() {
        _loadError = VedroErrorFormatter.friendly(e);
      });
    } finally {
      if (mounted && gen == _requestGen) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    if (!widget.appState.isSignedIn) {
      return Scaffold(
        backgroundColor: skin.canvas,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.grid_view_rounded, size: 36, color: skin.fg3),
              const SizedBox(height: 12),
              Text('连接媒体服务器后浏览媒体库', style: TextStyle(color: skin.fg2, fontSize: 14)),
              if (widget.onOpenAddServer != null) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => widget.onOpenAddServer!(),
                  child: const Text('添加媒体服务器'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final metrics = DisplayMetricsProfile.of(context);
    final prefs = widget.appState.prefs;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 820;
    final padX = prefs.horizontalMargin(wide);
    final gridGap = prefs.cardGap(wide);
    final isMac = !kIsWeb && Platform.isMacOS;
    final effDensity = prefs
            .overridesForPlatform(isMobile: metrics.isMobileOs)['grid_density']
            ?.toString() ??
        prefs.listDensity;
    final pageTitle = widget.customTitle ??
        (_selectedStudio != null
            ? '出品 · $_selectedStudio'
            : (_selectedGenreName != null
                ? '类型 · $_selectedGenreName'
                : (_onlyFavorite && _selectedLibrary == null
                    ? '我的收藏'
                    : (_selectedLibrary?.name ?? '全部媒体'))));

    return Scaffold(
      backgroundColor: skin.canvas,
      body: VedroSkinCanvas(
        child: Padding(
          padding: EdgeInsets.only(
            top: (!wide || widget.standalone) ? MediaQuery.paddingOf(context).top : widget.topInset,
          ),
          child: Column(
            children: [
              Stack(
                children: [
                  if (widget.standalone)
                    const Positioned.fill(child: WindowsWindowDragArea()),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      widget.standalone && isMac ? 82 : padX,
                      widget.standalone ? 12 : (wide ? 18 : 10),
                      (widget.standalone && !kIsWeb && Platform.isWindows) ? 148 : (padX - 6),
                      6,
                    ),
                    child: LayoutBuilder(
                  builder: (context, headerConstraints) {
                    final compactHeader =
                        widget.standalone && headerConstraints.maxWidth < 430;
                    final titleRow = Row(
                      children: [
                        if (widget.standalone) ...[
                          PressableScale(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                              decoration: BoxDecoration(
                                color: skin.surface2,
                                borderRadius: BorderRadius.circular(skin.radiusForPill(34)),
                                border: Border.all(color: skin.border, width: 0.7),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.arrow_back_ios_new_rounded, size: 13.5, color: skin.fg),
                                  const SizedBox(width: 4),
                                  Text('返回',
                                      style: TextStyle(
                                          color: skin.fg, fontSize: 13, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Flexible(
                                child: Text(
                                  pageTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: skin.applyHeadlineMood(
                                    TextStyle(
                                      color: skin.fg,
                                      fontSize: wide ? 26 : 22,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.6,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$_total',
                                style: TextStyle(
                                  color: skin.fg3,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!compactHeader) ..._sortActions(skin),
                      ],
                    );
                    if (!compactHeader) return titleRow;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        titleRow,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: _sortActions(skin),
                        ),
                      ],
                    );
                  },
                ),
                  ),
                ],
              ),
            // Filter strip: Libraries, Type, Unplayed, Favorite, Genre, Year
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.fromLTRB(padX, 6, padX, 12),
              child: Row(
                children: [
                  if (!_isFolderDrilldown) ...[
                    _FilterPill(
                      label: '全部',
                      selected: _selectedLibrary == null,
                      onTap: () {
                        setState(() {
                          _selectedLibrary = null;
                          _selectedGenreId = null;
                          _applyLibraryDefaults(null);
                        });
                        _loadFiltersAndReset();
                      },
                    ),
                    const SizedBox(width: 8),
                    ...widget.appState.views.map((lib) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _FilterPill(
                            label: lib.name,
                            selected: _selectedLibrary?.id == lib.id,
                            onTap: () {
                              setState(() {
                                _selectedLibrary = lib;
                                _selectedGenreId = null;
                                _applyLibraryDefaults(lib);
                              });
                              _loadFiltersAndReset();
                            },
                          ),
                        )),
                  ],
                  _FilterPill(
                    label: '电影',
                    selected: _userTypeOverride && _mediaTypeFilter == 'Movie',
                    onTap: () {
                      setState(() {
                        if (_userTypeOverride && _mediaTypeFilter == 'Movie') {
                          _applyLibraryDefaults(_selectedLibrary);
                        } else {
                          _userTypeOverride = true;
                          _mediaTypeFilter = 'Movie';
                          _recursiveQuery = true;
                        }
                      });
                      _resetAndLoad();
                    },
                  ),
                  const SizedBox(width: 8),
                  _FilterPill(
                    label: '剧集',
                    selected: _userTypeOverride && _mediaTypeFilter == 'Series',
                    onTap: () {
                      setState(() {
                        if (_userTypeOverride && _mediaTypeFilter == 'Series') {
                          _applyLibraryDefaults(_selectedLibrary);
                        } else {
                          _userTypeOverride = true;
                          _mediaTypeFilter = 'Series';
                          _recursiveQuery = true;
                        }
                      });
                      _resetAndLoad();
                    },
                  ),
                  const SizedBox(width: 8),
                  _FilterPill(
                    label: '未看',
                    selected: _onlyUnplayed,
                    onTap: () {
                      setState(() => _onlyUnplayed = !_onlyUnplayed);
                      _resetAndLoad();
                    },
                  ),
                  const SizedBox(width: 8),
                  _FilterPill(
                    label: '收藏',
                    selected: _onlyFavorite,
                    onTap: () {
                      setState(() => _onlyFavorite = !_onlyFavorite);
                      _resetAndLoad();
                    },
                  ),
                  if (_genres.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _MiniDropdown<String?>(
                      hint: _selectedGenreName ?? '类型',
                      value: _selectedGenreId,
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('全部类型')),
                        ..._genres.take(40).map((g) => DropdownMenuItem<String?>(
                              value: g['Id']?.toString(),
                              child: Text(g['Name']?.toString() ?? ''),
                            )),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _selectedGenreId = v;
                          _selectedGenreName = null;
                        });
                        _resetAndLoad();
                      },
                    ),
                  ],
                  if (_years.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _MiniDropdown<int?>(
                      hint: '年份',
                      value: _selectedYear,
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('全部年份')),
                        ..._years.take(45).map((y) => DropdownMenuItem<int?>(
                              value: y,
                              child: Text('$y'),
                            )),
                      ],
                      onChanged: (v) {
                        setState(() => _selectedYear = v);
                        _resetAndLoad();
                      },
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, gridConstraints) {
                  final textScaler = MediaQuery.textScalerOf(context);
                  final availW = (gridConstraints.maxWidth - padX * 2).clamp(140.0, 8000.0);
                  final effectiveStyle =
                      (skin.cardStyle == 'hover_reveal' && metrics.isTouchPrimary)
                          ? 'overlay_poster'
                          : skin.cardStyle;
                  final showBelowCaption = effectiveStyle != 'overlay_poster' &&
                      effectiveStyle != 'hover_reveal' &&
                      effectiveStyle != 'minimal_clean';
                  final isWideThumb = skin.mediaAspectRatio >= 1.2;
                  final gridLayout = PosterCardLayout.forGrid(
                    profile: metrics,
                    availableWidth: availW,
                    density: effDensity,
                    scale: prefs.posterScale,
                    aspectRatio: skin.mediaAspectRatio,
                    showBelowCaption: showBelowCaption,
                    crossSpacing: gridGap,
                    textScaler: textScaler,
                  );

                  if (_loading && _items.isEmpty) {
                    return GridView.builder(
                      padding: EdgeInsets.fromLTRB(padX, 4, padX, wide ? 44 : 108),
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: gridLayout.columns,
                        mainAxisSpacing: gridLayout.mainSpacing,
                        crossAxisSpacing: gridLayout.crossSpacing,
                        mainAxisExtent: gridLayout.cardHeight,
                      ),
                      itemCount: gridLayout.columns * 3,
                      itemBuilder: (_, __) => Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          VedroShimmer(aspectRatio: skin.mediaAspectRatio, borderRadius: 12),
                          if (showBelowCaption) ...[
                            SizedBox(height: gridLayout.captionTopGap),
                            const VedroShimmer(width: 84, height: 11, borderRadius: 4),
                          ],
                        ],
                      ),
                    );
                  }
                  if (_items.isEmpty) {
                    if (_loadError != null) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_off_rounded, size: 32, color: skin.fg3),
                              const SizedBox(height: 10),
                              Text(
                                '加载媒体库失败：$_loadError',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: skin.fg2, fontSize: 13.5),
                              ),
                              const SizedBox(height: 14),
                              FilledButton(
                                onPressed: _resetAndLoad,
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return Center(
                      child: Text(
                        '没有符合筛选条件的内容',
                        style: TextStyle(color: skin.fg3, fontSize: 14),
                      ),
                    );
                  }
                  if (_listViewMode) {
                    return RefreshIndicator(
                      onRefresh: _resetAndLoad,
                      child: ListView.separated(
                        controller: _scrollCtrl,
                        cacheExtent: PlatformPerfProfile.scrollCacheExtent,
                        padding: EdgeInsets.fromLTRB(padX, 4, padX, wide ? 44 : 108),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, idx) {
                          final item = _items[idx];
                          return _LibraryListTile(
                            item: item,
                            appState: widget.appState,
                            onTap: () => _handleItemTap(item),
                            onLongPressWithRect: (rect, thumbRadius) => showMediaItemContextSheet(
                              context: context,
                              item: item,
                              appState: widget.appState,
                              anchorRect: rect,
                              previewCornerRadius: thumbRadius,
                              onOpenDetail: () => _handleItemTap(item),
                              onQuickPlay: widget.onQuickPlay == null
                                  ? null
                                  : () => widget.onQuickPlay!(item),
                              onMutated: _resetAndLoad,
                            ),
                          );
                        },
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: _resetAndLoad,
                    child: GridView.builder(
                      key: const ValueKey('library-poster-grid'),
                      controller: _scrollCtrl,
                      cacheExtent: PlatformPerfProfile.scrollCacheExtent,
                      padding: EdgeInsets.fromLTRB(padX, 6, padX, wide ? 44 : 108),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: gridLayout.columns,
                        mainAxisSpacing: gridLayout.mainSpacing,
                        crossAxisSpacing: gridLayout.crossSpacing,
                        mainAxisExtent: gridLayout.cardHeight,
                      ),
                      itemCount: _items.length + (_loading ? 1 : 0),
                      itemBuilder: (context, idx) {
                        if (idx >= _items.length) {
                          return Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: skin.fg2,
                              ),
                            ),
                          );
                        }
                        final item = _items[idx];
                        return MediaCard(
                          item: item,
                          appState: widget.appState,
                          width: gridLayout.cardWidth,
                          landscape: isWideThumb,
                          onTap: () => _handleItemTap(item),
                          onQuickPlay: widget.onQuickPlay == null
                              ? null
                              : () => widget.onQuickPlay!(item),
                          onLongPressWithRect: (rect) => showMediaItemContextSheet(
                            context: context,
                            item: item,
                            appState: widget.appState,
                            anchorRect: rect,
                            landscapePreview: isWideThumb,
                            onOpenDetail: () => _handleItemTap(item),
                            onQuickPlay: widget.onQuickPlay == null
                                ? null
                                : () => widget.onQuickPlay!(item),
                            onMutated: _resetAndLoad,
                          ),
                        );
                      },
                    ),
                  );
                              },
                            ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  List<Widget> _sortActions(VedroSkin skin) => [
        IconButton(
          tooltip: _listViewMode ? '切换海报墙视图' : '切换列表视图',
          icon: Icon(
            _listViewMode ? Icons.grid_view_rounded : Icons.view_list_rounded,
            size: 20,
            color: skin.fg2,
          ),
          onPressed: () => setState(() => _listViewMode = !_listViewMode),
        ),
        PopupMenuButton<String>(
          tooltip: '排序',
          color: skin.surface2,
          icon: Icon(Icons.sort_rounded, size: 20, color: skin.fg2),
          onSelected: (v) {
            setState(() => _sortBy = v);
            _resetAndLoad();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'DateCreated', child: Text('添加时间')),
            PopupMenuItem(value: 'PremiereDate', child: Text('发行年份')),
            PopupMenuItem(value: 'CommunityRating', child: Text('评分')),
            PopupMenuItem(value: 'SortName', child: Text('名称')),
            PopupMenuItem(value: 'Random', child: Text('随机')),
          ],
        ),
        IconButton(
          tooltip: '升降序',
          icon: Icon(
            _sortOrder == 'Descending'
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            size: 19,
            color: skin.fg2,
          ),
          onPressed: () {
            setState(() => _sortOrder = _sortOrder == 'Descending' ? 'Ascending' : 'Descending');
            _resetAndLoad();
          },
        ),
      ];
}

class _LibraryListTile extends StatefulWidget {
  const _LibraryListTile({
    required this.item,
    required this.appState,
    required this.onTap,
    this.onLongPressWithRect,
  });

  final MediaItemModel item;
  final VedroAppState appState;
  final VoidCallback onTap;
  final void Function(Rect artRect, double thumbRadius)? onLongPressWithRect;

  @override
  State<_LibraryListTile> createState() => _LibraryListTileState();
}

class _LibraryListTileState extends State<_LibraryListTile> {
  final GlobalKey _artKey = GlobalKey(debugLabel: 'library-list-thumb');

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final item = widget.item;
    final thumbR = skin.cardRadius.clamp(6.0, 10.0);
    final peek = widget.onLongPressWithRect == null
        ? null
        : (Rect fallback) => widget.onLongPressWithRect!(
              vedroGlobalRectOfKey(context, _artKey) ?? fallback,
              thumbR,
            );
    return RepaintBoundary(
      child: PressableScale(
        onTap: widget.onTap,
        onLongPressWithRect: peek,
        onSecondaryTapWithRect: peek,
        hoverScale: 1.006,
        pressScale: 0.985,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: skin.unifiedTileColor(),
            borderRadius: BorderRadius.circular(skin.cardRadius.clamp(10.0, 16.0)),
            border: skin.cardBorder(),
          ),
          child: Row(
            children: [
              SizedBox(
                key: _artKey,
                width: 52,
                height: 78,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(thumbR),
                  child: VedroArtwork(
                    item: item,
                    appState: widget.appState,
                    width: 160,
                    displayWidth: 52,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: skin.fg,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.cardSubtitle,
                      style: TextStyle(color: skin.fg3, fontSize: 12.5),
                    ),
                    if (item.cleanOverview.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.cleanOverview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: skin.fg2, fontSize: 12.5, height: 1.4),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: skin.fg3),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniDropdown<T> extends StatefulWidget {
  const _MiniDropdown({
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String hint;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  State<_MiniDropdown<T>> createState() => _MiniDropdownState<T>();
}

class _MiniDropdownState<T> extends State<_MiniDropdown<T>> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    String currentLabel = widget.hint;
    for (final it in widget.items) {
      if (it.value == widget.value && it.child is Text) {
        final t = (it.child as Text).data;
        if (t != null && t.isNotEmpty) currentLabel = t;
        break;
      }
    }
    final active = widget.value != null;
    final radius = skin.radiusForPill(32);

    return Focus(
      canRequestFocus: false,
      onFocusChange: (f) {
        if (_focused != f) setState(() => _focused = f);
      },
      child: PopupMenuButton<int>(
        color: skin.surface2,
        elevation: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: skin.borderStrong, width: 0.8),
        ),
        onSelected: (idx) {
          if (idx >= 0 && idx < widget.items.length) {
            widget.onChanged(widget.items[idx].value);
          }
        },
        itemBuilder: (_) => List.generate(widget.items.length, (i) {
          final it = widget.items[i];
          final sel = it.value == widget.value;
          final text = it.child is Text ? ((it.child as Text).data ?? '') : '';
          return PopupMenuItem<int>(
            value: i,
            height: 36,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: sel ? skin.fg : skin.fg2,
                      fontSize: 13,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (sel) Icon(Icons.check_rounded, size: 15, color: skin.accent),
              ],
            ),
          );
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: active ? skin.activePillBg : skin.surface2,
            borderRadius: BorderRadius.circular(radius),
            border: _focused
                ? Border.all(color: skin.accent, width: 2.0)
                : ((!active && skin.frameStyle != 'borderless')
                    ? Border.all(color: skin.border, width: 0.7)
                    : null),
            boxShadow: _focused
                ? [BoxShadow(color: skin.accent.withValues(alpha: 0.35), blurRadius: 8)]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                currentLabel,
                style: TextStyle(
                  color: active ? skin.activePillFg : skin.fg2,
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 15,
                color: active ? skin.activePillFg : skin.fg3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: VedroTheme.easeOut,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? skin.activePillBg : skin.surface2,
          borderRadius: BorderRadius.circular(skin.radiusForPill(32)),
          border: (!selected && skin.frameStyle != 'borderless')
              ? Border.all(color: skin.border, width: 0.7)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? skin.activePillFg : skin.fg2,
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
