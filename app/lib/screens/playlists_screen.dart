import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/display_profile.dart';
import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/media_card.dart';
import '../widgets/vedro_ui.dart';
import '../widgets/windows_immersive_frame.dart';

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
    final name = await showVedroDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建片单', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
          decoration: const InputDecoration(hintText: '片单名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消', style: TextStyle(color: VedroSkin.of(ctx).fg2)),
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
      try {
        await widget.appState.core.invoke('create_playlist', {'name': name, 'item_ids': <String>[]});
        await widget.appState.refreshPlaylists();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('新建片单失败：$e')),
          );
        }
      }
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
    final skin = VedroSkin.of(context);
    final list = widget.appState.playlists;
    final wide = MediaQuery.sizeOf(context).width >= 820;

    return Scaffold(
      backgroundColor: skin.canvas,
      body: VedroSkinCanvas(
        child: Padding(
          padding: EdgeInsets.only(top: wide ? widget.topInset : MediaQuery.paddingOf(context).top),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(wide ? 24 : 20, wide ? 20 : 10, wide ? 24 : 16, 14),
                    child: Row(
                      children: [
                        Text(
                          '片单',
                          style: skin.applyHeadlineMood(
                            TextStyle(
                              color: skin.fg,
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.6,
                            ),
                          ),
                        ),
                        const Spacer(),
                        PressableScale(
                          onTap: widget.appState.isSignedIn ? _createDialog : null,
                          child: Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 15),
                            decoration: BoxDecoration(
                              color: skin.primaryCtaBg,
                              gradient: skin.primaryCtaGradient,
                              borderRadius: BorderRadius.circular(skin.radiusForPill(36)),
                              border: skin.primaryCtaBorder,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_rounded, size: 17, color: skin.primaryCtaFg),
                                const SizedBox(width: 4),
                                Text(
                                  '新建片单',
                                  style: TextStyle(
                                    color: skin.primaryCtaFg,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
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
                                Icon(Icons.bookmarks_outlined, size: 36, color: skin.fg3),
                                const SizedBox(height: 10),
                                Text(
                                  widget.appState.isSignedIn ? '暂无片单，点击右上角新建' : '连接服务器后管理片单',
                                  style: TextStyle(color: skin.fg3, fontSize: 13.5),
                                ),
                              ],
                            ),
                          )
                        : ListView(
                            padding: EdgeInsets.fromLTRB(20, 8, 20, wide ? 44 : 108),
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: skin.surface,
                                  borderRadius: BorderRadius.circular(skin.cardRadius.clamp(8.0, 18.0)),
                                  border: skin.cardBorder(),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  children: [
                                    for (var i = 0; i < list.length; i++) ...[
                                      if (i > 0) Divider(height: 1, indent: 16, endIndent: 16, color: skin.border),
                                      PressableScale(
                                        onTap: () => _openPlaylist(list[i]),
                                        hoverScale: 1.0,
                                        pressScale: 0.99,
                                        borderRadius: BorderRadius.circular(skin.cardRadius.clamp(8.0, 16.0)),
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
                                                  color: skin.surface2,
                                                  borderRadius: BorderRadius.circular(9),
                                                ),
                                                child: Icon(
                                                  Icons.bookmark_rounded,
                                                  size: 18,
                                                  color: skin.accent,
                                                ),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      list[i].name,
                                                      style: TextStyle(
                                                        color: skin.fg,
                                                        fontSize: 15,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                    if (list[i].childCount != null ||
                                                        list[i].recursiveItemCount != null)
                                                      Text(
                                                        '${list[i].recursiveItemCount ?? list[i].childCount ?? 0} 部影片',
                                                        style: TextStyle(
                                                          color: skin.fg3,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                  ],
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
  bool _editMode = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
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
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = VedroErrorFormatter.friendly(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeEntry(MediaItemModel item) async {
    final ok = await showVedroDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('移出片单「${item.displayName}」？'),
        content: const Text('仅从此片单移出，不会删除服务器中的影片文件。'),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: VedroTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移出'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final entryId = item.playlistItemId ?? item.id;
    try {
      await widget.appState.core.invoke('remove_from_playlist', {
        'playlist_id': widget.playlist.id,
        'entry_ids': [entryId],
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('移出失败：${VedroErrorFormatter.friendly(e)}')),
        );
      }
    }
  }

  Future<void> _confirmDeletePlaylist() async {
    final ok = await showVedroDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除片单「${widget.playlist.name}」？'),
        content: const Text('仅删除片单本身，不会删除服务器中的影片文件。'),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: VedroTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await widget.appState.deletePlaylist(widget.playlist.id);
        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除片单失败：${VedroErrorFormatter.friendly(e)}')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final profile = DisplayMetricsProfile.of(context);
    final prefs = widget.appState.prefs;
    final wide = !profile.usesMobileChrome;
    final padX = prefs.horizontalMargin(wide);
    final gridGap = prefs.cardGap(wide);
    final isMac = !kIsWeb && Platform.isMacOS;
    final effDensity = prefs
            .overridesForPlatform(isMobile: profile.isMobileOs)['grid_density']
            ?.toString() ??
        prefs.listDensity;

    return Scaffold(
      backgroundColor: skin.canvas,
      body: VedroSkinCanvas(
        child: SafeArea(
          child: Column(
            children: [
              Stack(
                children: [
                  const Positioned.fill(child: WindowsWindowDragArea()),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isMac ? 82 : padX,
                      10,
                      (!kIsWeb && Platform.isWindows) ? 148 : padX,
                      12,
                    ),
                    child: Row(
                  children: [
                    PressableScale(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: skin.surface2,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: skin.border, width: 0.7),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: skin.fg),
                            const SizedBox(width: 5),
                            Text('返回', style: TextStyle(color: skin.fg, fontSize: 13)),
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
                            style: TextStyle(
                              color: skin.fg,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _editMode
                                ? '编辑模式 · 点击卡片即可移出片单'
                                : '共 ${_items.length} 项 · 长按/右键或点击管理可移出',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _editMode ? VedroTheme.danger : skin.fg3,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_items.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: PressableScale(
                          onTap: () => setState(() => _editMode = !_editMode),
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                            decoration: BoxDecoration(
                              color: _editMode
                                  ? VedroTheme.danger.withValues(alpha: 0.16)
                                  : skin.surface2,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: _editMode
                                    ? VedroTheme.danger.withValues(alpha: 0.5)
                                    : skin.border,
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              _editMode ? '完成' : '管理',
                              style: TextStyle(
                                color: _editMode ? VedroTheme.danger : skin.fg,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
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
                ],
              ),
              Expanded(
                child: _loading
                    ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: skin.fg2))
                    : _loadError != null && _items.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('加载片单失败：$_loadError',
                                    style: TextStyle(color: skin.fg2, fontSize: 13.5)),
                                const SizedBox(height: 12),
                                FilledButton(onPressed: _load, child: const Text('重试')),
                              ],
                            ),
                          )
                        : _items.isEmpty
                            ? Center(
                                child: Text('此片单还没有影片，可在任意详情页点击「片单」添加',
                                    style: TextStyle(color: skin.fg3, fontSize: 13.5)),
                              )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final effectiveStyle =
                                (skin.cardStyle == 'hover_reveal' && profile.isTouchPrimary)
                                    ? 'overlay_poster'
                                    : skin.cardStyle;
                            final showBelowCaption = effectiveStyle != 'overlay_poster' &&
                                effectiveStyle != 'hover_reveal' &&
                                effectiveStyle != 'minimal_clean';
                            final gridLayout = PosterCardLayout.forGrid(
                              profile: profile,
                              availableWidth:
                                  (constraints.maxWidth - padX * 2).clamp(140.0, 8000.0),
                              density: effDensity,
                              scale: prefs.posterScale,
                              aspectRatio: skin.mediaAspectRatio,
                              showBelowCaption: showBelowCaption,
                              crossSpacing: gridGap,
                              textScaler: MediaQuery.textScalerOf(context),
                            );
                            return GridView.builder(
                              padding: EdgeInsets.fromLTRB(padX, 6, padX, 40),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: gridLayout.columns,
                                mainAxisSpacing: gridLayout.mainSpacing,
                                crossAxisSpacing: gridLayout.crossSpacing,
                                mainAxisExtent: gridLayout.cardHeight,
                              ),
                              itemCount: _items.length,
                              itemBuilder: (_, idx) {
                                final item = _items[idx];
                                final card = MediaCard(
                                  width: gridLayout.cardWidth,
                                  item: item,
                                  appState: widget.appState,
                                  onTap: _editMode
                                      ? () => _removeEntry(item)
                                      : () => widget.onItemTap(item),
                                  onQuickPlay: _editMode || widget.onQuickPlay == null
                                      ? null
                                      : () => widget.onQuickPlay!(item),
                                  onLongPress: () => _removeEntry(item),
                                );
                                if (!_editMode) return card;
                                return Stack(
                                  children: [
                                    card,
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: IgnorePointer(
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            color: VedroTheme.danger,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.remove_rounded,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
