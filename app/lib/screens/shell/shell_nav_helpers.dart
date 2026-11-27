part of '../shell_screen.dart';

/// Position of the active destination inside [navItems] (or `null` when none matches).
int? _navSlot(List<(int, String, IconData)> navItems, int activeIndex) {
  for (var i = 0; i < navItems.length; i++) {
    if (navItems[i].$1 == activeIndex) return i;
  }
  return null;
}

Rect _globalRectOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return Rect.zero;
  return box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
}

/// Consolidated desktop "⋯" menu: keeps the header calm (macOS toolbar style)
/// instead of a row of five look-alike circle buttons.
void _showShellOverflowMenu({
  required BuildContext context,
  required Rect anchorRect,
  required bool signedIn,
  required VoidCallback onOpenLocalMedia,
  required VoidCallback onOpenNetworkUrl,
  required VoidCallback onOpenFavorites,
  VoidCallback? onOpenLayout,
  required VoidCallback onRefresh,
}) {
  showVedroActionMenu(
    context: context,
    anchorRect: anchorRect,
    items: [
      VedroDropdownItem(
        value: 'local',
        label: '本地播放',
        subtitle: '打开视频文件或文件夹，也可直接拖入窗口',
        icon: Icons.folder_open_rounded,
        onTapOverride: onOpenLocalMedia,
      ),
      VedroDropdownItem(
        value: 'url',
        label: '网络链接',
        subtitle: 'HTTP / M3U8 / RTSP / RTMP',
        icon: Icons.link_rounded,
        onTapOverride: onOpenNetworkUrl,
      ),
      if (signedIn) ...[
        VedroDropdownItem(
          value: 'fav',
          label: '我的收藏',
          icon: Icons.favorite_border_rounded,
          onTapOverride: onOpenFavorites,
        ),
        if (onOpenLayout != null)
          VedroDropdownItem(
            value: 'layout',
            label: '自定义首页布局',
            icon: Icons.dashboard_customize_outlined,
            onTapOverride: onOpenLayout,
          ),
        VedroDropdownItem(
          value: 'refresh',
          label: '刷新首页',
          icon: Icons.refresh_rounded,
          onTapOverride: onRefresh,
        ),
      ],
    ],
  );
}

/// Destination label whose color / weight cross-fade on a spring instead of snapping.
class _NavLabel extends StatelessWidget {
  const _NavLabel({
    this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.idleColor,
    required this.fontSize,
  });

  final IconData? icon;
  final String label;
  final bool active;
  final Color activeColor;
  final Color idleColor;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: active ? activeColor : idleColor),
      duration: const Duration(milliseconds: 220),
      curve: VedroTheme.easeOut,
      builder: (context, color, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}
