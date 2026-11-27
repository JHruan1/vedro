part of '../detail_screen.dart';

class _AppleMicroBadge extends StatelessWidget {
  const _AppleMicroBadge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2.5),
      decoration: BoxDecoration(
        color: skin.subtleChipBg,
        borderRadius: BorderRadius.circular(4.5),
        border: skin.frameStyle == 'neon'
            ? Border.all(color: skin.accent.withValues(alpha: 0.35), width: 0.6)
            : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: skin.fg,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _AppleCircleActionButton extends StatefulWidget {
  const _AppleCircleActionButton({
    required this.icon,
    required this.active,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_AppleCircleActionButton> createState() => _AppleCircleActionButtonState();
}

class _AppleCircleActionButtonState extends State<_AppleCircleActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final isSquareish = skin.pillRadius < 20;
    return PressableScale(
      onTap: widget.onTap,
      onHoverChanged: (v) => setState(() => _hovered = v),
      hoverScale: 1.07,
      pressScale: 0.91,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: VedroTheme.easeOut,
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: isSquareish ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: isSquareish ? BorderRadius.circular(skin.pillRadius) : null,
          color: widget.active
              ? widget.color.withValues(alpha: 0.20)
              : (_hovered ? skin.subtleChipHoverBg : skin.subtleChipBg),
          border: skin.frameStyle == 'borderless'
              ? null
              : Border.all(color: _hovered ? skin.borderStrong : skin.border, width: 0.8),
        ),
        child: Icon(widget.icon, size: 20, color: widget.color),
      ),
    );
  }
}

class _ChaptersSection extends StatelessWidget {
  const _ChaptersSection({
    required this.chapters,
    required this.padX,
    required this.accent,
    required this.onSelectChapter,
  });

  final List<ChapterModel> chapters;
  final double padX;
  final Color accent;
  final ValueChanged<int> onSelectChapter;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: padX),
          child: Text(
            '章节导览 (${chapters.length})',
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
        const SizedBox(height: 12),
        SizedBox(
          height: 54,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: ListView.separated(
              padding: EdgeInsets.symmetric(horizontal: padX),
              scrollDirection: Axis.horizontal,
              itemCount: chapters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, idx) {
                final ch = chapters[idx];
                final title = ch.name.isNotEmpty ? ch.name : '第 ${idx + 1} 章';
                final ts = fmtTicksClock(ch.startPositionTicks);
                return PressableScale(
                  onTap: () => onSelectChapter(ch.startPositionTicks),
                  hoverScale: 1.03,
                  pressScale: 0.96,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: skin.surface,
                      borderRadius: BorderRadius.circular(skin.cardRadius.clamp(6.0, 14.0)),
                      border: skin.cardBorder(),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          ts,
                          style: TextStyle(
                            color: skin.fg3,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          style: TextStyle(
                            color: skin.fg,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ExpandableOverview extends StatefulWidget {
  const _ExpandableOverview({
    required this.text,
    required this.collapsedLines,
    required this.accent,
    required this.aiReady,
    required this.translating,
    required this.isTranslated,
    required this.onTranslateToggle,
  });

  final String text;
  final int collapsedLines;
  final Color accent;
  final bool aiReady;
  final bool translating;
  final bool isTranslated;
  final VoidCallback onTranslateToggle;

  @override
  State<_ExpandableOverview> createState() => _ExpandableOverviewState();
}

class _ExpandableOverviewState extends State<_ExpandableOverview> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final style = TextStyle(
      color: skin.isLight ? skin.fg2 : skin.fg.withValues(alpha: 0.88),
      fontSize: 14.5,
      height: 1.62,
      letterSpacing: 0.05,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: widget.collapsedLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = tp.didExceedMaxLines;
        tp.dispose();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: VedroTheme.easeOut,
              alignment: Alignment.topLeft,
              child: Text(
                widget.text,
                maxLines: _expanded ? null : widget.collapsedLines,
                overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                style: style,
              ),
            ),
            if (overflows || widget.aiReady) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 14,
                children: [
                  if (overflows)
                    PressableScale(
                      onTap: () => setState(() => _expanded = !_expanded),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text(
                          _expanded ? '收起简介' : '展开全部',
                          style: TextStyle(
                            color: skin.fg,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  if (widget.aiReady)
                    PressableScale(
                      onTap: widget.onTranslateToggle,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome_rounded, size: 13.5, color: widget.accent),
                            const SizedBox(width: 4),
                            Text(
                              widget.translating
                                  ? 'AI 翻译中…'
                                  : (widget.isTranslated ? '显示原文' : 'AI 翻译简介'),
                              style: TextStyle(
                                color: widget.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TitleHeadline extends StatelessWidget {
  const _TitleHeadline(this.text, this.wide, {this.centered = false});
  final String text;
  final bool wide;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return Text(
      text,
      maxLines: 2,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      overflow: TextOverflow.ellipsis,
      style: skin.applyHeadlineMood(
        TextStyle(
          color: skin.fg,
          fontSize: wide ? 40 : 26,
          fontWeight: FontWeight.w700,
          letterSpacing: wide ? -0.9 : -0.6,
          height: 1.1,
        ),
      ),
    );
  }
}

/// Skin-adaptive Primary Play CTA button (supports contrast, accent, dual-tone gradient, and outline styles).
class _ProgressPlayPill extends StatelessWidget {
  const _ProgressPlayPill({
    required this.label,
    required this.progress,
    required this.accent,
    required this.onTap,
    this.fullWidth = false,
    this.autofocus = false,
  });

  final String label;
  final double progress;
  final Color accent;
  final VoidCallback onTap;
  final bool fullWidth;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final h = fullWidth ? 50.0 : 46.0;
    final r = fullWidth ? skin.cardRadius.clamp(6.0, 16.0) : skin.radiusForPill(h);
    return PressableScale(
      onTap: onTap,
      autofocus: autofocus,
      hoverScale: fullWidth ? 1.015 : 1.03,
      pressScale: 0.96,
      child: Container(
        height: h,
        width: fullWidth ? double.infinity : null,
        constraints: fullWidth
            ? const BoxConstraints(minHeight: 50)
            : const BoxConstraints(minWidth: 152, maxWidth: 296),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: skin.primaryCtaBg,
          gradient: skin.primaryCtaGradient,
          borderRadius: BorderRadius.circular(r),
          border: skin.primaryCtaBorder,
          boxShadow: skin.primaryCtaShadow,
        ),
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_arrow_rounded, size: 23, color: skin.primaryCtaFg),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: skin.primaryCtaFg,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
