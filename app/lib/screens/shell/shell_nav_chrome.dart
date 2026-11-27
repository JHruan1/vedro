part of '../shell_screen.dart';

/// Scyfin / Plex / Infuse Pro Left Vertical Navigation Rail (`navLayout == 'left_rail'`).
class _VerticalSidebarRail extends StatelessWidget {
  const _VerticalSidebarRail({
    super.key,
    required this.appState,
    required this.compact,
    required this.activeIndex,
    required this.navItems,
    required this.onSelectIndex,
    required this.onOpenServerHub,
    required this.onOpenSearch,
    required this.onOpenLocalMedia,
    required this.onOpenNetworkUrl,
    required this.onOpenFavorites,
    required this.onOpenLayout,
    required this.onRefresh,
  });

  final VedroAppState appState;
  final bool compact;
  final int activeIndex;
  final List<(int, String, IconData)> navItems;
  final ValueChanged<int> onSelectIndex;
  final VoidCallback onOpenServerHub;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenLocalMedia;
  final VoidCallback onOpenNetworkUrl;
  final VoidCallback onOpenFavorites;
  final VoidCallback onOpenLayout;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: NativePlaybackChannel.fullscreenNotifier,
      builder: (context, isFullscreen, _) {
        final topPad = (!kIsWeb && Platform.isMacOS && !isFullscreen)
            ? 44.0
            : ((!kIsWeb && Platform.isWindows && !isFullscreen) ? 36.0 : 18.0);
        final w = compact ? 76.0 : 216.0;
        final serverLabel = appState.isSignedIn ? appState.activeServerDisplayName : '选择服务器';
        final routeName = appState.activeRouteDisplayName;
        final itemR = skin.cardRadius.clamp(6.0, 14.0);

        Widget railEntry({
          required IconData icon,
          required String label,
          required bool selected,
          required VoidCallback onTap,
          String? trailingHint,
        }) {
          final activeFg = skin.ctaStyle == 'contrast' ? skin.fg : skin.accent;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: PressableScale(
              onTap: onTap,
              hoverScale: 1.015,
              pressScale: 0.97,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: VedroTheme.easeOut,
                height: 40,
                padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12),
                decoration: BoxDecoration(
                  color: selected
                      ? (skin.ctaStyle == 'contrast'
                          ? skin.subtleChipHoverBg
                          : skin.accent.withValues(alpha: skin.isLight ? 0.14 : 0.20))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(itemR),
                  border: selected && skin.frameStyle != 'borderless'
                      ? Border.all(color: skin.accent.withValues(alpha: 0.45), width: 0.8)
                      : null,
                ),
                child: compact
                    ? Tooltip(
                        message: label,
                        child: Center(
                          child: Icon(
                            icon,
                            size: 20,
                            color: selected ? activeFg : skin.fg2,
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          Icon(icon, size: 18, color: selected ? activeFg : skin.fg2),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected ? activeFg : skin.fg2,
                                fontSize: 13.5,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (trailingHint != null)
                            Text(
                              trailingHint,
                              style: TextStyle(color: skin.fg3, fontSize: 10.5),
                            ),
                        ],
                      ),
              ),
            ),
          );
        }

        return Container(
          width: w,
          decoration: BoxDecoration(
            color: skin.panelSurface,
            border: Border(right: BorderSide(color: skin.border, width: 0.8)),
          ),
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(12, topPad, 12, 16),
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PressableScale(
                                onTap: onOpenServerHub,
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: compact ? 6 : 10,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: skin.surface2,
                                    borderRadius: BorderRadius.circular(itemR),
                                    border: Border.all(color: skin.border, width: 0.8),
                                  ),
                                  child: compact
                                      ? const Center(child: VedroBrandMark(size: 26))
                                      : Row(
                                          children: [
                                            const VedroBrandMark(size: 26),
                                            const SizedBox(width: 9),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    serverLabel,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: skin.fg,
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                  if (routeName != null && routeName.isNotEmpty)
                                                    Text(
                                                      routeName,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(color: skin.fg3, fontSize: 11),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            Icon(Icons.unfold_more_rounded, size: 15, color: skin.fg3),
                                          ],
                                        ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              railEntry(
                                icon: Icons.search_rounded,
                                label: appState.savedServers.length > 1 ? '聚合搜索' : '搜索',
                                selected: activeIndex == 2,
                                trailingHint: (!kIsWeb && Platform.isMacOS) ? '⌘K' : 'Ctrl+K',
                                onTap: onOpenSearch,
                              ),
                              const SizedBox(height: 6),
                              for (final (idx, label, icon) in navItems)
                                railEntry(
                                  icon: icon,
                                  label: label,
                                  selected: activeIndex == idx,
                                  onTap: () => onSelectIndex(idx),
                                ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                railEntry(
                                  icon: Icons.folder_open_rounded,
                                  label: '本地播放',
                                  selected: false,
                                  onTap: onOpenLocalMedia,
                                ),
                                railEntry(
                                  icon: Icons.link_rounded,
                                  label: '网络链接',
                                  selected: false,
                                  onTap: onOpenNetworkUrl,
                                ),
                                if (appState.isSignedIn) ...[
                                  railEntry(
                                    icon: Icons.favorite_border_rounded,
                                    label: '我的收藏',
                                    selected: false,
                                    onTap: onOpenFavorites,
                                  ),
                                  railEntry(
                                    icon: Icons.dashboard_customize_outlined,
                                    label: '首页布局',
                                    selected: false,
                                    onTap: onOpenLayout,
                                  ),
                                  railEntry(
                                    icon: Icons.refresh_rounded,
                                    label: '刷新数据',
                                    selected: false,
                                    onTap: onRefresh,
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
              ),
              if (!kIsWeb && Platform.isWindows && !isFullscreen)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 36,
                  child: WindowsWindowDragArea(),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Ultrachromic / visionOS Floating Centered Capsule Navigation Island (`navLayout == 'centered_capsule'`).
class _CenteredCapsuleNavIsland extends StatelessWidget {
  const _CenteredCapsuleNavIsland({
    super.key,
    required this.appState,
    required this.activeIndex,
    required this.navItems,
    required this.onSelectIndex,
    required this.onOpenServerHub,
    required this.onOpenSearch,
    required this.onOpenLocalMedia,
    required this.onOpenNetworkUrl,
    required this.onOpenFavorites,
    required this.onRefresh,
  });

  final VedroAppState appState;
  final int activeIndex;
  final List<(int, String, IconData)> navItems;
  final ValueChanged<int> onSelectIndex;
  final VoidCallback onOpenServerHub;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenLocalMedia;
  final VoidCallback onOpenNetworkUrl;
  final VoidCallback onOpenFavorites;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final islandR = skin.radiusForPill(48);
    final btnR = skin.radiusForPill(34);
    final serverLabel = appState.isSignedIn ? appState.activeServerDisplayName : '服务器';

    return SafeArea(
      bottom: false,
      child: Center(
        child: GlassSurface(
          borderRadius: islandR,
          blur: 32,
          color: skin.glassStrong,
          borderColor: skin.borderStrong,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
            children: [
              PressableScale(
                onTap: onOpenServerHub,
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: skin.subtleChipBg,
                    borderRadius: BorderRadius.circular(btnR),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const VedroBrandMark(size: 20),
                      const SizedBox(width: 7),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: Text(
                          serverLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: skin.fg,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(Icons.keyboard_arrow_down_rounded, size: 15, color: skin.fg3),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              for (final (idx, label, icon) in navItems)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: PressableScale(
                    onTap: () => onSelectIndex(idx),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: VedroTheme.easeOut,
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      decoration: BoxDecoration(
                        color: activeIndex == idx ? skin.activePillBg : Colors.transparent,
                        borderRadius: BorderRadius.circular(btnR),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            icon,
                            size: 15,
                            color: activeIndex == idx ? skin.activePillFg : skin.fg2,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            label,
                            style: TextStyle(
                              color: activeIndex == idx ? skin.activePillFg : skin.fg2,
                              fontSize: 13,
                              fontWeight: activeIndex == idx ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              _IslandIconBtn(
                icon: Icons.search_rounded,
                tooltip: (!kIsWeb && Platform.isMacOS) ? '搜索 (⌘K)' : '搜索 (Ctrl+K)',
                onTap: onOpenSearch,
              ),
              _IslandIconBtn(icon: Icons.folder_open_rounded, tooltip: '本地视频', onTap: onOpenLocalMedia),
              _IslandIconBtn(icon: Icons.link_rounded, tooltip: '打开网络链接', onTap: onOpenNetworkUrl),
              if (appState.isSignedIn) ...[
                _IslandIconBtn(icon: Icons.favorite_border_rounded, tooltip: '我的收藏', onTap: onOpenFavorites),
                _IslandIconBtn(icon: Icons.refresh_rounded, tooltip: '刷新', onTap: onRefresh),
              ],
            ],
          ),
          ),
        ),
      ),
    );
  }
}

class _IslandIconBtn extends StatelessWidget {
  const _IslandIconBtn({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: tooltip,
        child: PressableScale(
          onTap: onTap,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: skin.subtleChipBg,
              borderRadius: BorderRadius.circular(skin.radiusForPill(34)),
            ),
            child: Icon(icon, size: 15.5, color: skin.fg2),
          ),
        ),
      ),
    );
  }
}

class _FloatingDesktopHeader extends StatelessWidget {
  const _FloatingDesktopHeader({
    required this.appState,
    required this.clear,
    required this.activeIndex,
    required this.navItems,
    required this.onSelectIndex,
    required this.onOpenServerHub,
    required this.onOpenSearch,
    required this.onOpenLocalMedia,
    required this.onOpenNetworkUrl,
    required this.onOpenFavorites,
    required this.onOpenLayout,
    required this.onRefresh,
  });

  final VedroAppState appState;
  final bool clear;
  final int activeIndex;
  final List<(int, String, IconData)> navItems;
  final ValueChanged<int> onSelectIndex;
  final VoidCallback onOpenServerHub;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenLocalMedia;
  final VoidCallback onOpenNetworkUrl;
  final VoidCallback onOpenFavorites;
  final VoidCallback onOpenLayout;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    NativePlaybackChannel.ensureWindowListener();
    return ValueListenableBuilder<bool>(
      valueListenable: NativePlaybackChannel.fullscreenNotifier,
      builder: (context, isFullscreen, _) {
        final macTrafficClearance = (!kIsWeb && Platform.isMacOS && !isFullscreen) ? 82.0 : 28.0;
        final winCaptionClearance = (!kIsWeb && Platform.isWindows && !isFullscreen) ? 148.0 : 28.0;
        final routeName = appState.activeRouteDisplayName;
        final serverLabel = appState.isSignedIn ? appState.activeServerDisplayName : '选择服务器';
        final activeSrv = appState.activeServer;
        final cardStyle = activeSrv != null ? appState.serverCardStyleFor(activeSrv.id) : null;
        final cardTheme = activeSrv != null ? cardStyle?.resolveTheme(activeSrv.id) : null;
        final pillR = skin.radiusForPill(36);
        final isRoundBtn = skin.pillRadius >= 20;

        Widget headerCircleBtn({
          required String tooltip,
          required IconData icon,
          required VoidCallback onTap,
        }) {
          return Tooltip(
            message: tooltip,
            child: PressableScale(
              onTap: onTap,
              hoverScale: 1.06,
              pressScale: 0.92,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: clear ? const Color(0x1EFFFFFF) : skin.surface2,
                  shape: isRoundBtn ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: isRoundBtn ? null : BorderRadius.circular(pillR),
                  border: Border.all(
                    color: clear ? const Color(0x24FFFFFF) : skin.border,
                    width: 0.7,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: clear ? Colors.white : skin.fg2,
                ),
              ),
            ),
          );
        }

        final content = SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availW = constraints.maxWidth - macTrafficClearance - winCaptionClearance;
              final compactHeader = availW < 920;
              final narrowHeader = availW < 780;
              final searchWidth = availW >= 1040 ? 224.0 : (availW >= 860 ? 154.0 : 0.0);
              final btnGap = narrowHeader ? 6.0 : 8.0;
              final navPadH = compactHeader ? 10.0 : 14.0;
              return SizedBox(
                height: 58,
                child: Stack(
                  children: [
                    const Positioned.fill(child: WindowsWindowDragArea()),
                    Padding(
                      padding: EdgeInsets.fromLTRB(macTrafficClearance, 0, winCaptionClearance, 0),
                      child: Row(
                        children: [
                    PressableScale(
                      onTap: onOpenServerHub,
                      hoverScale: 1.02,
                      pressScale: 0.97,
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.fromLTRB(6, 0, 10, 0),
                        decoration: BoxDecoration(
                          color: clear ? const Color(0x26FFFFFF) : skin.surface2,
                          borderRadius: BorderRadius.circular(pillR),
                          border: Border.all(
                            color: clear ? const Color(0x2EFFFFFF) : skin.border,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (appState.isSignedIn && cardStyle != null && cardTheme != null)
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: cardTheme.accent.withValues(alpha: 0.22),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(cardStyle.iconData, size: 13.5, color: cardTheme.accent),
                              )
                            else
                              const VedroBrandMark(size: 24),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: narrowHeader ? 96 : (compactHeader ? 124 : 160)),
                              child: Text(
                                serverLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: clear ? Colors.white : skin.fg,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            if (!compactHeader &&
                                appState.isSignedIn &&
                                routeName != null &&
                                routeName.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: clear ? const Color(0x1CFFFFFF) : skin.subtleChipBg,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  routeName,
                                  style: TextStyle(
                                    color: clear ? const Color(0xCCFFFFFF) : skin.fg2,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 4),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: clear ? const Color(0xB8FFFFFF) : skin.fg3,
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: compactHeader ? 10 : 18),
                    for (final (idx, label, _) in navItems)
                      Padding(
                        padding: EdgeInsets.only(right: narrowHeader ? 2 : 4),
                        child: PressableScale(
                          onTap: () => onSelectIndex(idx),
                          hoverScale: 1.03,
                          pressScale: 0.96,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: VedroTheme.easeOut,
                            height: 34,
                            padding: EdgeInsets.symmetric(horizontal: navPadH),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: activeIndex == idx
                                  ? (clear
                                      ? const Color(0x28FFFFFF)
                                      : (skin.ctaStyle == 'contrast'
                                          ? skin.subtleChipHoverBg
                                          : skin.accent.withValues(alpha: skin.isLight ? 0.14 : 0.22)))
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(skin.radiusForPill(34)),
                              border: (activeIndex == idx && skin.frameStyle == 'neon' && !clear)
                                  ? Border.all(color: skin.accent.withValues(alpha: 0.55), width: 0.8)
                                  : null,
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: activeIndex == idx
                                    ? (clear
                                        ? Colors.white
                                        : (skin.ctaStyle == 'contrast' ? skin.fg : skin.accent))
                                    : (clear ? const Color(0xCCFFFFFF) : skin.fg2),
                                fontSize: 13.5,
                                fontWeight: activeIndex == idx ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    const Spacer(),
                    if (searchWidth > 0)
                      PressableScale(
                        onTap: onOpenSearch,
                        hoverScale: 1.02,
                        pressScale: 0.97,
                        child: Container(
                          width: searchWidth,
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: clear ? const Color(0x24FFFFFF) : skin.surface2,
                            borderRadius: BorderRadius.circular(pillR),
                            border: Border.all(
                              color: clear ? const Color(0x28FFFFFF) : skin.border,
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.search_rounded,
                                size: 16,
                                color: clear ? const Color(0xD9FFFFFF) : skin.fg3,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  appState.savedServers.length > 1 ? '聚合搜索' : '搜索',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: clear ? const Color(0xCCFFFFFF) : skin.fg3,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              if (searchWidth >= 200)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: clear ? const Color(0x1CFFFFFF) : skin.subtleChipBg,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    (!kIsWeb && Platform.isMacOS) ? '⌘K' : 'Ctrl+K',
                                    style: TextStyle(
                                      color: clear ? const Color(0xB8FFFFFF) : skin.fg3,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      )
                    else
                      headerCircleBtn(
                        tooltip: (!kIsWeb && Platform.isMacOS) ? '搜索 (⌘K)' : '搜索 (Ctrl+K)',
                        icon: Icons.search_rounded,
                        onTap: onOpenSearch,
                      ),
                    SizedBox(width: btnGap),
                    headerCircleBtn(
                      tooltip: '打开本地视频 / 文件夹（也支持直接拖入窗口）',
                      icon: Icons.folder_open_rounded,
                      onTap: onOpenLocalMedia,
                    ),
                    SizedBox(width: btnGap),
                    headerCircleBtn(
                      tooltip: '打开网络串流链接 (HTTP / HTTPS / RTSP / RTMP / M3U8)',
                      icon: Icons.link_rounded,
                      onTap: onOpenNetworkUrl,
                    ),
                    if (appState.isSignedIn) ...[
                      SizedBox(width: btnGap),
                      headerCircleBtn(
                        tooltip: '我的收藏',
                        icon: Icons.favorite_border_rounded,
                        onTap: onOpenFavorites,
                      ),
                      SizedBox(width: btnGap),
                      headerCircleBtn(
                        tooltip: '自定义首页布局',
                        icon: Icons.dashboard_customize_outlined,
                        onTap: onOpenLayout,
                      ),
                      SizedBox(width: btnGap),
                      headerCircleBtn(
                        tooltip: '刷新首页',
                        icon: Icons.refresh_rounded,
                        onTap: onRefresh,
                      ),
                    ],
                  ],
                ),
              ),
                  ],
                ),
              );
            },
          ),
        );

        if (clear) {
          return DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x94000000), Colors.transparent],
              ),
            ),
            child: content,
          );
        }

        // Feather-seamless frosted header when scrolled — NO harsh 1px line!
        final headerBlur = PlatformPerfProfile.clampLiveBlur(26);
        return RepaintBoundary(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: headerBlur, sigmaY: headerBlur),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: PlatformPerfProfile.adaptGlassFill(skin.glass),
                  border: skin.frameStyle == 'neon'
                      ? Border(bottom: BorderSide(color: skin.border, width: 0.7))
                      : null,
                ),
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NavTab {
  const _NavTab({required this.icon, required this.activeIcon, required this.label});
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class _BottomTabButton extends StatelessWidget {
  const _BottomTabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
    this.iconOnly = false,
  });
  final _NavTab tab;
  final bool selected;
  final VoidCallback onTap;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final activeColor = skin.accent;
    final pillFill = skin.isLight
        ? Colors.black.withValues(alpha: 0.065)
        : Colors.white.withValues(alpha: 0.11);
    final pillR = skin.radiusForPill(46);
    return Expanded(
      child: PressableScale(
        onTap: onTap,
        hoverScale: 1.0,
        pressScale: 0.94,
        borderRadius: BorderRadius.circular(pillR),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: VedroTheme.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: EdgeInsets.symmetric(vertical: iconOnly ? 8.5 : 6.5),
          decoration: BoxDecoration(
            color: selected ? pillFill : Colors.transparent,
            borderRadius: BorderRadius.circular(pillR),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: selected ? 1.12 : 1.0,
                duration: const Duration(milliseconds: 280),
                curve: VedroTheme.snappySpring,
                child: Icon(
                  selected ? tab.activeIcon : tab.icon,
                  size: iconOnly ? 21.5 : 20.5,
                  color: selected ? activeColor : skin.fg2,
                ),
              ),
              if (!iconOnly) ...[
                const SizedBox(height: 2.5),
                Text(
                  tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? activeColor : skin.fg2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
