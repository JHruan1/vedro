import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/platform/platform_perf.dart';
import '../core/theme/display_profile.dart';
import '../core/theme/vedro_motion.dart';
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
    this.onLongPressWithRect,
    this.width = 152,
    this.landscape = false,
    this.heroPrefix,
  });

  final MediaItemModel item;
  final VedroAppState appState;
  final VoidCallback onTap;
  final VoidCallback? onQuickPlay;
  final VoidCallback? onLongPress;
  final void Function(Rect anchorRect)? onLongPressWithRect;
  final double width;
  final bool landscape;
  final String? heroPrefix;

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  bool _hovered = false;
  bool _focused = false;
  bool get _highlighted => _hovered || _focused;
  final GlobalKey _artKey = GlobalKey(debugLabel: 'media-card-art');

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final item = widget.item;
    final prefs = widget.appState.prefs;
    final radius = prefs.effectiveCardRadius(skin);
    final aspect = widget.landscape ? (16 / 9) : skin.mediaAspectRatio;
    final showPlayFab = widget.onQuickPlay != null && !item.isFolderish && item.type != 'Person';
    final profile = DisplayMetricsProfile.of(context);
    final touchPrimary = profile.isTouchPrimary;
    final isWideArt = widget.landscape || skin.posterAspect == 'landscape_16_9';

    Widget artBox = VedroArtwork(
      item: item,
      appState: widget.appState,
      landscape: isWideArt,
      width: isWideArt ? 640 : 420,
      displayWidth: widget.width,
    );

    if (widget.heroPrefix != null) {
      final heroBorder = skin.cardBorder(hovered: false);
      artBox = Hero(
        tag: '${widget.heroPrefix}-${item.id}',
        flightShuttleBuilder: vedroRoundedHeroShuttleBuilder(radius, border: heroBorder),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          clipBehavior: Clip.antiAlias,
          child: artBox,
        ),
      );
    }
    if (!touchPrimary && skin.cardHoverEffect == 'zoom_art') {
      artBox = AnimatedScale(
        scale: _highlighted ? 1.06 : 1.0,
        duration: const Duration(milliseconds: 520),
        curve: VedroSpringCurve.snappy,
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
    // Visual-first: version counts live in the long-press menu, not on the art.
    const showVersionBadge = false;
    final subtitleText = item.cardSubtitleFor(
      showYear: prefs.showYear,
      showRatingInText: prefs.showRatings && !showRatingBadge,
    );
    final pressScale = skin.touchFeedbackStyle == 'clean_static'
        ? 1.0
        : (skin.touchFeedbackStyle == 'subtle_scale' ? 0.988 : 0.965);
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
              boxShadow: skin.posterShadow(hovered: !touchPrimary && _highlighted),
            );
            final cardForeground = BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: skin.cardBorder(hovered: !touchPrimary && _highlighted),
            );
            final peek = widget.onLongPressWithRect == null
                ? null
                : (Rect cardRect) => widget.onLongPressWithRect!(
                      _globalRectOfKey(context, _artKey) ?? cardRect,
                    );
            return PressableScale(
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              onLongPressWithRect: peek,
              onSecondaryTap: widget.onLongPress,
              onSecondaryTapWithRect: peek,
              onHoverChanged: touchPrimary ? null : (v) => setState(() => _hovered = v),
              onFocusChanged: (v) => setState(() => _focused = v),
              borderRadius: BorderRadius.circular(radius),
              hoverScale: touchPrimary || skin.cardHoverEffect == 'zoom_art' ? 1.0 : 1.02,
              pressScale: pressScale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    key: _artKey,
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
                opacity: isOverlayCard ? 1.0 : (_highlighted ? 1.0 : 0.0),
                duration: const Duration(milliseconds: 190),
                curve: VedroTheme.easeOut,
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    10,
                    28,
                    showPlayFab && _highlighted ? 48 : 10,
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
        if (!hideBadges && (showVersionBadge || showRatingBadge))
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
                  if (showVersionBadge) const SizedBox(width: 4),
                ],
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
                  color: (skin.ctaStyle == 'contrast' && skin.progressStyle != 'glow_accent')
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
                curve: VedroTheme.easeOut,
                child: AnimatedScale(
                  scale: _hovered ? 1.0 : 0.72,
                  duration: const Duration(milliseconds: 460),
                  curve: VedroSpringCurve.playful,
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
    this.onLongPressWithRect,
    this.width = 296,
  });

  final MediaItemModel item;
  final VedroAppState appState;
  final VoidCallback onTap;
  final VoidCallback onResumePlay;
  final VoidCallback? onLongPress;
  final void Function(Rect anchorRect)? onLongPressWithRect;
  final double width;

  @override
  State<ResumeCard> createState() => _ResumeCardState();
}

class _ResumeCardState extends State<ResumeCard> {
  bool _hovered = false;
  bool _focused = false;
  bool get _highlighted => _hovered || _focused;
  final GlobalKey _artKey = GlobalKey(debugLabel: 'resume-card-art');

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final radius = widget.appState.prefs.effectiveCardRadius(skin);
    final item = widget.item;
    final touchPrimary = DisplayMetricsProfile.of(context).isTouchPrimary;
    final hasLightNoBackdrop = skin.isLight && widget.appState.backdropArt(item) == null;
    final left = item.remainingText;
    final sub = item.type == 'Episode'
        ? item.cardSubtitle
        : [
            if (item.productionYear != null) '${item.productionYear}',
            if (fmtDurationTicks(item.runTimeTicks).isNotEmpty) fmtDurationTicks(item.runTimeTicks),
          ].join(' · ');

    final cardDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      color: skin.surface2,
      boxShadow: skin.posterShadow(hovered: !touchPrimary && _highlighted),
    );
    final cardForeground = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: skin.cardBorder(hovered: !touchPrimary && _highlighted),
    );
    final cardBody = Stack(
      fit: StackFit.expand,
      children: [
        VedroArtwork(
          item: item,
          appState: widget.appState,
          landscape: true,
          width: 680,
          displayWidth: widget.width,
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
                colors: hasLightNoBackdrop
                    ? [Colors.transparent, Colors.white.withValues(alpha: 0.72)]
                    : const [Colors.transparent, Color(0xBD000000)],
              ),
            ),
          ),
        ),
        // Whole card resumes on tap; the play glyph only appears as a hover/focus hint.
        Center(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _highlighted ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              curve: VedroTheme.easeOut,
              child: AnimatedScale(
                scale: _highlighted ? 1.0 : 0.7,
                duration: const Duration(milliseconds: 460),
                curve: VedroSpringCurve.playful,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.42),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.6),
                  ),
                  child: const Icon(Icons.play_arrow_rounded, size: 26, color: Colors.white),
                ),
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
              backgroundColor: hasLightNoBackdrop
                  ? Colors.black.withValues(alpha: 0.12)
                  : const Color(0x45FFFFFF),
              color: hasLightNoBackdrop
                  ? skin.accent
                  : (skin.ctaStyle == 'contrast' ? Colors.white : skin.accent),
            ),
          ),
        ),
      ],
    );

    final peek = widget.onLongPressWithRect == null
        ? null
        : (Rect cardRect) => widget.onLongPressWithRect!(
              _globalRectOfKey(context, _artKey) ?? cardRect,
            );
    return RepaintBoundary(
      child: SizedBox(
        width: widget.width,
        child: PressableScale(
          // "继续播放": a tap resumes immediately (Apple TV / Infuse); details live in
          // the long-press / right-click menu.
          onTap: widget.onResumePlay,
          onLongPress:
              widget.onLongPress ?? (widget.onLongPressWithRect == null ? widget.onTap : null),
          onLongPressWithRect: peek,
          onSecondaryTap:
              widget.onLongPress ?? (widget.onLongPressWithRect == null ? widget.onTap : null),
          onSecondaryTapWithRect: peek,
          onHoverChanged: touchPrimary ? null : (v) => setState(() => _hovered = v),
          onFocusChanged: (v) => setState(() => _focused = v),
          borderRadius: BorderRadius.circular(radius),
          hoverScale: touchPrimary ? 1.0 : 1.02,
          pressScale: 0.965,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                key: _artKey,
                aspectRatio: 16 / 9,
                child: touchPrimary
                    ? Container(
                        decoration: cardDecoration,
                        foregroundDecoration: cardForeground,
                        clipBehavior: Clip.antiAlias,
                        child: cardBody,
                      )
                    : AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: VedroTheme.easeOut,
                        decoration: cardDecoration,
                        foregroundDecoration: cardForeground,
                        clipBehavior: Clip.antiAlias,
                        child: cardBody,
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
                    ? (item.compactEpisodeCode != null
                        ? '${item.compactEpisodeCode} · $left'
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
  bool _focused = false;
  bool get _highlighted => _hovered || _focused;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final radius = widget.appState.prefs.effectiveCardRadius(skin);
    final touchPrimary = DisplayMetricsProfile.of(context).isTouchPrimary;
    final serverCover = widget.appState.libraryCoverUrl(widget.library, width: 720);
    final hasServerCover = serverCover != null && serverCover.isNotEmpty;

    final cardDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      color: skin.surface2,
      boxShadow: skin.posterShadow(hovered: !touchPrimary && _highlighted),
    );
    final cardForeground = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: skin.cardBorder(hovered: !touchPrimary && _highlighted),
    );

    return RepaintBoundary(
      child: SizedBox(
        width: widget.width,
        child: PressableScale(
          onTap: widget.onTap,
          onHoverChanged: touchPrimary ? null : (v) => setState(() => _hovered = v),
          onFocusChanged: (v) => setState(() => _focused = v),
          borderRadius: BorderRadius.circular(radius),
          hoverScale: touchPrimary ? 1.0 : 1.014,
          pressScale: 0.98,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: AnimatedContainer(
                  duration: touchPrimary ? Duration.zero : const Duration(milliseconds: 200),
                  curve: VedroTheme.easeOut,
                  decoration: cardDecoration,
                  foregroundDecoration: cardForeground,
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
                          displayWidth: widget.width,
                          showInitials: false,
                        )
                      else
                        GeneratedArt(seed: widget.library.id, label: null),
                      if (hasServerCover)
                        FadeNetworkImage(
                          url: serverCover,
                          fit: BoxFit.cover,
                          cacheWidth: PlatformPerfProfile.imageCacheWidthFor(
                            widget.width,
                            MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0,
                          ),
                        ),
                      // The library name lives once, in the caption below — no duplicated
                      // in-art title + scrim stacked on top of the same label.
                    ],
                  ),
                ),
              ),
              SizedBox(height: widget.width < 195 ? 5 : 8),
              Row(
                children: [
                  Icon(
                    _libraryIcon(widget.library.collectionType),
                    size: widget.width < 195 ? 14 : 15,
                    color: _highlighted ? skin.accent : skin.fg3,
                  ),
                  SizedBox(width: widget.width < 195 ? 5 : 6),
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
                ],
              ),
            ],
          ),
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

/// Global rect of a keyed box relative to the root Overlay (peek-menu anchor).
Rect? _globalRectOfKey(BuildContext context, GlobalKey key) =>
    vedroGlobalRectOfKey(context, key);

/// Library type glyph (visual-first: the icon says "movies / shows / music").
IconData _libraryIcon(String? collectionType) {
  switch ((collectionType ?? '').toLowerCase()) {
    case 'movies':
      return Icons.movie_outlined;
    case 'tvshows':
      return Icons.tv_rounded;
    case 'music':
      return Icons.music_note_rounded;
    case 'musicvideos':
      return Icons.music_video_outlined;
    case 'homevideos':
    case 'photos':
      return Icons.photo_library_outlined;
    case 'boxsets':
      return Icons.collections_bookmark_outlined;
    case 'livetv':
      return Icons.live_tv_rounded;
    case 'books':
      return Icons.menu_book_rounded;
    default:
      return Icons.video_library_outlined;
  }
}
