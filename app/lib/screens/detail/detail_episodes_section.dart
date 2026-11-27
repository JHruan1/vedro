part of '../detail_screen.dart';

/// Series season selector, range tabs & episode grid/list section.
extension _DetailEpisodesSectionExt on _DetailScreenState {
  /// Scalable Apple TV+ Season & Episode Picker supporting everything from 6-episode miniseries
  /// to 2,000+ episode anime (borderless capsules + full-bleed 16:9 stills + clean number keypad).
  Widget _buildEpisodeSection({
    required bool wide,
    required double padX,
    required Color accent,
    required MediaItemModel? nextEpToPlay,
  }) {
    final skin = VedroSkin.of(context);
    final activeSeason = _activeSeason;
    final rawSeasonOverview = activeSeason?.cleanOverview ?? '';
    // Hide season overview when it merely duplicates the series overview right above!
    final seasonOverview = (rawSeasonOverview.isNotEmpty &&
            rawSeasonOverview.trim() != _item.cleanOverview.trim())
        ? rawSeasonOverview
        : '';

    final ordered = _episodeDescending ? _episodes.reversed.toList() : _episodes;
    final query = _episodeFilterQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? ordered
        : ordered.where((ep) {
            final numStr = '${ep.indexNumber ?? ''}';
            final codeStr = (ep.episodeCode ?? '').toLowerCase();
            return numStr == query ||
                numStr.contains(query) ||
                codeStr.contains(query) ||
                ep.displayName.toLowerCase().contains(query) ||
                ep.cleanOverview.toLowerCase().contains(query);
          }).toList();

    final chunkSize = filtered.length >= 400 ? 100 : 50;
    final rangeCount = filtered.isEmpty ? 0 : ((filtered.length - 1) ~/ chunkSize) + 1;
    final safeRangeIdx = rangeCount == 0 ? 0 : _episodeRangeIndex.clamp(0, rangeCount - 1);
    final rangeStart = safeRangeIdx * chunkSize;
    final rangeEnd = (rangeStart + chunkSize).clamp(0, filtered.length);
    final visibleEps =
        (query.isEmpty && rangeCount > 1) ? filtered.sublist(rangeStart, rangeEnd) : filtered;
    final searchActive = _episodeSearchOpen || _episodeFilterQuery.isNotEmpty;
    final canBatchDownload = widget.appState.canDownloadItem(_resolveDownloadTarget());

    final pillBg = skin.isLight
        ? Colors.black.withValues(alpha: 0.055)
        : Colors.white.withValues(alpha: 0.09);
    final pillBorder = skin.isLight
        ? Border.all(color: skin.border, width: 0.7)
        : Border.all(color: Colors.white.withValues(alpha: 0.12), width: 0.75);

    Widget buildToolCircle({
      Key? key,
      required IconData icon,
      required String tooltip,
      required VoidCallback onTap,
      bool highlighted = false,
      String? wideLabel,
    }) {
      return Tooltip(
        message: tooltip,
        child: PressableScale(
          key: key,
          onTap: onTap,
          hoverScale: 1.03,
          pressScale: 0.94,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 34,
            width: wideLabel != null ? null : 34,
            padding: wideLabel != null
                ? const EdgeInsets.symmetric(horizontal: 11)
                : EdgeInsets.zero,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: highlighted
                  ? skin.accent.withValues(alpha: skin.isLight ? 0.14 : 0.22)
                  : pillBg,
              borderRadius: BorderRadius.circular(999),
              border: highlighted
                  ? Border.all(color: skin.accent.withValues(alpha: 0.55), width: 0.9)
                  : pillBorder,
            ),
            child: wideLabel != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 14, color: highlighted ? skin.accent : skin.fg2),
                      const SizedBox(width: 5),
                      Text(
                        wideLabel,
                        style: TextStyle(
                          color: highlighted ? skin.accent : skin.fg,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  )
                : Icon(icon, size: 15.5, color: highlighted ? skin.accent : skin.fg2),
          ),
        ),
      );
    }

    final viewModeLabel = switch (_episodeViewMode) {
      'grid' => '宫格',
      'cards' => '剧照',
      _ => '列表',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: padX),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Responsive iOS Header: Season Picker + Uniform 34px Controls (wraps cleanly on 360px phones)
              LayoutBuilder(
                builder: (context, headerConstraints) {
                  final seasonSelector = _seasons.length > 1
                      ? VedroPullDownButton<String>(
                          key: const ValueKey('detail-season-dropdown'),
                          height: 34,
                          displayLabelOverride:
                              '${activeSeason?.name ?? _seasons.first.name} · ${_episodes.length} 集',
                          value: _selectedSeasonId ?? _seasons.first.id,
                          items: _seasons
                              .map(
                                (s) => VedroDropdownItem<String>(
                                  value: s.id,
                                  label: s.name,
                                  subtitle: s.childCount != null && s.childCount! > 0
                                      ? '共 ${s.childCount} 集'
                                      : null,
                                  itemKey: ValueKey('season-option-${s.id}'),
                                ),
                              )
                              .toList(),
                          onChanged: _loadEpisodes,
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Flexible(
                              child: Text(
                                _seasons.first.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: skin.applyHeadlineMood(
                                  TextStyle(
                                    color: skin.fg,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '共 ${_episodes.length} 集',
                              style: TextStyle(
                                color: skin.fg3,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        );
                  final controls = Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (_episodes.length > 12)
                        buildToolCircle(
                          key: const ValueKey('detail-episode-search-toggle'),
                          icon: CupertinoIcons.search,
                          tooltip: '搜集名 / 跳集',
                          highlighted: searchActive,
                          onTap: () {
                            _setDetailState(() {
                              if (searchActive) {
                                _episodeSearchOpen = false;
                                _episodeJumpCtrl.clear();
                                _episodeFilterQuery = '';
                              } else {
                                _episodeSearchOpen = true;
                              }
                            });
                            if (_episodeSearchOpen) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) _episodeSearchFocus.requestFocus();
                              });
                            }
                          },
                        ),
                      buildToolCircle(
                        key: const ValueKey('detail-episode-sort-btn'),
                        icon: CupertinoIcons.arrow_up_arrow_down,
                        tooltip: _episodeDescending ? '当前倒序（点击切正序）' : '当前正序（点击切倒序）',
                        highlighted: _episodeDescending,
                        wideLabel: wide ? (_episodeDescending ? '倒序' : '正序') : null,
                        onTap: () => _setDetailState(() {
                          _episodeDescending = !_episodeDescending;
                          _episodeRangeIndex = 0;
                        }),
                      ),
                      if (canBatchDownload)
                        buildToolCircle(
                          key: const ValueKey('detail-batch-download-btn'),
                          icon: CupertinoIcons.arrow_down_to_line,
                          tooltip: '批量下载选集',
                          wideLabel: wide ? '批量下载' : null,
                          onTap: _openBatchDownloadDialog,
                        ),
                      VedroPullDownButton<String>(
                        key: const ValueKey('detail-episode-view-dropdown'),
                        height: 34,
                        displayLabelOverride: viewModeLabel,
                        value: _episodeViewMode,
                        items: const [
                          VedroDropdownItem(value: 'list', label: '列表视图'),
                          VedroDropdownItem(value: 'cards', label: '横向剧照'),
                          VedroDropdownItem(value: 'grid', label: '选集宫格'),
                        ],
                        onChanged: (mode) => _setDetailState(() {
                          _episodeViewMode = mode;
                          _episodeModeUserChosen = true;
                        }),
                      ),
                    ],
                  );
                  if (headerConstraints.maxWidth < 300) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        seasonSelector,
                        const SizedBox(height: 8),
                        controls,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: seasonSelector,
                        ),
                      ),
                      const SizedBox(width: 8),
                      controls,
                    ],
                  );
                },
              ),

              // Expandable Full-Width iOS Search Bar (Never truncates range pills!)
              AnimatedSize(
                duration: const Duration(milliseconds: 190),
                curve: VedroTheme.easeOut,
                child: searchActive
                    ? Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 36,
                                child: TextField(
                                  controller: _episodeJumpCtrl,
                                  focusNode: _episodeSearchFocus,
                                  onChanged: (v) => _setDetailState(() {
                                    _episodeFilterQuery = v;
                                    _episodeRangeIndex = 0;
                                  }),
                                  style: TextStyle(color: skin.fg, fontSize: 13.5),
                                  decoration: InputDecoration(
                                    hintText: '输入集数或分集标题定位…',
                                    hintStyle: TextStyle(color: skin.fg3, fontSize: 13),
                                    prefixIcon:
                                        Icon(CupertinoIcons.search, size: 16, color: skin.fg3),
                                    prefixIconConstraints: const BoxConstraints(minWidth: 36),
                                    suffixIcon: _episodeFilterQuery.isNotEmpty
                                        ? IconButton(
                                            padding: EdgeInsets.zero,
                                            icon: Icon(
                                              CupertinoIcons.clear_circled_solid,
                                              size: 16,
                                              color: skin.fg3,
                                            ),
                                            onPressed: () {
                                              _episodeJumpCtrl.clear();
                                              _setDetailState(() => _episodeFilterQuery = '');
                                            },
                                          )
                                        : null,
                                    contentPadding:
                                        const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                    filled: true,
                                    fillColor: pillBg,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(999),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(999),
                                      borderSide: BorderSide(
                                        color: skin.isLight
                                            ? skin.border
                                            : Colors.white.withValues(alpha: 0.12),
                                        width: 0.75,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(999),
                                      borderSide: BorderSide(color: skin.accent, width: 1.1),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            PressableScale(
                              onTap: () {
                                _episodeJumpCtrl.clear();
                                _episodeSearchFocus.unfocus();
                                _setDetailState(() {
                                  _episodeFilterQuery = '';
                                  _episodeSearchOpen = false;
                                });
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                child: Text(
                                  '取消',
                                  style: TextStyle(
                                    color: skin.accent,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              if (seasonOverview.isNotEmpty) ...[
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Text(
                    seasonOverview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: skin.fg2,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Full-Width Edge-to-Edge Episode Range Strip (Zero Clipping!)
        if (rangeCount > 1 && query.isEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 32,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: ListView.separated(
                padding: EdgeInsets.symmetric(horizontal: padX),
                scrollDirection: Axis.horizontal,
                itemCount: rangeCount,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, rIdx) {
                  final rStart = rIdx * chunkSize;
                  final rEnd = (rStart + chunkSize).clamp(0, filtered.length);
                  final firstNum = filtered[rStart].indexNumber ?? (rStart + 1);
                  final lastNum = filtered[rEnd - 1].indexNumber ?? rEnd;
                  final active = rIdx == safeRangeIdx;
                  return PressableScale(
                    onTap: () => _setDetailState(() => _episodeRangeIndex = rIdx),
                    borderRadius: BorderRadius.circular(999),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: active ? skin.activePillBg : pillBg,
                        borderRadius: BorderRadius.circular(999),
                        border: active ? null : pillBorder,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$firstNum-$lastNum',
                        style: TextStyle(
                          color: active ? skin.activePillFg : skin.fg2,
                          fontSize: 12,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],

        const SizedBox(height: 14),

        if (visibleEps.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: padX, vertical: 20),
            child: Text('没有匹配的分集', style: TextStyle(color: skin.fg3, fontSize: 13)),
          )
        else if (_episodeViewMode == 'grid')
          Padding(
            padding: EdgeInsets.symmetric(horizontal: padX),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tileW = wide ? 86.0 : 62.0;
                final cols = (constraints.maxWidth / (tileW + 8)).floor().clamp(4, 14);
                const gap = 8.0;
                final actualW = (constraints.maxWidth - gap * (cols - 1)) / cols;
                final tileR = skin.cardRadius.clamp(6.0, 12.0);
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: visibleEps.map((ep) {
                    final isNext = nextEpToPlay?.id == ep.id;
                    final hasProg = ep.resumeProgress > 0.01;
                    final epNum = ep.indexNumber != null ? '${ep.indexNumber}' : ep.displayName;
                    final tip = [
                      '${ep.episodeCode ?? 'E$epNum'} ${ep.displayName}',
                      if (fmtDurationTicks(ep.runTimeTicks).isNotEmpty)
                        fmtDurationTicks(ep.runTimeTicks),
                      if (fmtIsoDate(ep.premiereDate).isNotEmpty) fmtIsoDate(ep.premiereDate),
                      if (ep.versionCount > 1) '${ep.versionCount} 版本（右键/长按选版本）',
                    ].join(' · ');
                    return Tooltip(
                      message: tip,
                      child: PressableScale(
                        onTap: () => _play(ep, sourceId: _matchingSourceIdForEpisode(ep)),
                        onLongPress: ep.versionCount > 1
                            ? () => _openEpisodeVersionSheet(ep)
                            : () => _openItemDetail(ep),
                        onSecondaryTap: ep.versionCount > 1
                            ? () => _openEpisodeVersionSheet(ep)
                            : () => _openItemDetail(ep),
                        hoverScale: 1.04,
                        pressScale: 0.94,
                        child: Container(
                          width: actualW,
                          height: wide ? 46 : 42,
                          decoration: BoxDecoration(
                            color: isNext
                                ? skin.activePillBg
                                : (ep.played
                                    ? skin.surface.withValues(alpha: 0.65)
                                    : skin.surface),
                            borderRadius: BorderRadius.circular(tileR),
                            border: isNext ? null : skin.cardBorder(),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            children: [
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(
                                    epNum,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isNext
                                          ? skin.activePillFg
                                          : (ep.played ? skin.fg3 : skin.fg),
                                      fontSize: wide ? 14 : 13,
                                      fontWeight: isNext ? FontWeight.w700 : FontWeight.w600,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ),
                              ),
                              if (ep.played && !isNext)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Icon(Icons.check_rounded, size: 11, color: skin.fg3),
                                )
                              else if (widget.appState.prefs.showMultiVersionBadge &&
                                  ep.versionCount > 1)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Icon(
                                    Icons.layers_outlined,
                                    size: 10.5,
                                    color: isNext ? skin.activePillFg : skin.fg3,
                                  ),
                                ),
                              if (hasProg)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  height: 3,
                                  child: LinearProgressIndicator(
                                    value: ep.resumeProgress,
                                    backgroundColor: Colors.transparent,
                                    color: isNext ? skin.activePillFg : accent,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          )
        else if (_episodeViewMode == 'cards')
          SmoothHorizontalStrip(
            height: wide ? 298 : 258,
            padX: padX,
            paddleCenterY: (wide ? 284 : 232) / (16 / 9) / 2 + 10,
            spacing: 16,
            itemCount: visibleEps.length,
            itemBuilder: (_, idx) {
              final ep = visibleEps[idx];
              final season = _activeSeason;
              final fallback = (season != null &&
                      widget.appState.wideArt(season) != null &&
                      widget.appState.wideArt(_item)?.isPoster != false)
                  ? season
                  : _item;
              return _EpisodeHorizontalCard(
                episode: ep,
                seriesFallback: fallback,
                appState: widget.appState,
                width: wide ? 284 : 232,
                accent: accent,
                onTap: () => _play(ep, sourceId: _matchingSourceIdForEpisode(ep)),
                onOpenDetail: () => _openItemDetail(ep),
                onPickVersion: ep.versionCount > 1 ? () => _openEpisodeVersionSheet(ep) : null,
              );
            },
          )
        else
          Padding(
            padding: EdgeInsets.symmetric(horizontal: padX),
            child: Column(
              children: visibleEps.map((ep) {
                final season = _activeSeason;
                final fallback = (season != null &&
                        widget.appState.wideArt(season) != null &&
                        widget.appState.wideArt(_item)?.isPoster != false)
                    ? season
                    : _item;
                return _EpisodeRow(
                  episode: ep,
                  seriesFallback: fallback,
                  appState: widget.appState,
                  onTap: () => _play(ep, sourceId: _matchingSourceIdForEpisode(ep)),
                  onOpenDetail: () => _openItemDetail(ep),
                  onPickVersion:
                      ep.versionCount > 1 ? () => _openEpisodeVersionSheet(ep) : null,
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
