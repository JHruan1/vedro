part of '../player_screen.dart';

/// Custom IINA / Infuse precision scrub bar:
/// - Smoothly expands track height on hover/drag (4px -> 7px)
/// - Displays buffered track + Intro/Outro segment markers
/// - Floating hover timestamp preview pill above cursor
/// - Clickable right timestamp toggles Total vs Remaining time
class _CinemaScrubBar extends StatefulWidget {
  const _CinemaScrubBar({
    required this.positionSecs,
    required this.bufferedSecs,
    required this.durationSecs,
    required this.segments,
    this.chapters = const [],
    required this.showRemaining,
    this.seekStepSecs = 10.0,
    required this.fmtTime,
    required this.onToggleRemaining,
    this.onTogglePlayPause,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
    this.onDpadStep,
  });

  final double positionSecs;
  final double bufferedSecs;
  final double durationSecs;
  final List<MediaSegmentModel> segments;
  final List<({String title, double timeSecs})> chapters;
  final bool showRemaining;
  final double seekStepSecs;
  final String Function(double) fmtTime;
  final VoidCallback onToggleRemaining;
  final VoidCallback? onTogglePlayPause;
  final VoidCallback onScrubStart;
  final ValueChanged<double> onScrubUpdate;
  final ValueChanged<double> onScrubEnd;
  final ValueChanged<double>? onDpadStep;

  @override
  State<_CinemaScrubBar> createState() => _CinemaScrubBarState();
}

class _CinemaScrubBarState extends State<_CinemaScrubBar> {
  bool _hovering = false;
  bool _dragging = false;
  bool _focused = false;
  double? _hoverRatio;

  double _ratioFromDx(double dx, double width) =>
      width <= 0 ? 0.0 : (dx / width).clamp(0.0, 1.0);

  String? _chapterTitleAt(double secs) {
    String? title;
    for (final c in widget.chapters) {
      if (secs >= c.timeSecs) {
        title = c.title;
      } else {
        break;
      }
    }
    return title;
  }

  @override
  Widget build(BuildContext context) {
    final dur = widget.durationSecs > 0 ? widget.durationSecs : 1.0;
    final posRatio = (widget.positionSecs / dur).clamp(0.0, 1.0);
    final bufRatio = (widget.bufferedSecs / dur).clamp(0.0, 1.0);
    final active = _hovering || _dragging || _focused;
    final trackH = active ? 6.0 : 3.6;
    final skin = VedroSkin.of(context);
    final accent = skin.accent;
    final playedColor = skin.ctaStyle == 'contrast' ? skin.fg : skin.accent;
    final primaryInk = skin.fg;
    final secondaryInk = skin.fg2;
    final baseTrack = skin.fg.withValues(alpha: skin.isLight ? 0.16 : 0.22);
    final bufTrack = skin.fg.withValues(alpha: skin.isLight ? 0.28 : 0.34);

    final compactTime = MediaQuery.sizeOf(context).width < 480;
    final rightTimeText = widget.showRemaining && widget.durationSecs > 0
        ? '-${widget.fmtTime((widget.durationSecs - widget.positionSecs).clamp(0, widget.durationSecs))}'
        : widget.fmtTime(widget.durationSecs);

    return Row(
      children: [
        SizedBox(
          width: compactTime ? 46 : 56,
          child: Text(
            widget.fmtTime(widget.positionSecs),
            maxLines: 1,
            style: TextStyle(
              color: primaryInk.withValues(alpha: 0.90),
              fontSize: compactTime ? 11 : 11.5,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Focus(
            onFocusChange: (hasFocus) {
              if (_focused != hasFocus) setState(() => _focused = hasFocus);
            },
            onKeyEvent: (_, ev) {
              if (ev is KeyDownEvent || ev is KeyRepeatEvent) {
                if (ev.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  widget.onDpadStep?.call(-widget.seekStepSecs);
                  return KeyEventResult.handled;
                }
                if (ev.logicalKey == LogicalKeyboardKey.arrowRight) {
                  widget.onDpadStep?.call(widget.seekStepSecs);
                  return KeyEventResult.handled;
                }
              }
              if (ev is KeyDownEvent &&
                  (ev.logicalKey == LogicalKeyboardKey.select ||
                      ev.logicalKey == LogicalKeyboardKey.enter ||
                      ev.logicalKey == LogicalKeyboardKey.gameButtonA)) {
                widget.onTogglePlayPause?.call();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: _focused
                    ? Border.all(color: primaryInk.withValues(alpha: 0.85), width: 1.8)
                    : null,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final hoverSecs = _hoverRatio != null ? _hoverRatio! * dur : null;
                  final hoverChap = hoverSecs != null ? _chapterTitleAt(hoverSecs) : null;
                  final tooltipText = hoverSecs == null
                      ? ''
                      : (hoverChap != null && hoverChap.isNotEmpty
                          ? '${widget.fmtTime(hoverSecs)} · $hoverChap'
                          : widget.fmtTime(hoverSecs));
                  final estPillW = (tooltipText.length * 7.5 + 16.0).clamp(56.0, math.min(220.0, w));
                  return MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) => setState(() => _hovering = true),
                    onHover: (e) => setState(() => _hoverRatio = _ratioFromDx(e.localPosition.dx, w)),
                    onExit: (_) => setState(() {
                      _hovering = false;
                      _hoverRatio = null;
                    }),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) {
                        final secs = _ratioFromDx(d.localPosition.dx, w) * dur;
                        widget.onScrubEnd(secs);
                      },
                      onHorizontalDragStart: (d) {
                        setState(() => _dragging = true);
                        widget.onScrubStart();
                        widget.onScrubUpdate(_ratioFromDx(d.localPosition.dx, w) * dur);
                      },
                      onHorizontalDragUpdate: (d) {
                        final ratio = _ratioFromDx(d.localPosition.dx, w);
                        setState(() => _hoverRatio = ratio);
                        widget.onScrubUpdate(ratio * dur);
                      },
                      onHorizontalDragEnd: (_) {
                        final ratio = _hoverRatio ?? posRatio;
                        setState(() => _dragging = false);
                        widget.onScrubEnd(ratio * dur);
                      },
                      child: SizedBox(
                        height: 20,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.centerLeft,
                          children: [
                            // Base track
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              height: trackH,
                              decoration: BoxDecoration(
                                color: baseTrack,
                                borderRadius: BorderRadius.circular(trackH / 2),
                              ),
                            ),
                            // Buffered track
                            if (bufRatio > 0)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 140),
                                height: trackH,
                                width: w * bufRatio,
                                decoration: BoxDecoration(
                                  color: bufTrack,
                                  borderRadius: BorderRadius.circular(trackH / 2),
                                ),
                              ),
                            // Intro/Outro markers
                            for (final seg in widget.segments)
                              if (widget.durationSecs > 0)
                                Positioned(
                                  left: (seg.startSecs / dur).clamp(0.0, 1.0) * w,
                                  width: ((seg.endSecs - seg.startSecs) / dur).clamp(0.0, 1.0) * w,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 140),
                                    height: trackH,
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.72),
                                      borderRadius: BorderRadius.circular(trackH / 2),
                                    ),
                                  ),
                                ),
                            // Played progress bar
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 80),
                              height: trackH,
                              width: w * posRatio,
                              decoration: BoxDecoration(
                                color: playedColor,
                                borderRadius: BorderRadius.circular(trackH / 2),
                              ),
                            ),
                            // Chapter tick marks
                            if (widget.durationSecs > 0)
                              for (final chap in widget.chapters)
                                if (chap.timeSecs > 1.0 && chap.timeSecs < widget.durationSecs - 1.0)
                                  Positioned(
                                    left: (chap.timeSecs / dur).clamp(0.0, 1.0) * w,
                                    child: Container(
                                      width: 2,
                                      height: trackH + 2,
                                      color: skin.canvas.withValues(alpha: 0.75),
                                    ),
                                  ),
                            // Hover / TV-focus revealed sleek thumb
                            Positioned(
                              left: (w * posRatio - 5.5).clamp(0.0, (w - 11).clamp(0.0, w)),
                              child: AnimatedScale(
                                scale: active ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 140),
                                curve: VedroTheme.easeOut,
                                child: Container(
                                  width: 11,
                                  height: 11,
                                  decoration: BoxDecoration(
                                    color: playedColor,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: skin.isLight ? 0.25 : 0.6,
                                        ),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Hover timestamp & chapter tooltip pill
                            if (_hoverRatio != null && widget.durationSecs > 0)
                              Positioned(
                                left: (_hoverRatio! * w - estPillW / 2)
                                    .clamp(0.0, (w - estPillW).clamp(0.0, w)),
                                top: -28,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(maxWidth: math.min(220.0, w)),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: skin.surface2.withValues(alpha: 0.94),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: skin.borderStrong, width: 0.6),
                                    ),
                                    child: Text(
                                      tooltipText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: primaryInk,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        PressableScale(
          onTap: widget.onToggleRemaining,
          hoverScale: 1.02,
          pressScale: 0.96,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: compactTime ? 50 : 60,
            child: Text(
              rightTimeText,
              maxLines: 1,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: secondaryInk,
                fontSize: compactTime ? 11 : 11.5,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniVolumeBar extends StatefulWidget {
  const _MiniVolumeBar({required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_MiniVolumeBar> createState() => _MiniVolumeBarState();
}

class _MiniVolumeBarState extends State<_MiniVolumeBar> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final fillCol = skin.ctaStyle == 'contrast' ? skin.fg : skin.accent;
    return Focus(
      onFocusChange: (hasFocus) {
        if (_focused != hasFocus) setState(() => _focused = hasFocus);
      },
      onKeyEvent: (_, ev) {
        if (ev is KeyDownEvent || ev is KeyRepeatEvent) {
          if (ev.logicalKey == LogicalKeyboardKey.arrowLeft) {
            final next = (widget.value - 0.05).clamp(0.0, 1.0);
            if ((next - widget.value).abs() > 1e-4) {
              widget.onChanged(next);
              return KeyEventResult.handled;
            }
          }
          if (ev.logicalKey == LogicalKeyboardKey.arrowRight) {
            final next = (widget.value + 0.05).clamp(0.0, 1.0);
            if ((next - widget.value).abs() > 1e-4) {
              widget.onChanged(next);
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: _focused
              ? Border.all(color: skin.fg.withValues(alpha: 0.85), width: 1.6)
              : null,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            void update(double dx) {
              if (w <= 0) return;
              widget.onChanged((dx / w).clamp(0.0, 1.0));
            }

            return MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => update(d.localPosition.dx),
                onHorizontalDragUpdate: (d) => update(d.localPosition.dx),
                child: SizedBox(
                  height: 22,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        height: 3.5,
                        decoration: BoxDecoration(
                          color: skin.fg.withValues(alpha: skin.isLight ? 0.16 : 0.22),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Container(
                        height: 3.5,
                        width: w * widget.value.clamp(0.0, 1.0),
                        decoration: BoxDecoration(
                          color: fillCol,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Positioned(
                        left: (w * widget.value.clamp(0.0, 1.0) - 5)
                            .clamp(0.0, (w - 10).clamp(0.0, w)),
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: fillCol,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CircleHudButton extends StatefulWidget {
  const _CircleHudButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.active = false,
    this.iconSize = 18,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool active;
  final double iconSize;

  @override
  State<_CircleHudButton> createState() => _CircleHudButtonState();
}

class _CircleHudButtonState extends State<_CircleHudButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    final btn = PressableScale(
      onTap: widget.onTap,
      onHoverChanged: (v) => setState(() => _hovered = v),
      hoverScale: 1.06,
      pressScale: 0.9,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.active
              ? accent.withValues(alpha: 0.25)
              : (_hovered ? const Color(0x32FFFFFF) : const Color(0x20000000)),
          border: Border.all(
            color: widget.active
                ? accent.withValues(alpha: 0.7)
                : const Color(0x24FFFFFF),
            width: 0.7,
          ),
        ),
        child: Icon(
          widget.icon,
          size: widget.iconSize,
          color: widget.active ? accent : Colors.white,
        ),
      ),
    );
    return widget.tooltip != null ? Tooltip(message: widget.tooltip!, child: btn) : btn;
  }
}

class _DeckIconButton extends StatefulWidget {
  const _DeckIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  State<_DeckIconButton> createState() => _DeckIconButtonState();
}

class _DeckIconButtonState extends State<_DeckIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final btn = PressableScale(
      onTap: widget.onTap,
      onHoverChanged: (v) => setState(() => _hovered = v),
      hoverScale: 1.06,
      pressScale: 0.9,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _hovered
              ? skin.fg.withValues(alpha: skin.isLight ? 0.10 : 0.14)
              : Colors.transparent,
        ),
        child: Icon(widget.icon, size: 19.5, color: skin.fg),
      ),
    );
    return widget.tooltip != null ? Tooltip(message: widget.tooltip!, child: btn) : btn;
  }
}

class _DeckPillButton extends StatefulWidget {
  const _DeckPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.active = false,
    this.focusNode,
    this.themed = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool active;
  final FocusNode? focusNode;
  final bool themed;
  final bool compact;

  @override
  State<_DeckPillButton> createState() => _DeckPillButtonState();
}

class _DeckPillButtonState extends State<_DeckPillButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final accent = widget.themed ? skin.accent : Theme.of(context).colorScheme.secondary;
    final idleBg = widget.themed
        ? skin.fg.withValues(alpha: _hovered ? (skin.isLight ? 0.13 : 0.18) : (skin.isLight ? 0.07 : 0.10))
        : (_hovered ? const Color(0x2AFFFFFF) : const Color(0x18FFFFFF));
    final idleBorder = widget.themed ? skin.border : const Color(0x20FFFFFF);
    final idleFg = widget.themed ? skin.fg : const Color(0xF0FFFFFF);
    final pillRadius = widget.themed ? skin.pillRadius.clamp(7.0, 14.0) : 9.0;
    return PressableScale(
      focusNode: widget.focusNode,
      onTap: widget.onTap,
      onHoverChanged: (v) => setState(() => _hovered = v),
      hoverScale: 1.04,
      pressScale: 0.94,
      borderRadius: BorderRadius.circular(pillRadius),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: VedroTheme.easeOut,
        height: widget.compact ? 28 : 31,
        padding: EdgeInsets.symmetric(horizontal: widget.compact ? 9 : 10.5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.active
              ? accent.withValues(alpha: widget.themed && skin.isLight ? 0.16 : 0.24)
              : idleBg,
          borderRadius: BorderRadius.circular(pillRadius),
          border: Border.all(
            color: widget.active ? accent.withValues(alpha: 0.68) : idleBorder,
            width: 0.75,
          ),
        ),
        child: Text(
          widget.label,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: widget.active ? accent : idleFg,
            fontSize: widget.compact ? 11.5 : 12,
            fontWeight: widget.active ? FontWeight.w600 : FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _SheetOptionRow extends StatelessWidget {
  const _SheetOptionRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return PressableScale(
      onTap: onTap,
      hoverScale: 1.01,
      pressScale: 0.98,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1F2A42) : const Color(0xFF1E202B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : const Color(0xFF2D3142),
            width: selected ? 1.4 : 0.9,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 19,
              color: selected ? accent : const Color(0xFF6E748A),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFB3B9C9),
                        fontSize: 12,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '当前',
                  style: TextStyle(
                    color: Color(0xFF0B0B0D),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
