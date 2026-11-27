import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/platform/platform_perf.dart';
import '../core/theme/display_profile.dart';
import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import 'media_card.dart';
import 'vedro_ui.dart';

/// Skin-adaptive horizontal scrolling rail:
/// - Zero ugly desktop scrollbars
/// - Hover-revealed floating left/right edge navigation paddles on desktop
/// - Calm, generous vertical clearance so hovered cards and shadows never clip
class HorizontalMediaRail extends StatefulWidget {
  const HorizontalMediaRail({
    super.key,
    required this.title,
    required this.items,
    required this.appState,
    required this.onItemTap,
    this.onItemQuickPlay,
    this.onItemLongPress,
    this.onSeeAll,
    this.landscape = false,
    this.isResume = false,
    this.heroPrefix,
  });

  final String title;
  final List<MediaItemModel> items;
  final VedroAppState appState;
  final void Function(MediaItemModel) onItemTap;
  final void Function(MediaItemModel)? onItemQuickPlay;
  final void Function(MediaItemModel)? onItemLongPress;
  final VoidCallback? onSeeAll;
  final bool landscape;
  final bool isResume;
  final String? heroPrefix;

  @override
  State<HorizontalMediaRail> createState() => _HorizontalMediaRailState();
}

class _HorizontalMediaRailState extends State<HorizontalMediaRail> {
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final skin = VedroSkin.of(context);
    final profile = DisplayMetricsProfile.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final prefs = widget.appState.prefs;
    final wide = !profile.usesMobileChrome;
    final padX = prefs.horizontalMargin(wide);
    final gap = prefs.cardGap(wide);
    final topGap = prefs.sectionTopGap(wide);
    final scale = prefs.posterScale.clamp(0.75, 1.25);
    final isLandscapePoster = widget.landscape || skin.posterAspect == 'landscape_16_9';
    final cardWidth = widget.isResume
        ? ((wide ? 292.0 : 216.0) * scale)
        : (isLandscapePoster
            ? ((wide ? 272.0 : 204.0) * scale)
            : prefs.posterCardWidth(wide, profile));
    final aspect = (widget.isResume || isLandscapePoster) ? (16 / 9) : skin.mediaAspectRatio;
    final artHeight = cardWidth / aspect;
    final effectiveStyle =
        (skin.cardStyle == 'hover_reveal' && profile.isTouchPrimary) ? 'overlay_poster' : skin.cardStyle;
    final textBelow = widget.isResume ||
        (effectiveStyle != 'overlay_poster' &&
            effectiveStyle != 'hover_reveal' &&
            effectiveStyle != 'minimal_clean');
    final cardMetrics = PosterCardLayout.forCardWidth(
      cardWidth: cardWidth,
      aspectRatio: aspect,
      showBelowCaption: textBelow,
      textScaler: textScaler,
      devicePixelRatio: profile.devicePixelRatio,
    );
    final vPad = (wide || PlatformPerfProfile.isTv) ? 20.0 : 6.0;
    final railHeight = cardMetrics.cardHeight + vPad;

    final titleStyle = skin.applyHeadlineMood(
      TextStyle(
        color: skin.fg,
        fontSize: wide ? 20 : 16.5,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(padX, topGap, padX, wide ? 10 : 7),
          child: widget.onSeeAll != null
              ? PressableScale(
                  onTap: widget.onSeeAll,
                  hoverScale: 1.0,
                  pressScale: 0.97,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(Icons.chevron_right_rounded, size: wide ? 20 : 18, color: skin.fg3),
                      ],
                    ),
                  ),
                )
              : Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
        ),
        SmoothHorizontalStrip(
          controller: _scrollCtrl,
          height: railHeight,
          paddleCenterY: 6 + (artHeight / 2),
          padX: padX,
          spacing: gap,
          itemCount: widget.items.length,
          itemBuilder: (context, idx) {
            final item = widget.items[idx];
            if (widget.isResume) {
              return ResumeCard(
                item: item,
                appState: widget.appState,
                width: cardWidth,
                onTap: () => widget.onItemTap(item),
                onResumePlay: () => (widget.onItemQuickPlay ?? widget.onItemTap)(item),
                onLongPress: widget.onItemLongPress == null
                    ? null
                    : () => widget.onItemLongPress!(item),
              );
            }
            return MediaCard(
              item: item,
              appState: widget.appState,
              width: cardWidth,
              landscape: widget.landscape,
              heroPrefix: widget.heroPrefix,
              onTap: () => widget.onItemTap(item),
              onQuickPlay: widget.onItemQuickPlay == null
                  ? null
                  : () => widget.onItemQuickPlay!(item),
              onLongPress: widget.onItemLongPress == null
                  ? null
                  : () => widget.onItemLongPress!(item),
            );
          },
        ),
      ],
    );
  }
}

/// Generic horizontal rail for custom large cards (such as `LibraryCard`).
class CustomHorizontalRail extends StatefulWidget {
  const CustomHorizontalRail({
    super.key,
    required this.title,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.padXOverride,
    this.spacingOverride,
    this.topGapOverride,
  });

  final String title;
  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double? padXOverride;
  final double? spacingOverride;
  final double? topGapOverride;

  @override
  State<CustomHorizontalRail> createState() => _CustomHorizontalRailState();
}

class _CustomHorizontalRailState extends State<CustomHorizontalRail> {
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) return const SizedBox.shrink();
    final skin = VedroSkin.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final padX = widget.padXOverride ?? (wide ? 30.0 : 12.0);
    final gap = widget.spacingOverride ?? (wide ? 16.0 : 9.0);
    final topGap = widget.topGapOverride ?? (wide ? 20.0 : 10.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(padX, topGap, padX, wide ? 10 : 7),
          child: Text(
            widget.title,
            style: skin.applyHeadlineMood(
              TextStyle(
                color: skin.fg,
                fontSize: wide ? 20 : 16.5,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ),
        SmoothHorizontalStrip(
          controller: _scrollCtrl,
          height: widget.height,
          paddleCenterY: 6 + ((widget.height - 28) / 2),
          padX: padX,
          spacing: gap,
          itemCount: widget.itemCount,
          itemBuilder: widget.itemBuilder,
        ),
      ],
    );
  }
}

/// Reusable horizontal card strip with hidden scrollbars and hover-revealed edge paddles.
class SmoothHorizontalStrip extends StatefulWidget {
  const SmoothHorizontalStrip({
    super.key,
    this.controller,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.padX = 0,
    this.spacing = 14,
    this.paddleCenterY,
  });

  final ScrollController? controller;
  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double padX;
  final double spacing;
  final double? paddleCenterY;

  @override
  State<SmoothHorizontalStrip> createState() => _SmoothHorizontalStripState();
}

class _SmoothHorizontalStripState extends State<SmoothHorizontalStrip> {
  ScrollController? _ownedCtrl;
  ScrollController get _ctrl => widget.controller ?? (_ownedCtrl ??= ScrollController());

  bool _atStart = true;
  bool _atEnd = true;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    if (!PlatformPerfProfile.isMobile) {
      _ctrl.addListener(_syncEdges);
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncEdges());
    }
  }

  @override
  void didUpdateWidget(covariant SmoothHorizontalStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!PlatformPerfProfile.isMobile && oldWidget.itemCount != widget.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncEdges());
    }
  }

  @override
  void dispose() {
    if (!PlatformPerfProfile.isMobile) {
      _ctrl.removeListener(_syncEdges);
    }
    _ownedCtrl?.dispose();
    super.dispose();
  }

  void _syncEdges() {
    if (!mounted || !_ctrl.hasClients) return;
    final pos = _ctrl.position;
    final start = pos.pixels <= 6;
    final end = pos.maxScrollExtent <= 6 || pos.pixels >= pos.maxScrollExtent - 6;
    if (start != _atStart || end != _atEnd) {
      setState(() {
        _atStart = start;
        _atEnd = end;
      });
    }
  }

  void _scrollStep(int dir) {
    if (!_ctrl.hasClients) return;
    final vp = _ctrl.position.viewportDimension;
    final stride = (vp * 0.78).clamp(280.0, 920.0);
    final target = (_ctrl.offset + dir * stride).clamp(0.0, _ctrl.position.maxScrollExtent);
    _ctrl.animateTo(
      target,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final isTv = PlatformPerfProfile.isTv;
    final padTop = (wide || isTv) ? 9.0 : 3.0;
    final padBottom = (wide || isTv) ? 11.0 : 3.0;
    final paddleTop = ((widget.paddleCenterY ?? (widget.height * 0.44)) - 20)
        .clamp(8.0, (widget.height - 48).clamp(8.0, widget.height));

    final list = FocusTraversalGroup(
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView.separated(
          controller: _ctrl,
          padding: EdgeInsets.fromLTRB(widget.padX, padTop, widget.padX, padBottom),
          scrollDirection: Axis.horizontal,
          cacheExtent: PlatformPerfProfile.scrollCacheExtent,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          itemCount: widget.itemCount,
          separatorBuilder: (_, __) => SizedBox(width: widget.spacing),
          itemBuilder: widget.itemBuilder,
        ),
      ),
    );

    if (!wide || PlatformPerfProfile.isMobile || isTv) {
      return SizedBox(height: widget.height, child: list);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        height: widget.height,
        child: ClipRect(
          child: Stack(
            children: [
              NotificationListener<ScrollMetricsNotification>(
                onNotification: (_) {
                  _syncEdges();
                  return false;
                },
                child: list,
              ),
              if (!_atStart)
                Positioned(
                  left: 12,
                  top: paddleTop,
                  child: _EdgePaddleButton(
                    visible: _hovered,
                    icon: Icons.chevron_left_rounded,
                    onTap: () => _scrollStep(-1),
                  ),
                ),
              if (!_atEnd)
                Positioned(
                  right: 12,
                  top: paddleTop,
                  child: _EdgePaddleButton(
                    visible: _hovered,
                    icon: Icons.chevron_right_rounded,
                    onTap: () => _scrollStep(1),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EdgePaddleButton extends StatelessWidget {
  const _EdgePaddleButton({
    required this.visible,
    required this.icon,
    required this.onTap,
  });

  final bool visible;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return ExcludeFocus(
      excluding: !visible,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 180),
          curve: VedroTheme.easeOut,
          child: Material(
            color: skin.surface.withValues(alpha: 0.92),
            shape: CircleBorder(side: BorderSide(color: skin.borderStrong, width: 0.8)),
            elevation: 8,
            shadowColor: Colors.black.withValues(alpha: skin.isLight ? 0.22 : 0.65),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 38,
                height: 38,
                child: Icon(icon, size: 22, color: skin.fg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
