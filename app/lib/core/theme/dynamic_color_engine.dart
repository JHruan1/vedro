import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'vedro_skin.dart';

/// Real-time Monet / Apple Music style Artwork Palette Extractor & Theme Harmonizer.
/// Extracts vibrant, high-contrast seed colors directly from media posters/backdrops
/// with LRU memory caching and deterministic zero-latency fallback.
class DynamicColorEngine {
  DynamicColorEngine._();

  static final LinkedHashMap<String, Color> _urlCache = LinkedHashMap<String, Color>();
  static final Map<String, Future<Color?>> _inFlight = <String, Future<Color?>>{};
  static const int _maxCacheEntries = 96;

  static Color? cachedForUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    return _urlCache[url];
  }

  /// Deterministic rich cinematic seed color derived from item identity when offline
  /// or while network artwork is still decoding.
  static Color seedForIdentity(String id, [String name = '']) {
    final raw = '$id::$name';
    var hash = 0x811c9dc5;
    for (var i = 0; i < raw.length; i++) {
      hash ^= raw.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    final hue = (hash % 360).toDouble();
    final sat = 0.62 + ((hash >> 8) % 20) / 100.0; // 0.62 .. 0.81
    return HSLColor.fromAHSL(1.0, hue, sat.clamp(0.55, 0.82), 0.56).toColor();
  }

  /// Asynchronously sample decoded pixels of a network artwork URL (`18x18` grid)
  /// and score hues by chroma & mid-tone luminance (Monet-style vibrancy scoring).
  static Future<Color?> extractFromImageUrl(String? url) {
    final clean = url?.trim() ?? '';
    if (clean.isEmpty) return Future<Color?>.value(null);
    final hit = _urlCache[clean];
    if (hit != null) return Future<Color?>.value(hit);
    final pending = _inFlight[clean];
    if (pending != null) return pending;

    final future = _extractInternal(clean).whenComplete(() {
      _inFlight.remove(clean);
    });
    _inFlight[clean] = future;
    return future;
  }

  static Future<Color?> _extractInternal(String url) async {
    final completer = Completer<ImageInfo?>();
    final provider = ResizeImage(NetworkImage(url), width: 64, height: 64);
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    Timer? timer;

    void finish(ImageInfo? info) {
      timer?.cancel();
      try {
        stream.removeListener(listener);
      } catch (_) {}
      if (!completer.isCompleted) {
        completer.complete(info);
      } else {
        info?.dispose();
      }
    }

    listener = ImageStreamListener(
      (info, _) => finish(info.clone()),
      onError: (_, __) => finish(null),
    );
    timer = Timer(const Duration(milliseconds: 3500), () => finish(null));
    stream.addListener(listener);

    final info = await completer.future;
    if (info == null) return null;

    try {
      final image = info.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      final color = extractDominantSeedFromRgba(
        data.buffer.asUint8List(),
        width: image.width,
        height: image.height,
      );
      if (color != null) {
        if (_urlCache.length >= _maxCacheEntries) {
          _urlCache.remove(_urlCache.keys.first);
        }
        _urlCache[url] = color;
      }
      return color;
    } catch (_) {
      return null;
    } finally {
      info.dispose();
    }
  }

  /// Pure RGBA pixel histogram scorer (also directly unit-testable with synthetic bytes).
  static Color? extractDominantSeedFromRgba(
    List<int> rgba, {
    required int width,
    required int height,
  }) {
    if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
      return null;
    }
    const buckets = 36; // 10-degree hue bins
    final weights = List<double>.filled(buckets, 0.0);
    final rSum = List<double>.filled(buckets, 0.0);
    final gSum = List<double>.filled(buckets, 0.0);
    final bSum = List<double>.filled(buckets, 0.0);

    final stepX = math.max(1, width ~/ 20);
    final stepY = math.max(1, height ~/ 20);

    double fallbackR = 0, fallbackG = 0, fallbackB = 0, fallbackN = 0;

    for (var y = 0; y < height; y += stepY) {
      for (var x = 0; x < width; x += stepX) {
        final idx = (y * width + x) * 4;
        final a = rgba[idx + 3];
        if (a < 140) continue;
        final r = rgba[idx] / 255.0;
        final g = rgba[idx + 1] / 255.0;
        final b = rgba[idx + 2] / 255.0;

        final maxC = math.max(r, math.max(g, b));
        final minC = math.min(r, math.min(g, b));
        final delta = maxC - minC;
        final lum = (maxC + minC) * 0.5;

        if (lum > 0.06 && lum < 0.94) {
          fallbackR += r;
          fallbackG += g;
          fallbackB += b;
          fallbackN += 1.0;
        }

        // Ignore near-black letterbox bars, blown-out highlights, and neutral grey
        if (lum < 0.09 || lum > 0.89 || delta < 0.11) continue;

        final sat = lum > 0.5 ? delta / (2.0 - maxC - minC) : delta / (maxC + minC);
        if (sat < 0.14) continue;

        double hue;
        if (maxC == r) {
          hue = ((g - b) / delta) % 6.0;
        } else if (maxC == g) {
          hue = ((b - r) / delta) + 2.0;
        } else {
          hue = ((r - g) / delta) + 4.0;
        }
        hue = (hue * 60.0 + 360.0) % 360.0;

        // Favor rich chroma and mid-luminance cinematic tones
        final lumPenalty = 1.0 - ((lum - 0.48).abs() * 1.15).clamp(0.0, 0.72);
        final score = math.pow(sat, 1.35).toDouble() * lumPenalty;

        final bin = (hue ~/ 10).clamp(0, buckets - 1);
        weights[bin] += score;
        rSum[bin] += r * score;
        gSum[bin] += g * score;
        bSum[bin] += b * score;
      }
    }

    var bestBin = -1;
    var bestWeight = 0.0;
    for (var i = 0; i < buckets; i++) {
      // Smooth with immediate neighboring hue bins for perceptual stability
      final prev = weights[(i - 1 + buckets) % buckets] * 0.35;
      final next = weights[(i + 1) % buckets] * 0.35;
      final total = weights[i] + prev + next;
      if (total > bestWeight && weights[i] > 0) {
        bestWeight = total;
        bestBin = i;
      }
    }

    Color rawColor;
    if (bestBin >= 0 && weights[bestBin] > 0) {
      final w = weights[bestBin];
      rawColor = Color.fromARGB(
        255,
        ((rSum[bestBin] / w) * 255).round().clamp(0, 255),
        ((gSum[bestBin] / w) * 255).round().clamp(0, 255),
        ((bSum[bestBin] / w) * 255).round().clamp(0, 255),
      );
    } else if (fallbackN > 0) {
      rawColor = Color.fromARGB(
        255,
        ((fallbackR / fallbackN) * 255).round().clamp(0, 255),
        ((fallbackG / fallbackN) * 255).round().clamp(0, 255),
        ((fallbackB / fallbackN) * 255).round().clamp(0, 255),
      );
    } else {
      return null;
    }

    final hsl = HSLColor.fromColor(rawColor);
    return HSLColor.fromAHSL(
      1.0,
      hsl.hue,
      hsl.saturation.clamp(0.46, 0.86),
      hsl.lightness.clamp(0.48, 0.64),
    ).toColor();
  }

  /// Harmonize any `VedroSkin` Master Theme (`immersive_cinema`, `ios_frosted`,
  /// `ios_liquid_glass`, `material_design`) with a Monet / Accent seed color!
  static VedroSkin applySeedToSkin(
    VedroSkin base,
    Color seed, {
    String tonalChroma = 'standard',
    bool tintAtmosphere = true,
  }) {
    final chromaMul = switch (tonalChroma) {
      'soft' => 0.65,
      'vivid' => 1.28,
      _ => 1.0,
    };
    final hsl = HSLColor.fromColor(seed);
    final tunedSat = (hsl.saturation * chromaMul).clamp(0.32, 0.92);
    final tunedSeed = HSLColor.fromAHSL(1.0, hsl.hue, tunedSat, hsl.lightness.clamp(0.42, 0.64)).toColor();
    final isLight = base.isLight;

    // Material Design 3 / Material You full tonal container synthesis
    if (base.themeFamily == 'material_design') {
      final scheme = ColorScheme.fromSeed(
        seedColor: tunedSeed,
        brightness: isLight ? Brightness.light : Brightness.dark,
      );
      final canvas = isLight
          ? Color.lerp(const Color(0xFFF6F7FB), scheme.surfaceContainerLowest, 0.65 * chromaMul.clamp(0.5, 1.0))!
          : Color.lerp(const Color(0xFF0E1015), scheme.surface, 0.78 * chromaMul.clamp(0.5, 1.0))!;
      final surf = isLight ? scheme.surfaceContainerLow : scheme.surfaceContainer;
      final surf2 = isLight ? scheme.surfaceContainer : scheme.surfaceContainerHigh;
      final surf3 = isLight ? scheme.surfaceContainerHigh : scheme.surfaceContainerHighest;
      return base.copyWith(
        canvas: canvas,
        canvasGlow: scheme.primary.withValues(alpha: isLight ? 0.25 : 0.34),
        surface: surf,
        surface2: surf2,
        surface3: surf3,
        field: surf2,
        glass: surf.withValues(alpha: isLight ? 0.88 : 0.84),
        glassStrong: surf2.withValues(alpha: 0.95),
        border: scheme.outlineVariant.withValues(alpha: isLight ? 0.55 : 0.38),
        borderStrong: scheme.outline.withValues(alpha: isLight ? 0.65 : 0.55),
        fg: scheme.onSurface,
        fg2: scheme.onSurfaceVariant,
        fg3: scheme.onSurfaceVariant.withValues(alpha: 0.68),
        accent: scheme.primary,
        accentSecondary: scheme.secondary,
      );
    }

    // iOS / Cinema Master Themes (`immersive_cinema`, `ios_frosted`, `ios_liquid_glass`)
    final accent = HSLColor.fromAHSL(
      1.0,
      hsl.hue,
      tunedSat.clamp(0.52, 0.90),
      isLight ? 0.45 : 0.63,
    ).toColor();
    final accentSecondary = HSLColor.fromAHSL(
      1.0,
      (hsl.hue + 14.0) % 360.0,
      tunedSat.clamp(0.50, 0.88),
      isLight ? 0.38 : 0.52,
    ).toColor();

    if (!tintAtmosphere) {
      return base.copyWith(
        accent: accent,
        accentSecondary: accentSecondary,
        canvasGlow: HSLColor.fromAHSL(1.0, hsl.hue, tunedSat * 0.72, isLight ? 0.82 : 0.24).toColor(),
      );
    }

    // Subtle atmospheric room-tint (like Apple Music / iOS 26 / SenPlayer immersive pages)
    final roomTintDark = HSLColor.fromAHSL(1.0, hsl.hue, (tunedSat * 0.48).clamp(0.18, 0.46), 0.08).toColor();
    final roomTintLight = HSLColor.fromAHSL(1.0, hsl.hue, (tunedSat * 0.35).clamp(0.10, 0.32), 0.95).toColor();
    final tintStrength = base.themeFamily == 'ios_liquid_glass'
        ? 0.52
        : (base.themeFamily == 'ios_frosted' ? 0.44 : 0.38);

    final canvas = isLight
        ? Color.lerp(base.canvas, roomTintLight, tintStrength)!
        : Color.lerp(base.canvas, roomTintDark, tintStrength)!;
    final surfTint = isLight
        ? HSLColor.fromAHSL(1.0, hsl.hue, (tunedSat * 0.25).clamp(0.06, 0.24), 0.985).toColor()
        : HSLColor.fromAHSL(1.0, hsl.hue, (tunedSat * 0.42).clamp(0.14, 0.40), 0.135).toColor();
    final surface = Color.lerp(base.surface, surfTint, tintStrength * 0.85)!;
    final surface2 = Color.lerp(
      base.surface2,
      isLight
          ? HSLColor.fromAHSL(1.0, hsl.hue, (tunedSat * 0.28).clamp(0.08, 0.26), 0.93).toColor()
          : HSLColor.fromAHSL(1.0, hsl.hue, (tunedSat * 0.40).clamp(0.14, 0.38), 0.185).toColor(),
      tintStrength * 0.85,
    )!;
    final surface3 = Color.lerp(
      base.surface3,
      isLight
          ? HSLColor.fromAHSL(1.0, hsl.hue, (tunedSat * 0.30).clamp(0.10, 0.28), 0.88).toColor()
          : HSLColor.fromAHSL(1.0, hsl.hue, (tunedSat * 0.38).clamp(0.14, 0.36), 0.245).toColor(),
      tintStrength * 0.85,
    )!;
    final glow = HSLColor.fromAHSL(
      1.0,
      hsl.hue,
      (tunedSat * 0.78).clamp(0.30, 0.82),
      isLight ? 0.80 : 0.28,
    ).toColor();

    final glassAlpha = base.isLiquidGlass
        ? (isLight ? 0.62 : 0.54)
        : (isLight ? 0.78 : 0.72);
    final glassStrongAlpha = base.isLiquidGlass
        ? (isLight ? 0.78 : 0.72)
        : (isLight ? 0.92 : 0.88);

    return base.copyWith(
      canvas: canvas,
      canvasGlow: glow,
      surface: surface,
      surface2: surface2,
      surface3: surface3,
      field: Color.lerp(canvas, surface2, 0.58)!,
      glass: Color.lerp(surface, accent, isLight ? 0.05 : 0.10)!.withValues(alpha: glassAlpha),
      glassStrong: Color.lerp(surface2, accent, isLight ? 0.06 : 0.12)!.withValues(alpha: glassStrongAlpha),
      border: isLight
          ? Color.lerp(Colors.black, accent, 0.18)!.withValues(alpha: 0.11)
          : Color.lerp(Colors.white, accent, 0.28)!.withValues(alpha: base.isLiquidGlass ? 0.22 : 0.15),
      borderStrong: isLight
          ? Color.lerp(Colors.black, accent, 0.24)!.withValues(alpha: 0.22)
          : Color.lerp(Colors.white, accent, 0.36)!.withValues(alpha: base.isLiquidGlass ? 0.38 : 0.28),
      accent: accent,
      accentSecondary: accentSecondary,
    );
  }
}
