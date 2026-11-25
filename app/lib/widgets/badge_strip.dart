import 'package:flutter/material.dart';

import '../core/theme/vedro_theme.dart';

/// Displays cinema-grade technical pills (Dolby Vision, Dolby Atmos, HDR10+, 4K, Direct Play, embygo).
class BadgeStrip extends StatelessWidget {
  const BadgeStrip({super.key, required this.badges, this.compact = false});

  final List<String> badges;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: compact ? 4 : 6,
      runSpacing: compact ? 4 : 6,
      children: badges.map((b) => _BadgePill(label: b, compact: compact)).toList(),
    );
  }
}

class _BadgePill extends StatelessWidget {
  const _BadgePill({required this.label, required this.compact});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final lower = label.toLowerCase();
    final Color color;
    if (lower.contains('dolby vision') || lower.contains('dovi')) {
      color = VedroTheme.dolbyGold;
    } else if (lower.contains('atmos') || lower.contains('dts:x')) {
      color = VedroTheme.atmosCyan;
    } else if (lower.contains('hdr') || lower.contains('hlg')) {
      color = VedroTheme.hdrPurple;
    } else if (lower.contains('embygo') || lower.contains('direct')) {
      color = VedroTheme.embygoGreen;
    } else {
      color = VedroTheme.accent;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
