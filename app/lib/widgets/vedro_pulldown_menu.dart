part of 'vedro_ui.dart';

/// Present an anchored floating glass action menu (macOS / iOS pull-down style)
/// from [anchorRect]. Each item should carry an `onTapOverride` action.
Future<void> showVedroActionMenu({
  required BuildContext context,
  required Rect anchorRect,
  required List<VedroDropdownItem<String>> items,
  String? selectedValue,
  ThemeData? theme,
  double minWidth = 224,
  double maxWidth = 300,
}) {
  HapticFeedback.selectionClick();
  return Navigator.of(context).push(
    _VedroPullDownRoute<void>(
      triggerRect: anchorRect,
      theme: theme ?? Theme.of(context),
      minWidth: minWidth,
      maxWidth: maxWidth,
      items: items,
      selectedValue: selectedValue ?? const Object(),
      onSelectItem: (item) => item.onTapOverride?.call(),
    ),
  );
}

/// Option descriptor for `VedroPullDownButton<T>` (iOS-style Floating Glass Pull-Down Menu).
class VedroDropdownItem<T> {
  const VedroDropdownItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
    this.itemKey,
    this.onTapOverride,
    this.isDestructive = false,
  });

  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
  final Key? itemKey;
  final VoidCallback? onTapOverride;
  final bool isDestructive;
}

/// iOS 26 / Apple TV+ Style Pull-Down Selector Button (`下拉框`) with Floating Frosted / Liquid Glass Popover Menu.
/// Automatically clamps inside screen viewport bounds (zero overflow on 360px phones or 4K desktops).
class VedroPullDownButton<T> extends StatefulWidget {
  const VedroPullDownButton({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.prefixIcon,
    this.prefixLabel,
    this.displayLabelOverride,
    this.expanded = false,
    this.height = 38.0,
    this.menuMinWidth = 236.0,
    this.menuMaxWidth = 360.0,
  });

  final List<VedroDropdownItem<T>> items;
  final T value;
  final ValueChanged<T> onChanged;
  final IconData? prefixIcon;
  final String? prefixLabel;
  final String? displayLabelOverride;
  final bool expanded;
  final double height;
  final double menuMinWidth;
  final double menuMaxWidth;

  @override
  State<VedroPullDownButton<T>> createState() => _VedroPullDownButtonState<T>();
}

class _VedroPullDownButtonState<T> extends State<VedroPullDownButton<T>> {
  bool _isOpen = false;

  VedroDropdownItem<T>? get _activeItem {
    for (final item in widget.items) {
      if (item.onTapOverride == null && item.value == widget.value) {
        return item;
      }
    }
    for (final item in widget.items) {
      if (item.onTapOverride == null) return item;
    }
    return widget.items.isNotEmpty ? widget.items.first : null;
  }

  Future<void> _openMenu() async {
    if (widget.items.isEmpty || _isOpen) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    final triggerRect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final inheritedTheme = Theme.of(context);

    HapticFeedback.selectionClick();
    setState(() => _isOpen = true);
    try {
      await Navigator.of(context).push(
        _VedroPullDownRoute<void>(
          triggerRect: triggerRect,
          theme: inheritedTheme,
          minWidth: math.max(widget.menuMinWidth, box.size.width),
          maxWidth: widget.menuMaxWidth,
          items: widget.items,
          selectedValue: widget.value,
          onSelectItem: (item) {
            if (item.onTapOverride != null) {
              item.onTapOverride!();
            } else {
              widget.onChanged(item.value);
            }
          },
        ),
      );
    } finally {
      if (mounted) setState(() => _isOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final current = _activeItem;
    final mainLabel = widget.displayLabelOverride ?? current?.label ?? '';
    final r = skin.pillRadius >= 100
        ? (widget.height * 0.5)
        : skin.cardRadius.clamp(10.0, 16.0);

    final isGlass = skin.usesGlassPanels;
    final isLiquid = skin.isLiquidGlass;
    final bg = isLiquid
        ? skin.unifiedTileColor(hovered: _isOpen)
        : (isGlass
            ? skin.unifiedPanelColor
            : (skin.isLight
                ? skin.fg.withValues(alpha: _isOpen ? 0.09 : 0.055)
                : Colors.white.withValues(alpha: _isOpen ? 0.13 : 0.08)));

    final rowContent = Row(
      mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (widget.prefixIcon != null) ...[
          Icon(widget.prefixIcon, size: 15.5, color: skin.accent),
          const SizedBox(width: 7),
        ],
        if (widget.prefixLabel != null && widget.prefixLabel!.isNotEmpty) ...[
          Text(
            widget.prefixLabel!,
            style: TextStyle(
              color: skin.fg3,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          fit: widget.expanded ? FlexFit.tight : FlexFit.loose,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: widget.expanded ? double.infinity : 260,
            ),
            child: Text(
              mainLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: skin.fg,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        AnimatedRotation(
          turns: _isOpen ? 0.5 : 0.0,
          duration: const Duration(milliseconds: 180),
          curve: VedroTheme.easeOut,
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 17,
            color: skin.fg2,
          ),
        ),
      ],
    );

    Widget pill;
    if (isLiquid) {
      final pillBg = VedroLiquidGlassShader.liquidFillColor(
        isLight: skin.isLight,
        canvas: skin.canvas,
        surface: skin.surface,
        surface2: skin.surface2,
        density: VedroGlassDensity.panel,
        highlighted: _isOpen,
      );
      pill = CustomPaint(
        foregroundPainter: LiquidGlassRimPainter(
          radius: r,
          isLight: skin.isLight,
          accent: skin.accent,
          selected: _isOpen,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(r),
          child: Container(
            height: widget.height,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: pillBg,
              gradient: VedroLiquidGlassShader.liquidSheenGradient(
                isLight: skin.isLight,
                accent: skin.accent,
              ),
            ),
            child: rowContent,
          ),
        ),
      );
    } else {
      pill = AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: widget.height,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(r),
          border: Border.all(
            color: _isOpen
                ? skin.accent.withValues(alpha: 0.65)
                : (skin.isLight ? skin.border : Colors.white.withValues(alpha: 0.14)),
            width: _isOpen ? 1.1 : 0.8,
          ),
        ),
        child: rowContent,
      );
    }

    final button = PressableScale(
      onTap: _openMenu,
      hoverScale: 1.015,
      pressScale: 0.97,
      child: pill,
    );

    return widget.expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class _VedroPullDownRoute<T> extends PopupRoute<T> {
  _VedroPullDownRoute({
    required this.triggerRect,
    required this.theme,
    required this.minWidth,
    required this.maxWidth,
    required this.items,
    required this.selectedValue,
    required this.onSelectItem,
  });

  final Rect triggerRect;
  final ThemeData theme;
  final double minWidth;
  final double maxWidth;
  final List<VedroDropdownItem<dynamic>> items;
  final dynamic selectedValue;
  final ValueChanged<VedroDropdownItem<dynamic>> onSelectItem;

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: 0.08);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss menu';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 240);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 165);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final safeTop = media.padding.top + 52.0;
    final safeBottom = screen.height - media.padding.bottom - 12.0;
    final skin = theme.extension<VedroSkin>() ?? VedroSkin.immersiveCinema;

    final availW = (screen.width - 24.0).clamp(180.0, maxWidth);
    final menuW = minWidth.clamp(180.0, availW);
    final alignRight = triggerRect.center.dx > screen.width * 0.56;
    final rawLeft = alignRight ? (triggerRect.right - menuW) : triggerRect.left;
    final left = rawLeft.clamp(12.0, math.max(12.0, screen.width - menuW - 12.0)).toDouble();

    final spaceBelow = safeBottom - triggerRect.bottom - 6.0;
    final spaceAbove = triggerRect.top - safeTop - 6.0;
    final openUpward = spaceBelow < 180.0 && spaceAbove > spaceBelow;
    final maxMenuH = (openUpward ? spaceAbove : spaceBelow).clamp(140.0, 380.0);
    final startWFrac = (triggerRect.width / menuW).clamp(0.22, 1.0);
    final startR = math.min(triggerRect.width, triggerRect.height) * 0.5;
    final contentAlign = Alignment(alignRight ? 1.0 : -1.0, openUpward ? 1.0 : -1.0);

    // Glasmio-inspired smooth linear-decelerate button-to-menu morph curve (zero wobble).
    final morphCurve = CurvedAnimation(
      parent: animation,
      curve: const Cubic(0.22, 1.0, 0.36, 1.0),
      reverseCurve: Curves.easeInCubic,
    );

    final r = skin.cardRadius.clamp(12.0, 22.0);
    final isLiquid = skin.isLiquidGlass;
    final isFrosted = skin.usesGlassPanels && !isLiquid;
    final isGlassTheme = isLiquid || isFrosted;
    final liveSigma = isLiquid
        ? (VedroLiquidGlassShader.isAvailable
            ? VedroLiquidGlassShader.gpuBlurSigma(VedroGlassDensity.menu)
            : PlatformPerfProfile.clampLiveBlur(20.0))
        : (isFrosted ? PlatformPerfProfile.clampLiveBlur(20.0) : 0.0);
    final baseSurface = skin.isLight
        ? (isGlassTheme ? Colors.white : skin.surface)
        : Color.lerp(skin.surface2, skin.surface, 0.32)!;
    final menuFill = isLiquid
        ? VedroLiquidGlassShader.liquidFillColor(
            isLight: skin.isLight,
            canvas: skin.canvas,
            surface: skin.surface,
            surface2: skin.surface2,
            density: VedroGlassDensity.menu,
          )
        : (isFrosted
            ? baseSurface.withValues(alpha: skin.isLight ? 0.88 : 0.86)
            : baseSurface.withValues(alpha: 0.98));

    final divColor = skin.isLight
        ? Colors.black.withValues(alpha: 0.07)
        : Colors.white.withValues(alpha: 0.09);
    final selectedIdx = items.indexWhere((e) => e.value == selectedValue);
    final menuList = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: menuW,
        maxWidth: menuW,
        maxHeight: maxMenuH,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              key: const ValueKey('vedro-pulldown-menu-list'),
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var idx = 0; idx < items.length; idx++) ...[
                    if (idx > 0)
                      Divider(
                        height: 1,
                        thickness: 0.55,
                        indent: 14,
                        endIndent: 14,
                        color: divColor,
                      ),
                    _VedroPullDownRow(
                      key: items[idx].itemKey,
                      entry: items[idx],
                      skin: skin,
                      isSelected: items[idx].value == selectedValue,
                      autofocus: selectedIdx >= 0 && selectedIdx < 6
                          ? idx == selectedIdx
                          : idx == 0,
                      onExecute: () {
                        HapticFeedback.selectionClick();
                        Navigator.of(context).pop();
                        onSelectItem(items[idx]);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Widget buildMenuCard({
      required double curRadius,
      required double curSigma,
      required double shellOpacity,
      required Widget child,
    }) {
      final body = DecoratedBox(
        decoration: BoxDecoration(
          color: menuFill.withValues(alpha: (menuFill.a * shellOpacity).clamp(0.0, 1.0)),
          gradient: isLiquid
              ? VedroLiquidGlassShader.liquidSheenGradient(
                  isLight: skin.isLight,
                  accent: skin.accent,
                  intensity: 1.1,
                  opacityFactor: shellOpacity,
                )
              : null,
        ),
        child: child,
      );
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(curRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: (skin.isLight ? 0.16 : 0.54) * shellOpacity,
              ),
              blurRadius: 32,
              spreadRadius: 0,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: CustomPaint(
          foregroundPainter: isLiquid
              ? LiquidGlassRimPainter(
                  radius: curRadius,
                  isLight: skin.isLight,
                  accent: skin.accent,
                  intensity: 1.15 * shellOpacity,
                )
              : null,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: isLiquid
                ? const BoxDecoration()
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(curRadius),
                    border: Border.all(
                      color: (isFrosted
                              ? (skin.isLight
                                  ? Colors.black.withValues(alpha: 0.09)
                                  : Colors.white.withValues(alpha: 0.22))
                              : skin.borderStrong)
                          .withValues(
                        alpha: ((isFrosted
                                    ? (skin.isLight ? 0.09 : 0.22)
                                    : skin.borderStrong.a) *
                                shellOpacity)
                            .clamp(0.0, 1.0),
                      ),
                      width: 0.85,
                    ),
                  ),
            child: VedroLiquidGlassBackdrop(
              borderRadius: curRadius,
              blurSigma: curSigma,
              enableRefraction: isLiquid,
              isLight: skin.isLight,
              accent: skin.accent,
              liquidSpecular: skin.liquidSpecular,
              density: VedroGlassDensity.menu,
              suspendDuringPageTransition: false,
              intensityOverride: isLiquid ? (1.15 * shellOpacity).clamp(0.4, 1.35) : null,
              child: body,
            ),
          ),
        ),
      );
    }

    return Theme(
      data: theme,
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: morphCurve,
            builder: (_, __) {
              final t = morphCurve.value.clamp(0.0, 1.0);
              // Single unified layout tree from t=0..1 using true intrinsic menuList size:
              // ZERO outer Opacity layer so BackdropFilter stays in the root screen pass
              // for pixel-locked 360° Liquid Glass optics from frame 0!
              final curSigma = liveSigma * (0.45 + 0.55 * t);
              final curR = (startR + (r - startR) * t).clamp(8.0, 26.0).toDouble();
              final wFactor = (startWFrac + (1.0 - startWFrac) * t).clamp(0.22, 1.0).toDouble();
              final hFactor = (0.20 + 0.80 * t).clamp(0.20, 1.0).toDouble();
              final shellOpacity = (t / 0.26).clamp(0.0, 1.0);
              final contentOpacity = ((t - 0.08) / 0.48).clamp(0.0, 1.0);
              return Positioned(
                left: alignRight ? null : left,
                right: alignRight
                    ? (screen.width - (left + menuW)).clamp(12.0, screen.width - 12.0).toDouble()
                    : null,
                top: openUpward
                    ? null
                    : (triggerRect.bottom + 6.0).clamp(safeTop, safeBottom - 60.0).toDouble(),
                bottom: openUpward
                    ? (screen.height - (triggerRect.top - 6.0))
                        .clamp(12.0, screen.height - safeTop - 60.0)
                        .toDouble()
                    : null,
                child: buildMenuCard(
                  curRadius: curR,
                  curSigma: curSigma,
                  shellOpacity: shellOpacity,
                  child: ClipRect(
                    child: Align(
                      alignment: contentAlign,
                      widthFactor: wFactor,
                      heightFactor: hFactor,
                      child: Opacity(
                        opacity: contentOpacity,
                        child: menuList,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Edge-filling, zero-leak pull-down menu row shared across ALL platforms (macOS,
/// Windows, Linux, iOS, Android). Starts flush at `y = 0` and ends flush at the bottom
/// so the outer `ClipRRect(curRadius)` clips hovered/focused/selected fills cleanly
/// into the menu's rounded corners with ZERO top or bottom strips leaking out.
class _VedroPullDownRow extends StatefulWidget {
  const _VedroPullDownRow({
    super.key,
    required this.entry,
    required this.skin,
    required this.isSelected,
    required this.autofocus,
    required this.onExecute,
  });

  final VedroDropdownItem<dynamic> entry;
  final VedroSkin skin;
  final bool isSelected;
  final bool autofocus;
  final VoidCallback onExecute;

  @override
  State<_VedroPullDownRow> createState() => _VedroPullDownRowState();
}

class _VedroPullDownRowState extends State<_VedroPullDownRow> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final entry = widget.entry;
    final textColor = entry.isDestructive ? VedroTheme.danger : skin.fg;
    final showFocusHighlight =
        _focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final activeBg = _pressed
        ? skin.fg.withValues(alpha: skin.isLight ? 0.11 : 0.15)
        : ((_hovered || showFocusHighlight)
            ? skin.fg.withValues(alpha: skin.isLight ? 0.065 : 0.095)
            : (widget.isSelected
                ? skin.fg.withValues(alpha: skin.isLight ? 0.04 : 0.055)
                : Colors.transparent));

    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onShowHoverHighlight: (v) {
        if (_hovered != v) setState(() => _hovered = v);
      },
      onFocusChange: (v) {
        if (_focused != v) setState(() => _focused = v);
      },
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onExecute();
            return null;
          },
        ),
      },
      mouseCursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onExecute,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          color: activeBg,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 24,
                child: widget.isSelected
                    ? Icon(
                        Icons.check_rounded,
                        size: 17.5,
                        color: skin.ctaStyle == 'contrast' && !skin.isLight
                            ? Colors.white
                            : skin.accent,
                      )
                    : (entry.onTapOverride != null && entry.icon != null
                        ? Icon(
                            entry.icon,
                            size: 16.5,
                            color: entry.isDestructive ? VedroTheme.danger : skin.fg2,
                          )
                        : null),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13.5,
                        fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                        height: 1.28,
                      ),
                    ),
                    if (entry.subtitle != null && entry.subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        entry.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: skin.fg3,
                          fontSize: 11.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (entry.onTapOverride == null && entry.icon != null) ...[
                const SizedBox(width: 8),
                Icon(entry.icon, size: 15.5, color: skin.fg3),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
