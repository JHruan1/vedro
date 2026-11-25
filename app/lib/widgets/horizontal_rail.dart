import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/prism_theme.dart';
import '../state/app_state.dart';
import 'media_card.dart';

class HorizontalMediaRail extends StatelessWidget {
  const HorizontalMediaRail({
    super.key,
    required this.title,
    required this.items,
    required this.appState,
    required this.onItemTap,
    this.subtitle,
    this.onItemLongPress,
    this.onSeeAll,
    this.landscape = false,
  });

  final String title;
  final String? subtitle;
  final List<MediaItemModel> items;
  final PrismAppState appState;
  final void Function(MediaItemModel) onItemTap;
  final void Function(MediaItemModel)? onItemLongPress;
  final VoidCallback? onSeeAll;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final cardWidth = landscape ? 248.0 : 148.0;
    final railHeight = landscape ? 202.0 : 274.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: const TextStyle(color: PrismTheme.textSecondary, fontSize: 12),
                      ),
                  ],
                ),
              ),
              if (onSeeAll != null)
                TextButton(onPressed: onSeeAll, child: const Text('查看全部')),
            ],
          ),
        ),
        SizedBox(
          height: railHeight,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
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
