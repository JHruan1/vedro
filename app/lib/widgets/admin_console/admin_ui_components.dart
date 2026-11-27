part of '../admin_console_pane.dart';

class _AdminTabStrip extends StatelessWidget {
  const _AdminTabStrip({
    required this.selected,
    required this.tabs,
    required this.onSelected,
  });

  final String selected;
  final List<(String id, String label, int? count)> tabs;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return VedroAdaptiveSurface(
      borderRadius: 999,
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 480;
          Widget buildPill((String id, String label, int? count) tab, {required bool expand}) {
            final active = tab.$1 == selected;
            final pill = PressableScale(
              onTap: () => onSelected(tab.$1),
              borderRadius: BorderRadius.circular(999),
              hoverScale: 1.01,
              pressScale: 0.97,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 170),
                height: 32,
                padding: EdgeInsets.symmetric(horizontal: expand ? 6 : 14),
                decoration: BoxDecoration(
                  color: active ? skin.activePillBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tab.$2,
                      style: TextStyle(
                        color: active ? skin.activePillFg : skin.fg2,
                        fontSize: 12.5,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (tab.$3 != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        '${tab.$3}',
                        style: TextStyle(
                          color: active
                              ? skin.activePillFg.withValues(alpha: 0.85)
                              : skin.fg3,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
            return expand ? Expanded(child: pill) : pill;
          }

          if (wide) {
            return Row(
              children: [for (final t in tabs) buildPill(t, expand: true)],
            );
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  buildPill(tabs[i], expand: false),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BentoMetricCard extends StatelessWidget {
  const _BentoMetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return SizedBox(
      width: width,
      child: VedroAdaptiveSurface(
        borderRadius: skin.cardRadius.clamp(14.0, 20.0),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 15, color: tint),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: skin.fg,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: skin.fg3, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ConsolePanel extends StatelessWidget {
  const _ConsolePanel({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return VedroAdaptiveSurface(
      borderRadius: skin.cardRadius.clamp(14.0, 22.0),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16.5, color: skin.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: skin.fg,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          Divider(height: 22, color: skin.border),
          child,
        ],
      ),
    );
  }
}

class _EmptyConsoleState extends StatelessWidget {
  const _EmptyConsoleState({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return VedroAdaptiveSurface(
      borderRadius: skin.cardRadius.clamp(14.0, 22.0),
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 28, color: skin.fg3),
          const SizedBox(height: 10),
          Text(message, style: TextStyle(color: skin.fg3, fontSize: 13.5)),
        ],
      ),
    );
  }
}

class _StatusDotBadge extends StatelessWidget {
  const _StatusDotBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 2),
      decoration: BoxDecoration(
        color: skin.subtleChipBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: skin.fg2, fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _CircleIconBtn extends StatelessWidget {
  const _CircleIconBtn({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final fg = danger ? VedroTheme.danger : skin.fg2;
    final btn = PressableScale(
      onTap: onTap,
      hoverScale: 1.05,
      pressScale: 0.93,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: danger
              ? VedroTheme.danger.withValues(alpha: 0.12)
              : (skin.isLight
                  ? Colors.black.withValues(alpha: 0.05)
                  : Colors.white.withValues(alpha: 0.08)),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 15, color: fg),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: btn) : btn;
  }
}

class _CompactActionBtn extends StatelessWidget {
  const _CompactActionBtn({
    required this.icon,
    required this.label,
    this.onTap,
    this.primary = false,
    this.danger = false,
    this.accent,
    this.loading = false,
    this.expanded = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool danger;
  final Color? accent;
  final bool loading;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final bg = danger
        ? VedroTheme.danger.withValues(alpha: 0.14)
        : (primary
            ? (skin.ctaStyle == 'contrast' && !skin.isLight
                ? Colors.white
                : (accent ?? skin.accent))
            : (skin.isLight
                ? Colors.black.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.09)));
    final fg = danger
        ? VedroTheme.danger
        : (primary ? VedroTheme.highContrastOn(bg) : skin.fg);

    final pill = PressableScale(
      onTap: loading ? null : onTap,
      hoverScale: 1.02,
      pressScale: 0.96,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null ? skin.subtleChipBg : bg,
          borderRadius: BorderRadius.circular(999),
          border: (primary || danger)
              ? null
              : Border.all(
                  color: skin.isLight ? skin.border : Colors.white.withValues(alpha: 0.12),
                  width: 0.7,
                ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 1.7, color: fg),
              )
            else
              Icon(icon, size: 14, color: onTap == null ? skin.fg3 : fg),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onTap == null ? skin.fg3 : fg,
                  fontSize: 12.5,
                  fontWeight: primary ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return expanded ? SizedBox(width: double.infinity, child: pill) : pill;
  }
}

class _IosDialogField extends StatelessWidget {
  const _IosDialogField({
    required this.controller,
    required this.hintText,
    this.autofocus = false,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final bool autofocus;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return SizedBox(
      height: 40,
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        style: TextStyle(color: skin.fg, fontSize: 13.5),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: skin.fg3, fontSize: 13),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          filled: true,
          fillColor: skin.isLight
              ? Colors.black.withValues(alpha: 0.045)
              : Colors.white.withValues(alpha: 0.08),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: BorderSide(color: skin.accent, width: 1.1),
          ),
        ),
      ),
    );
  }
}

class _MiniQuotaStat extends StatelessWidget {
  const _MiniQuotaStat({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: skin.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: skin.fg3, fontSize: 11)),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
