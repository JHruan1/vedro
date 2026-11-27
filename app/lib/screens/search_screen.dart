import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/display_profile.dart';
import '../core/theme/vedro_skin.dart';
import '../state/app_state.dart';
import '../widgets/vedro_artwork.dart';
import '../widgets/vedro_ui.dart';

/// AfuseKt-caliber Multi-Server Aggregated Search screen:
/// - Server underline tabs (`所有` | Server A | Server B...)
/// - Media type filter pills (`全部` | `电影` | `剧集` | `演员`)
/// - Grouped horizontal 2:3 Poster Carousels per server
/// - Persisted Search History chips when idle
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.appState, required this.onSelectHit});

  final VedroAppState appState;
  final void Function(AggregatedSearchHit) onSelectHit;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final FocusScopeNode _resultsScope = FocusScopeNode(debugLabel: 'search-results-scope');
  Timer? _debounce;
  List<AggregatedSearchHit> _hits = [];
  List<Map<String, dynamic>> _servers = [];
  String? _filterServerId;
  String _typeFilter = 'all'; // all | Movie | Series | Person
  bool _searching = false;
  int _searchGen = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _resultsScope.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String val) {
    _debounce?.cancel();
    if (val.trim().isEmpty) {
      _searchGen++;
      setState(() {
        _hits = [];
        _servers = [];
        _filterServerId = null;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 240), () => _runSearch(val.trim()));
  }

  Future<void> _runSearch(
    String term, {
    bool saveHistory = false,
    bool focusResults = false,
  }) async {
    final gen = ++_searchGen;
    setState(() => _searching = true);
    if (saveHistory) {
      unawaited(widget.appState.addSearchHistory(term));
    }
    try {
      final res = await widget.appState.aggregatedSearch(term, limit: 36);
      if (mounted && gen == _searchGen) {
        setState(() {
          _hits = res.hits;
          _servers = res.servers;
          if (_filterServerId != null &&
              !_servers.any((s) => s['server_id']?.toString() == _filterServerId)) {
            _filterServerId = null;
          }
        });
        if (focusResults && res.hits.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _resultsScope.canRequestFocus) {
              _resultsScope.requestFocus();
            }
          });
        }
      }
    } catch (_) {
      // Keep previous/empty state gracefully
    } finally {
      if (mounted && gen == _searchGen) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final padX = wide ? 32.0 : 18.0;
    final accent = Theme.of(context).colorScheme.secondary;

    final filtered = _hits.where((h) {
      if (_filterServerId != null && h.serverId != _filterServerId) return false;
      if (_typeFilter != 'all' && h.type != _typeFilter) return false;
      return true;
    }).toList();

    // Group results by server for AfuseKt-style horizontal poster rows
    final grouped = <String, ({String name, List<AggregatedSearchHit> items})>{};
    for (final h in filtered) {
      final key = h.serverId.isNotEmpty ? h.serverId : 'active';
      final name = h.serverName.isNotEmpty ? h.serverName : widget.appState.activeServerDisplayName;
      grouped.putIfAbsent(key, () => (name: name, items: [])).items.add(h);
    }

    final skin = VedroSkin.of(context);
    final history = widget.appState.prefs.searchHistory;

    return Scaffold(
      backgroundColor: skin.canvas,
      body: VedroSkinCanvas(
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(padX, wide ? 72 : 10, padX, 10),
                child: Text(
                  widget.appState.savedServers.length > 1 ? '聚合搜索' : '搜索',
                  style: skin.applyHeadlineMood(
                    TextStyle(
                      color: skin.fg,
                      fontSize: wide ? 28 : 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.7,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(padX, 0, padX, 10),
                child: TextField(
                  controller: _ctrl,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) {
                      _runSearch(v.trim(), saveHistory: true, focusResults: true);
                    }
                  },
                  style: TextStyle(color: skin.fg, fontSize: 14.5),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: skin.surface2,
                    hintText: widget.appState.savedServers.length > 1
                        ? '跨 ${widget.appState.savedServers.length} 个服务器搜索片名、演员…'
                        : '片名、原名或演职员',
                    prefixIcon: Icon(Icons.search_rounded, size: 19, color: skin.fg3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(skin.cardRadius.clamp(8.0, 14.0)),
                      borderSide: BorderSide(color: skin.border, width: 0.7),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(skin.cardRadius.clamp(8.0, 14.0)),
                      borderSide: skin.frameStyle == 'borderless'
                          ? BorderSide.none
                          : BorderSide(color: skin.border, width: 0.7),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(skin.cardRadius.clamp(8.0, 14.0)),
                      borderSide: BorderSide(color: skin.accent, width: 1.2),
                    ),
                    suffixIcon: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _ctrl,
                      builder: (_, value, __) => value.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.cancel_rounded, size: 17, color: skin.fg3),
                              onPressed: () {
                                _debounce?.cancel();
                                _searchGen++;
                                _ctrl.clear();
                                setState(() {
                                  _hits = [];
                                  _servers = [];
                                  _filterServerId = null;
                                  _searching = false;
                                });
                              },
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),

            // Server capsule tabs (Apple Music / TV+ borderless pills)
            if (_servers.length > 1)
              SizedBox(
                height: 36,
                child: ListView(
                  padding: EdgeInsets.symmetric(horizontal: padX),
                  scrollDirection: Axis.horizontal,
                  children: [
                    _ServerTab(
                      label: '所有 (${_hits.length})',
                      selected: _filterServerId == null,
                      accent: accent,
                      onTap: () => setState(() => _filterServerId = null),
                    ),
                    ..._servers.map((s) {
                      final sid = s['server_id']?.toString() ?? '';
                      final sname = s['server_name']?.toString() ?? sid;
                      final cnt = (s['count'] as num?)?.toInt() ?? 0;
                      return _ServerTab(
                        label: '$sname ($cnt)',
                        selected: _filterServerId == sid,
                        accent: accent,
                        onTap: () => setState(() => _filterServerId = sid),
                      );
                    }),
                  ],
                ),
              ),

          // Type filter pills
          if (_hits.isNotEmpty)
            SizedBox(
              height: 46,
              child: ListView(
                padding: EdgeInsets.fromLTRB(padX, 10, padX, 4),
                scrollDirection: Axis.horizontal,
                children: [
                  for (final (id, label) in const [
                    ('all', '全部'),
                    ('Movie', '电影'),
                    ('Series', '电视剧'),
                    ('Person', '演员'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _TypePill(
                        label: label,
                        selected: _typeFilter == id,
                        onTap: () => setState(() => _typeFilter = id),
                      ),
                    ),
                ],
              ),
            ),

          if (_searching)
            LinearProgressIndicator(
              minHeight: 1.5,
              backgroundColor: Colors.transparent,
              color: accent,
            ),

          Expanded(
            child: _ctrl.text.trim().isEmpty
                ? _buildIdleHistory(padX, history, skin)
                : grouped.isEmpty
                    ? Center(
                        child: Text(
                          _searching ? '正在跨服务器检索…' : '没有找到匹配结果',
                          style: TextStyle(color: skin.fg3, fontSize: 13.5),
                        ),
                      )
                    : FocusScope(
                        node: _resultsScope,
                        child: ListView(
                        padding: EdgeInsets.fromLTRB(0, 10, 0, wide ? 44 : 112),
                        children: grouped.values.map((group) {
                          final profile = DisplayMetricsProfile.of(context);
                          final prefs = widget.appState.prefs;
                          final posterW = prefs.posterCardWidth(wide, profile);
                          final decodeW = (posterW * profile.devicePixelRatio).round().clamp(160, 480);
                          final cardMetrics = PosterCardLayout.forCardWidth(
                            cardWidth: posterW,
                            aspectRatio: 2 / 3,
                            showBelowCaption: true,
                            textScaler: MediaQuery.textScalerOf(context),
                            devicePixelRatio: profile.devicePixelRatio,
                          );
                          final r = prefs.effectiveCardRadius(skin);
                          return Padding(
                            padding: EdgeInsets.only(bottom: wide ? 22 : 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: EdgeInsets.fromLTRB(padX, 0, padX, 8),
                                  child: Row(
                                    children: [
                                      Text(
                                        group.name,
                                        style: TextStyle(
                                          color: skin.fg,
                                          fontSize: 16.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${group.items.length}',
                                        style: TextStyle(color: skin.fg3, fontSize: 12.5),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  height: cardMetrics.cardHeight + 4,
                                  child: ListView.separated(
                                    padding: EdgeInsets.symmetric(horizontal: padX, vertical: 2),
                                    scrollDirection: Axis.horizontal,
                                    clipBehavior: Clip.none,
                                    itemCount: group.items.length,
                                    separatorBuilder: (_, __) => SizedBox(width: prefs.cardGap(wide)),
                                    itemBuilder: (_, idx) {
                                      final hit = group.items[idx];
                                      final url = hit.primaryImageTag != null
                                          ? widget.appState.buildServerImageUrl(
                                              hit.serverId,
                                              hit.id,
                                              type: 'Primary',
                                              tag: hit.primaryImageTag,
                                              maxWidth: decodeW.clamp(240, 480),
                                            )
                                          : '';
                                      return RepaintBoundary(
                                        child: SizedBox(
                                        width: posterW,
                                        child: PressableScale(
                                          onTap: () {
                                            unawaited(widget.appState.addSearchHistory(_ctrl.text.trim()));
                                            widget.onSelectHit(hit);
                                          },
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              AspectRatio(
                                                aspectRatio: 2 / 3,
                                                child: Container(
                                                  foregroundDecoration: BoxDecoration(
                                                    borderRadius: BorderRadius.circular(r),
                                                    border: skin.cardBorder(),
                                                  ),
                                                  decoration: BoxDecoration(
                                                    borderRadius: BorderRadius.circular(r),
                                                    color: skin.surface2,
                                                    boxShadow: skin.posterShadow(),
                                                  ),
                                                  clipBehavior: Clip.antiAlias,
                                                  child: url.isNotEmpty
                                                      ? FadeNetworkImage(
                                                          url: url,
                                                          cacheWidth: decodeW,
                                                          placeholder: GeneratedArt(
                                                            seed: hit.id,
                                                            label: hit.name,
                                                          ),
                                                        )
                                                      : GeneratedArt(
                                                          seed: hit.id,
                                                          label: hit.name,
                                                        ),
                                                ),
                                              ),
                                              SizedBox(height: cardMetrics.captionTopGap),
                                              Text(
                                                hit.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                strutStyle: StrutStyle(
                                                  fontSize: cardMetrics.titleFontSize,
                                                  height: PosterCardLayout.kStrutHeight,
                                                  forceStrutHeight: true,
                                                ),
                                                style: TextStyle(
                                                  color: skin.fg,
                                                  fontSize: cardMetrics.titleFontSize,
                                                  height: PosterCardLayout.kStrutHeight,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              SizedBox(height: cardMetrics.captionMidGap),
                                              Text(
                                                hit.productionYear != null
                                                    ? '${hit.productionYear}'
                                                    : (hit.series ?? hit.type),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                strutStyle: StrutStyle(
                                                  fontSize: cardMetrics.metaFontSize,
                                                  height: PosterCardLayout.kStrutHeight,
                                                  forceStrutHeight: true,
                                                ),
                                                style: TextStyle(
                                                  color: skin.fg3,
                                                  fontSize: cardMetrics.metaFontSize,
                                                  height: PosterCardLayout.kStrutHeight,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                      ),
          ),
        ],
      ),
      ),
      ),
    );
  }

  Widget _buildIdleHistory(double padX, List<String> history, VedroSkin skin) {
    if (history.isEmpty) {
      return Center(
        child: Text(
          widget.appState.savedServers.isEmpty && !widget.appState.isSignedIn
              ? '请先在首页添加媒体服务器'
              : '支持跨多个已保存服务器并行聚合检索',
          style: TextStyle(color: skin.fg3, fontSize: 13.5),
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(padX, 14, padX, 40),
      children: [
        Row(
          children: [
            Text(
              '最近搜索',
              style: TextStyle(color: skin.fg2, fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton(
              onPressed: widget.appState.clearSearchHistory,
              child: Text('清空', style: TextStyle(color: skin.fg3, fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: history.map((term) {
            return PressableScale(
              onTap: () {
                _ctrl.text = term;
                _runSearch(term);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  color: skin.surface2,
                  borderRadius: BorderRadius.circular(skin.radiusForPill(32)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history_rounded, size: 14, color: skin.fg3),
                    const SizedBox(width: 6),
                    Text(term, style: TextStyle(color: skin.fg2, fontSize: 13)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _ServerTab extends StatelessWidget {
  const _ServerTab({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final r = skin.radiusForPill(32);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PressableScale(
        onTap: onTap,
        borderRadius: BorderRadius.circular(r),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? skin.activePillBg : skin.surface2,
            borderRadius: BorderRadius.circular(r),
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
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final r = skin.radiusForPill(32);
    return PressableScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(r),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? skin.activePillBg : skin.surface2,
          borderRadius: BorderRadius.circular(r),
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
