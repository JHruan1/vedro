import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/platform/platform_perf.dart';
import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';

/// Single action item inside an iOS-caliber Peek & Pop contextual menu.
class VedroPeekAction {
  const VedroPeekAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.isPrimary = false,
    this.isDestructive = false,
    this.itemKey,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String? subtitle;
  final bool isPrimary;
  final bool isDestructive;
  final Key? itemKey;
}

/// Present an authentic iOS 18 / Apple TV+ Peek & Pop contextual menu:
/// 1. Background smoothly blurs & dims (respecting `PlatformPerfProfile.clampLiveBlur`).
/// 2. The selected card preview lifts & scales up with real spring physics (`1.0 -> 1.06`)
///    and softly glides into safe viewport clearance if near the screen edge.
/// 3. A frosted / liquid-glass action menu springs directly out of the selected card's
///    bottom or top edge with anchored scale + slide + fade transitions.
Future<void> showVedroPeekMenu({
  required BuildContext context,
  required List<VedroPeekAction> actions,
  Rect? anchorRect,
  WidgetBuilder? previewBuilder,
  String? title,
  String? subtitle,
  double previewCornerRadius = 14.0,
}) {
  if (actions.isEmpty) return Future<void>.value();
  HapticFeedback.mediumImpact();
  final inheritedTheme = Theme.of(context);
  return Navigator.of(context, rootNavigator: true).push<void>(
    _VedroPeekMenuRoute(
      theme: inheritedTheme,
      anchorRect: anchorRect,
      previewBuilder: previewBuilder,
      title: title,
      subtitle: subtitle,
      actions: actions,
      previewCornerRadius: previewCornerRadius,
    ),
  );
}

class _VedroPeekMenuRoute extends PopupRoute<void> {
  _VedroPeekMenuRoute({
    required this.theme,
    required this.anchorRect,
    required this.previewBuilder,
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.previewCornerRadius,
  });

  final ThemeData theme;
  final Rect? anchorRect;
  final WidgetBuilder? previewBuilder;
  final String? title;
  final String? subtitle;
  final List<VedroPeekAction> actions;
  final double previewCornerRadius;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => '关闭菜单';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 460);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Theme(
      data: theme,
      child: _VedroPeekMenuStage(
        animation: animation,
        anchorRect: anchorRect,
        previewBuilder: previewBuilder,
        title: title,
        subtitle: subtitle,
        actions: actions,
        previewCornerRadius: previewCornerRadius,
      ),
    );
  }
}

class _VedroPeekMenuStage extends StatelessWidget {
  const _VedroPeekMenuStage({
    required this.animation,
    required this.anchorRect,
    required this.previewBuilder,
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.previewCornerRadius,
  });

  final Animation<double> animation;
  final Rect? anchorRect;
  final WidgetBuilder? previewBuilder;
  final String? title;
  final String? subtitle;
  final List<VedroPeekAction> actions;
  final double previewCornerRadius;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final media = MediaQuery.of(context);
    final screen = media.size;
    final safeTop = media.padding.top + 14.0;
    final safeBottom = screen.height - media.padding.bottom - 14.0;
    final safeLeft = media.padding.left + 14.0;
    final safeRight = screen.width - media.padding.right - 14.0;
    final reduceMotion = PlatformPerfProfile.shouldReduceMotion(context);

    final menuW = math.min(258.0, math.max(216.0, screen.width - 32.0));
    final hasHeader = (title != null && title!.trim().isNotEmpty) && previewBuilder == null;
    final estMenuH = (hasHeader ? 54.0 : 0.0) + actions.length * 46.5 + 12.0;
    final maxMenuH = (safeBottom - safeTop) * 0.56;
    final menuH = math.min(estMenuH, maxMenuH);
    const gap = 12.0;

    // Resolve card preview geometry (either anchored to the real tapped card or centered fallback)
    final bool hasPreview = previewBuilder != null && anchorRect != null;
    // The anchor is the card ART rect as currently rendered (already peek-swelled),
    // so the preview starts pixel-identical and only lifts a little further.
    final double targetScale = reduceMotion ? 1.0 : 1.035;

    late final Rect startRect;
    late final Rect liftedRect;
    late final double menuLeft;
    late final double menuTop;
    late final bool menuAbove;

    if (hasPreview) {
      final raw = anchorRect!;
      // Cap oversized previews (e.g. very wide landscape cards) so both card & menu fit comfortably
      final maxPreviewW = math.min(screen.width - 36.0, 340.0);
      final maxPreviewH = (safeBottom - safeTop - menuH - gap - 20.0).clamp(110.0, 320.0);
      var w = raw.width;
      var h = raw.height;
      if (w > maxPreviewW && w > 0) {
        final f = maxPreviewW / w;
        w *= f;
        h *= f;
      }
      if (h > maxPreviewH && h > 0) {
        final f = maxPreviewH / h;
        w *= f;
        h *= f;
      }
      // Start exactly on top of the real card (same size, aspect & radius); any
      // capping only applies to the lifted resting size, so nothing jumps at t = 0.
      startRect = raw;
      final capped = Rect.fromCenter(center: raw.center, width: w, height: h);

      // Compute scaled footprint to ensure lifted card + menu never clip off-screen
      final scaledW = w * targetScale;
      final scaledH = h * targetScale;
      final extraX = (scaledW - w) / 2;
      final extraY = (scaledH - h) / 2;

      var cx = capped.center.dx.clamp(
        safeLeft + w / 2 + extraX,
        math.max(safeLeft + w / 2 + extraX, safeRight - w / 2 - extraX),
      );
      var cy = capped.center.dy;

      // Decide whether menu pops below or above the selected card
      final spaceBelow = safeBottom - (cy + h / 2 + extraY + gap);
      final spaceAbove = (cy - h / 2 - extraY - gap) - safeTop;
      menuAbove = spaceBelow < menuH && spaceAbove > spaceBelow;

      if (!menuAbove) {
        final maxCy = safeBottom - menuH - gap - h / 2 - extraY;
        final minCy = safeTop + h / 2 + extraY;
        cy = cy.clamp(minCy, math.max(minCy, maxCy));
      } else {
        final minCy = safeTop + menuH + gap + h / 2 + extraY;
        final maxCy = safeBottom - h / 2 - extraY;
        cy = cy.clamp(math.min(minCy, maxCy), maxCy);
      }

      liftedRect = Rect.fromCenter(center: Offset(cx.toDouble(), cy.toDouble()), width: w, height: h);

      // Align menu horizontally with card's left edge (or right edge if near right screen border)
      final preferRight = liftedRect.center.dx > screen.width * 0.58;
      final rawMenuLeft = preferRight
          ? (liftedRect.right + extraX - menuW)
          : (liftedRect.left - extraX);
      menuLeft = rawMenuLeft.clamp(
        safeLeft,
        math.max(safeLeft, safeRight - menuW),
      );
      menuTop = menuAbove
          ? (liftedRect.top - extraY - gap - menuH).clamp(safeTop, safeBottom - menuH)
          : (liftedRect.bottom + extraY + gap).clamp(safeTop, safeBottom - menuH);
    } else {
      startRect = Rect.zero;
      liftedRect = Rect.zero;
      menuAbove = false;
      menuLeft = ((screen.width - menuW) / 2).clamp(safeLeft, math.max(safeLeft, safeRight - menuW));
      menuTop = ((screen.height - menuH) / 2).clamp(safeTop, math.max(safeTop, safeBottom - menuH));
    }

    // Origin point for menu expansion directly from the selected card edge
    final double menuAlignX = hasPreview
        ? (((liftedRect.center.dx - menuLeft) / menuW) * 2.0 - 1.0).clamp(-0.82, 0.82)
        : 0.0;
    final Alignment menuOrigin = Alignment(menuAlignX, menuAbove ? 1.0 : -1.0);

    final maxBlur = reduceMotion ? 0.0 : PlatformPerfProfile.clampLiveBlur(18.0);
    final dimAlpha = skin.isLight ? 0.26 : 0.48;
    // Menu corners match the preview's corners (one shape family, clamped 12–22).
    final clampedPreviewR = previewCornerRadius.clamp(10.0, 22.0);
    final menuRadius = (hasPreview ? clampedPreviewR : skin.cardRadius).clamp(12.0, 22.0);
    final isLiquid = skin.isLiquidGlass;
    // The full-screen scrim behind the menu already applies live blur (sigma 18).
    // Avoiding a second nested BackdropFilter inside Opacity+Scale eliminates the
    // Android/iOS rectangular blur bleed outside rounded corners.
    final menuBg = skin.isLight
        ? Colors.white.withValues(alpha: isLiquid ? 0.86 : 0.94)
        : Color.lerp(skin.surface2, skin.surface, 0.35)!
            .withValues(alpha: isLiquid ? 0.84 : 0.94);

    final bgAnim = CurvedAnimation(
      parent: animation,
      curve: VedroTheme.easeOut,
      reverseCurve: Curves.easeInCubic,
    );
    final cardSpring = CurvedAnimation(
      parent: animation,
      curve: reduceMotion ? Curves.easeOut : VedroTheme.snappySpring,
      reverseCurve: Curves.easeInCubic,
    );
    final menuSpring = CurvedAnimation(
      parent: animation,
      curve: Interval(
        reduceMotion ? 0.0 : 0.06,
        1.0,
        curve: reduceMotion ? Curves.easeOut : VedroTheme.snappySpring,
      ),
      reverseCurve: Curves.easeInCubic,
    );
    final menuFade = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.04, 0.62, curve: Curves.easeOut),
      reverseCurve: Curves.easeIn,
    );

    final menuCard = Container(
      key: const ValueKey('vedro-peek-context-menu'),
      width: menuW,
      constraints: BoxConstraints(maxHeight: maxMenuH),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(menuRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: skin.isLight ? 0.16 : 0.54),
            blurRadius: 34,
            spreadRadius: 0,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: CustomPaint(
        foregroundPainter: isLiquid
            ? LiquidGlassRimPainter(
                radius: menuRadius,
                isLight: skin.isLight,
                accent: skin.accent,
              )
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(menuRadius),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: isLiquid
                ? const BoxDecoration()
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(menuRadius),
                    border: Border.all(
                      color: skin.isLight
                          ? Colors.black.withValues(alpha: 0.08)
                          : Colors.white.withValues(alpha: 0.15),
                      width: 0.85,
                    ),
                  ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: menuBg,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: skin.isLight ? 0.35 : (isLiquid ? 0.12 : 0.06)),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (hasHeader) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: skin.fg,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.15,
                                ),
                              ),
                              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: skin.fg3, fontSize: 11.5),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Divider(
                          height: 1,
                          thickness: 0.6,
                          color: skin.isLight
                              ? Colors.black.withValues(alpha: 0.08)
                              : Colors.white.withValues(alpha: 0.10),
                        ),
                      ],
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            thickness: 0.55,
                            indent: 14,
                            endIndent: 14,
                            color: skin.isLight
                                ? Colors.black.withValues(alpha: 0.07)
                                : Colors.white.withValues(alpha: 0.09),
                          ),
                        _PeekActionRow(
                          action: actions[i],
                          autofocus: i == 0,
                          onExecute: () {
                            HapticFeedback.selectionClick();
                            Navigator.of(context).pop();
                            actions[i].onTap();
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (ctx, _) {
        final tBg = bgAnim.value.clamp(0.0, 1.0);
        final tCard = cardSpring.value;
        final tMenu = menuSpring.value;
        final tMenuOpacity = menuFade.value.clamp(0.0, 1.0);
        final blurSigma = maxBlur * tBg;

        final curRect = hasPreview
            ? Rect.lerp(startRect, liftedRect, tCard.clamp(0.0, 1.0))!
            : Rect.zero;
        final curCardScale = 1.0 + (targetScale - 1.0) * tCard;
        final menuScale = (0.76 + 0.24 * tMenu).clamp(0.5, 1.08);
        final menuSlideY = (menuAbove ? 10.0 : -10.0) * (1.0 - tBg);

        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. Progressive frosted backdrop + tap-to-dismiss barrier
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: blurSigma > 0.15
                  ? BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: dimAlpha * tBg),
                      ),
                    )
                  : ColoredBox(
                      color: Colors.black.withValues(alpha: dimAlpha * tBg),
                    ),
            ),

            // 2. Floating spring-lifted card preview (exact shape & corner conservation)
            if (hasPreview)
              Positioned(
                left: curRect.left,
                top: curRect.top,
                width: curRect.width,
                height: curRect.height,
                child: IgnorePointer(
                  child: Transform.scale(
                    scale: curCardScale,
                    alignment: Alignment.center,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(previewCornerRadius),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: (skin.isLight ? 0.22 : 0.62) * tBg,
                            ),
                            blurRadius: 32 * tBg + 4,
                            spreadRadius: 0,
                            offset: Offset(0, 14 * tBg),
                          ),
                        ],
                      ),
                      child: CustomPaint(
                        foregroundPainter: isLiquid
                            ? LiquidGlassRimPainter(
                                radius: previewCornerRadius,
                                isLight: skin.isLight,
                                accent: skin.accent,
                              )
                            : null,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(previewCornerRadius),
                          child: DecoratedBox(
                            position: DecorationPosition.foreground,
                            decoration: isLiquid
                                ? const BoxDecoration()
                                : BoxDecoration(
                                    borderRadius: BorderRadius.circular(previewCornerRadius),
                                    border: skin.cardBorder(),
                                  ),
                            child: Material(
                              type: MaterialType.transparency,
                              child: previewBuilder!(ctx),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // 3. Anchored iOS glass menu springing out from the card edge
            Positioned(
              left: menuLeft,
              top: (hasPreview && menuAbove) ? null : menuTop,
              bottom: (hasPreview && menuAbove)
                  ? (screen.height - (liftedRect.top - (liftedRect.height * (targetScale - 1.0) / 2) - gap))
                      .clamp(screen.height - safeBottom, screen.height - safeTop - 60.0)
                  : null,
              child: Opacity(
                opacity: tMenuOpacity,
                child: Transform.translate(
                  offset: Offset(0, menuSlideY.roundToDouble()),
                  child: Transform.scale(
                    scale: menuScale,
                    alignment: menuOrigin,
                    child: menuCard,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PeekActionRow extends StatefulWidget {
  const _PeekActionRow({
    required this.action,
    required this.autofocus,
    required this.onExecute,
  });

  final VedroPeekAction action;
  final bool autofocus;
  final VoidCallback onExecute;

  @override
  State<_PeekActionRow> createState() => _PeekActionRowState();
}

class _PeekActionRowState extends State<_PeekActionRow> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final action = widget.action;
    final Color fgColor = action.isDestructive
        ? VedroTheme.danger
        : (action.isPrimary ? skin.accent : skin.fg);
    final Color iconColor = action.isDestructive
        ? VedroTheme.danger
        : (action.isPrimary ? skin.accent : skin.fg2);
    final activeBg = _pressed
        ? skin.fg.withValues(alpha: skin.isLight ? 0.11 : 0.14)
        : ((_hovered || _focused)
            ? skin.fg.withValues(alpha: skin.isLight ? 0.06 : 0.08)
            : Colors.transparent);

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
        key: action.itemKey,
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onExecute,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          color: activeBg,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11.5),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      action.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fgColor,
                        fontSize: 14.5,
                        fontWeight: action.isPrimary ? FontWeight.w600 : FontWeight.w500,
                        letterSpacing: -0.1,
                      ),
                    ),
                    if (action.subtitle != null && action.subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 1.5),
                      Text(
                        action.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: skin.fg3, fontSize: 11.5),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(action.icon, size: 19, color: iconColor),
            ],
          ),
        ),
      ),
    );
  }
}
