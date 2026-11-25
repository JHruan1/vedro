import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/prism_theme.dart';
import '../state/app_state.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.appState, required this.onItemTap});

  final PrismAppState appState;
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
    _debounce = Timer(const Duration(milliseconds: 280), () => _runSearch(val.trim()));
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
    return Scaffold(
      appBar: AppBar(title: const Text('全局搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: TextField(
              controller: _ctrl,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                hintText: '搜索电影、剧集、演员...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          if (_searching) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _hints.isEmpty
                ? const Center(
                    child: Text('输入片名、原名或演员名即时检索', style: TextStyle(color: PrismTheme.textSecondary)),
                  )
                : ListView.builder(
                    itemCount: _hints.length,
                    itemBuilder: (_, idx) {
                      final h = _hints[idx];
                      final id = (h['ItemId'] ?? h['Id'] ?? '').toString();
                      final name = (h['Name'] ?? '').toString();
                      final type = (h['Type'] ?? 'Movie').toString();
                      return ListTile(
                        leading: Icon(type == 'Person' ? Icons.person_rounded : Icons.movie_rounded),
                        title: Text(name),
                        subtitle: Text([
                          type,
                          if (h['ProductionYear'] != null) '${h['ProductionYear']}',
                          if (h['Series'] != null) '${h['Series']}',
                        ].join(' • ')),
                        onTap: () {
                          if (type == 'Person') return;
                          widget.onItemTap(MediaItemModel(id: id, name: name, type: type));
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
