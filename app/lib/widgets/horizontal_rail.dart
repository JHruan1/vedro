import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import 'media_card.dart';

/// Apple TV+ / Infuse style horizontal scrolling rail:
/// - Zero ugly desktop scrollbars
/// - Smooth soft edge fade-out masks whenever off-screen items exist (never harshly chopped)
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
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final padX = wide ? 32.0 : 20.0;
    final cardWidth = widget.isResume
        ? (wide ? 306.0 : 268.0)
        : (widget.landscape
            ? (wide ? 286.0 : 252.0)
            : widget.appState.prefs.posterCardWidth(wide));
    final artHeight = widget.isResume || widget.landscape
        ? (cardWidth / (16 / 9))
        : (cardWidth / (2 / 3));
    final railHeight = artHeight + 76;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(padX, 28, padX, 10),
          child: widget.onSeeAll != null
              ? MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: widget.onSeeAll,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: VedroTheme.fg,
                              fontSize: wide ? 20 : 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right_rounded, size: 20, color: VedroTheme.fg3),
                      ],
                    ),
                  ),
                )
              : Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: VedroTheme.fg,
                    fontSize: wide ? 20 : 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
        ),
        SmoothHorizontalStrip(
          controller: _scrollCtrl,
          height: railHeight,
          paddleCenterY: 10 + (artHeight / 2),
          padX: padX,
          spacing: wide ? 18 : 13,
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
  });

  final String title;
  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

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
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final padX = wide ? 32.0 : 20.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(padX, 28, padX, 10),
          child: Text(
            widget.title,
            style: TextStyle(
              color: VedroTheme.fg,
              fontSize: wide ? 20 : 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
          ),
        ),
        SmoothHorizontalStrip(
          controller: _scrollCtrl,
          height: widget.height + 12,
          paddleCenterY: 10 + ((widget.height - 40) / 2),
          padX: padX,
          spacing: wide ? 18 : 13,
          itemCount: widget.itemCount,
          itemBuilder: widget.itemBuilder,
        ),
      ],
    );
  }
}

/// Reusable horizontal card strip with:
/// - Hidden scrollbars on all platforms
/// - Soft canvas-colored left/right edge fade masks when more items exist
/// - Hover-revealed floating edge chevron buttons on wide/desktop viewports
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
    _ctrl.addListener(_syncEdges);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncEdges());
  }

  @override
  void didUpdateWidget(covariant SmoothHorizontalStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncEdges());
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_syncEdges);
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
    final paddleTop = ((widget.paddleCenterY ?? (widget.height * 0.44)) - 20)
        .clamp(8.0, (widget.height - 48).clamp(8.0, widget.height));

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
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                  child: ListView.separated(
                    controller: _ctrl,
                    padding: EdgeInsets.fromLTRB(widget.padX, 10, widget.padX, 12),
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    itemCount: widget.itemCount,
                    separatorBuilder: (_, __) => SizedBox(width: widget.spacing),
                    itemBuilder: widget.itemBuilder,
                  ),
                ),
              ),

              // Subtle left edge fade dissolve when scrolled right
              if (!_atStart)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: wide ? 44 : 24,
                  child: const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            VedroTheme.canvas,
                            Color(0xB80B0B0D),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Subtle right edge fade dissolve when more items exist off-screen
              if (!_atEnd)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: wide ? 48 : 26,
                  child: const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerRight,
                          end: Alignment.centerLeft,
                          colors: [
                            VedroTheme.canvas,
                            Color(0xB80B0B0D),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Hover-revealed desktop edge paddles (Apple TV+ / Infuse style)
              if (wide && !_atStart)
                Positioned(
                  left: 10,
                  top: paddleTop,
                  child: _EdgePaddleButton(
                    visible: _hovered,
                    icon: Icons.chevron_left_rounded,
                    onTap: () => _scrollStep(-1),
                  ),
                ),
              if (wide && !_atEnd)
                Positioned(
                  right: 10,
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
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
        child: Material(
          color: const Color(0xE8161821),
          shape: const CircleBorder(
            side: BorderSide(color: Color(0x40FFFFFF), width: 0.9),
          ),
          elevation: 6,
          shadowColor: const Color(0x99000000),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, size: 24, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
