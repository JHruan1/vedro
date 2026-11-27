import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_skin.dart';
import '../state/app_state.dart';
import 'vedro_artwork.dart';
import 'vedro_ui.dart';

/// macOS Spotlight / Forward style multi-server aggregated instant search palette (`⌘K`).
Future<void> showSpotlightSearch({
  required BuildContext context,
  required VedroAppState appState,
  required void Function(AggregatedSearchHit) onSelectHit,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭搜索',
    barrierColor: const Color(0x8A000000),
    transitionDuration: const Duration(milliseconds: 440),
    pageBuilder: (_, __, ___) => _SpotlightSearchOverlay(
      appState: appState,
      onSelectHit: onSelectHit,
    ),
    transitionBuilder: vedroDialogTransition,
  );
}

class _SpotlightSearchOverlay extends StatefulWidget {
  const _SpotlightSearchOverlay({
    required this.appState,
    required this.onSelectHit,
  });

  final VedroAppState appState;
  final void Function(AggregatedSearchHit) onSelectHit;

  @override
  State<_SpotlightSearchOverlay> createState() => _SpotlightSearchOverlayState();
}

class _SpotlightSearchOverlayState extends State<_SpotlightSearchOverlay> {
  final _ctrl = TextEditingController();
  final _resultsScope = FocusScopeNode(debugLabel: 'spotlight_results_scope');
  Timer? _debounce;
  List<AggregatedSearchHit> _hits = [];
  List<Map<String, dynamic>> _servers = [];
  String? _filterServerId;
  bool _searching = false;
  int _searchGen = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _resultsScope.dispose();
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
    _debounce = Timer(const Duration(milliseconds: 220), () => _runSearch(val.trim()));
  }

  Future<void> _runSearch(String term) async {
    final gen = ++_searchGen;
    setState(() => _searching = true);
    try {
      final res = await widget.appState.aggregatedSearch(term, limit: 24);
      if (mounted && gen == _searchGen) {
        setState(() {
          _hits = res.hits;
          _servers = res.servers;
          if (_filterServerId != null &&
              !_servers.any((s) => s['server_id']?.toString() == _filterServerId)) {
            _filterServerId = null;
          }
        });
      }
    } catch (_) {
    } finally {
      if (mounted && gen == _searchGen) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final topPad = MediaQuery.sizeOf(context).height * 0.10;
    final filtered = _filterServerId == null
        ? _hits
        : _hits.where((h) => h.serverId == _filterServerId).toList();
    final multiServer = _servers.length > 1;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      alignment: Alignment.topCenter,
      insetPadding: EdgeInsets.fromLTRB(16, topPad.clamp(44.0, 110.0), 16, 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 660,
          maxHeight: MediaQuery.sizeOf(context).height * 0.76,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: skin.surface,
            borderRadius: BorderRadius.circular(skin.cardRadius.clamp(12.0, 22.0)),
            border: Border.all(color: skin.borderStrong, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: skin.isLight ? 0.22 : 0.72),
                blurRadius: 36,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, size: 20, color: skin.fg2),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            autofocus: true,
                            textInputAction: TextInputAction.search,
                            onChanged: _onChanged,
                            onSubmitted: (val) async {
                              final q = val.trim();
                              if (q.isEmpty) return;
                              _debounce?.cancel();
                              await _runSearch(q);
                              if (mounted && _hits.isNotEmpty) {
                                _resultsScope.requestFocus();
                              }
                            },
                            style: TextStyle(color: skin.fg, fontSize: 16),
                            decoration: InputDecoration(
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              hintText: widget.appState.savedServers.length > 1
                                  ? '跨 ${widget.appState.savedServers.length} 个服务器聚合搜索…'
                                  : '搜索电影、剧集、演职员…',
                              hintStyle: TextStyle(color: skin.fg3, fontSize: 16),
                            ),
                          ),
                        ),
                        if (_searching)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                color: skin.fg2,
                              ),
                            ),
                          ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, size: 18, color: skin.fg3),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  if (multiServer)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _SrvFilterChip(
                              label: '全部 (${_hits.length})',
                              selected: _filterServerId == null,
                              onTap: () => setState(() => _filterServerId = null),
                            ),
                            ..._servers.map((s) {
                              final sid = s['server_id']?.toString() ?? '';
                              final sname = s['server_name']?.toString() ?? sid;
                              final cnt = (s['count'] as num?)?.toInt() ?? 0;
                              return Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: _SrvFilterChip(
                                  label: '$sname ($cnt)',
                                  selected: _filterServerId == sid,
                                  onTap: () => setState(() => _filterServerId = sid),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  const Divider(height: 1),
                  if (filtered.isNotEmpty)
                    Flexible(
                      child: FocusScope(
                        node: _resultsScope,
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 72, endIndent: 16),
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
                              _typeLabel(h.type),
                            ].join(' · ');

                            return PressableScale(
                              hoverScale: 1.0,
                              pressScale: 0.99,
                              borderRadius: BorderRadius.circular(10),
                              onTap: () {
                                Navigator.of(context).pop();
                                widget.onSelectHit(h);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 58,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(7),
                                        border: Border.all(color: skin.border, width: 0.6),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: thumbUrl.isNotEmpty
                                          ? FadeNetworkImage(
                                              url: thumbUrl,
                                              cacheWidth: 120,
                                              placeholder: GeneratedArt(seed: h.id, label: h.name),
                                            )
                                          : GeneratedArt(seed: h.id, label: h.name),
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
                                            style: TextStyle(
                                              color: skin.fg,
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
                                              style: TextStyle(
                                                color: skin.fg3,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (multiServer)
                                      Container(
                                        margin: const EdgeInsets.only(right: 8),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: skin.surface2,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: skin.border, width: 0.6),
                                        ),
                                        child: Text(
                                          h.serverName,
                                          style: TextStyle(
                                            color: skin.fg2,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      size: 18,
                                      color: skin.fg3,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                      child: Text(
                        _ctrl.text.trim().isEmpty
                            ? (widget.appState.savedServers.isEmpty
                                ? '添加媒体服务器后即可跨服聚合搜索'
                                : '输入片名、原名或演员名即时聚合检索')
                            : '没有找到匹配内容',
                        style: TextStyle(color: skin.fg3, fontSize: 13),
                      ),
                    ),
                ],
              ),
        ),
      ),
    );
  }

  static String _typeLabel(String t) {
    switch (t) {
      case 'Movie':
        return '电影';
      case 'Series':
        return '剧集';
      case 'Episode':
        return '单集';
      case 'Person':
        return '演职员';
      default:
        return t;
    }
  }
}

class _SrvFilterChip extends StatelessWidget {
  const _SrvFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return PressableScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? skin.activePillBg : skin.subtleChipBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? skin.activePillFg : skin.fg2,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
