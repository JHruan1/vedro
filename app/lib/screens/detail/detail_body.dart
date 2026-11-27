part of '../detail_screen.dart';

/// Main themed detail canvas, hero backdrop, metadata, actions & credits layout.
extension _DetailBodyExt on _DetailScreenState {
  Widget _buildThemedDetail(BuildContext context) {
    final skin = VedroSkin.of(context);
    final detailOverlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: skin.isLight ? Brightness.dark : Brightness.light,
      statusBarBrightness: skin.isLight ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: skin.isLight ? Brightness.dark : Brightness.light,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    );
    final chromeSig = '${skin.isLight}|${skin.canvas.toARGB32()}|${skin.fg.toARGB32()}';
    if (_lastChromeSig != chromeSig) {
      _lastChromeSig = chromeSig;
      NativePlaybackChannel.syncWindowChrome(
        isLight: skin.isLight,
        canvasArgb: skin.canvas.toARGB32(),
        fgArgb: skin.fg.toARGB32(),
      );
    }
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 820;
    final ultraWide = size.width >= 1080;
    final padX = wide ? 44.0 : 20.0;
    final isMac = !kIsWeb && Platform.isMacOS;
    final topSafe = MediaQuery.paddingOf(context).top;
    final logoUrl = _item.type == 'Episode' ? null : widget.appState.logoArtUrl(_item);
    final src = _activeSource;
    final accent = skin.accent;
    final showSpecs = widget.appState.prefs.showSpecBadges;
    final overviewText = _translatedOverview?.isNotEmpty == true
        ? _translatedOverview!
        : _item.cleanOverview;
    final hasOverviewSlot =
        (_item.taglines.isNotEmpty) || overviewText.isNotEmpty || (_loading && _item.type != 'Person');
    final tagline = _item.taglines.isNotEmpty ? _item.taglines.first : null;
    final downloadTarget = _resolveDownloadTarget();
    final canDownload = widget.appState.canDownloadItem(downloadTarget ?? _item);

    final directors = _item.people
        .where((p) => (p.type ?? '').toLowerCase() == 'director')
        .map((p) => p.name)
        .toList();
    final castNames = _item.people
        .where((p) => (p.type ?? '').toLowerCase() == 'actor')
        .map((p) => p.name)
        .take(4)
        .toList();
    final statusLabel = _localizeStatus(_item.status);
    final premiere = fmtIsoDate(_item.premiereDate);

    // Aggregate clean specs from current item or first episode if Series
    final sampleMediaItem = _item.isPlayable
        ? _item
        : (_episodes.isNotEmpty ? _episodes.first : null);
    final specChips = showSpecs
        ? <String>[
            ..._item.inferredBadges,
            if (src != null) ...src.factChips.where((c) => !_item.inferredBadges.contains(c)),
            if (!_item.isPlayable && sampleMediaItem != null)
              ...sampleMediaItem.inferredBadges.where((c) => !_item.inferredBadges.contains(c)),
          ].take(6).toList()
        : const <String>[];

    // Pick next unwatched episode for Series main Play CTA (preferring server NextUp when present)
    MediaItemModel? nextEpToPlay;
    if (_episodes.isNotEmpty) {
      if (_seriesNextUp != null) {
        final match = _episodes.where((e) => e.id == _seriesNextUp!.id);
        if (match.isNotEmpty) nextEpToPlay = match.first;
      }
      nextEpToPlay ??= _episodes.firstWhere(
        (e) => e.resumeProgress > 0.01,
        orElse: () => _episodes.firstWhere(
          (e) => !e.played,
          orElse: () => _episodes.first,
        ),
      );
    }

    final playableVersions = _resolvedPlayableVersions;
    final seriesVersions = _resolvedSeriesVersions;
    if (_selectedSeriesVersionIndex >= seriesVersions.length && seriesVersions.isNotEmpty) {
      _selectedSeriesVersionIndex = 0;
    }
    final activeSeriesEpSource =
        nextEpToPlay != null ? _matchingSourceForEpisode(nextEpToPlay) : null;
    final activeEffSource = _item.isSeries ? activeSeriesEpSource : src;
    final hasKnownEmbeddedStreams = activeEffSource != null &&
        (activeEffSource.audioStreams.isNotEmpty || activeEffSource.videoStreams.isNotEmpty);

    final isEpisodeWithStill = _item.type == 'Episode' && _item.primaryImageTag != null;
    final coverW = _item.type == 'Person'
        ? (wide ? 156.0 : 104.0)
        : isEpisodeWithStill
            ? (wide ? 260.0 : 148.0)
            : (wide ? 188.0 : 112.0);
    final coverAspect = _item.type == 'Person'
        ? 1.0
        : (isEpisodeWithStill ? 16 / 9 : 2 / 3);

    // Editorial eyebrow (Studio + Type)
    final typeWord = _item.isSeries
        ? '剧集'
        : (_item.type == 'Movie' ? '电影' : (_item.type == 'Episode' ? '单集' : ''));
    final eyebrowParts = <String>[
      if (_item.type == 'Episode' && _item.seriesName != null) _item.seriesName!,
      if (_item.type == 'Episode' && _item.episodeCode != null) _item.episodeCode!,
      if (_item.type != 'Episode' && _item.studios.isNotEmpty) _item.studios.first,
      if (_item.type != 'Episode' && typeWord.isNotEmpty) typeWord,
    ];
    final eyebrowText = eyebrowParts.join(' · ');

    Widget buildActionRow() {
      return ListenableBuilder(
        listenable: widget.appState.downloadsTickNotifier,
        builder: (context, _) {
          final liveDlTask =
              widget.appState.findDownloadForItem(downloadTarget?.id ?? _item.id);
          final liveLocalReady = liveDlTask != null &&
              liveDlTask.status == 'completed' &&
              liveDlTask.filePath.isNotEmpty;
          // Keep Play CTA visible from Frame 0 for both Movies AND Series so buttons NEVER pop in late!
          final hasPrimaryPlay = _item.isPlayable || _item.isSeries;
          final String playLabel = _item.isPlayable
              ? (liveLocalReady
                  ? '播放离线缓存'
                  : (_item.playbackPositionTicks > 0
                      ? '继续播放 ${fmtDurationTicks(_item.playbackPositionTicks)}'
                      : '播放'))
              : (nextEpToPlay != null
                  ? (nextEpToPlay.resumeProgress > 0.01
                      ? '继续观看 ${nextEpToPlay.episodeCode ?? nextEpToPlay.displayName}'
                      : '播放 ${nextEpToPlay.episodeCode ?? '第 1 集'}')
                  : '播放 S01E01');
          final double playProgress =
              _item.isPlayable ? _item.resumeProgress : (nextEpToPlay?.resumeProgress ?? 0.0);
          Future<void> onPrimaryPlay() async {
            if (_item.isPlayable) {
              _play(
                _item,
                sourceId: _activeSource?.id,
                localPath: liveLocalReady ? liveDlTask.filePath : null,
              );
              return;
            }
            if (nextEpToPlay == null && _loadFuture != null) {
              await _loadFuture;
            }
            if (!mounted) return;
            final resolvedEp = nextEpToPlay ??
                (_episodes.isNotEmpty
                    ? _episodes.firstWhere(
                        (e) => e.resumeProgress > 0.01,
                        orElse: () => _episodes.firstWhere(
                          (e) => !e.played,
                          orElse: () => _episodes.first,
                        ),
                      )
                    : null);
            if (resolvedEp != null) {
              _play(
                resolvedEp,
                sourceId: _matchingSourceIdForEpisode(resolvedEp),
              );
            }
          }

          final actions = <({
            Key? key,
            IconData icon,
            String label,
            String tooltip,
            bool active,
            Color color,
            VoidCallback onTap,
          })>[
            if (_item.isPlayable && _item.playbackPositionTicks > 0)
              (
                key: null,
                icon: Icons.replay_rounded,
                label: '从头',
                tooltip: '从头播放',
                active: false,
                color: skin.fg,
                onTap: () => _play(_item, sourceId: _activeSource?.id, fromBeginning: true),
              ),
            if (_item.type != 'Person')
              (
                key: null,
                icon: Icons.check_rounded,
                label: _item.played ? '已看' : '标已看',
                tooltip: _item.played ? '已看（点击取消）' : '标为已看',
                active: _item.played,
                color: _item.played ? accent : skin.fg,
                onTap: () async {
                  try {
                    await widget.appState.togglePlayed(_item);
                    if (mounted) await _loadDetails();
                  } catch (e) {
                    if (mounted && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('更新播放状态失败：${VedroErrorFormatter.friendly(e)}')),
                      );
                    }
                  }
                },
              ),
            (
              key: null,
              icon: _item.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              label: _item.isFavorite ? '已收藏' : '收藏',
              tooltip: _item.isFavorite ? '取消收藏' : '收藏',
              active: _item.isFavorite,
              color: _item.isFavorite ? VedroTheme.danger : skin.fg,
              onTap: () async {
                try {
                  await widget.appState.toggleFavorite(_item);
                  if (mounted) await _loadDetails();
                } catch (e) {
                  if (mounted && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('更新收藏状态失败：${VedroErrorFormatter.friendly(e)}')),
                    );
                  }
                }
              },
            ),
            if (liveLocalReady || canDownload)
              (
                key: const ValueKey('detail-download-button'),
                icon: liveLocalReady ? Icons.download_done_rounded : Icons.arrow_downward_rounded,
                label: liveLocalReady ? '已缓存' : (_item.isSeries ? '下载' : '缓存'),
                tooltip: liveLocalReady ? '播放已缓存文件' : '离线下载',
                active: liveLocalReady,
                color: liveLocalReady ? const Color(0xFF10B981) : skin.fg,
                onTap: liveLocalReady
                    ? () => _play(downloadTarget ?? _item, localPath: liveDlTask.filePath)
                    : _startDownload,
              ),
            (
              key: null,
              icon: Icons.more_horiz_rounded,
              label: '更多',
              tooltip: '更多（字幕挂载 / 外部播放器 / 片单 / AI 翻译）',
              active: false,
              color: skin.fg,
              onTap: _openMoreSheet,
            ),
          ];

          return LayoutBuilder(
            builder: (ctx, constraints) {
              final singleLine = constraints.maxWidth >= 460;
              if (singleLine) {
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (hasPrimaryPlay)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: _ProgressPlayPill(
                          label: playLabel,
                          progress: playProgress,
                          accent: accent,
                          autofocus: PlatformPerfProfile.isTv,
                          onTap: onPrimaryPlay,
                        ),
                      ),
                    for (var i = 0; i < actions.length; i++)
                      KeyedSubtree(
                        key: actions[i].key,
                        child: Tooltip(
                          message: actions[i].tooltip,
                          child: _AppleCircleActionButton(
                            icon: actions[i].icon,
                            active: actions[i].active,
                            color: actions[i].color,
                            onTap: actions[i].onTap,
                          ),
                        ),
                      ),
                    if (playProgress > 0.02)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 64,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: playProgress.clamp(0.04, 1.0),
                                  minHeight: 3,
                                  backgroundColor: skin.fg.withValues(alpha: 0.16),
                                  color: skin.ctaStyle == 'contrast' ? skin.fg : accent,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '已看 ${(playProgress * 100).round()}%',
                              style: TextStyle(
                                color: skin.fg2,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasPrimaryPlay) ...[
                    _ProgressPlayPill(
                      label: playLabel,
                      progress: playProgress,
                      accent: accent,
                      fullWidth: true,
                      autofocus: PlatformPerfProfile.isTv,
                      onTap: onPrimaryPlay,
                    ),
                    if (playProgress > 0.02) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: playProgress.clamp(0.04, 1.0),
                                minHeight: 2.5,
                                backgroundColor: skin.fg.withValues(alpha: 0.16),
                                color: skin.ctaStyle == 'contrast' ? skin.fg : accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '已观看 ${(playProgress * 100).round()}%',
                            style: TextStyle(
                              color: skin.fg2,
                              fontSize: 11.5,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          key: actions[i].key,
                          child: PressableScale(
                            onTap: actions[i].onTap,
                            hoverScale: 1.03,
                            pressScale: 0.93,
                            child: Container(
                              height: 54,
                              decoration: BoxDecoration(
                                color: actions[i].active
                                    ? actions[i].color.withValues(alpha: 0.18)
                                    : skin.subtleChipBg,
                                borderRadius:
                                    BorderRadius.circular(skin.cardRadius.clamp(8.0, 14.0)),
                                border: skin.frameStyle == 'borderless'
                                    ? null
                                    : Border.all(color: skin.border, width: 0.7),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(actions[i].icon, size: 19, color: actions[i].color),
                                  const SizedBox(height: 3),
                                  Text(
                                    actions[i].label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: actions[i].active ? actions[i].color : skin.fg2,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              );
            },
          );
        },
      );
    }

    Widget buildOverviewBlock() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tagline != null) ...[
            Text(
              tagline,
              style: TextStyle(
                color: skin.fg,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 6),
          ],
          if (overviewText.isNotEmpty)
            _ExpandableOverview(
              text: overviewText,
              collapsedLines: 3,
              accent: accent,
              aiReady: widget.appState.prefs.isAiReady,
              translating: _translating,
              isTranslated: _translatedOverview != null,
              onTranslateToggle: _translatedOverview != null
                  ? () => _setDetailState(() => _translatedOverview = null)
                  : _translateOverview,
            )
          else if (_loading && _item.type != 'Person')
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  VedroShimmer(width: 440, height: 14, borderRadius: 4),
                  SizedBox(height: 8),
                  VedroShimmer(width: 300, height: 14, borderRadius: 4),
                ],
              ),
            ),
        ],
      );
    }

    final dotFacts = <Widget>[];
    void addDotFact(Widget w) {
      if (dotFacts.isNotEmpty) {
        dotFacts.add(Text(
          ' · ',
          style: TextStyle(color: skin.fg3, fontSize: 13.5),
        ));
      }
      dotFacts.add(w);
    }

    if (premiere.isNotEmpty) {
      addDotFact(Text(
        premiere,
        style: TextStyle(
          color: skin.fg2,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ));
    } else if (_item.productionYear != null) {
      addDotFact(Text(
        '${_item.productionYear}',
        style: TextStyle(
          color: skin.fg2,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ));
    }

    for (final g in _item.genres.take(4)) {
      addDotFact(
        PressableScale(
          onTap: widget.onGenreTap == null ? null : () => widget.onGenreTap!(g),
          borderRadius: BorderRadius.circular(6),
          hoverScale: 1.04,
          pressScale: 0.96,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            child: Text(
              g,
              style: TextStyle(
                color: skin.fg2,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    if (_item.isSeries && (_seasons.isNotEmpty || (_item.childCount ?? 0) > 0)) {
      addDotFact(Text(
        '共 ${_seasons.isNotEmpty ? _seasons.length : _item.childCount} 季${(_item.recursiveItemCount ?? 0) > 0 ? ' ${_item.recursiveItemCount} 集' : ''}',
        style: TextStyle(color: skin.fg2, fontSize: 13.5),
      ));
    }

    if (!_item.isFolderish && fmtDurationTicks(_item.runTimeTicks).isNotEmpty) {
      addDotFact(Text(
        fmtDurationTicks(_item.runTimeTicks),
        style: TextStyle(color: skin.fg2, fontSize: 13.5),
      ));
    } else if (_item.isSeries && fmtDurationTicks(_item.runTimeTicks).isNotEmpty) {
      addDotFact(Text(
        '单集 ${fmtDurationTicks(_item.runTimeTicks)}',
        style: TextStyle(color: skin.fg3, fontSize: 13.5),
      ));
    }

    if (_item.productionLocations.isNotEmpty) {
      addDotFact(Text(
        _item.productionLocations.take(2).join(' / '),
        style: TextStyle(color: skin.fg3, fontSize: 13.5),
      ));
    }

    for (final studio in _item.studios.take(2)) {
      addDotFact(
        PressableScale(
          onTap: () => _openStudio(studio),
          borderRadius: BorderRadius.circular(6),
          hoverScale: 1.04,
          pressScale: 0.96,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            child: Text(
              studio,
              style: TextStyle(
                color: skin.accent,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    final heroCreditRows = <(String role, String names)>[
      if (directors.isNotEmpty) ('导演', directors.take(2).join('、')),
      if (castNames.isNotEmpty) ('主演', castNames.join('、')),
      if (_item.studios.isNotEmpty) ('出品', _item.studios.take(2).join('、')),
      if (statusLabel.isNotEmpty) ('状态', statusLabel),
    ];

    final posterRadius = widget.appState.prefs.effectiveCardRadius(skin);
    Widget coverCard = RepaintBoundary(
      child: PressableScale(
        onTap: _openPosterLightbox,
        borderRadius: BorderRadius.circular(posterRadius),
        hoverScale: 1.02,
        pressScale: 0.97,
        child: Container(
          key: const ValueKey('detail-poster-cover'),
          width: coverW,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(posterRadius),
            color: skin.surface2,
            boxShadow: skin.posterShadow(hovered: true),
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(posterRadius),
            border: skin.cardBorder(hovered: false),
          ),
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: coverAspect,
            child: VedroArtwork(
              item: _item,
              appState: widget.appState,
              landscape: isEpisodeWithStill,
              width: 600,
              displayWidth: coverW,
            ),
          ),
        ),
      ),
    );
    if (widget.heroTag != null) {
      coverCard = Hero(tag: widget.heroTag!, child: coverCard);
    }

    final c = skin.canvas;
    // Always dissolve smoothly into solid `skin.canvas` so the Hero image is NEVER stacked a second time!
    final endCanvas = c;
    final heroVertStops = skin.isLight
        ? const [0.0, 0.24, 0.54, 0.82, 0.95, 1.0]
        : const [0.0, 0.22, 0.56, 0.84, 0.95, 1.0];
    final heroVertColors = skin.isLight
        ? [
            c.withValues(alpha: 0.48),
            c.withValues(alpha: 0.56),
            c.withValues(alpha: 0.89),
            endCanvas,
            endCanvas,
            endCanvas,
          ]
        : [
            c.withValues(alpha: 0.30),
            c.withValues(alpha: 0.08),
            c.withValues(alpha: 0.64),
            c.withValues(alpha: 0.92),
            endCanvas,
            endCanvas,
          ];

    final isCenteredEditorial = skin.detailLayout == 'centered_editorial';
    final isJellyfinGlass = skin.detailLayout == 'jellyfin_glass';

    Widget buildHeroBodyContent() {
      if (isCenteredEditorial) {
        return Column(
          key: const ValueKey('detail-centered-editorial-hero'),
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            coverCard,
            const SizedBox(height: 22),
            if (eyebrowText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  eyebrowText.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: skin.ctaStyle == 'contrast' ? skin.fg3 : skin.accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.9,
                  ),
                ),
              ),
            if (logoUrl != null && skin.preferClearLogo && !skin.isLight)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: wide ? 82 : 60,
                  maxWidth: wide ? 420 : 280,
                ),
                child: Image.network(
                  logoUrl,
                  cacheWidth: 640,
                  filterQuality: FilterQuality.medium,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      _TitleHeadline(_item.displayName, wide, centered: true),
                ),
              )
            else
              _TitleHeadline(_item.displayName, wide, centered: true),
            if (_item.originalTitle != null && _item.originalTitle != _item.name) ...[
              const SizedBox(height: 4),
              Text(
                _item.originalTitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: skin.fg3, fontSize: 13.5),
              ),
            ],
            if (dotFacts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 4,
                children: dotFacts,
              ),
            ],
            if ((_item.communityRating ?? 0) > 0 ||
                (_item.criticRating ?? 0) > 0 ||
                (_item.officialRating?.isNotEmpty == true) ||
                statusLabel.isNotEmpty ||
                specChips.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (_item.communityRating != null && _item.communityRating! > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded, size: 15.5, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 3),
                        Text(
                          _item.communityRating!.toStringAsFixed(1),
                          style: TextStyle(
                            color: skin.fg,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  if (_item.officialRating != null && _item.officialRating!.isNotEmpty)
                    _AppleMicroBadge(_item.officialRating!),
                  if (statusLabel.isNotEmpty) _AppleMicroBadge(statusLabel),
                  if (specChips.isNotEmpty) SpecGlyphRow(specs: specChips),
                ],
              ),
            ],
            if (hasOverviewSlot) ...[
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: buildOverviewBlock(),
              ),
            ],
            const SizedBox(height: 22),
            Center(child: buildActionRow()),
          ],
        );
      }

      final standardContent = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: wide ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              coverCard,
              SizedBox(width: wide ? 32 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (eyebrowText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          eyebrowText.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: skin.ctaStyle == 'contrast' ? skin.fg3 : skin.accent,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    if (wide && logoUrl != null && skin.preferClearLogo && !skin.isLight)
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: 74,
                          maxWidth: 400,
                        ),
                        child: Image.network(
                          logoUrl,
                          cacheWidth: 640,
                          filterQuality: FilterQuality.medium,
                          fit: BoxFit.contain,
                          alignment: Alignment.centerLeft,
                          errorBuilder: (_, __, ___) =>
                              _TitleHeadline(_item.displayName, wide),
                        ),
                      )
                    else
                      _TitleHeadline(_item.displayName, wide),
                    if (_item.originalTitle != null &&
                        _item.originalTitle != _item.name) ...[
                      const SizedBox(height: 4),
                      Text(
                        _item.originalTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: skin.fg3,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                    if (dotFacts.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 4,
                        children: dotFacts,
                      ),
                    ],
                    if ((_item.communityRating ?? 0) > 0 ||
                        (_item.criticRating ?? 0) > 0 ||
                        (_item.officialRating?.isNotEmpty == true) ||
                        statusLabel.isNotEmpty ||
                        specChips.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (_item.communityRating != null &&
                              _item.communityRating! > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded,
                                    size: 15.5, color: Color(0xFFF59E0B)),
                                const SizedBox(width: 3),
                                Text(
                                  _item.communityRating!.toStringAsFixed(1),
                                  style: TextStyle(
                                    color: skin.fg,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ],
                            ),
                          if (_item.criticRating != null &&
                              _item.criticRating! > 0)
                            Text(
                              '${_item.criticRating!.round()}% 好评',
                              style: TextStyle(
                                color: skin.fg2,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          if (_item.officialRating != null &&
                              _item.officialRating!.isNotEmpty)
                            _AppleMicroBadge(_item.officialRating!),
                          if (statusLabel.isNotEmpty && !ultraWide)
                            _AppleMicroBadge(statusLabel),
                          if (specChips.isNotEmpty) SpecGlyphRow(specs: specChips),
                        ],
                      ),
                    ],
                    if (wide) ...[
                      if (hasOverviewSlot) ...[
                        const SizedBox(height: 14),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 680),
                          child: buildOverviewBlock(),
                        ),
                      ],
                      const SizedBox(height: 22),
                      buildActionRow(),
                    ],
                  ],
                ),
              ),
              if (ultraWide && heroCreditRows.isNotEmpty) ...[
                const SizedBox(width: 36),
                SizedBox(
                  width: 228,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < heroCreditRows.length; i++) ...[
                          if (i > 0) const SizedBox(height: 10),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '${heroCreditRows[i].$1}  ',
                                  style: TextStyle(
                                    color: skin.fg3,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    height: 1.45,
                                  ),
                                ),
                                TextSpan(
                                  text: heroCreditRows[i].$2,
                                  style: TextStyle(
                                    color: skin.fg2,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (!wide) ...[
            const SizedBox(height: 20),
            buildActionRow(),
            if (hasOverviewSlot) ...[
              const SizedBox(height: 16),
              buildOverviewBlock(),
            ],
          ],
        ],
      );

      if (isJellyfinGlass) {
        return GlassSurface(
          key: const ValueKey('detail-jellyfin-glass-hero'),
          borderRadius: skin.cardRadius.clamp(10.0, 24.0),
          blur: 28,
          color: skin.panelSurface,
          borderColor: skin.borderStrong,
          padding: EdgeInsets.all(wide ? 26 : 18),
          child: standardContent,
        );
      }
      return standardContent;
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: detailOverlay,
      child: Scaffold(
      backgroundColor: skin.canvas,
      body: VedroSkinCanvas(
        suppressTopOrb: true,
        child: Stack(
          children: [
            CustomScrollView(
              cacheExtent: PlatformPerfProfile.scrollCacheExtent,
              slivers: [
                // 1. Seamless Full-Stage Hero adapting to `detailLayout` (`apple_immersive` | `jellyfin_glass` | `centered_editorial`)
                SliverToBoxAdapter(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: ClipRect(
                            key: const ValueKey('detail-backdrop-banner'),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                VedroArtwork(
                                  item: _item,
                                  appState: widget.appState,
                                  isHero: true,
                                  alignment: const Alignment(0, -0.32),
                                  showInitials: false,
                                ),
                                if (wide && !isCenteredEditorial)
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                        stops: const [0.0, 0.55, 1.0],
                                        colors: [
                                          c.withValues(alpha: skin.isLight ? 0.86 : 0.78),
                                          c.withValues(alpha: skin.isLight ? 0.55 : 0.40),
                                          c.withValues(alpha: skin.isLight ? 0.25 : 0.22),
                                        ],
                                      ),
                                    ),
                                  ),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      stops: heroVertStops,
                                      colors: heroVertColors,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (skin.backdropMode == 'solid_clean')
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: -2,
                          height: 5,
                          child: ColoredBox(color: c),
                        ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          padX,
                          wide ? (topSafe + (isJellyfinGlass ? 112 : 144)) : (topSafe + 108),
                          padX,
                          wide ? 32 : 24,
                        ),
                        child: buildHeroBodyContent(),
                      ),
                    ],
                  ),
                ),

                // 2. Body Content: Strictly Single-Select Version Grid + Version-Following Audio & Subtitle Selector!
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_loadError != null && !_loading)
                        Padding(
                          padding: EdgeInsets.fromLTRB(padX, 0, padX, 18),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: VedroTheme.danger.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: VedroTheme.danger.withValues(alpha: 0.30),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    size: 18, color: VedroTheme.danger),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '加载详情失败：$_loadError',
                                    style: TextStyle(color: skin.fg, fontSize: 13),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: _loadDetails,
                                  child: const Text('重试'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_item.isPlayable || _item.isSeries) ...[
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: padX),
                          child: _TracksPanel(
                            isSeries: _item.isSeries,
                            isLoading: _loading,
                            expectedVersionCount: _item.versionCount,
                            versions: _item.isSeries ? seriesVersions : playableVersions,
                            selectedVersionIndex: _item.isSeries
                                ? _selectedSeriesVersionIndex
                                : _selectedSourceIndex,
                            activeStreamSource: activeEffSource,
                            hasKnownEmbeddedStreams: hasKnownEmbeddedStreams,
                            selectedAudioIndex: _selectedAudioIndex,
                            selectedSubtitleIndex: _selectedSubtitleIndex,
                            preferredAudioLangOverride: _audioLangByVer[_activeVersionStateKey],
                            preferredSubLangOverride: _subLangByVer[_activeVersionStateKey],
                            localExternalSubPath: _localExternalSubPath,
                            appState: widget.appState,
                            onSelectVersionIndex: (idx) {
                              _setDetailState(() {
                                if (_item.isSeries) {
                                  _selectedSeriesVersionIndex = idx;
                                } else {
                                  _selectedSourceIndex = idx;
                                }
                              });
                            },
                            onSelectAudio: (idx) => _setDetailState(() => _selectedAudioIndex = idx),
                            onSelectSubtitle: (idx) => _setDetailState(() {
                              _selectedSubtitleIndex = idx;
                              if (idx != null) _localExternalSubPath = null;
                            }),
                            onSelectVersionAudioLang: (lang) => _setDetailState(() {
                              _audioLangByVer[_activeVersionStateKey] = lang;
                            }),
                            onSelectVersionSubLang: (lang) => _setDetailState(() {
                              _subLangByVer[_activeVersionStateKey] = lang;
                              _selectedSubtitleIndex = lang == 'off' ? -1 : null;
                            }),
                            onPickExternalSubtitle: _pickExternalSubtitleForDetail,
                            onClearExternalSubtitle: () =>
                                _setDetailState(() => _localExternalSubPath = null),
                          ),
                        ),
                        const SizedBox(height: 30),
                      ],

                      // 2c. TV Series Seasons & Scalable Episode Selector (pre-sized skeleton while loading -> 0 CLS!)
                      if (_seasons.isNotEmpty) ...[
                        _buildEpisodeSection(
                          wide: wide,
                          padX: padX,
                          accent: accent,
                          nextEpToPlay: nextEpToPlay,
                        ),
                        const SizedBox(height: 34),
                      ] else if (_loading && _item.isSeries) ...[
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: padX),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  VedroShimmer(width: 96, height: 34, borderRadius: 999),
                                  Spacer(),
                                  VedroShimmer(width: 72, height: 34, borderRadius: 999),
                                ],
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                height: wide ? 298 : 258,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: 4,
                                  separatorBuilder: (_, __) => const SizedBox(width: 16),
                                  itemBuilder: (_, __) => SizedBox(
                                    width: wide ? 284 : 232,
                                    child: const Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        VedroShimmer(aspectRatio: 16 / 9, borderRadius: 12),
                                        SizedBox(height: 10),
                                        VedroShimmer(width: 140, height: 14, borderRadius: 4),
                                        SizedBox(height: 6),
                                        VedroShimmer(width: 96, height: 11, borderRadius: 4),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 34),
                      ],

                      // 2d. Skin-Adaptive Cast & Crew (`circle_medallion` | `portrait_card` | `compact_pill`)
                      if (_item.people.isNotEmpty) ...[
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: padX),
                          child: Row(
                            children: [
                              Text(
                                '演职人员',
                                style: skin.applyHeadlineMood(
                                  TextStyle(
                                    color: skin.fg,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                              ),
                              if (directors.isNotEmpty && !ultraWide) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '导演：${directors.take(2).join(' · ')}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.right,
                                    style: TextStyle(color: skin.fg3, fontSize: 13),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        SmoothHorizontalStrip(
                          height: skin.castStyle == 'portrait_card'
                              ? 242
                              : (skin.castStyle == 'compact_pill' ? 68 : 152),
                          padX: padX,
                          paddleCenterY: skin.castStyle == 'portrait_card'
                              ? 84
                              : (skin.castStyle == 'compact_pill' ? 28 : 48),
                          spacing: skin.castStyle == 'compact_pill' ? 10 : 16,
                          itemCount: _item.people.take(36).length,
                          itemBuilder: (_, idx) {
                            final p = _item.people[idx];
                            final avatarUrl = p.primaryImageTag != null
                                ? widget.appState.buildImageUrl(
                                    p.id,
                                    type: 'Primary',
                                    tag: p.primaryImageTag,
                                    maxWidth: 320,
                                  )
                                : '';
                            final roleLabel = (p.role ?? '').trim().isNotEmpty
                                ? p.role!.trim()
                                : localizePersonRole(p.type);
                            void openPerson() => _openItemDetail(MediaItemModel(
                                  id: p.id,
                                  name: p.name,
                                  type: 'Person',
                                  primaryImageTag: p.primaryImageTag,
                                ));

                            if (skin.castStyle == 'portrait_card') {
                              final cardR = skin.cardRadius.clamp(6.0, 16.0);
                              return RepaintBoundary(
                                child: SizedBox(
                                width: 114,
                                child: PressableScale(
                                  onTap: openPerson,
                                  hoverScale: 1.03,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      AspectRatio(
                                        aspectRatio: 2 / 3,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: skin.surface2,
                                            borderRadius: BorderRadius.circular(cardR),
                                            boxShadow: skin.posterShadow(),
                                          ),
                                          foregroundDecoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(cardR),
                                            border: skin.cardBorder(),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: avatarUrl.isNotEmpty
                                              ? FadeNetworkImage(
                                                  url: avatarUrl,
                                                  cacheWidth: 260,
                                                  alignment: const Alignment(0, -0.3),
                                                  placeholder: GeneratedArt(
                                                    seed: p.id,
                                                    label: p.name,
                                                  ),
                                                )
                                              : GeneratedArt(seed: p.id, label: p.name),
                                        ),
                                      ),
                                      const SizedBox(height: 7),
                                      Text(
                                        p.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: skin.fg,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        roleLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: skin.fg3, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              );
                            }

                            if (skin.castStyle == 'compact_pill') {
                              final pillR = skin.radiusForPill(52);
                              return RepaintBoundary(
                                child: PressableScale(
                                onTap: openPerson,
                                hoverScale: 1.02,
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(7, 6, 14, 6),
                                  decoration: BoxDecoration(
                                    color: skin.panelSurface,
                                    borderRadius: BorderRadius.circular(pillR),
                                    border: skin.cardBorder(),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: skin.surface2,
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: avatarUrl.isNotEmpty
                                            ? FadeNetworkImage(
                                                url: avatarUrl,
                                                cacheWidth: 120,
                                                placeholder: GeneratedArt(
                                                  seed: p.id,
                                                  label: p.name,
                                                ),
                                              )
                                            : GeneratedArt(seed: p.id, label: p.name),
                                      ),
                                      const SizedBox(width: 10),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 140),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              p.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: skin.fg,
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              roleLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(color: skin.fg3, fontSize: 11),
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

                            return RepaintBoundary(
                              child: SizedBox(
                              width: 90,
                              child: PressableScale(
                                onTap: openPerson,
                                hoverScale: 1.04,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 86,
                                      height: 86,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: skin.surface2,
                                        boxShadow: skin.posterShadow(),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: avatarUrl.isNotEmpty
                                          ? FadeNetworkImage(
                                              url: avatarUrl,
                                              cacheWidth: 220,
                                              alignment: const Alignment(0, -0.35),
                                              placeholder: GeneratedArt(
                                                seed: p.id,
                                                label: p.name,
                                              ),
                                            )
                                          : GeneratedArt(seed: p.id, label: p.name),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      p.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: skin.fg,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      roleLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: skin.fg3, fontSize: 11.5),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            );
                          },
                        ),
                        const SizedBox(height: 28),
                      ],

                      // 2e. Chapters Strip
                      if (_item.chapters.isNotEmpty && _item.isPlayable) ...[
                        _ChaptersSection(
                          chapters: _item.chapters,
                          padX: padX,
                          accent: accent,
                          onSelectChapter: (ticks) => _play(
                            _item,
                            sourceId: _activeSource?.id,
                            startPositionTicks: ticks,
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ],
                  ),
                ),

                // 3. BoxSet / Folder Child Items (lazy SliverGrid.builder)
                if ((_item.type == 'BoxSet' || _item.type == 'Folder') &&
                    _collectionItems.isNotEmpty)
                  ..._buildLazyPosterGridSlivers(
                    title: _item.type == 'BoxSet'
                        ? '合集内容 (${_collectionItems.length})'
                        : '文件夹内容 (${_collectionItems.length})',
                    items: _collectionItems,
                    padX: padX,
                    wide: wide,
                    skin: skin,
                  ),

                // 4. Related Recommendations Rail
                if (_similar.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: HorizontalMediaRail(
                        title: '相关推荐',
                        items: _similar,
                        appState: widget.appState,
                        onItemTap: _openItemDetail,
                        onItemQuickPlay: (it) => it.isPlayable ? _play(it) : _openItemDetail(it),
                        onItemLongPress: (it) => showMediaItemContextSheet(
                          context: context,
                          item: it,
                          appState: widget.appState,
                          onOpenDetail: () => _openItemDetail(it),
                          onQuickPlay: it.isPlayable ? () => _play(it) : null,
                        ),
                      ),
                    ),
                  ),

                // 5. Person Filmography (lazy SliverGrid.builder — smooth even for 200+ credits!)
                if (_item.type == 'Person' && _personCredits.isNotEmpty)
                  ..._buildLazyPosterGridSlivers(
                    title: '参与作品 (${_personCredits.length})',
                    items: _personCredits,
                    padX: padX,
                    wide: wide,
                    skin: skin,
                  ),

                if (_loading &&
                    (_item.type == 'Person' ||
                        _item.type == 'BoxSet' ||
                        _item.type == 'Folder'))
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: skin.fg2),
                        ),
                      ),
                    ),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 56)),
              ],
            ),

            // Subtle Top Chrome Scrim so scrolled content melts cleanly under glass buttons
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topSafe + 58,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        skin.canvas.withValues(alpha: skin.isLight ? 0.62 : 0.56),
                        skin.canvas.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Full-width top drag bar on Windows (sits behind the floating Back button)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 58,
              child: WindowsWindowDragArea(),
            ),

            // Floating iOS Glass Top Chrome (Back + Mobile Quick More)
            Positioned(
              top: topSafe + 10,
              left: isMac ? 82 : (padX - 4),
              child: PressableScale(
                onTap: () => Navigator.of(context).pop(),
                hoverScale: 1.05,
                pressScale: 0.92,
                child: GlassSurface(
                  borderRadius: 999,
                  blur: 26,
                  color: skin.glass,
                  borderColor: skin.borderStrong,
                  padding: wide
                      ? const EdgeInsets.symmetric(horizontal: 13, vertical: 7.5)
                      : const EdgeInsets.all(9.5),
                  child: wide
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back_ios_new_rounded, size: 13.5, color: skin.fg),
                            const SizedBox(width: 4),
                            Text(
                              '返回',
                              style: TextStyle(
                                color: skin.fg,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      : Icon(Icons.arrow_back_ios_new_rounded, size: 17, color: skin.fg),
                ),
              ),
            ),
            if (!wide && _item.type != 'Person')
              Positioned(
                top: topSafe + 10,
                right: padX - 4,
                child: PressableScale(
                  onTap: _openMoreSheet,
                  hoverScale: 1.05,
                  pressScale: 0.92,
                  child: GlassSurface(
                    borderRadius: 999,
                    blur: 26,
                    color: skin.glass,
                    borderColor: skin.borderStrong,
                    padding: const EdgeInsets.all(9.5),
                    child: Icon(CupertinoIcons.ellipsis, size: 18, color: skin.fg),
                  ),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }

  List<Widget> _buildLazyPosterGridSlivers({
    required String title,
    required List<MediaItemModel> items,
    required double padX,
    required bool wide,
    required VedroSkin skin,
  }) {
    final metrics = DisplayMetricsProfile.of(context);
    final prefs = widget.appState.prefs;
    final gridGap = prefs.cardGap(wide);
    final effectiveStyle =
        (skin.cardStyle == 'hover_reveal' && metrics.isTouchPrimary)
            ? 'overlay_poster'
            : skin.cardStyle;
    final showBelowCaption = effectiveStyle != 'overlay_poster' &&
        effectiveStyle != 'hover_reveal' &&
        effectiveStyle != 'minimal_clean';
    final textScaler = MediaQuery.textScalerOf(context);
    final screenW = MediaQuery.sizeOf(context).width;
    final availW = (screenW - padX * 2).clamp(140.0, 8000.0);
    final gridLayout = PosterCardLayout.forGrid(
      profile: metrics,
      availableWidth: availW,
      density: prefs.listDensity,
      scale: prefs.posterScale,
      aspectRatio: 2 / 3,
      showBelowCaption: showBelowCaption,
      crossSpacing: gridGap,
      textScaler: textScaler,
    );
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(padX, 0, padX, 16),
          child: Text(
            title,
            style: skin.applyHeadlineMood(
              TextStyle(
                color: skin.fg,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(padX, 0, padX, 28),
        sliver: SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: gridLayout.columns,
            mainAxisSpacing: gridLayout.mainSpacing,
            crossAxisSpacing: gridLayout.crossSpacing,
            mainAxisExtent: gridLayout.cardHeight,
          ),
          itemCount: items.length,
          itemBuilder: (_, idx) {
            final c = items[idx];
            return MediaCard(
              item: c,
              appState: widget.appState,
              width: gridLayout.cardWidth,
              onTap: () => _openItemDetail(c),
              onQuickPlay: c.isPlayable ? () => _play(c) : null,
              onLongPress: () => showMediaItemContextSheet(
                context: context,
                item: c,
                appState: widget.appState,
                onOpenDetail: () => _openItemDetail(c),
                onQuickPlay: c.isPlayable ? () => _play(c) : null,
              ),
            );
          },
        ),
      ),
    ];
  }
}
