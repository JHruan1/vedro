import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/vedro_artwork.dart';

/// Multi-server Aggregated Search screen (queries all saved servers concurrently in Rust).
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.appState, required this.onSelectHit});

  final VedroAppState appState;
  final void Function(AggregatedSearchHit) onSelectHit;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<AggregatedSearchHit> _hits = [];
  List<Map<String, dynamic>> _servers = [];
  String? _filterServerId;
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String val) {
    _debounce?.cancel();
    if (val.trim().isEmpty) {
      setState(() {
        _hits = [];
        _servers = [];
        _filterServerId = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 220), () => _runSearch(val.trim()));
  }

  Future<void> _runSearch(String term) async {
    setState(() => _searching = true);
    try {
      final res = await widget.appState.aggregatedSearch(term, limit: 30);
      if (mounted) {
        setState(() {
          _hits = res.hits;
          _servers = res.servers;
          if (_filterServerId != null &&
              !_servers.any((s) => s['server_id']?.toString() == _filterServerId)) {
            _filterServerId = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final filtered = _filterServerId == null
        ? _hits
        : _hits.where((h) => h.serverId == _filterServerId).toList();
    final multiServer = _servers.length > 1;

    return Scaffold(
      backgroundColor: VedroTheme.canvas,
      appBar: AppBar(
        title: Text(widget.appState.savedServers.length > 1 ? '聚合搜索' : '搜索'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: TextField(
              controller: _ctrl,
              onChanged: _onChanged,
              style: const TextStyle(color: VedroTheme.fg, fontSize: 14),
              decoration: InputDecoration(
                hintText: widget.appState.savedServers.length > 1
                    ? '跨 ${widget.appState.savedServers.length} 个服务器聚合搜索…'
                    : '片名、原名或演职员',
                prefixIcon: const Icon(Icons.search_rounded, size: 19, color: VedroTheme.fg3),
                suffixIcon: _ctrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 17, color: VedroTheme.fg3),
                        onPressed: () {
                          _ctrl.clear();
                          setState(() {
                            _hits = [];
                            _servers = [];
                            _filterServerId = null;
                          });
                        },
                      )
                    : null,
              ),
            ),
          ),
          if (multiServer)
            SizedBox(
              height: 36,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                children: [
                  _FilterChip(
                    label: '全部 (${_hits.length})',
                    selected: _filterServerId == null,
                    onTap: () => setState(() => _filterServerId = null),
                  ),
                  ..._servers.map((s) {
                    final sid = s['server_id']?.toString() ?? '';
                    final sname = s['server_name']?.toString() ?? sid;
                    final cnt = (s['count'] as num?)?.toInt() ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _FilterChip(
                        label: '$sname ($cnt)',
                        selected: _filterServerId == sid,
                        onTap: () => setState(() => _filterServerId = sid),
                      ),
                    );
                  }),
                ],
              ),
            ),
          if (_searching)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(
                minHeight: 1.5,
                backgroundColor: Colors.transparent,
                color: VedroTheme.fg2,
              ),
            ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      widget.appState.savedServers.isEmpty && !widget.appState.isSignedIn
                          ? '请先在首页添加媒体服务器'
                          : (_ctrl.text.trim().isEmpty
                              ? '支持跨多个已保存服务器并行聚合检索'
                              : '没有找到匹配结果'),
                      style: const TextStyle(color: VedroTheme.fg3, fontSize: 13.5),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, wide ? 36 : 108),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, idx) {
                      final h = filtered[idx];
                      final thumbUrl = h.primaryImageTag != null
                          ? widget.appState.buildServerImageUrl(
                              h.serverId,
                              h.id,
                              type: 'Primary',
                              tag: h.primaryImageTag,
                              maxWidth: 120,
                            )
                          : '';
                      final sub = [
                        if (h.productionYear != null) '${h.productionYear}',
                        if (h.series != null) h.series!,
                        h.type,
                      ].join(' · ');

                      return InkWell(
                        onTap: () => widget.onSelectHit(h),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 60,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(color: VedroTheme.line, width: 0.6),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    GeneratedArt(seed: h.id, label: h.name),
                                    if (thumbUrl.isNotEmpty) FadeNetworkImage(url: thumbUrl),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      h.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: VedroTheme.fg,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (sub.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        sub,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: VedroTheme.fg3, fontSize: 12),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (multiServer)
                                Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: VedroTheme.surface2,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: VedroTheme.line, width: 0.6),
                                  ),
                                  child: Text(
                                    h.serverName,
                                    style: const TextStyle(color: VedroTheme.fg2, fontSize: 11),
                                  ),
                                ),
                              const Icon(Icons.chevron_right_rounded, size: 18, color: VedroTheme.fg3),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: selected ? VedroTheme.fg : VedroTheme.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? VedroTheme.fg : VedroTheme.line, width: 0.7),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? VedroTheme.canvas : VedroTheme.fg2,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
