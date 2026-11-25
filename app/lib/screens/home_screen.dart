import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/prism_theme.dart';
import '../state/app_state.dart';
import '../widgets/badge_strip.dart';
import '../widgets/horizontal_rail.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.appState,
    required this.onItemTap,
    required this.onLibraryTap,
  });

  final PrismAppState appState;
  final void Function(MediaItemModel) onItemTap;
  final void Function(MediaItemModel) onLibraryTap;

  @override
  Widget build(BuildContext context) {
    final heroItems = appState.popular.isNotEmpty
        ? appState.popular
        : (appState.latestByLibrary.isNotEmpty
            ? ((appState.latestByLibrary.first['items'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(MediaItemModel.fromJson)
                .toList())
            : const <MediaItemModel>[]);

    final caps = appState.capabilities;

    return RefreshIndicator(
      onRefresh: appState.refreshHome,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: Row(
              children: [
                Text(
                  caps?.serverName.isNotEmpty == true ? caps!.serverName : 'Prism Player',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 10),
                if (caps != null)
                  BadgeStrip(
                    compact: true,
                    badges: [
                      if (caps.isEmbyGo) 'embygo DirectPlay' else caps.dialect.toUpperCase(),
                      if (caps.usesStreamTickets) 'StreamTicket',
                    ],
                  ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: '刷新首页',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: appState.refreshHome,
              ),
            ],
          ),
          if (appState.remoteBannerMessage != null)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: PrismTheme.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cast_connected_rounded, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(appState.remoteBannerMessage!)),
                  ],
                ),
              ),
            ),
          if (heroItems.isNotEmpty)
            SliverToBoxAdapter(
              child: _HeroSpotlight(
                item: heroItems.first,
                appState: appState,
                isPopular: appState.popular.isNotEmpty,
                onTap: () => onItemTap(heroItems.first),
              ),
            ),
          // Library shortcuts
          if (appState.views.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: appState.views
                      .map((lib) => ActionChip(
                            avatar: Icon(
                              lib.collectionType == 'tvshows'
                                  ? Icons.live_tv_rounded
                                  : Icons.movie_creation_rounded,
                              size: 16,
                              color: PrismTheme.accent,
                            ),
                            label: Text(lib.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            onPressed: () => onLibraryTap(lib),
                          ))
                      .toList(),
                ),
              ),
            ),
          // Continue Watching (supports embygo HideFromResume on long press)
          SliverToBoxAdapter(
            child: HorizontalMediaRail(
              title: '继续观看',
              subtitle: caps?.supportsHideFromResume == true ? '长按可从继续观看移除（保留播放进度）' : null,
              items: appState.resume,
              appState: appState,
              landscape: true,
              onItemTap: onItemTap,
              onItemLongPress: caps?.supportsHideFromResume == true
                  ? (item) => _confirmHideFromResume(context, item)
                  : null,
            ),
          ),
          SliverToBoxAdapter(
            child: HorizontalMediaRail(
              title: '下一集',
              items: appState.nextUp,
              appState: appState,
              landscape: true,
              onItemTap: onItemTap,
            ),
          ),
          if (appState.popular.length > 1)
            SliverToBoxAdapter(
              child: HorizontalMediaRail(
                title: '全站热播',
                subtitle: 'embygo 近 30 天观看排行',
                items: appState.popular,
                appState: appState,
                onItemTap: onItemTap,
              ),
            ),
          SliverToBoxAdapter(
            child: HorizontalMediaRail(
              title: '猜你喜欢',
              items: appState.suggestions,
              appState: appState,
              onItemTap: onItemTap,
            ),
          ),
          // Recently added per library
          ...appState.latestByLibrary.map((entry) {
            final lib = MediaItemModel.fromJson(entry['library'] as Map<String, dynamic>);
            final items = ((entry['items'] as List<dynamic>?) ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(MediaItemModel.fromJson)
                .toList();
            return SliverToBoxAdapter(
              child: HorizontalMediaRail(
                title: '最近添加 · ${lib.name}',
                items: items,
                appState: appState,
                onItemTap: onItemTap,
                onSeeAll: () => onLibraryTap(lib),
              ),
            );
          }),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  void _confirmHideFromResume(BuildContext context, MediaItemModel item) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.visibility_off_rounded),
          title: Text('从「继续观看」移除 ${item.name}'),
          subtitle: const Text('不会清除已保存的播放位置和观看次数'),
          onTap: () {
            Navigator.pop(ctx);
            appState.hideFromResume(item.id);
          },
        ),
      ),
    );
  }
}

class _HeroSpotlight extends StatelessWidget {
  const _HeroSpotlight({
    required this.item,
    required this.appState,
    required this.isPopular,
    required this.onTap,
  });

  final MediaItemModel item;
  final PrismAppState appState;
  final bool isPopular;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bgUrl = item.backdropImageTag != null
        ? appState.buildImageUrl(item.id, type: 'Backdrop', tag: item.backdropImageTag, maxWidth: 1600)
        : (item.primaryImageTag != null
            ? appState.buildImageUrl(item.id, type: 'Primary', tag: item.primaryImageTag, maxWidth: 1200)
            : '');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          height: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: PrismTheme.surfaceElevated,
            border: Border.all(color: PrismTheme.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (bgUrl.isNotEmpty)
                Image.network(
                  bgUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x2207090F), Color(0xEA07090F)],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    BadgeStrip(
                      badges: [
                        if (isPopular) '热门精选',
                        ...item.inferredBadges.take(3),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                    ),
                    if (item.overview != null && item.overview!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.overview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: PrismTheme.textSecondary, fontSize: 13.5),
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: onTap,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('立即播放'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
