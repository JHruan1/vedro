part of '../detail_screen.dart';

class _EpisodeHorizontalCard extends StatefulWidget {
  const _EpisodeHorizontalCard({
    required this.episode,
    required this.seriesFallback,
    required this.appState,
    required this.width,
    required this.accent,
    required this.onTap,
    required this.onOpenDetail,
    this.onPickVersion,
  });

  final MediaItemModel episode;
  final MediaItemModel seriesFallback;
  final VedroAppState appState;
  final double width;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onOpenDetail;
  final VoidCallback? onPickVersion;

  @override
  State<_EpisodeHorizontalCard> createState() => _EpisodeHorizontalCardState();
}

class _EpisodeHorizontalCardState extends State<_EpisodeHorizontalCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final ep = widget.episode;
    final hasProgress = ep.resumeProgress > 0.01;
    final airDate = fmtIsoDate(ep.premiereDate);
    final dur = fmtDurationTicks(ep.runTimeTicks);
    final epOverview = ep.cleanOverview;
    final cardR = widget.appState.prefs.effectiveCardRadius(skin);

    return RepaintBoundary(
      child: SizedBox(
      width: widget.width,
      child: PressableScale(
        onTap: widget.onTap,
        onLongPressWithRect: (rect) => showMediaItemContextSheet(
          context: context,
          item: ep,
          appState: widget.appState,
          anchorRect: rect,
          landscapePreview: true,
          previewFallbackItem: widget.seriesFallback,
          onQuickPlay: widget.onTap,
          onOpenDetail: widget.onOpenDetail,
          onPickVersion: widget.onPickVersion,
          versionCount: ep.versionCount,
        ),
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
                  borderRadius: BorderRadius.circular(cardR),
                  color: skin.surface2,
                  boxShadow: skin.posterShadow(hovered: _hovered),
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(cardR),
                  border: skin.cardBorder(hovered: _hovered),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    VedroArtwork(
                      item: ep,
                      fallbackItem: widget.seriesFallback,
                      appState: widget.appState,
                      landscape: true,
                      width: 520,
                      displayWidth: widget.width,
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0.55, 1.0],
                          colors: [Colors.transparent, Color(0x99000000)],
                        ),
                      ),
                    ),
                    IgnorePointer(
                      ignoring: !_hovered,
                      child: AnimatedOpacity(
                        opacity: _hovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 160),
                        child: Center(
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: skin.primaryCtaBg,
                              gradient: skin.primaryCtaGradient,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              size: 24,
                              color: skin.primaryCtaFg,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.onPickVersion != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 5),
                              child: PressableScale(
                                onTap: widget.onPickVersion,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xB809090B),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${ep.versionCount} 版本',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          PressableScale(
                            onTap: widget.onOpenDetail,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                color: Color(0xA609090B),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.more_horiz_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasProgress)
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 9,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: ep.resumeProgress,
                            minHeight: 3,
                            backgroundColor: const Color(0x45FFFFFF),
                            color: skin.ctaStyle == 'contrast' ? Colors.white : skin.accent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                if (ep.indexNumber != null)
                  Text(
                    '第 ${ep.indexNumber} 集',
                    style: TextStyle(
                      color: skin.fg3,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                const Spacer(),
                if (ep.played)
                  Icon(Icons.check_circle_rounded, size: 13.5, color: skin.fg3),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              ep.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: skin.fg,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            if (epOverview.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                epOverview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: skin.fg2, fontSize: 12, height: 1.42),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              [
                if (dur.isNotEmpty) dur,
                if (airDate.isNotEmpty) airDate,
                if (widget.appState.prefs.showRatings &&
                    ep.communityRating != null &&
                    ep.communityRating! > 0)
                  '★ ${ep.communityRating!.toStringAsFixed(1)}',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: skin.fg3,
                fontSize: 11.5,
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

class _EpisodeRow extends StatefulWidget {
  const _EpisodeRow({
    required this.episode,
    required this.seriesFallback,
    required this.appState,
    required this.onTap,
    required this.onOpenDetail,
    this.onPickVersion,
  });

  final MediaItemModel episode;
  final MediaItemModel seriesFallback;
  final VedroAppState appState;
  final VoidCallback onTap;
  final VoidCallback onOpenDetail;
  final VoidCallback? onPickVersion;

  @override
  State<_EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends State<_EpisodeRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final ep = widget.episode;
    final dur = fmtDurationTicks(ep.runTimeTicks);
    final airDate = fmtIsoDate(ep.premiereDate);
    final epOverview = ep.cleanOverview;
    final screenW = MediaQuery.sizeOf(context).width;
    final isMobile = screenW < 580;
    final thumbW = isMobile ? 116.0 : 162.0;

    final rawTitle = ep.displayName.trim();
    final alreadyHasNum = ep.indexNumber != null &&
        RegExp('^第\\s*${ep.indexNumber}\\s*[集话]|^${ep.indexNumber}[.、\\s]')
            .hasMatch(rawTitle);
    final headlineText = (ep.indexNumber != null && !alreadyHasNum)
        ? '${ep.indexNumber}. $rawTitle'
        : (rawTitle.isNotEmpty
            ? rawTitle
            : (ep.indexNumber != null ? '第 ${ep.indexNumber} 集' : '未命名分集'));

    final metaParts = <String>[
      if (dur.isNotEmpty) dur,
      if (airDate.isNotEmpty) airDate,
      if (widget.appState.prefs.showRatings &&
          ep.communityRating != null &&
          ep.communityRating! > 0)
        '★ ${ep.communityRating!.toStringAsFixed(1)}',
    ];

    return RepaintBoundary(
      child: Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PressableScale(
        onTap: widget.onTap,
        onLongPressWithRect: (rect) => showMediaItemContextSheet(
          context: context,
          item: ep,
          appState: widget.appState,
          anchorRect: rect,
          landscapePreview: true,
          previewFallbackItem: widget.seriesFallback,
          onQuickPlay: widget.onTap,
          onOpenDetail: widget.onOpenDetail,
          onPickVersion: widget.onPickVersion,
          versionCount: ep.versionCount,
        ),
        onHoverChanged: (v) => setState(() => _hovered = v),
        hoverScale: 1.006,
        pressScale: 0.985,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.all(isMobile ? 10 : 12),
          decoration: BoxDecoration(
            color: skin.unifiedTileColor(hovered: _hovered),
            borderRadius: BorderRadius.circular(skin.cardRadius.clamp(10.0, 18.0)),
            border: skin.cardBorder(hovered: _hovered),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: thumbW,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(skin.cardRadius.clamp(6.0, 11.0)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        VedroArtwork(
                          item: ep,
                          fallbackItem: widget.seriesFallback,
                          appState: widget.appState,
                          landscape: true,
                          width: 420,
                          displayWidth: thumbW,
                        ),
                        if (ep.indexNumber != null)
                          Positioned(
                            left: 5,
                            bottom: ep.resumeProgress > 0.01 ? 8 : 5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xB8090B10),
                                borderRadius: BorderRadius.circular(4.5),
                              ),
                              child: Text(
                                'EP ${ep.indexNumber!.toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ),
                        if (ep.played)
                          Positioned(
                            top: 5,
                            right: 5,
                            child: Container(
                              width: 17,
                              height: 17,
                              decoration: const BoxDecoration(
                                color: Color(0xB8090B10),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: const Icon(Icons.check_rounded, size: 11, color: Colors.white),
                            ),
                          ),
                        if (ep.resumeProgress > 0.01)
                          Positioned(
                            left: 5,
                            right: 5,
                            bottom: 4,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: ep.resumeProgress,
                                minHeight: 2.5,
                                backgroundColor: const Color(0x45FFFFFF),
                                color: skin.ctaStyle == 'contrast' ? Colors.white : skin.accent,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: isMobile ? 12 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Line 1: 100% Dedicated to Episode Number + Title (NEVER covered by version pills!)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            headlineText,
                            maxLines: isMobile ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ep.played ? skin.fg2 : skin.fg,
                              fontSize: isMobile ? 14.5 : 15,
                              fontWeight: FontWeight.w600,
                              height: 1.28,
                              letterSpacing: -0.15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        PressableScale(
                          onTap: widget.onOpenDetail,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 1, 2, 4),
                            child: Icon(CupertinoIcons.ellipsis, size: 16, color: skin.fg3),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Line 2: Metadata + Clean Clickable Version Pill (When Multi-Version)
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (metaParts.isNotEmpty)
                          Text(
                            metaParts.join(' · '),
                            style: TextStyle(
                              color: skin.fg3,
                              fontSize: 11.5,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        if (widget.onPickVersion != null)
                          PressableScale(
                            onTap: widget.onPickVersion,
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: skin.accent.withValues(alpha: skin.isLight ? 0.12 : 0.18),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${ep.versionCount} 版本',
                                    style: TextStyle(
                                      color: skin.isLight ? skin.accent : Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 12,
                                    color: skin.isLight ? skin.accent : Colors.white70,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (epOverview.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        epOverview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: skin.fg2,
                          fontSize: 12.5,
                          height: 1.44,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
