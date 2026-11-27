import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/platform/platform_perf.dart';
import '../core/theme/vedro_skin.dart';
import '../state/app_state.dart';

/// Deterministic, low-chroma two-tone field with clean display initials
/// for any media item without artwork (adapts seamlessly to both Light & Dark skins!).
class GeneratedArt extends StatelessWidget {
  const GeneratedArt({
    super.key,
    required this.seed,
    this.label,
    this.forceDark = false,
  });

  final String seed;
  final String? label;
  final bool forceDark;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final isLight = skin.isLight && !forceDark;
    final (h1, h2) = deterministicHues(seed);
    final c1 = isLight
        ? HSLColor.fromAHSL(1.0, h1, 0.30, 0.90).toColor()
        : HSLColor.fromAHSL(1.0, h1, 0.28, 0.20).toColor();
    final c2 = isLight
        ? HSLColor.fromAHSL(1.0, h2, 0.22, 0.83).toColor()
        : HSLColor.fromAHSL(1.0, h2, 0.24, 0.09).toColor();
    final glow = isLight
        ? HSLColor.fromAHSL(0.36, h1, 0.44, 0.76).toColor()
        : HSLColor.fromAHSL(0.38, h1, 0.45, 0.34).toColor();
    final text = label == null ? '' : artworkInitials(label);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: const Alignment(-0.9, -1.0),
          end: const Alignment(0.9, 1.0),
          colors: [c1, c2],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.45, -0.55),
                radius: 1.15,
                colors: [glow, Colors.transparent],
              ),
            ),
          ),
          if (label != null)
            LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 160.0;
                final fontSize = (text.length > 3 ? w * 0.16 : w * 0.23).clamp(13.0, 44.0);
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        color: isLight
                            ? HSLColor.fromAHSL(0.55, h1, 0.28, 0.28).toColor()
                            : const Color(0x78FFFFFF),
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
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

/// Network image that smoothly fades in once decoded and automatically retries
/// transient cold-start / proxy warm-up errors in-place so posters NEVER stay blank
/// until the user switches tabs!
class FadeNetworkImage extends StatefulWidget {
  const FadeNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.cacheWidth,
    this.filterQuality = FilterQuality.medium,
    this.placeholder,
  });

  final String url;
  final BoxFit fit;
  final Alignment alignment;
  final int? cacheWidth;
  final FilterQuality filterQuality;
  final Widget? placeholder;

  @override
  State<FadeNetworkImage> createState() => _FadeNetworkImageState();
}

class _FadeNetworkImageState extends State<FadeNetworkImage> {
  int _attempt = 0;
  Timer? _retryTimer;

  @override
  void didUpdateWidget(covariant FadeNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _retryTimer?.cancel();
      _attempt = 0;
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  void _scheduleTransientRetry() {
    if (_attempt >= 3 || (_retryTimer?.isActive ?? false)) return;
    final delayMs = switch (_attempt) {
      0 => 650,
      1 => 1600,
      _ => 3200,
    };
    _retryTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      final baseProvider = NetworkImage(widget.url);
      PaintingBinding.instance.imageCache.evict(baseProvider);
      if (widget.cacheWidth != null) {
        PaintingBinding.instance.imageCache.evict(
          ResizeImage.resizeIfNeeded(widget.cacheWidth, null, baseProvider),
        );
      }
      setState(() => _attempt += 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.isEmpty) return widget.placeholder ?? const SizedBox.shrink();
    return Image.network(
      widget.url,
      key: ValueKey('${widget.url}#$_attempt'),
      fit: widget.fit,
      alignment: widget.alignment,
      cacheWidth: widget.cacheWidth,
      filterQuality: widget.filterQuality,
      gaplessPlayback: true,
      frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return widget.placeholder ?? const SizedBox.shrink();
      },
      errorBuilder: (_, __, ___) {
        _scheduleTransientRetry();
        return widget.placeholder ?? const SizedBox.shrink();
      },
    );
  }
}

/// Portrait poster displayed inside a 16:9 slot (exact `embygo` Web `FramedPoster` treatment):
/// compact blurred, darkened, saturated ambient fill + soft cinema scrim + crisp centered 2:3 cover.
class FramedPoster extends StatelessWidget {
  const FramedPoster({super.key, required this.url, this.tinyUrl, this.cacheWidth});
  final String url;
  final String? tinyUrl;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final bgUrl = (tinyUrl != null && tinyUrl!.isNotEmpty) ? tinyUrl! : url;
    final sigma = PlatformPerfProfile.framedPosterBlurSigma;
    return RepaintBoundary(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Transform.scale(
              scale: 1.14,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: sigma,
                  sigmaY: sigma,
                  tileMode: TileMode.clamp,
                ),
                child: ColorFiltered(
                  // Matches embygo Web `brightness-[.55] saturate-[1.3]`
                  colorFilter: const ColorFilter.matrix(<double>[
                    0.667, -0.058, -0.058, 0, 0,
                    -0.115, 0.610, -0.058, 0, 0,
                    -0.115, -0.115, 0.725, 0, 0,
                    0, 0, 0, 1, 0,
                  ]),
                  child: FadeNetworkImage(
                    url: bgUrl,
                    fit: BoxFit.cover,
                    cacheWidth: 96,
                    filterQuality: FilterQuality.low,
                  ),
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0x99000000), Color(0x33000000)],
                ),
              ),
            ),
            Center(
              child: FractionallySizedBox(
                heightFactor: 0.84,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x99000000),
                          blurRadius: 14,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: FadeNetworkImage(
                      url: url,
                      fit: BoxFit.cover,
                      cacheWidth: cacheWidth ?? 260,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Strictly clipped ultra-soft color-wash diffusion when a detail banner lacks a 16:9 widescreen backdrop.
/// Decodes at tiny `cacheWidth: 96` inside a `RepaintBoundary` so portrait poster faces NEVER appear
/// stretched AND GPU raster cost stays negligible on phones and desktop GPUs!
class _AmbientBlurBackdrop extends StatelessWidget {
  const _AmbientBlurBackdrop({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final sigma = PlatformPerfProfile.ambientBlurSigma;
    return RepaintBoundary(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Transform.scale(
              scale: 1.45,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: sigma,
                  sigmaY: sigma,
                  tileMode: TileMode.clamp,
                ),
                child: Image.network(
                  url,
                  cacheWidth: 96,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  color: Colors.white.withValues(alpha: skin.isLight ? 0.34 : 0.42),
                  colorBlendMode: BlendMode.modulate,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: skin.canvas.withValues(alpha: skin.isLight ? 0.35 : 0.38),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Unified artwork surface for posters (2:3) and widescreen cards/heroes (16:9).
/// Always layers `GeneratedArt` beneath real imagery so slow/missing covers look calm and intentional.
class VedroArtwork extends StatelessWidget {
  const VedroArtwork({
    super.key,
    required this.item,
    required this.appState,
    this.fallbackItem,
    this.landscape = false,
    this.isHero = false,
    this.width,
    this.displayWidth,
    this.alignment = Alignment.center,
    this.showInitials = true,
  });

  final MediaItemModel item;
  final VedroAppState appState;
  final MediaItemModel? fallbackItem;
  final bool landscape;
  final bool isHero;
  final int? width;
  final double? displayWidth;
  final Alignment alignment;
  final bool showInitials;

  @override
  Widget build(BuildContext context) {
    final seed = item.type == 'Episode' && !landscape
        ? (item.seriesId ?? item.id)
        : (item.id.isNotEmpty ? item.id : item.name);
    final label = showInitials
        ? (item.type == 'Episode' ? (item.seriesName ?? item.displayName) : item.name)
        : null;

    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final placeholder = GeneratedArt(seed: seed, label: label);
    Widget? artLayer;
    var replacesPlaceholder = false;
    if (isHero) {
      final reqW = width ?? (PlatformPerfProfile.isMobile ? 1280 : 1920);
      final logicalW = displayWidth ?? (reqW.toDouble() / 1.5);
      final cacheW = PlatformPerfProfile.imageCacheWidthFor(logicalW, dpr);
      final art = appState.backdropArt(item, width: reqW) ??
          (fallbackItem != null ? appState.backdropArt(fallbackItem!, width: reqW) : null);
      if (art != null) {
        if (art.isPoster) {
          artLayer = _AmbientBlurBackdrop(url: art.url);
        } else {
          replacesPlaceholder = true;
          artLayer = FadeNetworkImage(
            url: art.url,
            fit: BoxFit.cover,
            alignment: alignment,
            cacheWidth: cacheW,
            placeholder: placeholder,
          );
        }
      }
    } else if (landscape) {
      final w = width ?? 640;
      final logicalW = displayWidth ?? (w.toDouble() / 1.6);
      final cacheW = PlatformPerfProfile.imageCacheWidthFor(logicalW, dpr);
      final primaryArt = appState.wideArt(item, width: w);
      final fbArt = fallbackItem != null ? appState.wideArt(fallbackItem!, width: w) : null;
      // Prefer real 16:9 landscape still/backdrop from item first, then from fallbackItem (Season/Series),
      // then fall back to item/Season/Series portrait cover via `FramedPoster` (matching embygo Web!).
      final ResolvedArt? chosen;
      if (primaryArt != null && !primaryArt.isPoster) {
        chosen = primaryArt;
      } else if (fbArt != null && !fbArt.isPoster) {
        chosen = fbArt;
      } else {
        chosen = primaryArt ?? fbArt;
      }
      if (chosen != null) {
        if (chosen.isPoster) {
          artLayer = FramedPoster(url: chosen.url, tinyUrl: chosen.tinyUrl, cacheWidth: cacheW);
        } else {
          replacesPlaceholder = true;
          artLayer = FadeNetworkImage(
            url: chosen.url,
            fit: BoxFit.cover,
            alignment: alignment,
            cacheWidth: cacheW,
            placeholder: placeholder,
          );
        }
      }
    } else {
      final reqW = width ?? 420;
      final logicalW = displayWidth ?? (reqW.toDouble() / 1.6);
      final cacheW = PlatformPerfProfile.imageCacheWidthFor(logicalW, dpr);
      final url = appState.posterArtUrl(item, width: reqW) ??
          (fallbackItem != null ? appState.posterArtUrl(fallbackItem!, width: reqW) : null);
      if (url != null) {
        replacesPlaceholder = true;
        artLayer = FadeNetworkImage(
          url: url,
          fit: BoxFit.cover,
          alignment: alignment,
          cacheWidth: cacheW,
          placeholder: placeholder,
        );
      }
    }

    if (artLayer == null) {
      return ClipRect(child: placeholder);
    }
    if (replacesPlaceholder) {
      return ClipRect(child: artLayer);
    }
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          placeholder,
          artLayer,
        ],
      ),
    );
  }
}

/// Smooth GPU-animated dark shimmer placeholder (replaces jarring frozen spinners).
class VedroShimmer extends StatefulWidget {
  const VedroShimmer({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 12,
    this.aspectRatio,
  });

  final double? width;
  final double? height;
  final double borderRadius;
  final double? aspectRatio;

  @override
  State<VedroShimmer> createState() => _VedroShimmerState();
}

class _VedroShimmerState extends State<VedroShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final Widget box;
    if (MediaQuery.disableAnimationsOf(context)) {
      box = Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          color: skin.surface,
        ),
      );
    } else {
      box = RepaintBoundary(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            final t = _ctrl.value;
            final slide = -1.0 + 3.0 * t;
            return Container(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                gradient: LinearGradient(
                  begin: Alignment(slide - 0.8, -0.3),
                  end: Alignment(slide + 0.8, 0.3),
                  colors: [
                    skin.surface,
                    skin.surface2,
                    skin.surface,
                  ],
                ),
              ),
            );
          },
        ),
      );
    }
    if (widget.aspectRatio != null) {
      return AspectRatio(aspectRatio: widget.aspectRatio!, child: box);
    }
    return box;
  }
}

class HeroSkeleton extends StatelessWidget {
  const HeroSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final screenH = MediaQuery.sizeOf(context).height;
    final heroH = (screenH * 0.66).clamp(420.0, 680.0);
    return SizedBox(
      height: heroH,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const VedroShimmer(borderRadius: 0),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.35, 1.0],
                colors: [Colors.transparent, skin.canvas],
              ),
            ),
          ),
          const Positioned(
            left: 32,
            right: 32,
            bottom: 48,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VedroShimmer(width: 90, height: 14, borderRadius: 4),
                SizedBox(height: 14),
                VedroShimmer(width: 320, height: 42, borderRadius: 8),
                SizedBox(height: 14),
                VedroShimmer(width: 440, height: 14, borderRadius: 4),
                SizedBox(height: 8),
                VedroShimmer(width: 300, height: 14, borderRadius: 4),
                SizedBox(height: 24),
                Row(
                  children: [
                    VedroShimmer(width: 112, height: 44, borderRadius: 12),
                    SizedBox(width: 12),
                    VedroShimmer(width: 96, height: 44, borderRadius: 12),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RailSkeleton extends StatelessWidget {
  const RailSkeleton({super.key, this.landscape = false});
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    final cardW = landscape ? 290.0 : 152.0;
    final ratio = landscape ? 16 / 9 : 2 / 3;
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 28),
            child: VedroShimmer(width: 132, height: 20, borderRadius: 6),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: (cardW / ratio) + 52,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 7,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (_, idx) => SizedBox(
                width: cardW,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    VedroShimmer(aspectRatio: ratio, borderRadius: 14),
                    const SizedBox(height: 10),
                    VedroShimmer(
                      width: math.max(70, cardW * 0.72),
                      height: 13,
                      borderRadius: 4,
                    ),
                    const SizedBox(height: 6),
                    VedroShimmer(
                      width: math.max(44, cardW * 0.42),
                      height: 11,
                      borderRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
