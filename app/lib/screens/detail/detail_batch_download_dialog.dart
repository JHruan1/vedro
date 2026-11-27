part of '../detail_screen.dart';

/// Scalable Multi-Episode & Multi-Version Batch Download Picker (strictly single-selects version by index!).
class _BatchDownloadDialog extends StatefulWidget {
  const _BatchDownloadDialog({
    required this.series,
    required this.seasons,
    required this.initialSeasonId,
    required this.initialEpisodes,
    required this.initialVersionIndex,
    required this.appState,
  });

  final MediaItemModel series;
  final List<MediaItemModel> seasons;
  final String? initialSeasonId;
  final List<MediaItemModel> initialEpisodes;
  final int initialVersionIndex;
  final VedroAppState appState;

  @override
  State<_BatchDownloadDialog> createState() => _BatchDownloadDialogState();
}

class _BatchDownloadDialogState extends State<_BatchDownloadDialog> {
  String? _seasonId;
  late List<MediaItemModel> _episodes;
  final Map<String, List<MediaItemModel>> _seasonCache = {};
  final Map<String, MediaItemModel> _selectedById = {};
  int _versionIndex = 0;
  int _rangeIdx = 0;
  bool _loadingSeason = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _seasonId = widget.initialSeasonId;
    _episodes = List<MediaItemModel>.from(widget.initialEpisodes);
    if (_seasonId != null) {
      _seasonCache[_seasonId!] = _episodes;
    }
    _versionIndex = widget.initialVersionIndex;
    _ensureDefaultVersion();
  }

  List<ResolvedMediaVersion> get _availableVersions {
    List<MediaSourceModel> best = const [];
    for (final ep in _episodes) {
      if (ep.mediaSources.length > best.length) {
        best = ep.mediaSources;
      }
    }
    return MediaSourceModel.resolveVersions(best, stripEpisodePrefix: true);
  }

  void _ensureDefaultVersion() {
    final vers = _availableVersions;
    if (vers.isEmpty) {
      _versionIndex = 0;
      return;
    }
    if (_versionIndex < 0 || _versionIndex >= vers.length) {
      _versionIndex = 0;
    }
  }

  MediaSourceModel? _resolveSourceFor(MediaItemModel ep) {
    if (ep.mediaSources.isEmpty) return null;
    if (ep.mediaSources.length == 1) return ep.mediaSources.first;
    final vers = _availableVersions;
    if (vers.isEmpty) return ep.mediaSources.first;
    final chosen = vers[_versionIndex.clamp(0, vers.length - 1)];
    final epVers = MediaSourceModel.resolveVersions(ep.mediaSources);
    for (final ev in epVers) {
      if (ev.seriesMatchSignature == chosen.seriesMatchSignature) return ev.source;
    }
    return ep.mediaSources[_versionIndex.clamp(0, ep.mediaSources.length - 1)];
  }

  Future<void> _selectSeason(String seasonId) async {
    if (seasonId == _seasonId) return;
    setState(() {
      _seasonId = seasonId;
      _rangeIdx = 0;
    });
    if (_seasonCache.containsKey(seasonId)) {
      setState(() {
        _episodes = _seasonCache[seasonId]!;
        _ensureDefaultVersion();
      });
      return;
    }
    setState(() => _loadingSeason = true);
    try {
      final eRes = await widget.appState.core.invoke('get_episodes', {
        'series_id': widget.series.id,
        'season_id': seasonId,
        'limit': 5000,
      }) as Map<String, dynamic>;
      final loaded = ((eRes['Items'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MediaItemModel.fromJson)
          .toList();
      _seasonCache[seasonId] = loaded;
      if (mounted && _seasonId == seasonId) {
        setState(() {
          _episodes = loaded;
          _ensureDefaultVersion();
        });
      }
    } catch (e) {
      if (mounted && _seasonId == seasonId) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载分集失败：${VedroErrorFormatter.friendly(e)}')),
        );
      }
    } finally {
      if (mounted && _seasonId == seasonId) setState(() => _loadingSeason = false);
    }
  }

  bool _isAlreadyQueuedOrDone(MediaItemModel ep) {
    final src = _resolveSourceFor(ep);
    final existing = widget.appState.findDownloadForItem(ep.id, mediaSourceId: src?.id);
    return existing != null && (existing.status == 'completed' || existing.isActive);
  }

  int get _selectedTotalBytes {
    var total = 0;
    for (final ep in _selectedById.values) {
      total += _resolveSourceFor(ep)?.size ?? 0;
    }
    return total;
  }

  Future<void> _submit() async {
    if (_selectedById.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final ordered = _selectedById.values.toList()
        ..sort((a, b) {
          final sa = a.parentIndexNumber ?? 0;
          final sb = b.parentIndexNumber ?? 0;
          if (sa != sb) return sa.compareTo(sb);
          return (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0);
        });
      final vers = _availableVersions;
      final chosenLabel = vers.isNotEmpty
          ? vers[_versionIndex.clamp(0, vers.length - 1)].displayTitle
          : null;
      final batch = ordered.map((ep) {
        final src = _resolveSourceFor(ep);
        return (
          item: ep,
          mediaSourceId: src?.id,
          versionLabel: chosenLabel ?? src?.name ?? src?.container?.toUpperCase(),
          expectedBytes: src?.size,
        );
      }).toList();

      final added = await widget.appState.enqueueBatchDownloads(batch);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            added > 0
                ? '已加入下载队列：$added 集（支持 HTTP Range 断点续传，设置 → 下载与缓存）'
                : '所选剧集已在下载队列或已缓存',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF991B1B),
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
            style: const TextStyle(color: Colors.white),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final versions = _availableVersions;
    final safeVerIdx = versions.isEmpty ? 0 : _versionIndex.clamp(0, versions.length - 1);
    final totalBytes = _selectedTotalBytes;

    final chunkSize = _episodes.length >= 400 ? 100 : 50;
    final rangeCount = _episodes.isEmpty ? 0 : ((_episodes.length - 1) ~/ chunkSize) + 1;
    final safeRangeIdx = rangeCount == 0 ? 0 : _rangeIdx.clamp(0, rangeCount - 1);
    final start = safeRangeIdx * chunkSize;
    final end = (start + chunkSize).clamp(0, _episodes.length);
    final visibleEps = rangeCount > 1 ? _episodes.sublist(start, end) : _episodes;

    return Dialog(
      key: const ValueKey('detail-batch-download-dialog'),
      backgroundColor: skin.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(skin.cardRadius.clamp(12.0, 22.0)),
        side: BorderSide(color: skin.borderStrong, width: 0.9),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: (MediaQuery.sizeOf(context).height * 0.86).clamp(360.0, 720.0),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                children: [
                  Icon(Icons.arrow_downward_rounded, size: 19, color: skin.fg),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '选择下载剧集与版本 · ${widget.series.displayName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: skin.fg,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: skin.fg2),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            Expanded(
              child: CustomScrollView(
                slivers: [
                  if (widget.seasons.length > 1)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          itemCount: widget.seasons.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, idx) {
                            final s = widget.seasons[idx];
                            final active = s.id == _seasonId;
                            return PressableScale(
                              onTap: () => _selectSeason(s.id),
                              borderRadius: BorderRadius.circular(skin.radiusForPill(36)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: active ? skin.activePillBg : skin.surface2,
                                  borderRadius: BorderRadius.circular(skin.radiusForPill(36)),
                                ),
                                child: Text(
                                  s.name,
                                  style: TextStyle(
                                    color: active ? skin.activePillFg : skin.fg2,
                                    fontSize: 12.5,
                                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                  if (versions.length > 1)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '下载版本 (${versions.length})',
                              style: TextStyle(color: skin.fg3, fontSize: 11.5, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                for (var i = 0; i < versions.length; i++)
                                  PressableScale(
                                    onTap: () => setState(() => _versionIndex = i),
                                    borderRadius: BorderRadius.circular(skin.radiusForPill(30)),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
                                      decoration: BoxDecoration(
                                        color: i == safeVerIdx ? skin.activePillBg : skin.surface2,
                                        borderRadius: BorderRadius.circular(skin.radiusForPill(30)),
                                      ),
                                      child: Text(
                                        versions[i].displayTitle,
                                        style: TextStyle(
                                          color: i == safeVerIdx ? skin.activePillFg : skin.fg2,
                                          fontSize: 12,
                                          fontWeight: i == safeVerIdx ? FontWeight.w600 : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                      child: Row(
                        children: [
                          if (rangeCount > 1)
                            Expanded(
                              child: SizedBox(
                                height: 30,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: rangeCount,
                                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                                  itemBuilder: (_, rIdx) {
                                    final rStart = rIdx * chunkSize;
                                    final rEnd = (rStart + chunkSize).clamp(0, _episodes.length);
                                    final firstNum = _episodes[rStart].indexNumber ?? (rStart + 1);
                                    final lastNum = _episodes[rEnd - 1].indexNumber ?? rEnd;
                                    final active = rIdx == safeRangeIdx;
                                    return PressableScale(
                                      onTap: () => setState(() => _rangeIdx = rIdx),
                                      borderRadius: BorderRadius.circular(skin.radiusForPill(28)),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: active ? skin.activePillBg : skin.surface2,
                                          borderRadius: BorderRadius.circular(skin.radiusForPill(28)),
                                        ),
                                        child: Text(
                                          '$firstNum-$lastNum',
                                          style: TextStyle(
                                            color: active ? skin.activePillFg : skin.fg2,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            )
                          else
                            const Spacer(),
                          const SizedBox(width: 8),
                          TextButton(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: skin.fg,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: () {
                              setState(() {
                                for (final ep in visibleEps) {
                                  if (!_isAlreadyQueuedOrDone(ep)) {
                                    _selectedById[ep.id] = ep;
                                  }
                                }
                              });
                            },
                            child: Text(rangeCount > 1 ? '全选本段' : '全选', style: const TextStyle(fontSize: 12)),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: skin.fg2,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: () {
                              setState(() {
                                for (final ep in visibleEps) {
                                  if (!ep.played && !_isAlreadyQueuedOrDone(ep)) {
                                    _selectedById[ep.id] = ep;
                                  }
                                }
                              });
                            },
                            child: const Text('选未看', style: TextStyle(fontSize: 12)),
                          ),
                          if (_selectedById.isNotEmpty)
                            TextButton(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: skin.fg3,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: () => setState(() => _selectedById.clear()),
                              child: const Text('清空', style: TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                  ),

                  if (_loadingSeason)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2, color: skin.fg2),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      sliver: SliverList.separated(
                        itemCount: visibleEps.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, idx) {
                          final ep = visibleEps[idx];
                          final src = _resolveSourceFor(ep);
                          final existing =
                              widget.appState.findDownloadForItem(ep.id, mediaSourceId: src?.id);
                          final done = existing != null && existing.status == 'completed';
                          final active = existing != null && existing.isActive;
                          final disabled = done || active;
                          final checked = _selectedById.containsKey(ep.id);
                          final sizeText = fmtFileSize(src?.size);

                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: disabled
                                ? null
                                : () {
                                    setState(() {
                                      if (checked) {
                                        _selectedById.remove(ep.id);
                                      } else {
                                        _selectedById[ep.id] = ep;
                                      }
                                    });
                                  },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10.5),
                              decoration: BoxDecoration(
                                color: checked ? skin.surface3 : skin.surface2,
                                borderRadius: BorderRadius.circular(skin.cardRadius.clamp(6.0, 12.0)),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    done
                                        ? Icons.check_circle_rounded
                                        : (checked
                                            ? Icons.check_circle_rounded
                                            : Icons.radio_button_unchecked_rounded),
                                    size: 19,
                                    color: done
                                        ? const Color(0xFF10B981)
                                        : (checked ? skin.accent : skin.fg3),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${ep.episodeCode ?? 'E${ep.indexNumber ?? idx + 1}'} · ${ep.displayName}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: disabled ? skin.fg3 : skin.fg,
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        if (src != null && (src.name?.isNotEmpty == true))
                                          Text(
                                            src.name!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(color: skin.fg3, fontSize: 11),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (done)
                                    const Text(
                                      '已下载',
                                      style: TextStyle(
                                        color: Color(0xFF10B981),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  else if (active)
                                    Text(
                                      '队列中',
                                      style: TextStyle(
                                        color: skin.accent,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  else if (sizeText.isNotEmpty)
                                    Text(
                                      sizeText,
                                      style: TextStyle(
                                        color: skin.fg2,
                                        fontSize: 12,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedById.isEmpty
                          ? '请勾选需要下载的剧集'
                          : '已选 ${_selectedById.length} 集${totalBytes > 0 ? ' · 共 ${fmtQuotaBytes(totalBytes)}' : ''}',
                      style: TextStyle(
                        color: skin.fg,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: skin.primaryCtaBg,
                      foregroundColor: skin.primaryCtaFg,
                      disabledBackgroundColor: skin.surface3,
                      disabledForegroundColor: skin.fg3,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(skin.radiusForPill(42)),
                      ),
                    ),
                    onPressed: (_selectedById.isEmpty || _submitting)
                        ? null
                        : _submit,
                    child: Text(
                      _submitting
                          ? '提交中…'
                          : '开始下载${_selectedById.isNotEmpty ? ' (${_selectedById.length})' : ''}',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
