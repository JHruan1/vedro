import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/platform/platform_perf.dart';
import '../core/theme/display_profile.dart';
import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import 'vedro_artwork.dart';
import 'vedro_ui.dart';

/// Skin-adaptive poster or widescreen media card:
/// - Always backed by `GeneratedArt` beneath real artwork.
/// - Adapts corner geometry, border frame (`borderless` / `hairline` / `neon`),
///   shadows, typography mood, and hover Play FAB to the active `VedroSkin`.
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
    final skin = VedroSkin.of(context);
    final item = widget.item;
    final prefs = widget.appState.prefs;
    final radius = prefs.effectiveCardRadius(skin);
    final aspect = widget.landscape ? (16 / 9) : skin.mediaAspectRatio;
    final showPlayFab = widget.onQuickPlay != null && !item.isFolderish && item.type != 'Person';

    Widget artBox = VedroArtwork(
      item: item,
      appState: widget.appState,
      landscape: widget.landscape || skin.posterAspect == 'landscape_16_9',
      width: (widget.landscape || skin.posterAspect == 'landscape_16_9') ? 640 : 420,
    );

    final touchPrimary = DisplayMetricsProfile.of(context).isTouchPrimary;
    if (widget.heroPrefix != null) {
      artBox = Hero(tag: '${widget.heroPrefix}-${item.id}', child: artBox);
    }
    if (!touchPrimary && skin.cardHoverEffect == 'zoom_art') {
      artBox = AnimatedScale(
        scale: _hovered ? 1.065 : 1.0,
        duration: const Duration(milliseconds: 220),
        curve: VedroTheme.easeOut,
        child: artBox,
      );
    }

    final effectiveStyle =
        (skin.cardStyle == 'hover_reveal' && touchPrimary) ? 'overlay_poster' : skin.cardStyle;
    final isOverlayCard = effectiveStyle == 'overlay_poster';
    final isHoverReveal = effectiveStyle == 'hover_reveal';
    final isMinimalClean = effectiveStyle == 'minimal_clean';
    final showBelowCaption = !isOverlayCard && !isHoverReveal && !isMinimalClean;
    final hideBadges = skin.badgeStyle == 'hidden';
    final showRatingBadge =
        !hideBadges && prefs.showRatings && skin.showCardRating && (item.communityRating ?? 0) > 0;
    final showVersionBadge =
        !hideBadges && prefs.showMultiVersionBadge && item.versionCount > 1;
    final subtitleText = item.cardSubtitleFor(
      showYear: prefs.showYear,
      showRatingInText: prefs.showRatings && !showRatingBadge,
    );
    final pressScale = skin.touchFeedbackStyle == 'clean_static'
        ? 1.0
        : (skin.touchFeedbackStyle == 'subtle_scale' ? 0.988 : 0.965);
    final profile = DisplayMetricsProfile.of(context);
    final textScaler = MediaQuery.textScalerOf(context);

    return RepaintBoundary(
      child: SizedBox(
        width: widget.width,
        child: LayoutBuilder(
        builder: (context, constraints) {
          final actualW = constraints.hasBoundedWidth && constraints.maxWidth > 0
              ? constraints.maxWidth
              : widget.width;
          final metrics = PosterCardLayout.forCardWidth(
            cardWidth: actualW,
            aspectRatio: aspect,
            showBelowCaption: showBelowCaption,
            textScaler: textScaler,
            devicePixelRatio: profile.devicePixelRatio,
          );
          final cardDecoration = BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: skin.surface2,
            boxShadow: skin.posterShadow(hovered: !touchPrimary && _hovered),
          );
          final cardForeground = BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: skin.cardBorder(hovered: !touchPrimary && _hovered),
          );
          return PressableScale(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onSecondaryTap: widget.onLongPress,
            onHoverChanged: touchPrimary ? null : (v) => setState(() => _hovered = v),
            hoverScale: touchPrimary || skin.cardHoverEffect == 'zoom_art' ? 1.0 : 1.02,
            pressScale: pressScale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: aspect,
                  child: touchPrimary
                      ? Container(
                          decoration: cardDecoration,
                          foregroundDecoration: cardForeground,
                          clipBehavior: Clip.antiAlias,
                          child: _buildPosterStack(
                            skin: skin,
                            item: item,
                            prefs: prefs,
                            artBox: artBox,
                            isOverlayCard: isOverlayCard,
                            isHoverReveal: isHoverReveal,
                            showPlayFab: false,
                            hideBadges: hideBadges,
                            showRatingBadge: showRatingBadge,
                            showVersionBadge: showVersionBadge,
                            subtitleText: subtitleText,
                            metrics: metrics,
                          ),
                        )
                      : AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: VedroTheme.easeOut,
                          decoration: cardDecoration,
                          foregroundDecoration: cardForeground,
                          clipBehavior: Clip.antiAlias,
                          child: _buildPosterStack(
                            skin: skin,
                            item: item,
                            prefs: prefs,
                            artBox: artBox,
                            isOverlayCard: isOverlayCard,
                            isHoverReveal: isHoverReveal,
                            showPlayFab: showPlayFab,
                            hideBadges: hideBadges,
                            showRatingBadge: showRatingBadge,
                            showVersionBadge: showVersionBadge,
                            subtitleText: subtitleText,
                            metrics: metrics,
                          ),
                        ),
                ),
                if (showBelowCaption) ...[
                  SizedBox(height: metrics.captionTopGap),
                  Text(
                    item.cardTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    strutStyle: StrutStyle(
                      fontSize: metrics.titleFontSize,
                      height: PosterCardLayout.kStrutHeight,
                      forceStrutHeight: true,
                    ),
                    style: TextStyle(
                      color: skin.fg,
                      fontWeight: FontWeight.w500,
                      fontSize: metrics.titleFontSize,
                      height: PosterCardLayout.kStrutHeight,
                      letterSpacing: -0.1,
                    ),
                  ),
                  SizedBox(height: metrics.captionMidGap),
                  Text(
                    subtitleText.isNotEmpty ? subtitleText : ' ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    strutStyle: StrutStyle(
                      fontSize: metrics.metaFontSize,
                      height: PosterCardLayout.kStrutHeight,
                      forceStrutHeight: true,
                    ),
                    style: TextStyle(
                      color: skin.fg3,
                      fontSize: metrics.metaFontSize,
                      height: PosterCardLayout.kStrutHeight,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
      ),
    );
  }

  Widget _buildPosterStack({
    required VedroSkin skin,
    required MediaItemModel item,
    required dynamic prefs,
    required Widget artBox,
    required bool isOverlayCard,
    required bool isHoverReveal,
    required bool showPlayFab,
    required bool hideBadges,
    required bool showRatingBadge,
    required bool showVersionBadge,
    required String subtitleText,
    required PosterCardLayout metrics,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        artBox,
        if (isOverlayCard || isHoverReveal)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: isOverlayCard ? 1.0 : (_hovered ? 1.0 : 0.0),
                duration: const Duration(milliseconds: 190),
                curve: Curves.easeOut,
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    10,
                    28,
                    showPlayFab && _hovered ? 48 : 10,
                    item.resumeProgress > 0.01 ? 14 : 9,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.0, 0.45, 1.0],
                      colors: [
                        Colors.transparent,
                        Color(0x9005060A),
                        Color(0xEB05060A),
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.cardTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: metrics.titleFontSize,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                        ),
                      ),
                      if (subtitleText.isNotEmpty) ...[
                        const SizedBox(height: 1.5),
                        Text(
                          subtitleText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: const Color(0xBDFFFFFF),
                            fontSize: metrics.metaFontSize,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (!hideBadges && prefs.showWatchedBadge && item.played)
          Positioned(
            top: skin.badgeStyle == 'accent_ribbon' ? 0 : 6,
            right: skin.badgeStyle == 'accent_ribbon' ? 0 : 6,
            child: skin.badgeStyle == 'minimal_dot'
                ? Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: skin.accent,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(color: Color(0x88000000), blurRadius: 4),
                      ],
                    ),
                  )
                : _CornerBadge(
                    accentRibbon: skin.badgeStyle == 'accent_ribbon',
                    accentColor: skin.accent,
                    child: Icon(
                      Icons.check_rounded,
                      size: 11.5,
                      color: skin.badgeStyle == 'accent_ribbon'
                          ? highContrastOn(skin.accent)
                          : Colors.white,
                    ),
                  ),
          )
        else if (!hideBadges &&
            prefs.showUnplayedCount &&
            item.unplayedItemCount != null &&
            item.unplayedItemCount! > 0)
          Positioned(
            top: skin.badgeStyle == 'accent_ribbon' ? 0 : 6,
            right: skin.badgeStyle == 'accent_ribbon' ? 0 : 6,
            child: skin.badgeStyle == 'minimal_dot'
                ? Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: skin.accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: skin.accent.withValues(alpha: 0.6),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  )
                : _CornerBadge(
                    accentRibbon: skin.badgeStyle == 'accent_ribbon',
                    accentColor: skin.accent,
                    child: Text(
                      '${item.unplayedItemCount}',
                      style: TextStyle(
                        color: skin.badgeStyle == 'accent_ribbon'
                            ? highContrastOn(skin.accent)
                            : Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
          ),
        if (!hideBadges && (item.isFavorite || showVersionBadge || showRatingBadge))
          Positioned(
            top: 6,
            left: 6,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showRatingBadge) ...[
                  _CornerBadge(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          size: 10.5,
                          color: Color(0xFFFBBF24),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          item.communityRating!.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (item.isFavorite || showVersionBadge) const SizedBox(width: 4),
                ],
                if (item.isFavorite)
                  const _CornerBadge(
                    child: Icon(Icons.favorite_rounded, size: 11, color: Colors.white),
                  ),
                if (item.isFavorite && showVersionBadge) const SizedBox(width: 4),
                if (showVersionBadge)
                  _CornerBadge(
                    child: Text(
                      '${item.versionCount}×',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (item.resumeProgress > 0.01) ...[
          if (skin.progressStyle != 'edge_flush')
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
            left: skin.progressStyle == 'edge_flush' ? 0 : 8,
            right: skin.progressStyle == 'edge_flush' ? 0 : 8,
            bottom: skin.progressStyle == 'edge_flush' ? 0 : 8,
            child: Container(
              decoration: skin.progressStyle == 'glow_accent'
                  ? BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: skin.accent.withValues(alpha: 0.75),
                          blurRadius: 8,
                        ),
                      ],
                    )
                  : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  skin.progressStyle == 'edge_flush' ? 0 : 2.5,
                ),
                child: LinearProgressIndicator(
                  value: item.resumeProgress,
                  minHeight: skin.progressStyle == 'edge_flush' ? 3.5 : 3,
                  backgroundColor: const Color(0x45FFFFFF),
                  color: (skin.ctaStyle == 'contrast' &&
                          skin.progressStyle != 'glow_accent')
                      ? Colors.white
                      : skin.accent,
                ),
              ),
            ),
          ),
        ],
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
                      decoration: BoxDecoration(
                        color: skin.primaryCtaBg,
                        gradient: skin.primaryCtaGradient,
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x70000000),
                            blurRadius: 14,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        size: 21,
                        color: skin.primaryCtaFg,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Dedicated 16:9 Continue Watching card.
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
    final skin = VedroSkin.of(context);
    final radius = widget.appState.prefs.effectiveCardRadius(skin);
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
        hoverScale: 1.014,
        pressScale: 0.98,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: VedroTheme.easeOut,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  color: skin.surface2,
                  boxShadow: skin.posterShadow(hovered: _hovered),
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: skin.cardBorder(hovered: _hovered),
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
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 44,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: skin.isLight && widget.appState.backdropArt(item) == null
                                ? [Colors.transparent, Colors.white.withValues(alpha: 0.72)]
                                : const [Colors.transparent, Color(0xBD000000)],
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: PressableScale(
                        onTap: widget.onResumePlay,
                        hoverScale: 1.1,
                        pressScale: 0.9,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: skin.isLight && widget.appState.backdropArt(item) == null
                                ? Colors.white.withValues(alpha: _hovered ? 0.96 : 0.86)
                                : (_hovered ? const Color(0x66000000) : const Color(0x42000000)),
                            border: Border.all(
                              color: skin.isLight && widget.appState.backdropArt(item) == null
                                  ? skin.accent.withValues(alpha: 0.35)
                                  : (_hovered ? Colors.white : const Color(0xD9FFFFFF)),
                              width: 2.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: skin.isLight ? 0.12 : 0.34),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            size: 26,
                            color: skin.isLight && widget.appState.backdropArt(item) == null
                                ? skin.accent
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 8,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: item.resumeProgress.clamp(0.02, 1.0),
                          minHeight: 3.5,
                          backgroundColor: skin.isLight && widget.appState.backdropArt(item) == null
                              ? Colors.black.withValues(alpha: 0.12)
                              : const Color(0x45FFFFFF),
                          color: skin.ctaStyle == 'contrast' ? Colors.white : skin.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: widget.width < 128 ? 6 : 8),
            Text(
              item.cardTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              strutStyle: StrutStyle(
                fontSize: widget.width < 128 ? 12.5 : 13.5,
                height: PosterCardLayout.kStrutHeight,
                forceStrutHeight: true,
              ),
              style: TextStyle(
                color: skin.fg,
                fontWeight: FontWeight.w500,
                fontSize: widget.width < 128 ? 12.5 : 13.5,
                height: PosterCardLayout.kStrutHeight,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              left.isNotEmpty
                  ? (item.type == 'Episode' && item.episodeCode != null
                      ? '${item.episodeCode} · $left'
                      : left)
                  : (sub.isNotEmpty ? sub : ' '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              strutStyle: StrutStyle(
                fontSize: widget.width < 128 ? 11.0 : 12.0,
                height: PosterCardLayout.kStrutHeight,
                forceStrutHeight: true,
              ),
              style: TextStyle(
                color: skin.fg3,
                fontSize: widget.width < 128 ? 11.0 : 12.0,
                height: PosterCardLayout.kStrutHeight,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 16:9 Library tile prioritizing the server's own library cover.
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
    final skin = VedroSkin.of(context);
    final radius = widget.appState.prefs.effectiveCardRadius(skin);
    final serverCover = widget.appState.libraryCoverUrl(widget.library, width: 720);
    final hasServerCover = serverCover != null && serverCover.isNotEmpty;

    return SizedBox(
      width: widget.width,
      child: PressableScale(
        onTap: widget.onTap,
        onHoverChanged: (v) => setState(() => _hovered = v),
        hoverScale: 1.014,
        pressScale: 0.98,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: VedroTheme.easeOut,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  color: skin.surface2,
                  boxShadow: skin.posterShadow(hovered: _hovered),
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: skin.cardBorder(hovered: _hovered),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (!hasServerCover && widget.coverItem != null)
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
                    if (hasServerCover)
                      FadeNetworkImage(
                        url: serverCover,
                        fit: BoxFit.cover,
                        cacheWidth: PlatformPerfProfile.imageCacheWidthFor(
                          widget.width,
                          MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0,
                        ),
                      ),
                    if (!hasServerCover)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.35, 1.0],
                            colors: skin.isLight && widget.coverItem == null
                                ? [
                                    Colors.transparent,
                                    Colors.white.withValues(alpha: 0.88),
                                  ]
                                : const [
                                    Colors.transparent,
                                    Color(0xB8000000),
                                  ],
                          ),
                        ),
                      ),
                    if (!hasServerCover)
                      Positioned(
                        left: 11,
                        right: 11,
                        bottom: 9,
                        child: Text(
                          widget.library.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: skin.applyHeadlineMood(
                            TextStyle(
                              color: skin.isLight && widget.coverItem == null
                                  ? skin.fg
                                  : Colors.white,
                              fontSize: widget.width < 195 ? 14.5 : 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(height: widget.width < 195 ? 5 : 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.library.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    strutStyle: StrutStyle(
                      fontSize: widget.width < 195 ? 12.5 : 13.5,
                      height: PosterCardLayout.kStrutHeight,
                      forceStrutHeight: true,
                    ),
                    style: TextStyle(
                      color: skin.fg,
                      fontSize: widget.width < 195 ? 12.5 : 13.5,
                      height: PosterCardLayout.kStrutHeight,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                AnimatedOpacity(
                  opacity: _hovered ? 1.0 : 0.45,
                  duration: const Duration(milliseconds: 160),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: skin.fg2,
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
  const _CornerBadge({
    required this.child,
    this.accentRibbon = false,
    this.accentColor,
  });

  final Widget child;
  final bool accentRibbon;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    if (accentRibbon && accentColor != null) {
      return Container(
        height: 22,
        constraints: const BoxConstraints(minWidth: 24),
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accentColor,
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(9),
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor!.withValues(alpha: 0.45),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: child,
      );
    }
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
