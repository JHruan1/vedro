import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import 'vedro_ui.dart';

/// Clean, Apple TV+ / Infuse style poster or widescreen episode card.
/// Zero neon badges covering artwork — pure photography, subtle hairline frame,
/// tactile spring hover/press scale, and restrained typography underneath.
class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.item,
    required this.appState,
    required this.onTap,
    this.onLongPress,
    this.width = 148,
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
    final imgUrl = item.primaryImageTag != null || item.backdropImageTag != null
        ? appState.buildImageUrl(
            item.id,
            type: landscape && item.backdropImageTag != null ? 'Backdrop' : 'Primary',
            tag: landscape ? (item.backdropImageTag ?? item.primaryImageTag) : item.primaryImageTag,
            maxWidth: landscape ? 640 : 400,
          )
        : '';

    final titleText = item.seriesName != null && item.type == 'Episode'
        ? item.seriesName!
        : item.name;
    final subtitleText = item.type == 'Episode'
        ? [if (item.episodeCode != null) item.episodeCode!, item.name].join(' · ')
        : [
            if (item.productionYear != null) '${item.productionYear}',
            if (item.communityRating != null) item.communityRating!.toStringAsFixed(1),
          ].join(' · ');

    return SizedBox(
      width: width,
      child: PressableScale(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: aspect,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: VedroTheme.surface,
                  border: Border.all(color: VedroTheme.line, width: 0.6),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x52000000),
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imgUrl.isNotEmpty)
                      Image.network(
                        imgUrl,
                        fit: BoxFit.cover,
                        frameBuilder: (_, child, frame, sync) {
                          if (sync) return child;
                          return AnimatedOpacity(
                            opacity: frame == null ? 0 : 1,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            child: child,
                          );
                        },
                        errorBuilder: (_, __, ___) => _PlaceholderPoster(title: item.name),
                      )
                    else
                      _PlaceholderPoster(title: item.name),
                    // Subtle unwatched count pill for TV series (Apple monochrome glass)
                    if (item.unplayedItemCount != null && item.unplayedItemCount! > 0)
                      Positioned(
                        top: 7,
                        right: 7,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xB80B0B0D),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: VedroTheme.lineStrong, width: 0.5),
                          ),
                          child: Text(
                            '${item.unplayedItemCount}',
                            style: const TextStyle(
                              color: VedroTheme.fg,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                    // Ultra-thin crisp white progress line ONLY for in-progress items
                    if (item.resumeProgress > 0.01) ...[
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 28,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0xAA000000)],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: item.resumeProgress,
                            minHeight: 2.5,
                            backgroundColor: const Color(0x45FFFFFF),
                            color: VedroTheme.fg,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              titleText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: VedroTheme.fg,
                fontWeight: FontWeight.w500,
                fontSize: 13.5,
                letterSpacing: -0.1,
              ),
            ),
            if (subtitleText.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subtitleText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: VedroTheme.fg3,
                  fontSize: 12,
                ),
              ),
            ],
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
      color: VedroTheme.surface2,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Text(
        title,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: VedroTheme.fg3,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
