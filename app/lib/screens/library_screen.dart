import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/media_card.dart';
import '../widgets/vedro_artwork.dart';
import '../widgets/vedro_ui.dart';

/// Infinite-paging library browser supporting large catalogs with shimmer skeletons and sleek pills.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.appState,
    required this.onItemTap,
    this.onQuickPlay,
    this.initialLibrary,
    this.topInset = 0,
    this.standalone = false,
  });

  final VedroAppState appState;
  final void Function(MediaItemModel) onItemTap;
  final void Function(MediaItemModel)? onQuickPlay;
  final MediaItemModel? initialLibrary;
  final double topInset;
  final bool standalone;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _scrollCtrl = ScrollController();
  MediaItemModel? _selectedLibrary;
  String _sortBy = 'DateCreated';
  String _sortOrder = 'Descending';
  String? _selectedGenreId;
  bool _onlyUnplayed = false;
  bool _onlyFavorite = false;

  List<MediaItemModel> _items = [];
  List<Map<String, dynamic>> _genres = [];
  int _total = 0;
  bool _loading = false;
  static const int _pageSize = 60;

  @override
  void initState() {
    super.initState();
    _selectedLibrary = widget.initialLibrary ??
        (widget.appState.views.isNotEmpty ? widget.appState.views.first : null);
    _scrollCtrl.addListener(_onScroll);
    _loadFiltersAndReset();
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
      _loadPage(_items.length);
    }
  }

  Future<void> _loadFiltersAndReset() async {
    try {
      final f = await widget.appState.core.invoke('get_filters', {
        if (_selectedLibrary != null) 'parent_id': _selectedLibrary!.id,
      }) as Map<String, dynamic>;
      _genres = ((f['Genres'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (_) {}
    await _resetAndLoad();
  }

  Future<void> _resetAndLoad() async {
    setState(() {
      _items = [];
      _total = 0;
    });
    await _loadPage(0);
  }

  Future<void> _loadPage(int startIndex) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await widget.appState.core.invoke('get_items', {
        if (_selectedLibrary != null) 'ParentId': _selectedLibrary!.id,
        'IncludeItemTypes': 'Movie,Series',
        'Recursive': true,
        'SortBy': _sortBy,
        'SortOrder': _sortOrder,
        'StartIndex': startIndex,
        'Limit': _pageSize,
        if (_selectedGenreId != null) 'GenreIds': _selectedGenreId,
        if (_onlyUnplayed) 'IsPlayed': false,
        if (_onlyFavorite) 'IsFavorite': true,
      }) as Map<String, dynamic>;
      final fetched = ((res['Items'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MediaItemModel.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _items.addAll(fetched);
        _total = (res['TotalRecordCount'] as num?)?.toInt() ?? _items.length;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 820;
    final padX = wide ? 32.0 : 20.0;
    final cols = ((width - padX * 2) / (wide ? 176 : 132)).floor().clamp(3, 9);

    return Scaffold(
      backgroundColor: VedroTheme.canvas,
      appBar: widget.standalone || !wide
          ? AppBar(
              title: Text(_selectedLibrary?.name ?? '媒体库'),
              actions: _sortActions(),
            )
          : null,
      body: Padding(
        padding: EdgeInsets.only(top: widget.standalone ? 0 : widget.topInset),
        child: Column(
          children: [
            if (wide && !widget.standalone)
              Padding(
                padding: EdgeInsets.fromLTRB(padX, 18, padX, 6),
                child: Row(
                  children: [
                    Text(
                      _selectedLibrary?.name ?? '媒体库',
                      style: const TextStyle(
                        color: VedroTheme.fg,
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$_total 项',
                      style: const TextStyle(
                        color: VedroTheme.fg3,
                        fontSize: 13.5,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Spacer(),
                    ..._sortActions(),
                  ],
                ),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.fromLTRB(padX, 6, padX, 12),
              child: Row(
                children: [
                  ...widget.appState.views.map((lib) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _FilterPill(
                          label: lib.name,
                          selected: _selectedLibrary?.id == lib.id,
                          onTap: () {
                            setState(() {
                              _selectedLibrary = lib;
                              _selectedGenreId = null;
                            });
                            _loadFiltersAndReset();
                          },
                        ),
                      )),
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
                    Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: VedroTheme.surface2,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: VedroTheme.line, width: 0.7),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _selectedGenreId,
                          dropdownColor: VedroTheme.surface2,
                          style: const TextStyle(color: VedroTheme.fg2, fontSize: 12.5),
                          hint: const Text('类型', style: TextStyle(color: VedroTheme.fg2, fontSize: 12.5)),
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('全部类型')),
                            ..._genres.take(40).map((g) => DropdownMenuItem<String?>(
                                  value: g['Id']?.toString(),
                                  child: Text(g['Name']?.toString() ?? ''),
                                )),
                          ],
                          onChanged: (v) {
                            setState(() => _selectedGenreId = v);
                            _resetAndLoad();
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!wide || widget.standalone)
              Padding(
                padding: EdgeInsets.fromLTRB(padX + 2, 0, padX, 8),
                child: Row(
                  children: [
                    Text(
                      '共 $_total 项',
                      style: const TextStyle(color: VedroTheme.fg3, fontSize: 12),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _loading && _items.isEmpty
                  ? GridView.builder(
                      padding: EdgeInsets.fromLTRB(padX, 4, padX, wide ? 44 : 108),
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 20,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.56,
                      ),
                      itemCount: cols * 3,
                      itemBuilder: (_, __) => const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          VedroShimmer(aspectRatio: 2 / 3, borderRadius: 14),
                          SizedBox(height: 9),
                          VedroShimmer(width: 100, height: 12, borderRadius: 4),
                        ],
                      ),
                    )
                  : GridView.builder(
                      controller: _scrollCtrl,
                      padding: EdgeInsets.fromLTRB(padX, 4, padX, wide ? 44 : 108),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 20,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.56,
                      ),
                      itemCount: _items.length + (_loading ? 1 : 0),
                      itemBuilder: (context, idx) {
                        if (idx >= _items.length) {
                          return const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: VedroTheme.fg2,
                              ),
                            ),
                          );
                        }
                        final item = _items[idx];
                        return MediaCard(
                          item: item,
                          appState: widget.appState,
                          onTap: () => widget.onItemTap(item),
                          onQuickPlay: widget.onQuickPlay == null
                              ? null
                              : () => widget.onQuickPlay!(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _sortActions() => [
        PopupMenuButton<String>(
          tooltip: '排序',
          color: VedroTheme.surface2,
          icon: const Icon(Icons.sort_rounded, size: 20, color: VedroTheme.fg2),
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
            color: VedroTheme.fg2,
          ),
          onPressed: () {
            setState(() => _sortOrder = _sortOrder == 'Descending' ? 'Ascending' : 'Descending');
            _resetAndLoad();
          },
        ),
      ];
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? VedroTheme.fg : VedroTheme.surface2,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? VedroTheme.fg : VedroTheme.line,
            width: 0.7,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? VedroTheme.canvas : VedroTheme.fg2,
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
