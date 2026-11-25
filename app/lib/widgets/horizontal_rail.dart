import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import 'media_card.dart';

class HorizontalMediaRail extends StatelessWidget {
  const HorizontalMediaRail({
    super.key,
    required this.title,
    required this.items,
    required this.appState,
    required this.onItemTap,
    this.onItemLongPress,
    this.onSeeAll,
    this.landscape = false,
  });

  final String title;
  final List<MediaItemModel> items;
  final VedroAppState appState;
  final void Function(MediaItemModel) onItemTap;
  final void Function(MediaItemModel)? onItemLongPress;
  final VoidCallback? onSeeAll;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final cardWidth = landscape ? 256.0 : 146.0;
    final railHeight = landscape ? 202.0 : 272.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: VedroTheme.fg,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (onSeeAll != null)
                GestureDetector(
                  onTap: onSeeAll,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('全部', style: TextStyle(color: VedroTheme.fg2, fontSize: 13)),
                      SizedBox(width: 2),
                      Icon(Icons.chevron_right_rounded, size: 16, color: VedroTheme.fg3),
                    ],
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: railHeight,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, idx) {
              final item = items[idx];
              return MediaCard(
                item: item,
                appState: appState,
                width: cardWidth,
                landscape: landscape,
                onTap: () => onItemTap(item),
                onLongPress: onItemLongPress == null ? null : () => onItemLongPress!(item),
              );
            },
          ),
        ),
      ],
    );
  }
}
