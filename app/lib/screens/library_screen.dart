import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/media_card.dart';

/// Infinite-paging library browser supporting 550,000+ item embygo catalogs with
/// Genre/Year/Sort/Unplayed/Favorite filters.
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
    final cols = (width / 172).floor().clamp(2, 8);

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedLibrary?.name ?? '全部媒体库'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '排序方式',
            icon: const Icon(Icons.sort_rounded),
            onSelected: (v) {
              setState(() => _sortBy = v);
              _resetAndLoad();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'DateCreated', child: Text('按添加时间')),
              PopupMenuItem(value: 'PremiereDate', child: Text('按发行年份')),
              PopupMenuItem(value: 'CommunityRating', child: Text('按评分')),
              PopupMenuItem(value: 'SortName', child: Text('按名称')),
              PopupMenuItem(value: 'Random', child: Text('随机探索')),
            ],
          ),
          IconButton(
            tooltip: '切换升序/降序',
            icon: Icon(_sortOrder == 'Descending' ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded),
            onPressed: () {
              setState(() => _sortOrder = _sortOrder == 'Descending' ? 'Ascending' : 'Descending');
              _resetAndLoad();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Library & Filter bar
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ...widget.appState.views.map((lib) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(lib.name),
                        selected: _selectedLibrary?.id == lib.id,
                        onSelected: (_) {
                          setState(() {
                            _selectedLibrary = lib;
                            _selectedGenreId = null;
                          });
                          _loadFiltersAndReset();
                        },
                      ),
                    )),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('未看'),
                  selected: _onlyUnplayed,
                  onSelected: (v) {
                    setState(() => _onlyUnplayed = v);
                    _resetAndLoad();
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('收藏'),
                  selected: _onlyFavorite,
                  onSelected: (v) {
                    setState(() => _onlyFavorite = v);
                    _resetAndLoad();
                  },
                ),
                if (_genres.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  DropdownButton<String?>(
                    value: _selectedGenreId,
                    hint: const Text('类型'),
                    underline: const SizedBox.shrink(),
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
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            child: Row(
              children: [
                Text(
                  '共 $_total 部作品',
                  style: const TextStyle(color: VedroTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 16,
                crossAxisSpacing: 14,
                childAspectRatio: 0.56,
              ),
              itemCount: _items.length + (_loading ? 1 : 0),
              itemBuilder: (context, idx) {
                if (idx >= _items.length) {
                  return const Center(child: CircularProgressIndicator());
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
