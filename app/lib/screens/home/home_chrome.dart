part of '../home_screen.dart';

/// Pull distance (logical px) that arms the stretch-to-refresh gesture.
const double _kPullToRefreshTrigger = 92.0;

/// iOS-style pinned mobile navigation bar for Home:
/// - fully transparent over the hero artwork, then
/// - progressively frosts (blur + glass fill + hairline) as content scrolls under it,
/// exactly like UINavigationBar's scroll-edge appearance.
class _HomeMobileTopBar extends StatelessWidget {
  const _HomeMobileTopBar({
    required this.appState,
    required this.scrollOffset,
    required this.solidAfter,
    required this.onOpenServerHub,
    this.onOpenFavorites,
  });

  final VedroAppState appState;
  final ValueListenable<double> scrollOffset;
  final double solidAfter;
  final VoidCallback onOpenServerHub;
  final VoidCallback? onOpenFavorites;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final serverName = appState.activeServerDisplayName;

    return ValueListenableBuilder<double>(
      valueListenable: scrollOffset,
      builder: (context, offset, _) {
        final t = (1.0 + (offset - solidAfter) / 48.0).clamp(0.0, 1.0);
        final overArt = t < 0.5;
        final pillBg = skin.isLight
            ? Color.lerp(skin.surface.withValues(alpha: 0.84), skin.fg.withValues(alpha: 0.06), t)!
            : Color.lerp(skin.surface.withValues(alpha: 0.62), Colors.white.withValues(alpha: 0.08), t)!;
        final pillFg = skin.isLight ? skin.fg : Colors.white;
        final barBlur = PlatformPerfProfile.clampLiveBlur(22) * t;
        // Airy translucent top header veil when scrolled — never an opaque "forehead" brick.
        final veilAlpha = (skin.isLiquidGlass
                ? (skin.isLight ? 0.52 : 0.42)
                : (skin.usesGlassPanels
                    ? (skin.isLight ? 0.58 : 0.48)
                    : (skin.isLight ? 0.64 : 0.54))) *
            t;
        final veilBase = skin.isLight ? skin.surface : skin.canvas;

        // Avoid nested BackdropFilter stalls when the scrolled top veil is already blurred
        // (keeps exact unified 360° LiquidGlassRimPainter + sheen while cutting GPU passes 4x!).
        Widget pill({required Widget child, required EdgeInsets padding}) => GlassSurface(
              borderRadius: 19,
              blur: 18,
              enableBlur: overArt,
              color: skin.isLiquidGlass ? null : pillBg,
              borderColor: skin.isLight && overArt ? skin.border : Colors.transparent,
              padding: padding,
              child: child,
            );

        return Stack(
          children: [
            if (t > 0.01)
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: barBlur,
                        sigmaY: barBlur,
                        tileMode: TileMode.clamp,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              veilBase.withValues(alpha: (veilAlpha * 1.15).clamp(0.0, 0.74)),
                              veilBase.withValues(alpha: veilAlpha.clamp(0.0, 0.66)),
                            ],
                          ),
                          border: Border(
                            bottom: BorderSide(
                              color: (skin.isLiquidGlass ? skin.borderStrong : skin.border)
                                  .withValues(alpha: (skin.isLiquidGlass ? 0.28 : 0.16) * t),
                              width: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Flexible(
                      child: PressableScale(
                        onTap: onOpenServerHub,
                        pressScale: 0.94,
                        child: pill(
                          padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const VedroBrandMark(size: 24),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  serverName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: pillFg,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 17,
                                color: pillFg.withValues(alpha: 0.75),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (onOpenFavorites != null)
                      PressableScale(
                        onTap: onOpenFavorites,
                        pressScale: 0.88,
                        child: pill(
                          padding: const EdgeInsets.all(8.5),
                          child: Icon(Icons.favorite_border_rounded, size: 18, color: pillFg),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Floating glass activity indicator for the stretch-to-refresh gesture: the
/// iOS spokes reveal one by one while pulling, then spin while refreshing.
class _PullRefreshIndicator extends StatelessWidget {
  const _PullRefreshIndicator({required this.progress, required this.refreshing});

  final ValueListenable<double> progress;
  final ValueListenable<bool> refreshing;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([progress, refreshing]),
        builder: (context, _) {
          final busy = refreshing.value;
          final p = progress.value;
          final visible = busy || p > 0.04;
          // Unmount the live GlassSurface / BackdropFilter completely while idle on Home
          // so zero extra GPU backdrop layers sit in the overlay at opacity 0.
          if (!visible) return const SizedBox.shrink();
          return AnimatedScale(
            scale: busy ? 1.0 : (0.55 + 0.45 * p),
            duration: Duration(milliseconds: busy ? 420 : 60),
            curve: busy ? VedroSpringCurve.playful : Curves.linear,
            child: GlassSurface(
              borderRadius: 20,
              blur: 18,
              padding: const EdgeInsets.all(9),
              child: SizedBox(
                width: 22,
                height: 22,
                child: busy
                    ? CupertinoActivityIndicator(radius: 10, color: skin.fg)
                    : CupertinoActivityIndicator.partiallyRevealed(
                        radius: 10,
                        progress: p,
                        color: skin.fg,
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
