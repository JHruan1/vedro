import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import 'vedro_artwork.dart';
import 'vedro_ui.dart';

/// macOS Spotlight / Forward style floating frosted-glass instant search palette.
Future<void> showSpotlightSearch({
  required BuildContext context,
  required VedroAppState appState,
  required void Function(MediaItemModel) onSelect,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭搜索',
    barrierColor: const Color(0x8A000000),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => _SpotlightSearchOverlay(
      appState: appState,
      onSelect: onSelect,
    ),
    transitionBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _SpotlightSearchOverlay extends StatefulWidget {
  const _SpotlightSearchOverlay({
    required this.appState,
    required this.onSelect,
  });

  final VedroAppState appState;
  final void Function(MediaItemModel) onSelect;

  @override
  State<_SpotlightSearchOverlay> createState() => _SpotlightSearchOverlayState();
}

class _SpotlightSearchOverlayState extends State<_SpotlightSearchOverlay> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _hints = [];
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
        _hints = [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), () => _runSearch(val.trim()));
  }

  Future<void> _runSearch(String term) async {
    setState(() => _searching = true);
    try {
      final res = await widget.appState.core.invoke('search_hints', {
        'term': term,
        'limit': 32,
      }) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _hints = ((res['SearchHints'] as List<dynamic>?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList();
        });
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.sizeOf(context).height * 0.11;
    return Material(
      type: MaterialType.transparency,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, topPad.clamp(48.0, 120.0), 16, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 620,
              maxHeight: MediaQuery.sizeOf(context).height * 0.72,
            ),
            child: GlassSurface(
              borderRadius: 20,
              blur: 32,
              color: VedroTheme.glassStrong,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded, size: 20, color: VedroTheme.fg2),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            autofocus: true,
                            onChanged: _onChanged,
                            style: const TextStyle(color: VedroTheme.fg, fontSize: 16),
                            decoration: const InputDecoration(
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              hintText: '搜索电影、剧集、演职员…',
                              hintStyle: TextStyle(color: VedroTheme.fg3, fontSize: 16),
                            ),
                          ),
                        ),
                        if (_searching)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                color: VedroTheme.fg2,
                              ),
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18, color: VedroTheme.fg3),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (_hints.isNotEmpty)
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _hints.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72, endIndent: 16),
                        itemBuilder: (_, idx) {
                          final h = _hints[idx];
                          final id = (h['ItemId'] ?? h['Id'] ?? '').toString();
                          final name = (h['Name'] ?? '').toString();
                          final type = (h['Type'] ?? 'Movie').toString();
                          final imgTag = h['PrimaryImageTag']?.toString();
                          final thumbUrl = imgTag != null
                              ? widget.appState.buildImageUrl(id, type: 'Primary', tag: imgTag, maxWidth: 120)
                              : '';
                          final sub = [
                            if (h['ProductionYear'] != null) '${h['ProductionYear']}',
                            if (h['Series'] != null) '${h['Series']}',
                            _typeLabel(type),
                          ].join(' · ');

                          return InkWell(
                            onTap: () {
                              Navigator.of(context).pop();
                              widget.onSelect(MediaItemModel(
                                id: id,
                                name: name,
                                type: type,
                                primaryImageTag: imgTag,
                              ));
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
                                      border: Border.all(color: VedroTheme.line, width: 0.6),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        GeneratedArt(seed: id, label: name),
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
                                          name,
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
                                  const Icon(Icons.chevron_right_rounded, size: 18, color: VedroTheme.fg3),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                      child: Text(
                        _ctrl.text.trim().isEmpty ? '输入片名、原名或演员名即时检索' : '没有找到匹配内容',
                        style: const TextStyle(color: VedroTheme.fg3, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
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
