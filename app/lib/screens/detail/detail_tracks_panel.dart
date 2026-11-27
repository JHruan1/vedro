part of '../detail_screen.dart';

/// Unified iOS-Caliber Pull-Down Selector Bar (`下拉框`) for Version, Audio, and Subtitle on `DetailScreen`.
/// - Strictly single-selects version by integer index (never highlights >1 version even when 4+ share Name/Id)
/// - Passively reflects version-specific tracks & filename traits with ZERO cloud-drive API probes
/// - Adapts cleanly to 320px–430px portrait phones (stacked full-width Version + 2-column Audio/Subtitle) and wide desktops.
class _TracksPanel extends StatelessWidget {
  const _TracksPanel({
    required this.isSeries,
    this.isLoading = false,
    this.expectedVersionCount = 1,
    required this.versions,
    required this.selectedVersionIndex,
    required this.activeStreamSource,
    this.hasKnownEmbeddedStreams = false,
    required this.selectedAudioIndex,
    required this.selectedSubtitleIndex,
    this.preferredAudioLangOverride,
    this.preferredSubLangOverride,
    required this.localExternalSubPath,
    required this.appState,
    required this.onSelectVersionIndex,
    required this.onSelectAudio,
    required this.onSelectSubtitle,
    required this.onSelectVersionAudioLang,
    required this.onSelectVersionSubLang,
    required this.onPickExternalSubtitle,
    required this.onClearExternalSubtitle,
  });

  final bool isSeries;
  final bool isLoading;
  final int expectedVersionCount;
  final List<ResolvedMediaVersion> versions;
  final int selectedVersionIndex;
  final MediaSourceModel? activeStreamSource;
  final bool hasKnownEmbeddedStreams;
  final int? selectedAudioIndex;
  final int? selectedSubtitleIndex;
  final String? preferredAudioLangOverride;
  final String? preferredSubLangOverride;
  final String? localExternalSubPath;
  final VedroAppState appState;
  final ValueChanged<int> onSelectVersionIndex;
  final ValueChanged<int?> onSelectAudio;
  final ValueChanged<int?> onSelectSubtitle;
  final ValueChanged<String> onSelectVersionAudioLang;
  final ValueChanged<String> onSelectVersionSubLang;
  final VoidCallback onPickExternalSubtitle;
  final VoidCallback onClearExternalSubtitle;

  String? _inferPassiveAudioTrait(MediaSourceModel? src, ResolvedMediaVersion? ver) {
    if (src == null) return null;
    final raw = '${ver?.displayTitle ?? ''} ${ver?.folderBadge ?? ''} ${src.name ?? ''} ${src.path ?? ''}'
        .toLowerCase();
    if (raw.contains('国粤英')) return '国粤英多音轨';
    if (raw.contains('国粤') || (raw.contains('mandarin') && raw.contains('cantonese'))) {
      return '国粤双语';
    }
    if (raw.contains('国英')) return '国英双语';
    if (raw.contains('台配') || raw.contains('国配') || raw.contains('国语')) return '国语配音';
    if (raw.contains('粤语') || raw.contains('粤配') || raw.contains('cantonese')) return '粤语配音';
    if (raw.contains('日语音轨') || raw.contains('双语') || raw.contains('dual')) return '多音轨封装';
    return null;
  }

  String? _inferPassiveSubtitleTrait(MediaSourceModel? src, ResolvedMediaVersion? ver) {
    if (src == null) return null;
    final raw = '${ver?.displayTitle ?? ''} ${ver?.folderBadge ?? ''} ${src.name ?? ''} ${src.path ?? ''}'
        .toLowerCase();
    if (raw.contains('特效') || raw.contains('ass')) return 'ASS 特效字幕';
    if (raw.contains('简繁英') || raw.contains('中英')) return '中英双语字幕';
    if (raw.contains('简繁') || raw.contains('chs') || raw.contains('cht')) return '内封中文字幕';
    if (raw.contains('sup') || raw.contains('pgs')) return '原盘图形字幕';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final safeVerIdx = versions.isEmpty
        ? 0
        : selectedVersionIndex.clamp(0, versions.length - 1);
    final activeVer = versions.isNotEmpty ? versions[safeVerIdx] : null;
    final streamSrc = activeStreamSource ?? activeVer?.source;
    final audios = streamSrc?.audioStreams ?? const <MediaStreamModel>[];
    final subs = streamSrc?.subtitleStreams ?? const <MediaStreamModel>[];
    final passiveAudio = _inferPassiveAudioTrait(streamSrc, activeVer);
    final passiveSub = _inferPassiveSubtitleTrait(streamSrc, activeVer);
    final extFileName = localExternalSubPath?.trim().isNotEmpty == true
        ? localExternalSubPath!.replaceAll('\\', '/').split('/').last
        : null;
    final hasAnyRealTracks =
        audios.isNotEmpty || subs.isNotEmpty || hasKnownEmbeddedStreams || extFileName != null;

    if (isLoading && versions.isEmpty) {
      if (isSeries && expectedVersionCount <= 1) {
        return const SizedBox.shrink();
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final compactMobile = constraints.maxWidth < 560;
          if (compactMobile) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const VedroShimmer(height: 36, borderRadius: 999),
                if (!isSeries) ...[
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Expanded(child: VedroShimmer(height: 36, borderRadius: 999)),
                      SizedBox(width: 8),
                      Expanded(child: VedroShimmer(height: 36, borderRadius: 999)),
                    ],
                  ),
                ],
              ],
            );
          }
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              const VedroShimmer(width: 168, height: 36, borderRadius: 999),
              if (!isSeries) ...[
                const VedroShimmer(width: 142, height: 36, borderRadius: 999),
                const VedroShimmer(width: 142, height: 36, borderRadius: 999),
              ],
            ],
          );
        },
      );
    }

    if (versions.length <= 1 && isSeries && !hasAnyRealTracks) {
      return const SizedBox.shrink();
    }

    final showVersionDropdown = versions.length > 1 || (!isSeries && versions.isNotEmpty);
    final showTrackDropdowns = !isSeries || hasAnyRealTracks;

    // 1. Version Pull-Down Items
    final versionItems = <VedroDropdownItem<int>>[
      for (var i = 0; i < versions.length; i++)
        () {
          final v = versions[i];
          final src = v.source;
          final video = src.videoStreams.isNotEmpty ? src.videoStreams.first : null;
          final res = video?.height != null
              ? (video!.height! >= 2160 ? '4K' : '${video.height}p')
              : '';
          final sz = fmtFileSize(src.size);
          final cont = (src.container ?? '').trim().toUpperCase();
          final sub = <String>[
            if (res.isNotEmpty && !v.displayTitle.toUpperCase().contains(res)) res,
            if (sz.isNotEmpty) sz,
            if (cont.isNotEmpty) cont,
          ].join(' · ');
          return VedroDropdownItem<int>(
            value: i,
            label: v.displayTitle,
            subtitle: sub.isEmpty ? null : sub,
            itemKey: ValueKey('${isSeries ? 'series' : 'movie'}-version-item-$i'),
          );
        }(),
    ];

    // 2. Audio Pull-Down Items & Active Label
    String audioButtonLabel = passiveAudio ?? '默认音轨';
    if (selectedAudioIndex != null) {
      final match = audios.where((a) => a.index == selectedAudioIndex);
      if (match.isNotEmpty) audioButtonLabel = match.first.label;
    } else if (audios.isNotEmpty) {
      audioButtonLabel = audios.first.label;
    }

    final audioItems = <VedroDropdownItem<int?>>[
      VedroDropdownItem<int?>(
        value: null,
        label: '默认音轨',
        subtitle: audios.isNotEmpty ? audios.first.detailedSpec : passiveAudio,
        itemKey: const ValueKey('detail-audio-default-item'),
      ),
      for (final a in audios)
        VedroDropdownItem<int?>(
          value: a.index,
          label: a.label,
          subtitle: a.detailedSpec,
          itemKey: ValueKey('detail-audio-item-${a.index}'),
        ),
    ];

    // 3. Subtitle Pull-Down Items & Active Label
    String subtitleButtonLabel;
    if (extFileName != null) {
      subtitleButtonLabel = extFileName;
    } else if (selectedSubtitleIndex == -1) {
      subtitleButtonLabel = '关闭字幕';
    } else if (selectedSubtitleIndex != null) {
      final match = subs.where((s) => s.index == selectedSubtitleIndex);
      subtitleButtonLabel = match.isNotEmpty ? match.first.label : '默认字幕';
    } else if (subs.isNotEmpty) {
      subtitleButtonLabel = subs.first.label;
    } else if (hasKnownEmbeddedStreams) {
      subtitleButtonLabel = '无内封字幕';
    } else {
      subtitleButtonLabel = passiveSub ?? '默认字幕';
    }

    final subtitleItems = <VedroDropdownItem<int?>>[
      VedroDropdownItem<int?>(
        value: null,
        label: (hasKnownEmbeddedStreams && subs.isEmpty) ? '无内封字幕' : '默认字幕',
        subtitle: subs.isNotEmpty ? subs.first.detailedSpec : passiveSub,
        itemKey: const ValueKey('detail-subtitle-default-item'),
      ),
      const VedroDropdownItem<int?>(
        value: -1,
        label: '关闭字幕',
        itemKey: ValueKey('detail-subtitle-off-item'),
      ),
      for (final s in subs)
        VedroDropdownItem<int?>(
          value: s.index,
          label: s.label,
          subtitle: s.detailedSpec,
          itemKey: ValueKey('detail-subtitle-item-${s.index}'),
        ),
      if (extFileName != null)
        VedroDropdownItem<int?>(
          value: -998,
          label: '移除外挂字幕',
          subtitle: extFileName,
          icon: Icons.close_rounded,
          isDestructive: true,
          itemKey: const ValueKey('detail-clear-local-sub-btn'),
          onTapOverride: onClearExternalSubtitle,
        ),
      if (!isSeries)
        VedroDropdownItem<int?>(
          value: -999,
          label: '挂载本地字幕文件…',
          icon: Icons.upload_file_rounded,
          itemKey: const ValueKey('detail-mount-local-sub-btn'),
          onTapOverride: onPickExternalSubtitle,
        ),
    ];

    return LayoutBuilder(
      key: const ValueKey('detail-version-selector'),
      builder: (context, constraints) {
        final compactMobile = constraints.maxWidth < 560;

        Widget buildVersionBtn({required bool expanded}) => VedroPullDownButton<int>(
              key: const ValueKey('detail-version-dropdown'),
              prefixLabel: versions.length > 1 ? '版本 · ${versions.length}' : '版本',
              value: safeVerIdx,
              items: versionItems,
              expanded: expanded,
              menuMaxWidth: 380,
              onChanged: onSelectVersionIndex,
            );

        Widget buildAudioBtn({required bool expanded}) => VedroPullDownButton<int?>(
              key: const ValueKey('detail-audio-dropdown'),
              prefixLabel: '音轨',
              displayLabelOverride: audioButtonLabel,
              value: selectedAudioIndex,
              items: audioItems,
              expanded: expanded,
              onChanged: onSelectAudio,
            );

        Widget buildSubBtn({required bool expanded}) => VedroPullDownButton<int?>(
              key: const ValueKey('detail-subtitle-dropdown'),
              prefixLabel: '字幕',
              displayLabelOverride: subtitleButtonLabel,
              value: extFileName != null ? -997 : selectedSubtitleIndex,
              items: subtitleItems,
              expanded: expanded,
              onChanged: (val) {
                if (val == -997) return;
                onSelectSubtitle(val);
              },
            );

        if (compactMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showVersionDropdown) buildVersionBtn(expanded: true),
              if (showVersionDropdown && showTrackDropdowns) const SizedBox(height: 8),
              if (showTrackDropdowns)
                KeyedSubtree(
                  key: const ValueKey('detail-audio-subtitle-panel'),
                  child: Row(
                    children: [
                      Expanded(child: buildAudioBtn(expanded: true)),
                      const SizedBox(width: 8),
                      Expanded(child: buildSubBtn(expanded: true)),
                    ],
                  ),
                ),
            ],
          );
        }

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (showVersionDropdown) buildVersionBtn(expanded: false),
            if (showTrackDropdowns)
              KeyedSubtree(
                key: const ValueKey('detail-audio-subtitle-panel'),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    buildAudioBtn(expanded: false),
                    buildSubBtn(expanded: false),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
