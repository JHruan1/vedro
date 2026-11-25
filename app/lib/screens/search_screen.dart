import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/vedro_artwork.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.appState, required this.onItemTap});

  final VedroAppState appState;
  final void Function(MediaItemModel) onItemTap;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
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
      setState(() => _hints = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 220), () => _runSearch(val.trim()));
  }

  Future<void> _runSearch(String term) async {
    setState(() => _searching = true);
    try {
      final res = await widget.appState.core.invoke('search_hints', {
        'term': term,
        'limit': 40,
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
    final wide = MediaQuery.sizeOf(context).width >= 820;

    return Scaffold(
      backgroundColor: VedroTheme.canvas,
      appBar: AppBar(title: const Text('搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: TextField(
              controller: _ctrl,
              onChanged: _onChanged,
              style: const TextStyle(color: VedroTheme.fg, fontSize: 14),
              decoration: InputDecoration(
                hintText: '片名、原名或演职员',
                prefixIcon: const Icon(Icons.search_rounded, size: 19, color: VedroTheme.fg3),
                suffixIcon: _ctrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 17, color: VedroTheme.fg3),
                        onPressed: () {
                          _ctrl.clear();
                          setState(() => _hints = []);
                        },
                      )
                    : null,
              ),
            ),
          ),
          if (_searching)
            const LinearProgressIndicator(
              minHeight: 1.5,
              backgroundColor: Colors.transparent,
              color: VedroTheme.fg2,
            ),
          Expanded(
            child: _hints.isEmpty
                ? const Center(
                    child: Text(
                      '输入关键字搜索媒体库',
                      style: TextStyle(color: VedroTheme.fg3, fontSize: 13.5),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, wide ? 36 : 108),
                    itemCount: _hints.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
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
                        type,
                      ].join(' · ');

                      return InkWell(
                        onTap: () => widget.onItemTap(MediaItemModel(
                          id: id,
                          name: name,
                          type: type,
                          primaryImageTag: imgTag,
                        )),
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
          ),
        ],
      ),
    );
  }
}
