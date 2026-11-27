part of '../home_screen.dart';

/// Multi-personality Home Hero Stage supporting 3 structural layouts:
/// - `'full_bleed'`: Edge-to-edge full-screen cinema Hero (zero white border boxes on thumbnails, sealed bottom seam!)
/// - `'framed_stage'`: ElegantFin / Jellyseerr inset panoramic rounded card stage
/// - `'split_showcase'`: Criterion / Kinfolk editorial 2-column magazine showcase
class _CinemaHeroBanner extends StatefulWidget {
  const _CinemaHeroBanner({
    required this.featured,
    required this.appState,
    required this.scrollOffsetListenable,
    required this.topNavClearance,
    required this.onPlay,
    required this.onDetail,
    this.onGenreTap,
  });

  final List<({MediaItemModel item, String eyebrow})> featured;
  final VedroAppState appState;
  final ValueListenable<double> scrollOffsetListenable;
  final double topNavClearance;
  final void Function(MediaItemModel) onPlay;
  final void Function(MediaItemModel) onDetail;
  final ValueChanged<String>? onGenreTap;

  @override
  State<_CinemaHeroBanner> createState() => _CinemaHeroBannerState();
}

class _CinemaHeroBannerState extends State<_CinemaHeroBanner> {
  late final PageController _pageCtrl = PageController();
  int _active = 0;
  bool _paused = false;
  bool _userDragging = false;
  bool _hovered = false;
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    _syncDynamicHeroColor();
    _armTimer();
  }

  @override
  void didUpdateWidget(covariant _CinemaHeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_active >= widget.featured.length) {
      _active = 0;
      if (_pageCtrl.hasClients) {
        _pageCtrl.jumpToPage(0);
      }
    }
    if (oldWidget.featured != widget.featured) {
      _syncDynamicHeroColor();
    }
  }

  void _syncDynamicHeroColor() {
    if (widget.featured.isEmpty) return;
    final safeIdx = _active.clamp(0, widget.featured.length - 1);
    final target = widget.featured[safeIdx].item;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.appState.updateDynamicSeedFromItem(target);
      }
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _armTimer() {
    _autoTimer?.cancel();
    if (widget.featured.length < 2 || _paused || _userDragging) return;
    _autoTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted || _userDragging) return;
      // Skip invisible background Hero advances when scrolled past or on another tab/route!
      if (!TickerMode.of(context) || widget.scrollOffsetListenable.value > 380) {
        _armTimer();
        return;
      }
      final next = (_active + 1) % widget.featured.length;
      _select(next);
    });
  }

  void _select(int index) {
    if (widget.featured.isEmpty) return;
    final target = index.clamp(0, widget.featured.length - 1);
    if (_pageCtrl.hasClients && widget.featured.length > 1) {
      _pageCtrl.animateToPage(
        target,
        duration: const Duration(milliseconds: 680),
        curve: VedroSpringCurve.smooth,
      );
    } else {
      setState(() => _active = target);
      _syncDynamicHeroColor();
    }
    _armTimer();
  }

  void _onPageChanged(int index) {
    if (_active == index) return;
    setState(() => _active = index);
    _syncDynamicHeroColor();
    _armTimer();
  }

  /// Borderless floating preview thumbnails (ZERO white border boxes!) + sleek active indicator bar.
  /// Width-aware so 960dp TV and split_showcase narrow columns NEVER overflow or collide with CTAs.
  Widget _buildBorderlessPreviewStrip(
    VedroSkin skin, {
    bool onLightSurface = false,
    double? maxWidth,
  }) {
    final count = widget.featured.length;
    if (count == 0) return const SizedBox.shrink();
    double thumbW = 92;
    double spacing = 10;
    if (maxWidth != null && maxWidth.isFinite) {
      final fullNeed = count * thumbW + (count - 1) * spacing;
      if (fullNeed > maxWidth) {
        spacing = 7;
        final fitW = (maxWidth - (count - 1) * spacing) / count;
        if (fitW < 54) {
          return _buildCapsuleDots(skin: skin, onLightSurface: onLightSurface);
        }
        thumbW = fitW.clamp(54.0, 92.0);
      }
    }
    final thumbH = (thumbW * 9 / 16).roundToDouble();
    final barActiveColor = skin.ctaStyle == 'contrast'
        ? (onLightSurface ? skin.fg : Colors.white)
        : skin.accent;
    return Row(
      key: const ValueKey('hero-preview-strip'),
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final active = i == _active;
        final entry = widget.featured[i];
        return Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : spacing),
          child: PressableScale(
            onTap: () => _select(i),
            hoverScale: 1.05,
            pressScale: 0.95,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: active ? 1.04 : 0.94,
                  duration: const Duration(milliseconds: 460),
                  curve: VedroSpringCurve.bouncy,
                  child: Container(
                    width: thumbW,
                    height: thumbH,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(skin.cardRadius.clamp(6.0, 11.0)),
                      boxShadow: active
                          ? const [
                              BoxShadow(
                                color: Color(0xA6000000),
                                blurRadius: 18,
                                offset: Offset(0, 7),
                              ),
                            ]
                          : const [
                              BoxShadow(
                                color: Color(0x40000000),
                                blurRadius: 8,
                                offset: Offset(0, 3),
                              ),
                            ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: AnimatedOpacity(
                      opacity: active ? 1.0 : 0.42,
                      duration: const Duration(milliseconds: 320),
                      curve: VedroTheme.easeOut,
                      child: VedroArtwork(
                        item: entry.item,
                        appState: widget.appState,
                        landscape: true,
                        width: 320,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 420),
                  curve: VedroTheme.easeOut,
                  width: active ? (thumbW * 0.30).clamp(18.0, 28.0) : 8,
                  height: 3,
                  decoration: BoxDecoration(
                    color: active
                        ? barActiveColor
                        : (onLightSurface
                            ? skin.fg.withValues(alpha: 0.18)
                            : const Color(0x38FFFFFF)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCapsuleDots({bool onLightSurface = false, required VedroSkin skin}) {
    final activeColor = onLightSurface ? skin.fg : Colors.white;
    final inactiveColor = onLightSurface ? skin.fg.withValues(alpha: 0.24) : const Color(0x52FFFFFF);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.featured.length, (i) {
        final active = i == _active;
        return PressableScale(
          onTap: () => _select(i),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 420),
              curve: VedroTheme.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active ? activeColor : inactiveColor,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildHeroInfoColumn({
    required BuildContext context,
    required VedroSkin skin,
    required MediaItemModel item,
    required String eyebrow,
    required String? logoUrl,
    required bool wide,
    required bool onPhoto,
  }) {
    final textPrimary = onPhoto ? Colors.white : skin.fg;
    final textSecondary = onPhoto ? const Color(0xD9FFFFFF) : skin.fg2;
    final textMuted = onPhoto ? const Color(0xC0FFFFFF) : skin.fg3;
    final pillR = skin.radiusForPill(44);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: VedroTheme.easeOut,
      switchOutCurve: Curves.easeInCubic,
      // Copy is always left-anchored (default switcher layout would center a
      // narrow column inside the hero's full-width slot).
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.bottomStart,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: Column(
        key: ValueKey(item.id),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            eyebrow,
            style: TextStyle(
              color: onPhoto ? textMuted : skin.accent,
              fontSize: wide ? 12.5 : 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          SizedBox(height: wide ? 10 : 6),
          if (logoUrl != null && skin.preferClearLogo && (onPhoto || !skin.isLight))
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: wide ? 104 : 74,
                maxWidth: wide ? 420 : 280,
              ),
              child: Image.network(
                logoUrl,
                cacheWidth: 640,
                filterQuality: FilterQuality.medium,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                errorBuilder: (_, __, ___) => _HeroTitleText(
                  text: item.cardTitle,
                  wide: wide,
                  color: textPrimary,
                ),
              ),
            )
          else
            _HeroTitleText(text: item.cardTitle, wide: wide, color: textPrimary),
          Builder(
            builder: (context) {
              final metaStyle = TextStyle(
                color: textSecondary,
                fontSize: wide ? 13.5 : 12.5,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              );
              final parts = <Widget>[
                if (item.type == 'Episode' && item.cardSubtitle.isNotEmpty)
                  Text(item.cardSubtitle, style: metaStyle),
                if (item.communityRating != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.star_rounded,
                        size: wide ? 15 : 13.5,
                        color: onPhoto ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        item.communityRating!.toStringAsFixed(1),
                        style: metaStyle.copyWith(
                          color: onPhoto ? const Color(0xF2FFFFFF) : const Color(0xFFD97706),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                if (item.productionYear != null) Text('${item.productionYear}', style: metaStyle),
                for (final g in item.genres.take(wide ? 3 : 2))
                  PressableScale(
                    onTap: widget.onGenreTap == null ? null : () => widget.onGenreTap!(g),
                    canRequestFocus: wide,
                    borderRadius: BorderRadius.circular(6),
                    child: Text(g, style: metaStyle),
                  ),
              ];
              if (parts.isEmpty) return const SizedBox.shrink();
              final dot = Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Text('·', style: metaStyle.copyWith(color: textMuted)),
              );
              return Padding(
                padding: EdgeInsets.only(top: wide ? 12 : 8),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < parts.length; i++) ...[
                      if (i > 0) dot,
                      parts[i],
                    ],
                  ],
                ),
              );
            },
          ),
          if (wide && item.cleanOverview.isNotEmpty) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                item.cleanOverview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 14,
                  height: 1.55,
                ),
              ),
            ),
          ],
          SizedBox(height: wide ? 24 : 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PressableScale(
                onTap: () => widget.onPlay(item),
                hoverScale: 1.03,
                pressScale: 0.96,
                child: Container(
                  height: wide ? 44 : 38,
                  padding: EdgeInsets.symmetric(horizontal: wide ? 26 : 20),
                  decoration: BoxDecoration(
                    color: onPhoto && skin.isLight ? Colors.white : skin.primaryCtaBg,
                    gradient: onPhoto && skin.isLight ? null : skin.primaryCtaGradient,
                    borderRadius: BorderRadius.circular(pillR),
                    border: onPhoto && skin.isLight ? null : skin.primaryCtaBorder,
                    boxShadow: onPhoto
                        ? const [
                            BoxShadow(
                              color: Color(0x48000000),
                              blurRadius: 18,
                              offset: Offset(0, 6),
                            ),
                          ]
                        : skin.primaryCtaShadow,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        size: 22,
                        color: onPhoto && skin.isLight
                            ? const Color(0xFF09090B)
                            : skin.primaryCtaFg,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '播放',
                        style: TextStyle(
                          color: onPhoto && skin.isLight
                              ? const Color(0xFF09090B)
                              : skin.primaryCtaFg,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              PressableScale(
                onTap: () => widget.onDetail(item),
                hoverScale: 1.03,
                pressScale: 0.96,
                child: onPhoto
                    ? GlassSurface(
                        borderRadius: pillR,
                        blur: 24,
                        color: const Color(0x40FFFFFF),
                        borderColor: Colors.transparent,
                        padding: EdgeInsets.symmetric(
                          horizontal: wide ? 22 : 18,
                          vertical: wide ? 11 : 8.5,
                        ),
                        child: Text(
                          '详情',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: wide ? 14.5 : 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : Container(
                        height: wide ? 44 : 38,
                        padding: EdgeInsets.symmetric(horizontal: wide ? 22 : 18),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: skin.surface2,
                          borderRadius: BorderRadius.circular(pillR),
                          border: Border.all(color: skin.borderStrong, width: 0.8),
                        ),
                        child: Text(
                          '详情',
                          style: TextStyle(
                            color: skin.fg,
                            fontSize: wide ? 14.5 : 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 820;
    final padX = widget.appState.prefs.horizontalMargin(wide);
    final current = widget.featured[_active];
    final item = current.item;
    final logoUrl = widget.appState.logoArtUrl(item);

    Widget wrapHeroInteraction(Widget child) {
      return Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) {
          if (focused) {
            _paused = true;
            _autoTimer?.cancel();
          } else if (!_hovered) {
            _paused = false;
            _armTimer();
          }
        },
        child: MouseRegion(
          onEnter: (_) {
            setState(() => _hovered = true);
            _paused = true;
            _autoTimer?.cancel();
          },
          onExit: (_) {
            setState(() => _hovered = false);
            _paused = false;
            _armTimer();
          },
          child: child,
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Layout Mode B: Criterion / Kinfolk 2-Column Editorial Split Showcase
    // -------------------------------------------------------------------------
    if (wide && skin.heroStyle == 'split_showcase') {
      final cardR = skin.cardRadius.clamp(8.0, 24.0);
      return wrapHeroInteraction(
        Padding(
          key: const ValueKey('hero-split-showcase'),
          padding: EdgeInsets.fromLTRB(padX, widget.topNavClearance + 14, padX, 12),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: skin.panelSurface,
              borderRadius: BorderRadius.circular(cardR),
              border: skin.cardBorder(),
              boxShadow: skin.posterShadow(),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 5,
                  child: _buildHeroInfoColumn(
                    context: context,
                    skin: skin,
                    item: item,
                    eyebrow: current.eyebrow,
                    logoUrl: logoUrl,
                    wide: true,
                    onPhoto: false,
                  ),
                ),
                const SizedBox(width: 28),
                Expanded(
                  flex: 6,
                  child: LayoutBuilder(
                    builder: (_, colConstraints) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(cardR),
                              boxShadow: skin.posterShadow(hovered: true),
                            ),
                            foregroundDecoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(cardR),
                              border: skin.cardBorder(),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                for (var i = 0; i < widget.featured.length; i++)
                                  AnimatedOpacity(
                                    opacity: i == _active ? 1.0 : 0.0,
                                    duration: const Duration(milliseconds: 480),
                                    curve: Curves.easeOutCubic,
                                    child: VedroArtwork(
                                      item: widget.featured[i].item,
                                      appState: widget.appState,
                                      isHero: true,
                                      showInitials: false,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (widget.featured.length > 1) ...[
                          const SizedBox(height: 14),
                          _buildBorderlessPreviewStrip(
                            skin,
                            onLightSurface: skin.isLight,
                            maxWidth: colConstraints.maxWidth,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Layout Mode C: ElegantFin / Jellyseerr Framed Rounded Panoramic Stage
    // -------------------------------------------------------------------------
    if (skin.heroStyle == 'framed_stage') {
      final stageR = skin.cardRadius.clamp(10.0, 26.0);
      final stageH = (size.height * (wide ? 0.56 : 0.44)).clamp(310.0, 560.0);
      final stageStripMaxW = (size.width - padX * 2 - 420).clamp(180.0, 620.0);
      return wrapHeroInteraction(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              key: const ValueKey('hero-framed-stage'),
              padding: EdgeInsets.fromLTRB(
                padX,
                wide ? widget.topNavClearance + 8 : MediaQuery.paddingOf(context).top + 58,
                padX,
                4,
              ),
              child: Container(
                height: stageH,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(stageR),
                  boxShadow: skin.posterShadow(hovered: true),
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(stageR),
                  border: skin.cardBorder(),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n is ScrollStartNotification && n.dragDetails != null) {
                          _userDragging = true;
                          _autoTimer?.cancel();
                        } else if (n is ScrollEndNotification && _userDragging) {
                          _userDragging = false;
                          _armTimer();
                        }
                        return false;
                      },
                      child: PageView.builder(
                        key: const ValueKey('hero-page-view'),
                        controller: _pageCtrl,
                        itemCount: widget.featured.length,
                        physics: const BouncingScrollPhysics(),
                        onPageChanged: _onPageChanged,
                        itemBuilder: (ctx, idx) {
                          final slide = widget.featured[idx];
                          final slideLogo = widget.appState.logoArtUrl(slide.item);
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => widget.onDetail(slide.item),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRect(
                                  child: _HeroParallax(
                                    pageController: _pageCtrl,
                                    index: idx,
                                    fallbackPage: _active,
                                    child: VedroArtwork(
                                      item: slide.item,
                                      appState: widget.appState,
                                      isHero: true,
                                      alignment: const Alignment(0, -0.45),
                                      showInitials: false,
                                    ),
                                  ),
                                ),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                      stops: const [0.0, 0.55, 1.0],
                                      colors: skin.isLight
                                          ? [
                                              skin.surface.withValues(alpha: 0.94),
                                              skin.surface.withValues(alpha: 0.58),
                                              skin.surface.withValues(alpha: 0.06),
                                            ]
                                          : const [
                                              Color(0xD808090E),
                                              Color(0x6E08090E),
                                              Color(0x1808090E),
                                            ],
                                    ),
                                  ),
                                ),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      stops: const [0.0, 0.45, 1.0],
                                      colors: skin.isLight
                                          ? [
                                              skin.surface.withValues(alpha: 0.08),
                                              skin.surface.withValues(alpha: 0.24),
                                              skin.surface.withValues(alpha: 0.90),
                                            ]
                                          : const [
                                              Color(0x2808090E),
                                              Color(0x3808090E),
                                              Color(0xDE08090E),
                                            ],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: wide ? 34 : 16,
                                  right: wide ? size.width * 0.34 : 16,
                                  bottom: wide ? 32 : 28,
                                  child: _buildHeroInfoColumn(
                                    context: context,
                                    skin: skin,
                                    item: slide.item,
                                    eyebrow: slide.eyebrow,
                                    logoUrl: slideLogo,
                                    wide: wide,
                                    onPhoto: !skin.isLight,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    if (widget.featured.length > 1)
                      Positioned(
                        right: wide ? 28 : 16,
                        left: wide ? null : 16,
                        bottom: wide ? 26 : 10,
                        child: wide
                            ? _buildBorderlessPreviewStrip(
                                skin,
                                onLightSurface: skin.isLight,
                                maxWidth: stageStripMaxW,
                              )
                            : _buildCapsuleDots(skin: skin, onLightSurface: skin.isLight),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Layout Mode A (Default): Apple TV+ Full-Bleed Cinema Hero
    // - Horizontal `PageView.builder` swipeable left/right with 1:1 finger physics!
    // - `ClipRect` + direct canvas gradient dissolve (zero offscreen saveLayer!)
    // -------------------------------------------------------------------------
    final heroH = wide
        ? (size.height * 0.70).clamp(460.0, 740.0)
        : (size.height * 0.49).clamp(328.0, 420.0);
    final canvasColor = skin.canvas;
    final fullBleedStripMaxW = (size.width - padX * 2 - 420).clamp(180.0, 620.0);

    return wrapHeroInteraction(
      SizedBox(
        key: const ValueKey('hero-full-bleed'),
        height: heroH,
        child: Stack(
          fit: StackFit.expand,
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is ScrollStartNotification && n.dragDetails != null) {
                  _userDragging = true;
                  _autoTimer?.cancel();
                } else if (n is ScrollEndNotification && _userDragging) {
                  _userDragging = false;
                  _armTimer();
                }
                return false;
              },
              // Clip horizontally to the hero, but let the stretched artwork grow upward
              // into the rubber-band overscroll gap (iOS stretchy header).
              child: ClipRect(
                clipper: const _HeroUpwardOpenClipper(),
                child: PageView.builder(
                key: const ValueKey('hero-page-view'),
                controller: _pageCtrl,
                itemCount: widget.featured.length,
                physics: const BouncingScrollPhysics(),
                clipBehavior: Clip.none,
                onPageChanged: _onPageChanged,
                itemBuilder: (ctx, idx) {
                  final slide = widget.featured[idx];
                  final slideLogo = widget.appState.logoArtUrl(slide.item);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onDetail(slide.item),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Direct zero-saveLayer gradient dissolve into `skin.canvas` (no offscreen ShaderMask!)
                        _HeroStretch(
                          scrollOffset: widget.scrollOffsetListenable,
                          heroHeight: heroH,
                          child: RepaintBoundary(
                          child: ClipRect(
                            key: ValueKey('hero-alpha-mask-$idx'),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Positioned.fill(
                                  child: _HeroParallax(
                                    pageController: _pageCtrl,
                                    index: idx,
                                    fallbackPage: _active,
                                    scrollOffset: widget.scrollOffsetListenable,
                                    child: VedroArtwork(
                                      item: slide.item,
                                      appState: widget.appState,
                                      isHero: true,
                                      alignment: const Alignment(0, -0.46),
                                      showInitials: false,
                                    ),
                                  ),
                                ),
                                if (wide)
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                        stops: const [0.0, 0.48, 0.82, 1.0],
                                        colors: skin.isLight
                                            ? [
                                                canvasColor.withValues(alpha: 0.88),
                                                canvasColor.withValues(alpha: 0.52),
                                                canvasColor.withValues(alpha: 0.12),
                                                Colors.transparent,
                                              ]
                                            : [
                                                canvasColor.withValues(alpha: 0.84),
                                                canvasColor.withValues(alpha: 0.44),
                                                canvasColor.withValues(alpha: 0.08),
                                                Colors.transparent,
                                              ],
                                      ),
                                    ),
                                  ),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      stops: (!wide && skin.isLight)
                                          ? const [0.0, 0.22, 0.48, 0.78, 1.0]
                                          : const [0.0, 0.28, 0.62, 0.90, 1.0],
                                      colors: skin.isLight
                                          ? [
                                              canvasColor.withValues(alpha: 0.36),
                                              Colors.transparent,
                                              canvasColor.withValues(alpha: wide ? 0.46 : 0.72),
                                              canvasColor.withValues(alpha: 0.96),
                                              canvasColor,
                                            ]
                                          : [
                                              canvasColor.withValues(alpha: 0.36),
                                              Colors.transparent,
                                              canvasColor.withValues(alpha: 0.42),
                                              canvasColor.withValues(alpha: 0.94),
                                              canvasColor,
                                            ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ),
                        ),
                        Positioned(
                          left: padX,
                          right: wide ? size.width * 0.36 : padX,
                          bottom: wide ? 44 : 34,
                          child: _HeroScrollFade(
                            scrollOffset: widget.scrollOffsetListenable,
                            fadeDistance: heroH * 0.5,
                            child: _buildHeroInfoColumn(
                              context: context,
                              skin: skin,
                              item: slide.item,
                              eyebrow: slide.eyebrow,
                              logoUrl: slideLogo,
                              wide: wide,
                              onPhoto: !skin.isLight,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              ),
            ),

            if (wide && widget.featured.length > 1) ...[
              Positioned(
                left: 14,
                top: 0,
                bottom: 0,
                child: Center(
                  child: ExcludeFocus(
                    excluding: !_hovered,
                    child: IgnorePointer(
                      ignoring: !_hovered,
                      child: AnimatedOpacity(
                        opacity: _hovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 180),
                        child: PressableScale(
                          onTap: () => _select(
                              (_active - 1 + widget.featured.length) % widget.featured.length),
                          child: GlassSurface(
                            borderRadius: 20,
                            blur: 18,
                            color: skin.isLight ? const Color(0xCCFFFFFF) : const Color(0x66141418),
                            borderColor: skin.isLight ? skin.border : Colors.transparent,
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.chevron_left_rounded,
                              size: 22,
                              color: skin.isLight ? skin.fg : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 14,
                top: 0,
                bottom: 0,
                child: Center(
                  child: ExcludeFocus(
                    excluding: !_hovered,
                    child: IgnorePointer(
                      ignoring: !_hovered,
                      child: AnimatedOpacity(
                        opacity: _hovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 180),
                        child: PressableScale(
                          onTap: () => _select((_active + 1) % widget.featured.length),
                          child: GlassSurface(
                            borderRadius: 20,
                            blur: 18,
                            color: skin.isLight ? const Color(0xCCFFFFFF) : const Color(0x66141418),
                            borderColor: skin.isLight ? skin.border : Colors.transparent,
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              size: 22,
                              color: skin.isLight ? skin.fg : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],

            if (widget.featured.length > 1)
              Positioned(
                right: padX,
                left: wide ? null : padX,
                bottom: wide ? 40 : 8,
                child: wide
                    ? _buildBorderlessPreviewStrip(
                        skin,
                        onLightSurface: skin.isLight,
                        maxWidth: fullBleedStripMaxW,
                      )
                    : _buildCapsuleDots(skin: skin, onLightSurface: skin.isLight),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeroTitleText extends StatelessWidget {
  const _HeroTitleText({
    required this.text,
    required this.wide,
    this.color = Colors.white,
  });
  final String text;
  final bool wide;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: skin.applyHeadlineMood(
        TextStyle(
          color: color,
          fontSize: wide ? 42 : 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          height: 1.08,
        ),
      ),
    );
  }
}

/// Clip rect that is bounded on the left, right and bottom but open upward, so
/// the hero artwork can stretch into the overscroll gap without bleeding sideways.
class _HeroUpwardOpenClipper extends CustomClipper<Rect> {
  const _HeroUpwardOpenClipper();

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, -4000, size.width, size.height);

  @override
  bool shouldReclip(covariant _HeroUpwardOpenClipper oldClipper) => false;
}

/// iOS stretchy header: rubber-band overscroll scales the artwork from its bottom
/// edge so the canvas never peeks through above the hero.
class _HeroStretch extends StatelessWidget {
  const _HeroStretch({
    required this.scrollOffset,
    required this.heroHeight,
    required this.child,
  });

  final ValueListenable<double> scrollOffset;
  final double heroHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: scrollOffset,
      child: child,
      builder: (context, offset, child) {
        final pull = offset < 0 ? -offset : 0.0;
        return Transform.scale(
          scale: 1.0 + pull / heroHeight.clamp(1.0, double.infinity),
          alignment: Alignment.bottomCenter,
          child: child,
        );
      },
    );
  }
}

/// Depth parallax: artwork glides at ~60 % of the page swipe speed and ~65 % of
/// the vertical scroll speed (compositor-only transform, zero relayout).
class _HeroParallax extends StatelessWidget {
  const _HeroParallax({
    required this.pageController,
    required this.index,
    required this.fallbackPage,
    required this.child,
    this.scrollOffset,
  });

  final PageController pageController;
  final int index;
  final int fallbackPage;
  final ValueListenable<double>? scrollOffset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: Listenable.merge([pageController, if (scrollOffset != null) scrollOffset!]),
        child: child,
        builder: (context, child) {
          var page = fallbackPage.toDouble();
          if (pageController.hasClients && pageController.position.hasContentDimensions) {
            page = pageController.page ?? page;
          }
          final dx = (page - index).clamp(-1.0, 1.0) * constraints.maxWidth * 0.4;
          final scroll = scrollOffset?.value ?? 0.0;
          final dy = scroll > 0 ? scroll * 0.35 : 0.0;
          return Transform.translate(offset: Offset(dx, dy), child: child);
        },
      ),
    );
  }
}

/// Fades the hero copy & CTAs out as the hero scrolls away (Apple TV app).
class _HeroScrollFade extends StatelessWidget {
  const _HeroScrollFade({
    required this.scrollOffset,
    required this.fadeDistance,
    required this.child,
  });

  final ValueListenable<double> scrollOffset;
  final double fadeDistance;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: scrollOffset,
      child: child,
      builder: (context, offset, child) {
        final t = offset <= 0 ? 1.0 : (1.0 - offset / fadeDistance).clamp(0.0, 1.0);
        return IgnorePointer(
          ignoring: t < 0.05,
          child: Opacity(opacity: t, child: child),
        );
      },
    );
  }
}
