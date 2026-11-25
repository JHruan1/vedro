import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/media_card.dart';
import '../widgets/vedro_ui.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({
    super.key,
    required this.appState,
    required this.onItemTap,
    this.onQuickPlay,
    this.topInset = 0,
  });

  final VedroAppState appState;
  final void Function(MediaItemModel) onItemTap;
  final void Function(MediaItemModel)? onQuickPlay;
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

  void _openPlaylist(MediaItemModel pl) {
    Navigator.of(context).push(
      vedroRoute(_PlaylistDetailPage(
        playlist: pl,
        appState: widget.appState,
        onItemTap: widget.onItemTap,
        onQuickPlay: widget.onQuickPlay,
      )),
    );
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
            constraints: const BoxConstraints(maxWidth: 760),
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
                          onPressed: widget.appState.isSignedIn ? _createDialog : null,
                          icon: const Icon(Icons.add_rounded, size: 17),
                          label: const Text('新建片单'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: list.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.bookmarks_outlined, size: 36, color: VedroTheme.fg3),
                              const SizedBox(height: 10),
                              Text(
                                widget.appState.isSignedIn ? '暂无片单，点击右上角新建' : '连接服务器后管理片单',
                                style: const TextStyle(color: VedroTheme.fg3, fontSize: 13.5),
                              ),
                            ],
                          ),
                        )
                      : ListView(
                          padding: EdgeInsets.fromLTRB(20, 8, 20, wide ? 44 : 108),
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: VedroTheme.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: VedroTheme.line, width: 0.8),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  for (var i = 0; i < list.length; i++) ...[
                                    if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                                    InkWell(
                                      onTap: () => _openPlaylist(list[i]),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 14,
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 34,
                                              height: 34,
                                              decoration: BoxDecoration(
                                                color: VedroTheme.surface2,
                                                borderRadius: BorderRadius.circular(9),
                                              ),
                                              child: const Icon(
                                                Icons.bookmark_rounded,
                                                size: 18,
                                                color: VedroTheme.fg2,
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    list[i].name,
                                                    style: const TextStyle(
                                                      color: VedroTheme.fg,
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                  if (list[i].childCount != null ||
                                                      list[i].recursiveItemCount != null)
                                                    Text(
                                                      '${list[i].recursiveItemCount ?? list[i].childCount ?? 0} 部影片',
                                                      style: const TextStyle(
                                                        color: VedroTheme.fg3,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
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

class _PlaylistDetailPage extends StatefulWidget {
  const _PlaylistDetailPage({
    required this.playlist,
    required this.appState,
    required this.onItemTap,
    this.onQuickPlay,
  });

  final MediaItemModel playlist;
  final VedroAppState appState;
  final void Function(MediaItemModel) onItemTap;
  final void Function(MediaItemModel)? onQuickPlay;

  @override
  State<_PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<_PlaylistDetailPage> {
  List<MediaItemModel> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await widget.appState.core.invoke('get_playlist_items', {
        'playlist_id': widget.playlist.id,
      }) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _items = ((res['Items'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MediaItemModel.fromJson)
            .toList();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeEntry(MediaItemModel item) async {
    final entryId = item.playlistItemId ?? item.id;
    await widget.appState.core.invoke('remove_from_playlist', {
      'playlist_id': widget.playlist.id,
      'entry_ids': [entryId],
    });
    await _load();
  }

  Future<void> _confirmDeletePlaylist() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除片单「${widget.playlist.name}」？'),
        content: const Text('仅删除片单本身，不会删除服务器中的影片文件。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: VedroTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.appState.deletePlaylist(widget.playlist.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 820;
    final padX = wide ? 36.0 : 20.0;
    final isMac = !kIsWeb && Platform.isMacOS;
    final cardW = widget.appState.prefs.posterCardWidth(wide);
    final cols = ((width - padX * 2) / (cardW + 16)).floor().clamp(3, 9);

    return Scaffold(
      backgroundColor: VedroTheme.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(isMac ? 82 : padX, 10, padX, 12),
              child: Row(
                children: [
                  PressableScale(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: VedroTheme.surface2,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: VedroTheme.line, width: 0.7),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: VedroTheme.fg),
                          SizedBox(width: 5),
                          Text('返回', style: TextStyle(color: VedroTheme.fg, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: VedroTheme.fg,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '共 ${_items.length} 项 · 长按/右键卡片可移出片单',
                          style: const TextStyle(color: VedroTheme.fg3, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '删除片单',
                    icon: const Icon(Icons.delete_outline_rounded, color: VedroTheme.danger),
                    onPressed: _confirmDeletePlaylist,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: VedroTheme.fg2))
                  : _items.isEmpty
                      ? const Center(
                          child: Text('此片单还没有影片，可在任意详情页点击「片单」添加',
                              style: TextStyle(color: VedroTheme.fg3, fontSize: 13.5)),
                        )
                      : GridView.builder(
                          padding: EdgeInsets.fromLTRB(padX, 6, padX, 40),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            mainAxisSpacing: 20,
                            crossAxisSpacing: 16,
                            childAspectRatio: 0.56,
                          ),
                          itemCount: _items.length,
                          itemBuilder: (_, idx) {
                            final item = _items[idx];
                            return MediaCard(
                              item: item,
                              appState: widget.appState,
                              onTap: () => widget.onItemTap(item),
                              onQuickPlay: widget.onQuickPlay == null
                                  ? null
                                  : () => widget.onQuickPlay!(item),
                              onLongPress: () => _removeEntry(item),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
