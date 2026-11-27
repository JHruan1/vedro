import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/models/models.dart';
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

/// Network image that smoothly fades in once decoded and gracefully disappears
/// on error so `GeneratedArt` beneath remains visible with zero layout jump.
class FadeNetworkImage extends StatelessWidget {
  const FadeNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final String url;
  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const SizedBox.shrink();
    return Image.network(
      url,
      fit: fit,
      alignment: alignment,
      gaplessPlayback: true,
      frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
          child: child,
        );
      },
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}

/// Portrait poster displayed inside a 16:9 slot: clipped soft ambient poster fills
/// the field while the crisp poster sits framed with a soft cinema float shadow.
class FramedPoster extends StatelessWidget {
  const FramedPoster({super.key, required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Transform.scale(
            scale: 1.18,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix(<double>[
                  0.62, 0, 0, 0, 0,
                  0, 0.62, 0, 0, 0,
                  0, 0, 0.62, 0, 0,
                  0, 0, 0, 1, 0,
                ]),
                child: FadeNetworkImage(url: url, fit: BoxFit.cover),
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
                        blurRadius: 20,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: FadeNetworkImage(url: url, fit: BoxFit.cover),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Strictly clipped ultra-soft color-wash diffusion when a detail banner lacks a 16:9 widescreen backdrop.
/// Uses wide Gaussian diffusion (`sigma = 56`) so portrait poster faces NEVER appear stretched or double-stacked behind the poster card!
class _AmbientBlurBackdrop extends StatelessWidget {
  const _AmbientBlurBackdrop({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Transform.scale(
            scale: 1.52,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: 56,
                sigmaY: 56,
                tileMode: TileMode.clamp,
              ),
              child: Opacity(
                opacity: skin.isLight ? 0.34 : 0.42,
                child: FadeNetworkImage(url: url, fit: BoxFit.cover),
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
    this.alignment = Alignment.center,
    this.showInitials = true,
  });

  final MediaItemModel item;
  final VedroAppState appState;
  final MediaItemModel? fallbackItem;
  final bool landscape;
  final bool isHero;
  final int? width;
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

    Widget? artLayer;
    if (isHero) {
      final art = appState.backdropArt(item, width: width ?? 1920) ??
          (fallbackItem != null ? appState.backdropArt(fallbackItem!, width: width ?? 1920) : null);
      if (art != null) {
        artLayer = art.isPoster
            ? _AmbientBlurBackdrop(url: art.url)
            : FadeNetworkImage(url: art.url, fit: BoxFit.cover, alignment: alignment);
      }
    } else if (landscape) {
      final art = appState.wideArt(item, width: width ?? 640) ??
          (fallbackItem != null ? appState.wideArt(fallbackItem!, width: width ?? 640) : null);
      if (art != null) {
        artLayer = art.isPoster
            ? FramedPoster(url: art.url)
            : FadeNetworkImage(url: art.url, fit: BoxFit.cover, alignment: alignment);
      }
    } else {
      final url = appState.posterArtUrl(item, width: width ?? 420) ??
          (fallbackItem != null ? appState.posterArtUrl(fallbackItem!, width: width ?? 420) : null);
      if (url != null) {
        artLayer = FadeNetworkImage(url: url, fit: BoxFit.cover, alignment: alignment);
      }
    }

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          GeneratedArt(seed: seed, label: label),
          if (artLayer != null) artLayer,
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
    final box = AnimatedBuilder(
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
    );
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
