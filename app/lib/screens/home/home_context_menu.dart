part of '../home_screen.dart';

/// Universal iOS-caliber Peek & Pop contextual menu for media cards & episodes.
/// When [anchorRect] is provided, the tapped card floats with spring lift above a
/// progressive frosted blur and the action menu springs directly from the card edge.
void showMediaItemContextSheet({
  required BuildContext context,
  required MediaItemModel item,
  required VedroAppState appState,
  required VoidCallback onOpenDetail,
  VoidCallback? onQuickPlay,
  VoidCallback? onPickVersion,
  int versionCount = 1,
  bool allowHideFromResume = false,
  VoidCallback? onMutated,
  Rect? anchorRect,
  bool landscapePreview = false,
  MediaItemModel? previewFallbackItem,
  double? previewCornerRadius,
}) {
  final skin = VedroSkin.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  Future<void> openAddToPlaylistSheet() async {
    try {
      await appState.refreshPlaylists();
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('加载片单失败：${VedroErrorFormatter.friendly(e)}')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    showGlassSheet<void>(
      context: context,
      builder: (ctx) {
        final s = VedroSkin.of(ctx);
        final lists = appState.playlists;
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '加入片单',
                style: TextStyle(color: s.fg, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            if (lists.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('暂无片单，请先在片单页新建', style: TextStyle(color: s.fg3, fontSize: 13)),
              )
            else
              for (var i = 0; i < lists.length; i++)
                ListTile(
                  autofocus: i == 0,
                  leading: Icon(Icons.bookmark_outline_rounded, color: s.fg2),
                  title: Text(lists[i].name, style: TextStyle(color: s.fg, fontSize: 14)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      await appState.core.invoke('add_to_playlist', {
                        'playlist_id': lists[i].id,
                        'item_ids': [item.id],
                      });
                      messenger.showSnackBar(
                        SnackBar(content: Text('已加入片单「${lists[i].name}」')),
                      );
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('加入片单失败：${VedroErrorFormatter.friendly(e)}')),
                      );
                    }
                  },
                ),
          ],
        );
      },
    );
  }

  final actions = <VedroPeekAction>[
    if (onQuickPlay != null && item.isPlayable)
      VedroPeekAction(
        label: item.playbackPositionTicks > 0 ? '继续播放' : '立即播放',
        icon: Icons.play_arrow_rounded,
        isPrimary: true,
        onTap: onQuickPlay,
      ),
    if (item.isPlayable && item.playbackPositionTicks > 0)
      VedroPeekAction(
        label: '从头播放',
        icon: Icons.replay_rounded,
        onTap: () {
          final restartItem = MediaItemModel(
            id: item.id,
            name: item.name,
            type: item.type,
            seriesId: item.seriesId,
            seriesName: item.seriesName,
            parentIndexNumber: item.parentIndexNumber,
            indexNumber: item.indexNumber,
            runTimeTicks: item.runTimeTicks,
            playbackPositionTicks: 0,
            mediaSources: item.mediaSources,
            chapters: item.chapters,
          );
          navigator.push(vedroRoute(PlayerScreen(item: restartItem, appState: appState)));
        },
      ),
    if (onPickVersion != null && versionCount > 1)
      VedroPeekAction(
        label: '切换版本',
        subtitle: '$versionCount',
        icon: Icons.layers_outlined,
        onTap: onPickVersion,
      ),
    VedroPeekAction(
      label: '查看详情',
      icon: Icons.info_outline_rounded,
      onTap: onOpenDetail,
    ),
    if (item.type != 'Person' && item.type != 'Folder') ...[
      VedroPeekAction(
        label: item.played ? '标为未看' : '标为已看',
        icon: item.played ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
        onTap: () {
          unawaited(appState.togglePlayed(item).then((_) {
            onMutated?.call();
            messenger.showSnackBar(
              SnackBar(content: Text(item.played ? '已标为未看' : '已标为已看')),
            );
          }).catchError((Object e) {
            messenger.showSnackBar(
              SnackBar(content: Text('操作失败：${VedroErrorFormatter.friendly(e)}')),
            );
          }));
        },
      ),
      if (item.type != 'Episode')
        VedroPeekAction(
          label: item.isFavorite ? '取消收藏' : '加入收藏',
          icon: item.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          onTap: () {
            unawaited(appState.toggleFavorite(item).then((_) {
              onMutated?.call();
              messenger.showSnackBar(
                SnackBar(content: Text(item.isFavorite ? '已取消收藏' : '已加入收藏')),
              );
            }).catchError((Object e) {
              messenger.showSnackBar(
                SnackBar(content: Text('操作失败：${VedroErrorFormatter.friendly(e)}')),
              );
            }));
          },
        ),
      if (item.type != 'Episode')
        VedroPeekAction(
          label: '加入片单',
          icon: Icons.playlist_add_rounded,
          onTap: () => unawaited(openAddToPlaylistSheet()),
        ),
    ],
    if (allowHideFromResume)
      VedroPeekAction(
        label: '从继续观看移除',
        icon: Icons.visibility_off_outlined,
        isDestructive: true,
        onTap: () {
          unawaited(appState.hideFromResume(item.id).then((_) {
            onMutated?.call();
          }).catchError((Object e) {
            if (context.mounted) {
              messenger.showSnackBar(
                SnackBar(content: Text('移除失败：${VedroErrorFormatter.friendly(e)}')),
              );
            }
          }));
        },
      ),
  ];

  final cardRadius = previewCornerRadius ?? appState.prefs.effectiveCardRadius(skin);
  // Match preview artwork aspect directly to the measured anchor rect so the
  // preview never stretches or crops across orientations.
  final isWide = anchorRect != null
      ? anchorRect.width > anchorRect.height * 1.15
      : (landscapePreview || item.type == 'Episode' || skin.posterAspect == 'landscape_16_9');
  final previewSubtitle = item.type == 'Episode'
      ? [
          if (item.compactEpisodeCode != null) item.compactEpisodeCode!,
          if (fmtDurationTicks(item.runTimeTicks).isNotEmpty) fmtDurationTicks(item.runTimeTicks),
        ].join(' · ')
      : item.cardSubtitle;

  showVedroPeekMenu(
    context: context,
    anchorRect: anchorRect,
    title: item.cardTitle,
    subtitle: previewSubtitle,
    previewCornerRadius: cardRadius,
    previewBuilder: anchorRect == null
        ? null
        : (ctx) => Stack(
              fit: StackFit.expand,
              children: [
                VedroArtwork(
                  item: item,
                  fallbackItem: previewFallbackItem,
                  appState: appState,
                  landscape: isWide,
                  width: isWide ? 640 : 420,
                  displayWidth: anchorRect.width,
                ),
                if (item.resumeProgress > 0.01)
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 8,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: item.resumeProgress.clamp(0.02, 1.0),
                        minHeight: 3,
                        backgroundColor: const Color(0x45FFFFFF),
                        color: skin.accent,
                      ),
                    ),
                  ),
              ],
            ),
    actions: actions,
  );
}
