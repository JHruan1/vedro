import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import 'vedro_artwork.dart';
import 'vedro_ui.dart';

/// SenPlayer / Forward / Apple TV+ style poster or widescreen media card.
/// - Always backed by `GeneratedArt` beneath real artwork (zero ugly gray placeholders).
/// - Quiet monochrome corner badges (watched / unplayed count / favorite / version count).
/// - Desktop hover illuminates hairline ring, deepens shadow, and smoothly reveals Play FAB.
class MediaCard extends StatefulWidget {
  const MediaCard({
    super.key,
    required this.item,
    required this.appState,
    required this.onTap,
    this.onQuickPlay,
    this.onLongPress,
    this.width = 152,
    this.landscape = false,
    this.heroPrefix,
  });

  final MediaItemModel item;
  final VedroAppState appState;
  final VoidCallback onTap;
  final VoidCallback? onQuickPlay;
  final VoidCallback? onLongPress;
  final double width;
  final bool landscape;
  final String? heroPrefix;

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final prefs = widget.appState.prefs;
    final radius = prefs.cardRadius;
    final aspect = widget.landscape ? 16 / 9 : 2 / 3;
    final showPlayFab = widget.onQuickPlay != null && !item.isFolderish && item.type != 'Person';

    Widget artBox = VedroArtwork(
      item: item,
      appState: widget.appState,
      landscape: widget.landscape,
      width: widget.landscape ? 640 : 420,
    );

    if (widget.heroPrefix != null) {
      artBox = Hero(tag: '${widget.heroPrefix}-${item.id}', child: artBox);
    }

    return SizedBox(
      width: widget.width,
      child: PressableScale(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onSecondaryTap: widget.onLongPress,
        onHoverChanged: (v) => setState(() => _hovered = v),
        hoverScale: 1.028,
        pressScale: 0.965,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: aspect,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: VedroTheme.easeOut,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  color: VedroTheme.surface2,
                  boxShadow: [
                    BoxShadow(
                      color: _hovered ? const Color(0x90000000) : const Color(0x52000000),
                      blurRadius: _hovered ? 24 : 12,
                      offset: Offset(0, _hovered ? 10 : 5),
                    ),
                  ],
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: _hovered ? const Color(0x99FFFFFF) : VedroTheme.line,
                    width: _hovered ? 1.5 : 0.8,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    artBox,
                    // Quiet top-right watched / unplayed count badge
                    if (prefs.showWatchedBadge && item.played)
                      const Positioned(
                        top: 7,
                        right: 7,
                        child: _CornerBadge(
                          child: Icon(Icons.check_rounded, size: 12, color: Colors.white),
                        ),
                      )
                    else if (prefs.showUnplayedCount &&
                        item.unplayedItemCount != null &&
                        item.unplayedItemCount! > 0)
                      Positioned(
                        top: 7,
                        right: 7,
                        child: _CornerBadge(
                          child: Text(
                            '${item.unplayedItemCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                    // Quiet top-left favorite / multi-version indicator
                    if (item.isFavorite || item.versionCount > 1)
                      Positioned(
                        top: 7,
                        left: 7,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (item.isFavorite)
                              const _CornerBadge(
                                child: Icon(Icons.favorite_rounded, size: 11, color: Colors.white),
                              ),
                            if (item.isFavorite && item.versionCount > 1) const SizedBox(width: 4),
                            if (item.versionCount > 1)
                              _CornerBadge(
                                child: Text(
                                  '${item.versionCount}×',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    // Progress bar for partially watched items
                    if (item.resumeProgress > 0.01) ...[
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 30,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0xB3000000)],
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
                            minHeight: 3,
                            backgroundColor: const Color(0x45FFFFFF),
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                    // Hover-revealed quick-play circular white FAB (desktop magic!)
                    if (showPlayFab)
                      Positioned(
                        right: 10,
                        bottom: item.resumeProgress > 0.01 ? 16 : 10,
                        child: IgnorePointer(
                          ignoring: !_hovered,
                          child: AnimatedOpacity(
                            opacity: _hovered ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            child: AnimatedScale(
                              scale: _hovered ? 1.0 : 0.85,
                              duration: const Duration(milliseconds: 200),
                              curve: VedroTheme.springCurve,
                              child: GestureDetector(
                                onTap: widget.onQuickPlay,
                                child: Container(
                                  width: 38,
                                  height: 38,
                                  decoration: const BoxDecoration(
                                    color: Color(0xF2FFFFFF),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0x70000000),
                                        blurRadius: 14,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 21,
                                    color: VedroTheme.canvas,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 9),
            Text(
              item.cardTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: VedroTheme.fg,
                fontWeight: FontWeight.w500,
                fontSize: 13.5,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.cardSubtitle.isNotEmpty ? item.cardSubtitle : ' ',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: VedroTheme.fg3,
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dedicated 16:9 Continue Watching card with remaining time, progress strip,
/// and tactile white "继续" pill button (works identically great on touch & desktop).
class ResumeCard extends StatefulWidget {
  const ResumeCard({
    super.key,
    required this.item,
    required this.appState,
    required this.onTap,
    required this.onResumePlay,
    this.onLongPress,
    this.width = 296,
  });

  final MediaItemModel item;
  final VedroAppState appState;
  final VoidCallback onTap;
  final VoidCallback onResumePlay;
  final VoidCallback? onLongPress;
  final double width;

  @override
  State<ResumeCard> createState() => _ResumeCardState();
}

class _ResumeCardState extends State<ResumeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final left = item.remainingText;
    final sub = item.type == 'Episode'
        ? item.cardSubtitle
        : [
            if (item.productionYear != null) '${item.productionYear}',
            if (fmtDurationTicks(item.runTimeTicks).isNotEmpty)
              fmtDurationTicks(item.runTimeTicks),
          ].join(' · ');

    return SizedBox(
      width: widget.width,
      child: PressableScale(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onSecondaryTap: widget.onLongPress,
        onHoverChanged: (v) => setState(() => _hovered = v),
        hoverScale: 1.02,
        pressScale: 0.97,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: VedroTheme.easeOut,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: VedroTheme.surface2,
                  boxShadow: [
                    BoxShadow(
                      color: _hovered ? const Color(0x90000000) : const Color(0x52000000),
                      blurRadius: _hovered ? 24 : 12,
                      offset: Offset(0, _hovered ? 10 : 5),
                    ),
                  ],
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _hovered ? const Color(0x99FFFFFF) : VedroTheme.line,
                    width: _hovered ? 1.5 : 0.8,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    VedroArtwork(
                      item: item,
                      appState: widget.appState,
                      landscape: true,
                      width: 680,
                    ),
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 76,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xCC000000)],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 16,
                      child: PressableScale(
                        onTap: widget.onResumePlay,
                        hoverScale: 1.05,
                        pressScale: 0.93,
                        child: Container(
                          height: 30,
                          padding: const EdgeInsets.only(left: 9, right: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xEBFFFFFF),
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: const [
                              BoxShadow(color: Color(0x45000000), blurRadius: 8, offset: Offset(0, 2)),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.play_arrow_rounded, size: 16, color: VedroTheme.canvas),
                              const SizedBox(width: 3),
                              Text(
                                item.playbackPositionTicks > 0 ? '继续' : '播放',
                                style: const TextStyle(
                                  color: VedroTheme.canvas,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (left.isNotEmpty)
                      Positioned(
                        right: 12,
                        bottom: 20,
                        child: Text(
                          left,
                          style: const TextStyle(
                            color: Color(0xDCFFFFFF),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 8,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: item.resumeProgress.clamp(0.02, 1.0),
                          minHeight: 3,
                          backgroundColor: const Color(0x40FFFFFF),
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 9),
            Text(
              item.cardTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: VedroTheme.fg,
                fontWeight: FontWeight.w500,
                fontSize: 13.5,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub.isNotEmpty ? sub : ' ',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: VedroTheme.fg3,
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 16:9 Library tile prioritizing the server's own library cover (`Primary`/`Backdrop`/`Thumb`),
/// gracefully falling back to a recent item's widescreen backdrop only when the library has none.
class LibraryCard extends StatefulWidget {
  const LibraryCard({
    super.key,
    required this.library,
    this.coverItem,
    required this.appState,
    required this.onTap,
    this.width = 276,
  });

  final MediaItemModel library;
  final MediaItemModel? coverItem;
  final VedroAppState appState;
  final VoidCallback onTap;
  final double width;

  @override
  State<LibraryCard> createState() => _LibraryCardState();
}

class _LibraryCardState extends State<LibraryCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final serverCover = widget.appState.libraryCoverUrl(widget.library, width: 720);
    final hasServerCover = serverCover != null && serverCover.isNotEmpty;

    return SizedBox(
      width: widget.width,
      child: PressableScale(
        onTap: widget.onTap,
        onHoverChanged: (v) => setState(() => _hovered = v),
        hoverScale: 1.022,
        pressScale: 0.97,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: VedroTheme.easeOut,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: VedroTheme.surface2,
                  boxShadow: [
                    BoxShadow(
                      color: _hovered ? const Color(0x90000000) : const Color(0x52000000),
                      blurRadius: _hovered ? 24 : 12,
                      offset: Offset(0, _hovered ? 10 : 5),
                    ),
                  ],
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _hovered ? const Color(0x99FFFFFF) : VedroTheme.line,
                    width: _hovered ? 1.5 : 0.8,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Fallback layer beneath server cover (shows if server cover is absent or fails)
                    if (widget.coverItem != null)
                      VedroArtwork(
                        item: widget.coverItem!,
                        appState: widget.appState,
                        landscape: true,
                        width: 720,
                        showInitials: false,
                      )
                    else
                      GeneratedArt(
                        seed: widget.library.id,
                        label: hasServerCover ? null : widget.library.name,
                      ),
                    // Authoritative server-generated / custom library cover on top!
                    if (hasServerCover)
                      FadeNetworkImage(
                        url: serverCover,
                        fit: BoxFit.cover,
                      ),
                    // Subtle bottom-edge gradient only when no server cover (server covers often include titles/art)
                    if (!hasServerCover)
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [0.35, 1.0],
                            colors: [
                              Colors.transparent,
                              Color(0xB8000000),
                            ],
                          ),
                        ),
                      ),
                    if (!hasServerCover)
                      Positioned(
                        left: 14,
                        right: 14,
                        bottom: 12,
                        child: Text(
                          widget.library.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.library.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VedroTheme.fg,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                AnimatedOpacity(
                  opacity: _hovered ? 1.0 : 0.45,
                  duration: const Duration(milliseconds: 160),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: VedroTheme.fg2,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CornerBadge extends StatelessWidget {
  const _CornerBadge({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 5.5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xA80B0B0D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x24FFFFFF), width: 0.5),
      ),
      child: child,
    );
  }
}
