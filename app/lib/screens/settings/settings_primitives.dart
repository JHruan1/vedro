part of '../settings_screen.dart';

/// Genuine macOS / iOS System Settings vibrant gradient squircle icon tile.
class _AppleSquircleIcon extends StatelessWidget {
  const _AppleSquircleIcon({
    required this.icon,
    required this.top,
    required this.bottom,
    this.size = 26,
  });

  final IconData icon;
  final Color top;
  final Color bottom;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ),
        borderRadius: BorderRadius.circular(size * 0.27),
        boxShadow: [
          BoxShadow(
            color: bottom.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, size: size * 0.58, color: Colors.white),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          color: skin.fg3,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _GroupedCard extends StatelessWidget {
  const _GroupedCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return VedroAdaptiveSurface(
      borderRadius: skin.cardRadius.clamp(12.0, 22.0),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 16, endIndent: 16, color: skin.border),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _InfoKVRow extends StatelessWidget {
  const _InfoKVRow(
    this.label,
    this.value, {
    this.mono = false,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool mono;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(color: skin.fg2, fontSize: 13.5),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: highlight ? skin.accent : skin.fg,
                fontSize: 13.5,
                fontFamily: mono ? 'monospace' : null,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.title,
    required this.onTap,
    this.trailing,
  });

  final String title;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(child: Text(title, style: TextStyle(color: skin.fg, fontSize: 14))),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: selected ? skin.fg : skin.fg2,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: skin.fg3, fontSize: 11.5),
                    ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_rounded, size: 18, color: skin.accent),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _AppleMenuPickerRow<T> extends StatelessWidget {
  const _AppleMenuPickerRow({
    required this.title,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String title;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final safeValue = items.containsKey(value) ? value : items.keys.first;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          Expanded(child: Text(title, style: TextStyle(color: skin.fg, fontSize: 14))),
          const SizedBox(width: 12),
          VedroPullDownButton<T>(
            height: 34,
            value: safeValue,
            items: items.entries
                .map((e) => VedroDropdownItem<T>(value: e.key, label: e.value))
                .toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _InlineSegmentedRow<T> extends StatelessWidget {
  const _InlineSegmentedRow({
    required this.title,
    required this.value,
    required this.items,
    required this.onChanged,
    this.keyPrefix,
  });

  final String title;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final seg = Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: skin.surface2,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: skin.border, width: 0.7),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: items.map((entry) {
            final active = entry.$1 == value;
            return PressableScale(
              key: keyPrefix != null ? ValueKey('$keyPrefix-${entry.$1}') : null,
              onTap: () => onChanged(entry.$1),
              hoverScale: 1.0,
              pressScale: 0.96,
              borderRadius: BorderRadius.circular(7),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: active ? skin.activePillBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  entry.$2,
                  style: TextStyle(
                    color: active ? skin.activePillFg : skin.fg3,
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 460) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: skin.fg, fontSize: 14)),
                const SizedBox(height: 8),
                seg,
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(child: Text(title, style: TextStyle(color: skin.fg, fontSize: 14))),
              const SizedBox(width: 10),
              seg,
            ],
          ),
        );
      },
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return PressableScale(
      onTap: () => onChanged(!value),
      hoverScale: 1.0,
      pressScale: 0.99,
      borderRadius: BorderRadius.circular(skin.cardRadius.clamp(10.0, 18.0)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: skin.fg, fontSize: 14)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: TextStyle(color: skin.fg3, fontSize: 12)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            ExcludeFocus(
              child: Transform.scale(
                scale: 0.78,
                child: CupertinoSwitch(
                  value: value,
                  activeTrackColor: skin.accent,
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.title,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String title;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final step = divisions > 0 ? (max - min) / divisions : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: VedroPrecisionSlider(
        label: title,
        valueText: valueText,
        value: value.clamp(min, max),
        min: min,
        max: max,
        step: step,
        onChanged: onChanged,
      ),
    );
  }
}
