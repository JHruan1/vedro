import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import 'badge_strip.dart';

class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.item,
    required this.appState,
    required this.onTap,
    this.onLongPress,
    this.width = 152,
    this.landscape = false,
  });

  final MediaItemModel item;
  final VedroAppState appState;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double width;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    final aspect = landscape ? 16 / 9 : 2 / 3;
    final imgUrl = item.primaryImageTag != null
        ? appState.buildImageUrl(
            item.id,
            type: landscape && item.backdropImageTag != null ? 'Backdrop' : 'Primary',
            tag: landscape ? (item.backdropImageTag ?? item.primaryImageTag) : item.primaryImageTag,
            maxWidth: landscape ? 640 : 400,
          )
        : '';
    final badges = item.inferredBadges.take(2).toList();

    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: aspect,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: VedroTheme.surfaceElevated,
                      child: imgUrl.isNotEmpty
                          ? Image.network(
                              imgUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _PlaceholderPoster(title: item.name),
                            )
                          : _PlaceholderPoster(title: item.name),
                    ),
                    // Top-left technical badge (DoVi / Atmos / 4K)
                    if (badges.isNotEmpty)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: BadgeStrip(badges: badges, compact: true),
                      ),
                    // Top-right unwatched count or played checkmark
                    if (item.unplayedItemCount != null && item.unplayedItemCount! > 0)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: VedroTheme.accent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${item.unplayedItemCount}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                      )
                    else if (item.played)
                      const Positioned(
                        top: 6,
                        right: 6,
                        child: CircleAvatar(
                          radius: 11,
                          backgroundColor: VedroTheme.embygoGreen,
                          child: Icon(Icons.check, size: 14, color: Colors.black),
                        ),
                      ),
                    // Bottom resume progress bar
                    if (item.resumeProgress > 0.01)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: item.resumeProgress,
                          minHeight: 4,
                          backgroundColor: Colors.black54,
                          color: VedroTheme.accent,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.seriesName != null && item.type == 'Episode'
                  ? '${item.seriesName} ${item.episodeCode ?? ''}'.trim()
                  : item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            Text(
              item.type == 'Episode'
                  ? item.name
                  : [
                      if (item.productionYear != null) '${item.productionYear}',
                      if (item.communityRating != null) '★ ${item.communityRating!.toStringAsFixed(1)}',
                    ].join(' • '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: VedroTheme.textSecondary, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderPoster extends StatelessWidget {
  const _PlaceholderPoster({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A2236), Color(0xFF0D111C)],
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(10),
      child: Text(
        title,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: VedroTheme.textSecondary, fontWeight: FontWeight.w600),
      ),
    );
  }
}
