import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/media_card.dart';
import '../widgets/vedro_ui.dart';

/// Infinite-paging library browser supporting large catalogs with clean Apple-style filters.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.appState,
    required this.onItemTap,
    this.initialLibrary,
  });

  final VedroAppState appState;
  final void Function(MediaItemModel) onItemTap;
  final MediaItemModel? initialLibrary;

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
    final cols = (width / 168).floor().clamp(2, 8);

    return Scaffold(
      backgroundColor: VedroTheme.canvas,
      appBar: AppBar(
        title: Text(_selectedLibrary?.name ?? '媒体库'),
        actions: [
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
              _sortOrder == 'Descending' ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              size: 19,
              color: VedroTheme.fg2,
            ),
            onPressed: () {
              setState(() => _sortOrder = _sortOrder == 'Descending' ? 'Ascending' : 'Descending');
              _resetAndLoad();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
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
                      borderRadius: BorderRadius.circular(8),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
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
            child: GridView.builder(
              controller: _scrollCtrl,
              padding: EdgeInsets.fromLTRB(20, 4, 20, wide ? 36 : 104),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 18,
                crossAxisSpacing: 14,
                childAspectRatio: 0.56,
              ),
              itemCount: _items.length + (_loading ? 1 : 0),
              itemBuilder: (context, idx) {
                if (idx >= _items.length) {
                  return const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: VedroTheme.fg2),
                    ),
                  );
                }
                final item = _items[idx];
                return MediaCard(
                  item: item,
                  appState: widget.appState,
                  onTap: () => widget.onItemTap(item),
                );
              },
            ),
          ),
        ],
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
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? VedroTheme.fg : VedroTheme.surface2,
          borderRadius: BorderRadius.circular(8),
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
