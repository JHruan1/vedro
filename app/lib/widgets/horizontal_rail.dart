import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import 'media_card.dart';
import 'vedro_ui.dart';

/// Titled horizontal scrolling rail with smooth desktop left/right scroll buttons,
/// Apple bouncing physics, and optional custom card builder (e.g. ResumeCard / LibraryCard).
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
  bool _atStart = true;
  bool _atEnd = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_syncEdges);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncEdges());
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _syncEdges() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    final start = pos.pixels <= 4;
    final end = pos.pixels >= pos.maxScrollExtent - 4;
    if (start != _atStart || end != _atEnd) {
      setState(() {
        _atStart = start;
        _atEnd = end;
      });
    }
  }

  void _scrollStep(int dir) {
    if (!_scrollCtrl.hasClients) return;
    final vp = _scrollCtrl.position.viewportDimension;
    final stride = (vp * 0.8).clamp(280.0, 960.0);
    final target = (_scrollCtrl.offset + dir * stride)
        .clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.animateTo(
      target,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
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
    final railHeight = widget.isResume || widget.landscape
        ? (cardWidth / (16 / 9)) + 68
        : (cardWidth / (2 / 3)) + 68;
    final showArrows = wide && !(_atStart && _atEnd);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(padX, 30, padX, 12),
          child: Row(
            children: [
              Expanded(
                child: widget.onSeeAll != null
                    ? GestureDetector(
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
                                  fontSize: wide ? 21 : 18,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.35,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right_rounded, size: 20, color: VedroTheme.fg3),
                          ],
                        ),
                      )
                    : Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: VedroTheme.fg,
                          fontSize: wide ? 21 : 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.35,
                        ),
                      ),
              ),
              if (showArrows) ...[
                _RailArrowButton(
                  icon: Icons.chevron_left_rounded,
                  disabled: _atStart,
                  onTap: () => _scrollStep(-1),
                ),
                const SizedBox(width: 6),
                _RailArrowButton(
                  icon: Icons.chevron_right_rounded,
                  disabled: _atEnd,
                  onTap: () => _scrollStep(1),
                ),
              ],
            ],
          ),
        ),
        SizedBox(
          height: railHeight,
          child: ListView.separated(
            controller: _scrollCtrl,
            clipBehavior: Clip.none,
            padding: EdgeInsets.fromLTRB(padX, 8, padX, 10),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: widget.items.length,
            separatorBuilder: (_, __) => SizedBox(width: wide ? 18 : 13),
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
  bool _atStart = true;
  bool _atEnd = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_syncEdges);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncEdges());
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _syncEdges() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    final start = pos.pixels <= 4;
    final end = pos.pixels >= pos.maxScrollExtent - 4;
    if (start != _atStart || end != _atEnd) {
      setState(() {
        _atStart = start;
        _atEnd = end;
      });
    }
  }

  void _scrollStep(int dir) {
    if (!_scrollCtrl.hasClients) return;
    final vp = _scrollCtrl.position.viewportDimension;
    final target = (_scrollCtrl.offset + dir * (vp * 0.8).clamp(300.0, 960.0))
        .clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.animateTo(
      target,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) return const SizedBox.shrink();
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final padX = wide ? 32.0 : 20.0;
    final showArrows = wide && !(_atStart && _atEnd);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(padX, 30, padX, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    color: VedroTheme.fg,
                    fontSize: wide ? 21 : 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.35,
                  ),
                ),
              ),
              if (showArrows) ...[
                _RailArrowButton(
                  icon: Icons.chevron_left_rounded,
                  disabled: _atStart,
                  onTap: () => _scrollStep(-1),
                ),
                const SizedBox(width: 6),
                _RailArrowButton(
                  icon: Icons.chevron_right_rounded,
                  disabled: _atEnd,
                  onTap: () => _scrollStep(1),
                ),
              ],
            ],
          ),
        ),
        SizedBox(
          height: widget.height,
          child: ListView.separated(
            controller: _scrollCtrl,
            clipBehavior: Clip.none,
            padding: EdgeInsets.fromLTRB(padX, 8, padX, 10),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: widget.itemCount,
            separatorBuilder: (_, __) => SizedBox(width: wide ? 18 : 13),
            itemBuilder: widget.itemBuilder,
          ),
        ),
      ],
    );
  }
}

class _RailArrowButton extends StatelessWidget {
  const _RailArrowButton({
    required this.icon,
    required this.disabled,
    required this.onTap,
  });

  final IconData icon;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.3 : 1.0,
      child: PressableScale(
        onTap: disabled ? null : onTap,
        hoverScale: 1.06,
        pressScale: 0.92,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: VedroTheme.surface2,
            shape: BoxShape.circle,
            border: Border.all(color: VedroTheme.line, width: 0.8),
          ),
          child: Icon(icon, size: 18, color: VedroTheme.fg2),
        ),
      ),
    );
  }
}
