import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({
    super.key,
    required this.appState,
    required this.onItemTap,
    this.topInset = 0,
  });

  final VedroAppState appState;
  final void Function(MediaItemModel) onItemTap;
  final double topInset;

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
        title: const Text('新建片单', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '片单名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: VedroTheme.fg2)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('创建'),
          ),
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
    final wide = MediaQuery.sizeOf(context).width >= 820;

    return Scaffold(
      backgroundColor: VedroTheme.canvas,
      appBar: !wide
          ? AppBar(
              title: const Text('片单'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 22, color: VedroTheme.fg),
                  tooltip: '新建片单',
                  onPressed: _createDialog,
                ),
              ],
            )
          : null,
      body: Padding(
        padding: EdgeInsets.only(top: widget.topInset),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                if (wide)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
                    child: Row(
                      children: [
                        const Text(
                          '片单',
                          style: TextStyle(
                            color: VedroTheme.fg,
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: _createDialog,
                          icon: const Icon(Icons.add_rounded, size: 17),
                          label: const Text('新建片单'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: list.isEmpty
                      ? const Center(
                          child: Text('暂无片单', style: TextStyle(color: VedroTheme.fg3, fontSize: 13.5)),
                        )
                      : ListView(
                          padding: EdgeInsets.fromLTRB(20, 8, 20, wide ? 44 : 108),
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: VedroTheme.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: VedroTheme.line, width: 0.7),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  for (var i = 0; i < list.length; i++) ...[
                                    if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                                    InkWell(
                                      onTap: () => widget.onItemTap(list[i]),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 14,
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.bookmark_outline_rounded,
                                              size: 19,
                                              color: VedroTheme.fg2,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                list[i].name,
                                                style: const TextStyle(
                                                  color: VedroTheme.fg,
                                                  fontSize: 14.5,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '${list[i].unplayedItemCount ?? 0}',
                                              style: const TextStyle(color: VedroTheme.fg3, fontSize: 13),
                                            ),
                                            const SizedBox(width: 6),
                                            const Icon(
                                              Icons.chevron_right_rounded,
                                              size: 18,
                                              color: VedroTheme.fg3,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
