import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/prism_theme.dart';
import '../state/app_state.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key, required this.appState, required this.onItemTap});

  final PrismAppState appState;
  final void Function(MediaItemModel) onItemTap;

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  @override
  void initState() {
    super.initState();
    widget.appState.refreshPlaylists();
  }

  Future<void> _createDialog() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建片单'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：杜比视界蓝光原盘收藏'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('创建')),
        ],
      ),
    );
    ctrl.dispose();
    if (name != null && name.isNotEmpty) {
      await widget.appState.core.invoke('create_playlist', {'name': name, 'item_ids': <String>[]});
      await widget.appState.refreshPlaylists();
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.appState.playlists;
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的片单'),
        actions: [
          IconButton(icon: const Icon(Icons.add_rounded), tooltip: '新建片单', onPressed: _createDialog),
        ],
      ),
      body: list.isEmpty
          ? const Center(child: Text('暂无片单，点击右上角 + 创建', style: TextStyle(color: PrismTheme.textSecondary)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              itemBuilder: (_, idx) {
                final pl = list[idx];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: const Icon(Icons.playlist_play_rounded, color: PrismTheme.accent),
                    title: Text(pl.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${pl.childCount ?? 0} 部影片'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => widget.onItemTap(pl),
                  ),
                );
              },
            ),
    );
  }
}

extension on MediaItemModel {
  int? get childCount => unplayedItemCount;
}
