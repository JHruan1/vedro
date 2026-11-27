import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../platform/platform_perf.dart';
import '../theme/display_profile.dart';
import '../theme/dynamic_color_engine.dart';
import '../theme/vedro_skin.dart';

/// Deterministic legacy v1 hash for local passcode verification (kept for compatibility).
String hashPasscode(String pin) {
  final bytes = utf8.encode('vedro.lock.v1::$pin');
  var h1 = 0x811c9dc5;
  var h2 = 0x01000193;
  for (final b in bytes) {
    h1 = ((h1 ^ b) * 0x01000193) & 0xFFFFFFFF;
    h2 = ((h2 + (b << 5) - b) ^ (h1 >> 3)) & 0xFFFFFFFF;
  }
  return '${h1.toRadixString(16).padLeft(8, '0')}${h2.toRadixString(16).padLeft(8, '0')}';
}

String _mixPasscodeV2(String salt, String pin) {
  var state = utf8.encode('vedro.lock.v2::$salt::$pin');
  var a = 0x6a09e667;
  var b = 0xbb67ae85;
  var c = 0x3c6ef372;
  var d = 0xa54ff53a;
  for (var round = 0; round < 10000; round++) {
    a = (a ^ round ^ 0x9e3779b9) & 0xFFFFFFFF;
    for (var i = 0; i < state.length; i++) {
      final byte = state[i];
      a = ((a ^ byte) * 0x01000193) & 0xFFFFFFFF;
      b = (((b << 7) | (b >>> 25)) ^ (a + byte + i)) & 0xFFFFFFFF;
      c = ((c + b + 0x85ebca6b) ^ (a >>> 11)) & 0xFFFFFFFF;
      d = (((d ^ c) * 0xc2b2ae35) ^ (b >>> 13)) & 0xFFFFFFFF;
    }
    final tmp = a;
    a = (b ^ (d >>> 5)) & 0xFFFFFFFF;
    b = (c + tmp) & 0xFFFFFFFF;
    c = (d ^ (a << 3)) & 0xFFFFFFFF;
    d = (tmp + b) & 0xFFFFFFFF;
  }
  return '${a.toRadixString(16).padLeft(8, '0')}'
      '${b.toRadixString(16).padLeft(8, '0')}'
      '${c.toRadixString(16).padLeft(8, '0')}'
      '${d.toRadixString(16).padLeft(8, '0')}';
}

/// Generate a salted, key-stretched (`10,000` rounds) v2 passcode hash (`vedro.lock.v2:<salt>:<digest>`).
String createSaltedPasscodeHash(String pin) {
  final rng = math.Random.secure();
  final saltBytes = List<int>.generate(12, (_) => rng.nextInt(256));
  final salt = saltBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  final digest = _mixPasscodeV2(salt, pin);
  return 'vedro.lock.v2:$salt:$digest';
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// Verify a candidate PIN against either a salted `vedro.lock.v2` hash or legacy v1 hash.
bool verifyPasscode(String pin, String storedHash) {
  final stored = storedHash.trim();
  if (stored.isEmpty) return false;
  if (stored.startsWith('vedro.lock.v2:')) {
    final parts = stored.split(':');
    if (parts.length != 3 || parts[1].isEmpty || parts[2].isEmpty) return false;
    return _constantTimeEquals(_mixPasscodeV2(parts[1], pin), parts[2]);
  }
  return _constantTimeEquals(hashPasscode(pin), stored);
}

double _finiteDouble(dynamic raw, double fallback, double min, double max) {
  if (raw is num) {
    final d = raw.toDouble();
    if (d.isFinite) return d.clamp(min, max).toDouble();
  }
  return fallback;
}

int _clampedInt(dynamic raw, int fallback, int min, int max) {
  if (raw is num) {
    final d = raw.toDouble();
    if (d.isFinite) return d.round().clamp(min, max);
  }
  return fallback;
}

class AccentPalette {
  const AccentPalette({
    required this.id,
    required this.label,
    required this.accent,
    required this.fill,
  });

  final String id;
  final String label;
  final Color accent;
  final Color fill;

  static const List<AccentPalette> all = [
    AccentPalette(id: 'blue', label: '海湾蓝', accent: Color(0xFF0A84FF), fill: Color(0xFF0066DB)),
    AccentPalette(id: 'cyan', label: '冰川青', accent: Color(0xFF32ADE6), fill: Color(0xFF0284C7)),
    AccentPalette(id: 'emerald', label: '翡翠绿', accent: Color(0xFF30D158), fill: Color(0xFF10B981)),
    AccentPalette(id: 'purple', label: '极光紫', accent: Color(0xFFBF5AF2), fill: Color(0xFF9333EA)),
    AccentPalette(id: 'amber', label: '流光橙', accent: Color(0xFFFF9F0A), fill: Color(0xFFD97706)),
    AccentPalette(id: 'pink', label: '樱花粉', accent: Color(0xFFFF375F), fill: Color(0xFFE11D48)),
    AccentPalette(id: 'rose', label: '绯霞红', accent: Color(0xFFFF453A), fill: Color(0xFFDC2626)),
    AccentPalette(id: 'indigo', label: '星际靛', accent: Color(0xFF5E5CE6), fill: Color(0xFF4F46E5)),
    AccentPalette(id: 'silver', label: '曜石银', accent: Color(0xFFE5E7EB), fill: Color(0xFF4B5563)),
  ];

  static AccentPalette byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return all.first;
  }
}

/// Visual theme preset for an individual Media Server Card.
class ServerCardTheme {
  const ServerCardTheme({
    required this.id,
    required this.label,
    required this.accent,
    required this.bgTop,
    required this.bgBottom,
  });

  final String id;
  final String label;
  final Color accent;
  final Color bgTop;
  final Color bgBottom;

  Color cardBgTop(VedroSkin skin) =>
      skin.isLight ? Color.lerp(skin.surface, accent, 0.12)! : bgTop;

  Color cardBgBottom(VedroSkin skin) =>
      skin.isLight ? Color.lerp(skin.surface, accent, 0.03)! : bgBottom;

  Color cardAccent(VedroSkin skin) {
    if (!skin.isLight) return accent;
    if (id == 'graphite') return const Color(0xFF475569);
    if (id == 'amber') return const Color(0xFFD97706);
    if (id == 'emerald') return const Color(0xFF059669);
    return HSLColor.fromColor(accent)
        .withLightness(
          HSLColor.fromColor(accent).lightness.clamp(0.28, 0.44),
        )
        .toColor();
  }

  static const List<ServerCardTheme> all = [
    ServerCardTheme(
      id: 'cobalt',
      label: '午夜蓝',
      accent: Color(0xFF5B9BFF),
      bgTop: Color(0xFF151E30),
      bgBottom: Color(0xFF11131B),
    ),
    ServerCardTheme(
      id: 'emerald',
      label: '翡翠绿',
      accent: Color(0xFF34D399),
      bgTop: Color(0xFF112620),
      bgBottom: Color(0xFF111517),
    ),
    ServerCardTheme(
      id: 'violet',
      label: '暮光紫',
      accent: Color(0xFFA78BFA),
      bgTop: Color(0xFF201833),
      bgBottom: Color(0xFF13121B),
    ),
    ServerCardTheme(
      id: 'amber',
      label: '琥珀金',
      accent: Color(0xFFFBBF24),
      bgTop: Color(0xFF282012),
      bgBottom: Color(0xFF151311),
    ),
    ServerCardTheme(
      id: 'rose',
      label: '玫瑰红',
      accent: Color(0xFFFB7185),
      bgTop: Color(0xFF2B161E),
      bgBottom: Color(0xFF161215),
    ),
    ServerCardTheme(
      id: 'graphite',
      label: '曜石黑',
      accent: Color(0xFFD1D5DB),
      bgTop: Color(0xFF1C1D22),
      bgBottom: Color(0xFF121317),
    ),
  ];

  static ServerCardTheme byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return all.first;
  }

  /// Deterministic default theme per server id when user hasn't customized one yet.
  static ServerCardTheme forSeed(String seed) {
    var h = 0;
    for (var i = 0; i < seed.length; i++) {
      h = (h * 31 + seed.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return all[h % all.length];
  }
}

/// Per-server customizable card appearance & privacy settings.
class ServerCardStyle {
  const ServerCardStyle({
    this.customName = '',
    this.subtitle = '',
    this.themeId = '',
    this.iconId = 'server',
    this.hideAddress = false,
  });

  final String customName;
  final String subtitle;
  final String themeId; // '' => auto deterministic
  final String iconId; // server | film | tv | home | cloud | bolt | globe | sparkles
  final bool hideAddress;

  static const Map<String, (String label, IconData icon)> icons = {
    'server': ('服务器', Icons.dns_rounded),
    'film': ('影院', Icons.movie_filter_rounded),
    'tv': ('剧集', Icons.live_tv_rounded),
    'home': ('家庭 NAS', Icons.home_rounded),
    'cloud': ('云盘', Icons.cloud_rounded),
    'bolt': ('高速专线', Icons.bolt_rounded),
    'globe': ('海外节点', Icons.public_rounded),
    'sparkles': ('番剧动漫', Icons.auto_awesome_rounded),
  };

  IconData get iconData => icons[iconId]?.$2 ?? Icons.dns_rounded;

  ServerCardTheme resolveTheme(String serverId) =>
      themeId.isNotEmpty ? ServerCardTheme.byId(themeId) : ServerCardTheme.forSeed(serverId);

  ServerCardStyle copyWith({
    String? customName,
    String? subtitle,
    String? themeId,
    String? iconId,
    bool? hideAddress,
  }) =>
      ServerCardStyle(
        customName: customName ?? this.customName,
        subtitle: subtitle ?? this.subtitle,
        themeId: themeId ?? this.themeId,
        iconId: iconId ?? this.iconId,
        hideAddress: hideAddress ?? this.hideAddress,
      );

  Map<String, dynamic> toJson() => {
        'custom_name': customName,
        'subtitle': subtitle,
        'theme_id': themeId,
        'icon_id': iconId,
        'hide_address': hideAddress,
      };

  factory ServerCardStyle.fromJson(Map<String, dynamic> j) => ServerCardStyle(
        customName: (j['custom_name'] ?? '').toString(),
        subtitle: (j['subtitle'] ?? '').toString(),
        themeId: (j['theme_id'] ?? '').toString(),
        iconId: (j['icon_id'] ?? 'server').toString(),
        hideAddress: j['hide_address'] == true,
      );
}

class DownloadTaskModel {
  const DownloadTaskModel({
    required this.id,
    required this.itemId,
    required this.title,
    this.subtitle = '',
    this.mediaSourceId,
    this.versionLabel = '',
    this.filePath = '',
    this.etag,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.speedBytesPerSec = 0,
    this.retryCount = 0,
    this.status = 'queued', // queued | downloading | paused | completed | failed
    this.error,
    this.createdAt = 0,
  });

  final String id;
  final String itemId;
  final String title;
  final String subtitle;
  final String? mediaSourceId;
  final String versionLabel;
  final String filePath;
  final String? etag;
  final int totalBytes;
  final int downloadedBytes;
  final int speedBytesPerSec;
  final int retryCount;
  final String status;
  final String? error;
  final int createdAt;

  double get progress =>
      totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : (status == 'completed' ? 1.0 : 0.0);

  bool get isActive => status == 'downloading' || status == 'queued';

  DownloadTaskModel copyWith({
    String? mediaSourceId,
    String? versionLabel,
    String? filePath,
    String? etag,
    int? totalBytes,
    int? downloadedBytes,
    int? speedBytesPerSec,
    int? retryCount,
    String? status,
    String? error,
    bool clearError = false,
  }) =>
      DownloadTaskModel(
        id: id,
        itemId: itemId,
        title: title,
        subtitle: subtitle,
        mediaSourceId: mediaSourceId ?? this.mediaSourceId,
        versionLabel: versionLabel ?? this.versionLabel,
        filePath: filePath ?? this.filePath,
        etag: etag ?? this.etag,
        totalBytes: totalBytes ?? this.totalBytes,
        downloadedBytes: downloadedBytes ?? this.downloadedBytes,
        speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
        retryCount: retryCount ?? this.retryCount,
        status: status ?? this.status,
        error: clearError ? null : (error ?? this.error),
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'item_id': itemId,
        'title': title,
        'subtitle': subtitle,
        if (mediaSourceId != null && mediaSourceId!.isNotEmpty) 'media_source_id': mediaSourceId,
        if (versionLabel.isNotEmpty) 'version_label': versionLabel,
        'file_path': filePath,
        if (etag != null && etag!.isNotEmpty) 'etag': etag,
        'total_bytes': totalBytes,
        'downloaded_bytes': downloadedBytes,
        'retry_count': retryCount,
        'status': status,
        if (error != null) 'error': error,
        'created_at': createdAt,
      };

  factory DownloadTaskModel.fromJson(Map<String, dynamic> j) => DownloadTaskModel(
        id: (j['id'] ?? '').toString(),
        itemId: (j['item_id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        subtitle: (j['subtitle'] ?? '').toString(),
        mediaSourceId: j['media_source_id']?.toString(),
        versionLabel: (j['version_label'] ?? '').toString(),
        filePath: (j['file_path'] ?? '').toString(),
        etag: j['etag']?.toString(),
        totalBytes: (j['total_bytes'] as num?)?.toInt() ?? 0,
        downloadedBytes: (j['downloaded_bytes'] as num?)?.toInt() ?? 0,
        retryCount: (j['retry_count'] as num?)?.toInt() ?? 0,
        status: (j['status'] ?? 'queued').toString(),
        error: j['error']?.toString(),
        createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
      );
}

class VedroPreferences {
  const VedroPreferences({
    // 应用风格 & 主题引擎
    this.skinId = 'immersive_cinema',
    this.themeMode = 'dark', // dark | light | system
    this.dynamicMonet = true,
    this.customAccentHex = '',
    this.tonalChroma = 'standard', // soft | standard | vivid
    this.autoShrinkNavOnScroll = false,
    this.showNavLabels = true,
    this.useSkinGeometry = true,
    this.customSkins = const [],
    this.skinOverrides = const {},
    this.mobileSkinOverrides = const {},
    this.hardwareProfileInitSig = '',
    this.accentId = 'blue',
    this.cardRadius = 15.0,
    this.glassIntensity = 'standard',
    this.reduceMotion = false,
    // 列表配置
    this.listDensity = 'comfortable', // compact | comfortable | spacious
    this.sectionSpacing = 'compact', // compact | standard | spacious
    this.posterScale = 1.0, // 0.75 .. 1.25
    this.showRatings = true,
    this.showYear = true,
    this.showWatchedBadge = true,
    this.showUnplayedCount = true,
    this.showMultiVersionBadge = false,
    this.defaultSort = 'DateCreated',
    // 界面偏好
    this.showSpecBadges = true,
    this.showRemainingTime = false,
    this.confirmExitPlayer = false,
    this.confirmExitApp = true,
    this.incognitoMode = false,
    this.tvModeOverride = false,
    this.ignoredUpdateVersion = '',
    // 播放设置
    this.bufferSizeMb = 128,
    this.autoPlayNext = true,
    this.autoSkipIntro = false,
    this.autoSkipOutro = false,
    this.customSkipIntroSecs = 0,
    this.customSkipOutroSecs = 0,
    this.rememberPosition = true,
    this.rememberBrightness = true,
    this.savedBrightness = 1.0,
    this.rememberVolume = true,
    this.savedVolume = 100.0,
    this.rememberSpeed = true,
    this.rememberAspect = true,
    this.showNetworkSpeed = true,
    this.defaultSpeed = 1.0,
    this.longPressSpeed = 2.0,
    this.seekStepSecs = 10,
    this.pinchToZoom = true,
    this.enablePip = true,
    this.backgroundAudio = false,
    this.externalPlayer = 'builtin', // builtin | iina | infuse | mpv | vlc | potplayer
    // 视频设置
    this.defaultAspect = 'fit',
    this.videoSync = 'audio',
    this.hdrComputePeak = true,
    this.anime4kEnabled = false,
    this.anime4kMode = 'B', // A | B | C | A+A | B+B
    this.anime4kOnlyAnime = true,
    this.customMpvConf = '',
    // 音频设置
    this.preferredAudioLang = 'auto',
    this.maxVolumePercent = 150,
    this.audioDelayMs = 0,
    // 字幕设置
    this.preferredSubLang = 'zh',
    this.autoLoadExternalSubs = true,
    this.forceAssOverride = false,
    this.subtitleFontFamily = '',
    this.subtitleFontScale = 1.0,
    this.subtitlePos = 96,
    this.subtitleColorHex = '#FFFFFF',
    this.subtitleOutlineWidth = 2.4,
    this.subtitleBgOpacity = 0.0,
    this.subtitleDelaySecs = 0.0,
    // 弹幕设置
    this.danmakuEnabled = false,
    this.danmakuOpacity = 0.82,
    this.danmakuFontSize = 18.0,
    this.danmakuSpeedSecs = 9.0,
    this.danmakuArea = 0.5,
    this.danmakuHideTop = false,
    this.danmakuHideBottom = false,
    this.danmakuApiUrl = '',
    // AI 服务（翻译 & 语音识别转字幕）— 默认预填哔哩哔哩免费 Index-Translate（客户端本机 IP 直连）
    this.aiEnabled = false,
    this.aiBaseUrl = 'https://index-translate.bilibili.com/v1',
    this.aiApiKey = '',
    this.aiModel = 'Index-Translate-35B-A3B',
    this.aiTargetLang = '简体中文',
    this.aiBilingualSubtitle = true,
    this.aiSubtitleMode = 'bilingual_trans_top', // bilingual_trans_top | bilingual_orig_top | translated_only
    this.aiSubtitleFontScale = 1.0,
    this.aiSubtitleBatchSize = 18,
    this.aiSubtitleLookaheadSecs = 60,
    this.aiDirectClientIp = true,
    this.aiCachedModels = const [],
    // AI 语音识别 (ASR · 无字幕视频听音转双语字幕)
    this.asrEnabled = false,
    this.asrEngine = 'local', // local (内置 sherpa-onnx SenseVoice) | cloud (OpenAI/Groq/硅基流动)
    this.asrUseChinaMirror = true,
    this.asrBaseUrl = 'https://api.groq.com/openai/v1',
    this.asrApiKey = '',
    this.asrModel = 'whisper-large-v3-turbo',
    this.asrSourceLang = 'auto', // auto | ja | en | zh | ko
    this.asrDirectClientIp = false,
    // 低功耗 GPU 美颜滤镜
    this.beautyFilterPreset = 'off', // off | natural | rosy | bright | soft_glow | vivid
    this.beautyFilterStrength = 0.55,
    // 隐私保护
    this.passcodeEnabled = false,
    this.passcodeHash = '',
    this.lockTimeoutSecs = 60,
    this.blurInBackground = false,
    // 下载管理
    this.downloadWifiOnly = true,
    this.downloadMaxConcurrent = 2,
    this.downloadCustomDir = '',
    // 字体管理 & 搜索历史 & 服务器卡片设置
    this.customFontPaths = const [],
    this.searchHistory = const [],
    this.serverCardStyles = const {},
    this.serverCardLayout = 'grid', // grid | list
  });

  final String skinId;
  final String themeMode;
  final bool dynamicMonet;
  final String customAccentHex;
  final String tonalChroma;
  final bool autoShrinkNavOnScroll;
  final bool showNavLabels;
  final bool useSkinGeometry;
  final List<CustomSkinSpec> customSkins;
  final Map<String, dynamic> skinOverrides;
  final Map<String, dynamic> mobileSkinOverrides;
  final String hardwareProfileInitSig;
  final String accentId;
  final double cardRadius;
  final String glassIntensity;
  final bool reduceMotion;

  final String listDensity;
  final String sectionSpacing;
  final double posterScale;
  final bool showRatings;
  final bool showYear;
  final bool showWatchedBadge;
  final bool showUnplayedCount;
  final bool showMultiVersionBadge;
  final String defaultSort;

  final bool showSpecBadges;
  final bool showRemainingTime;
  final bool confirmExitPlayer;
  final bool confirmExitApp;
  final bool incognitoMode;
  final bool tvModeOverride;
  final String ignoredUpdateVersion;

  final int bufferSizeMb;
  final bool autoPlayNext;
  final bool autoSkipIntro;
  final bool autoSkipOutro;
  final int customSkipIntroSecs;
  final int customSkipOutroSecs;
  final bool rememberPosition;
  final bool rememberBrightness;
  final double savedBrightness;
  final bool rememberVolume;
  final double savedVolume;
  final bool rememberSpeed;
  final bool rememberAspect;
  final bool showNetworkSpeed;
  final double defaultSpeed;
  final double longPressSpeed;
  final int seekStepSecs;
  final bool pinchToZoom;
  final bool enablePip;
  final bool backgroundAudio;
  final String externalPlayer;

  final String defaultAspect;
  final String videoSync;
  final bool hdrComputePeak;
  final bool anime4kEnabled;
  final String anime4kMode;
  final bool anime4kOnlyAnime;
  final String customMpvConf;

  final String preferredAudioLang;
  final int maxVolumePercent;
  final int audioDelayMs;

  final String preferredSubLang;
  final bool autoLoadExternalSubs;
  final bool forceAssOverride;
  final String subtitleFontFamily;
  final double subtitleFontScale;
  final int subtitlePos;
  final String subtitleColorHex;
  final double subtitleOutlineWidth;
  final double subtitleBgOpacity;
  final double subtitleDelaySecs;

  final bool danmakuEnabled;
  final double danmakuOpacity;
  final double danmakuFontSize;
  final double danmakuSpeedSecs;
  final double danmakuArea;
  final bool danmakuHideTop;
  final bool danmakuHideBottom;
  final String danmakuApiUrl;

  final bool aiEnabled;
  final String aiBaseUrl;
  final String aiApiKey;
  final String aiModel;
  final String aiTargetLang;
  final bool aiBilingualSubtitle;
  final String aiSubtitleMode;
  final double aiSubtitleFontScale;
  final int aiSubtitleBatchSize;
  final int aiSubtitleLookaheadSecs;
  final bool aiDirectClientIp;
  final List<String> aiCachedModels;

  final bool asrEnabled;
  final String asrEngine;
  final bool asrUseChinaMirror;
  final String asrBaseUrl;
  final String asrApiKey;
  final String asrModel;
  final String asrSourceLang;
  final bool asrDirectClientIp;

  final String beautyFilterPreset;
  final double beautyFilterStrength;

  final bool passcodeEnabled;
  final String passcodeHash;
  final int lockTimeoutSecs;
  final bool blurInBackground;

  final bool downloadWifiOnly;
  final int downloadMaxConcurrent;
  final String downloadCustomDir;

  final List<String> customFontPaths;
  final List<String> searchHistory;
  final Map<String, ServerCardStyle> serverCardStyles;
  final String serverCardLayout;

  AccentPalette get accentPalette => AccentPalette.byId(accentId);

  static bool get _currentIsMobileOs =>
      !kIsWeb && ((Platform.isAndroid && !PlatformPerfProfile.isTv) || Platform.isIOS);

  Map<String, dynamic> overridesForPlatform({bool? isMobile}) {
    final mobile = isMobile ?? _currentIsMobileOs;
    return mobile ? mobileSkinOverrides : skinOverrides;
  }

  VedroSkin activeSkinFor({
    bool? isMobile,
    Brightness? systemBrightness,
    Color? dynamicSeedOverride,
  }) {
    var base = VedroSkin.byId(skinId, customSkins: customSkins);
    final isLegacyExplicitLight = skinId == 'daylight' || skinId == 'editorial_paper';
    if (!base.isCustom && !isLegacyExplicitLight) {
      final wantLight = switch (themeMode) {
        'light' => true,
        'system' => systemBrightness == Brightness.light,
        _ => false,
      };
      base = base.withPolarity(wantLight);
    }

    if (dynamicMonet && dynamicSeedOverride != null) {
      base = DynamicColorEngine.applySeedToSkin(
        base,
        dynamicSeedOverride,
        tonalChroma: tonalChroma,
        tintAtmosphere: true,
      );
    } else if (accentId == 'custom' && customAccentHex.trim().isNotEmpty) {
      final seed = VedroSkin.parseHex(customAccentHex, base.accent);
      base = DynamicColorEngine.applySeedToSkin(
        base,
        seed,
        tonalChroma: tonalChroma,
        tintAtmosphere: base.themeFamily == 'material_design',
      );
    } else if (!base.isCustom &&
        (accentId != 'blue' || base.themeFamily == 'material_design' || tonalChroma != 'standard')) {
      final pal = accentPalette;
      if (accentId == 'silver') {
        base = base.copyWith(accent: pal.accent, accentSecondary: pal.fill);
      } else {
        base = DynamicColorEngine.applySeedToSkin(
          base,
          pal.accent,
          tonalChroma: tonalChroma,
          tintAtmosphere: base.themeFamily == 'material_design',
        );
      }
    }

    final ov = overridesForPlatform(isMobile: isMobile);
    if (ov.isNotEmpty) {
      base = base.applyOverrides(ov);
    }
    if (!useSkinGeometry) {
      base = base.copyWith(cardRadius: cardRadius);
    }
    return base;
  }

  VedroSkin get activeSkin => activeSkinFor();

  /// Build initial or reset defaults calibrated to a `DisplayMetricsProfile`.
  VedroPreferences applyHardwareDefaults(DisplayMetricsProfile profile) {
    final rec = profile.recommendedSkinOverrides;
    return copyWith(
      skinId: profile.recommendedSkinId,
      useSkinGeometry: true,
      skinOverrides: profile.isMobileOs ? skinOverrides : rec,
      mobileSkinOverrides: profile.isMobileOs ? rec : mobileSkinOverrides,
      hardwareProfileInitSig: profile.profileSignature,
      listDensity: profile.recommendedListDensity,
      bufferSizeMb: profile.recommendedBufferSizeMb,
      subtitleFontScale: profile.recommendedSubtitleScale,
      subtitleOutlineWidth: profile.recommendedSubtitleOutline,
    );
  }

  double effectiveCardRadius(VedroSkin skin) =>
      useSkinGeometry ? skin.cardRadius : cardRadius;

  bool get isAiReady =>
      aiEnabled && aiBaseUrl.trim().isNotEmpty && aiModel.trim().isNotEmpty;

  bool get isAsrReady =>
      asrEnabled && asrBaseUrl.trim().isNotEmpty && asrModel.trim().isNotEmpty;

  double posterCardWidth(bool wide, [DisplayMetricsProfile? metrics]) {
    final ov = overridesForPlatform(isMobile: !wide && _currentIsMobileOs);
    final effDensity = ov['grid_density']?.toString() ?? listDensity;
    final scale = posterScale.clamp(0.75, 1.25);
    if (metrics != null) {
      return metrics.posterWidthFor(effDensity, scale: scale);
    }
    final base = switch (effDensity) {
      'compact' => wide ? 132.0 : 94.0,
      'spacious' => wide ? 176.0 : 122.0,
      _ => wide ? 152.0 : 106.0,
    };
    return base * scale;
  }

  double horizontalMargin(bool wide) {
    if (wide) {
      return switch (sectionSpacing) {
        'compact' => 24.0,
        'spacious' => 36.0,
        _ => 30.0,
      };
    }
    return switch (sectionSpacing) {
      'compact' => 12.0,
      'spacious' => 18.0,
      _ => 14.0,
    };
  }

  double cardGap(bool wide) {
    if (wide) {
      return switch (sectionSpacing) {
        'compact' => 13.0,
        'spacious' => 20.0,
        _ => 16.0,
      };
    }
    return switch (sectionSpacing) {
      'compact' => 8.5,
      'spacious' => 13.0,
      _ => 10.0,
    };
  }

  double sectionTopGap(bool wide) {
    if (wide) {
      return switch (sectionSpacing) {
        'compact' => 18.0,
        'spacious' => 30.0,
        _ => 24.0,
      };
    }
    return switch (sectionSpacing) {
      'compact' => 11.0,
      'spacious' => 20.0,
      _ => 15.0,
    };
  }

  VedroPreferences copyWith({
    String? skinId,
    String? themeMode,
    bool? dynamicMonet,
    String? customAccentHex,
    String? tonalChroma,
    bool? autoShrinkNavOnScroll,
    bool? showNavLabels,
    bool? useSkinGeometry,
    List<CustomSkinSpec>? customSkins,
    Map<String, dynamic>? skinOverrides,
    Map<String, dynamic>? mobileSkinOverrides,
    String? hardwareProfileInitSig,
    String? accentId,
    double? cardRadius,
    String? glassIntensity,
    bool? reduceMotion,
    String? listDensity,
    String? sectionSpacing,
    double? posterScale,
    bool? showRatings,
    bool? showYear,
    bool? showWatchedBadge,
    bool? showUnplayedCount,
    bool? showMultiVersionBadge,
    String? defaultSort,
    bool? showSpecBadges,
    bool? showRemainingTime,
    bool? confirmExitPlayer,
    bool? confirmExitApp,
    bool? incognitoMode,
    bool? tvModeOverride,
    String? ignoredUpdateVersion,
    int? bufferSizeMb,
    bool? autoPlayNext,
    bool? autoSkipIntro,
    bool? autoSkipOutro,
    int? customSkipIntroSecs,
    int? customSkipOutroSecs,
    bool? rememberPosition,
    bool? rememberBrightness,
    double? savedBrightness,
    bool? rememberVolume,
    double? savedVolume,
    bool? rememberSpeed,
    bool? rememberAspect,
    bool? showNetworkSpeed,
    double? defaultSpeed,
    double? longPressSpeed,
    int? seekStepSecs,
    bool? pinchToZoom,
    bool? enablePip,
    bool? backgroundAudio,
    String? externalPlayer,
    String? defaultAspect,
    String? videoSync,
    bool? hdrComputePeak,
    bool? anime4kEnabled,
    String? anime4kMode,
    bool? anime4kOnlyAnime,
    String? customMpvConf,
    String? preferredAudioLang,
    int? maxVolumePercent,
    int? audioDelayMs,
    String? preferredSubLang,
    bool? autoLoadExternalSubs,
    bool? forceAssOverride,
    String? subtitleFontFamily,
    double? subtitleFontScale,
    int? subtitlePos,
    String? subtitleColorHex,
    double? subtitleOutlineWidth,
    double? subtitleBgOpacity,
    double? subtitleDelaySecs,
    bool? danmakuEnabled,
    double? danmakuOpacity,
    double? danmakuFontSize,
    double? danmakuSpeedSecs,
    double? danmakuArea,
    bool? danmakuHideTop,
    bool? danmakuHideBottom,
    String? danmakuApiUrl,
    bool? aiEnabled,
    String? aiBaseUrl,
    String? aiApiKey,
    String? aiModel,
    String? aiTargetLang,
    bool? aiBilingualSubtitle,
    String? aiSubtitleMode,
    double? aiSubtitleFontScale,
    int? aiSubtitleBatchSize,
    int? aiSubtitleLookaheadSecs,
    bool? aiDirectClientIp,
    List<String>? aiCachedModels,
    bool? asrEnabled,
    String? asrEngine,
    bool? asrUseChinaMirror,
    String? asrBaseUrl,
    String? asrApiKey,
    String? asrModel,
    String? asrSourceLang,
    bool? asrDirectClientIp,
    String? beautyFilterPreset,
    double? beautyFilterStrength,
    bool? passcodeEnabled,
    String? passcodeHash,
    int? lockTimeoutSecs,
    bool? blurInBackground,
    bool? downloadWifiOnly,
    int? downloadMaxConcurrent,
    String? downloadCustomDir,
    List<String>? customFontPaths,
    List<String>? searchHistory,
    Map<String, ServerCardStyle>? serverCardStyles,
    String? serverCardLayout,
  }) =>
      VedroPreferences(
        skinId: skinId ?? this.skinId,
        themeMode: themeMode ?? this.themeMode,
        dynamicMonet: dynamicMonet ?? this.dynamicMonet,
        customAccentHex: customAccentHex ?? this.customAccentHex,
        tonalChroma: tonalChroma ?? this.tonalChroma,
        autoShrinkNavOnScroll: autoShrinkNavOnScroll ?? this.autoShrinkNavOnScroll,
        showNavLabels: showNavLabels ?? this.showNavLabels,
        useSkinGeometry: useSkinGeometry ?? this.useSkinGeometry,
        customSkins: customSkins ?? this.customSkins,
        skinOverrides: skinOverrides ?? this.skinOverrides,
        mobileSkinOverrides: mobileSkinOverrides ?? this.mobileSkinOverrides,
        hardwareProfileInitSig: hardwareProfileInitSig ?? this.hardwareProfileInitSig,
        accentId: accentId ?? this.accentId,
        cardRadius: cardRadius ?? this.cardRadius,
        glassIntensity: glassIntensity ?? this.glassIntensity,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        listDensity: listDensity ?? this.listDensity,
        sectionSpacing: sectionSpacing ?? this.sectionSpacing,
        posterScale: posterScale ?? this.posterScale,
        showRatings: showRatings ?? this.showRatings,
        showYear: showYear ?? this.showYear,
        showWatchedBadge: showWatchedBadge ?? this.showWatchedBadge,
        showUnplayedCount: showUnplayedCount ?? this.showUnplayedCount,
        showMultiVersionBadge: showMultiVersionBadge ?? this.showMultiVersionBadge,
        defaultSort: defaultSort ?? this.defaultSort,
        showSpecBadges: showSpecBadges ?? this.showSpecBadges,
        showRemainingTime: showRemainingTime ?? this.showRemainingTime,
        confirmExitPlayer: confirmExitPlayer ?? this.confirmExitPlayer,
        confirmExitApp: confirmExitApp ?? this.confirmExitApp,
        incognitoMode: incognitoMode ?? this.incognitoMode,
        tvModeOverride: tvModeOverride ?? this.tvModeOverride,
        ignoredUpdateVersion: ignoredUpdateVersion ?? this.ignoredUpdateVersion,
        bufferSizeMb: bufferSizeMb ?? this.bufferSizeMb,
        autoPlayNext: autoPlayNext ?? this.autoPlayNext,
        autoSkipIntro: autoSkipIntro ?? this.autoSkipIntro,
        autoSkipOutro: autoSkipOutro ?? this.autoSkipOutro,
        customSkipIntroSecs: customSkipIntroSecs ?? this.customSkipIntroSecs,
        customSkipOutroSecs: customSkipOutroSecs ?? this.customSkipOutroSecs,
        rememberPosition: rememberPosition ?? this.rememberPosition,
        rememberBrightness: rememberBrightness ?? this.rememberBrightness,
        savedBrightness: savedBrightness ?? this.savedBrightness,
        rememberVolume: rememberVolume ?? this.rememberVolume,
        savedVolume: savedVolume ?? this.savedVolume,
        rememberSpeed: rememberSpeed ?? this.rememberSpeed,
        rememberAspect: rememberAspect ?? this.rememberAspect,
        showNetworkSpeed: showNetworkSpeed ?? this.showNetworkSpeed,
        defaultSpeed: defaultSpeed ?? this.defaultSpeed,
        longPressSpeed: longPressSpeed ?? this.longPressSpeed,
        seekStepSecs: seekStepSecs ?? this.seekStepSecs,
        pinchToZoom: pinchToZoom ?? this.pinchToZoom,
        enablePip: enablePip ?? this.enablePip,
        backgroundAudio: backgroundAudio ?? this.backgroundAudio,
        externalPlayer: externalPlayer ?? this.externalPlayer,
        defaultAspect: defaultAspect ?? this.defaultAspect,
        videoSync: videoSync ?? this.videoSync,
        hdrComputePeak: hdrComputePeak ?? this.hdrComputePeak,
        anime4kEnabled: anime4kEnabled ?? this.anime4kEnabled,
        anime4kMode: anime4kMode ?? this.anime4kMode,
        anime4kOnlyAnime: anime4kOnlyAnime ?? this.anime4kOnlyAnime,
        customMpvConf: customMpvConf ?? this.customMpvConf,
        preferredAudioLang: preferredAudioLang ?? this.preferredAudioLang,
        maxVolumePercent: maxVolumePercent ?? this.maxVolumePercent,
        audioDelayMs: audioDelayMs ?? this.audioDelayMs,
        preferredSubLang: preferredSubLang ?? this.preferredSubLang,
        autoLoadExternalSubs: autoLoadExternalSubs ?? this.autoLoadExternalSubs,
        forceAssOverride: forceAssOverride ?? this.forceAssOverride,
        subtitleFontFamily: subtitleFontFamily ?? this.subtitleFontFamily,
        subtitleFontScale: subtitleFontScale ?? this.subtitleFontScale,
        subtitlePos: subtitlePos ?? this.subtitlePos,
        subtitleColorHex: subtitleColorHex ?? this.subtitleColorHex,
        subtitleOutlineWidth: subtitleOutlineWidth ?? this.subtitleOutlineWidth,
        subtitleBgOpacity: subtitleBgOpacity ?? this.subtitleBgOpacity,
        subtitleDelaySecs: subtitleDelaySecs ?? this.subtitleDelaySecs,
        danmakuEnabled: danmakuEnabled ?? this.danmakuEnabled,
        danmakuOpacity: danmakuOpacity ?? this.danmakuOpacity,
        danmakuFontSize: danmakuFontSize ?? this.danmakuFontSize,
        danmakuSpeedSecs: danmakuSpeedSecs ?? this.danmakuSpeedSecs,
        danmakuArea: danmakuArea ?? this.danmakuArea,
        danmakuHideTop: danmakuHideTop ?? this.danmakuHideTop,
        danmakuHideBottom: danmakuHideBottom ?? this.danmakuHideBottom,
        danmakuApiUrl: danmakuApiUrl ?? this.danmakuApiUrl,
        aiEnabled: aiEnabled ?? this.aiEnabled,
        aiBaseUrl: aiBaseUrl ?? this.aiBaseUrl,
        aiApiKey: aiApiKey ?? this.aiApiKey,
        aiModel: aiModel ?? this.aiModel,
        aiTargetLang: aiTargetLang ?? this.aiTargetLang,
        aiBilingualSubtitle: aiBilingualSubtitle ?? this.aiBilingualSubtitle,
        aiSubtitleMode: aiSubtitleMode ?? this.aiSubtitleMode,
        aiSubtitleFontScale: aiSubtitleFontScale ?? this.aiSubtitleFontScale,
        aiSubtitleBatchSize: aiSubtitleBatchSize ?? this.aiSubtitleBatchSize,
        aiSubtitleLookaheadSecs: aiSubtitleLookaheadSecs ?? this.aiSubtitleLookaheadSecs,
        aiDirectClientIp: aiDirectClientIp ?? this.aiDirectClientIp,
        aiCachedModels: aiCachedModels ?? this.aiCachedModels,
        asrEnabled: asrEnabled ?? this.asrEnabled,
        asrEngine: asrEngine ?? this.asrEngine,
        asrUseChinaMirror: asrUseChinaMirror ?? this.asrUseChinaMirror,
        asrBaseUrl: asrBaseUrl ?? this.asrBaseUrl,
        asrApiKey: asrApiKey ?? this.asrApiKey,
        asrModel: asrModel ?? this.asrModel,
        asrSourceLang: asrSourceLang ?? this.asrSourceLang,
        asrDirectClientIp: asrDirectClientIp ?? this.asrDirectClientIp,
        beautyFilterPreset: beautyFilterPreset ?? this.beautyFilterPreset,
        beautyFilterStrength: beautyFilterStrength ?? this.beautyFilterStrength,
        passcodeEnabled: passcodeEnabled ?? this.passcodeEnabled,
        passcodeHash: passcodeHash ?? this.passcodeHash,
        lockTimeoutSecs: lockTimeoutSecs ?? this.lockTimeoutSecs,
        blurInBackground: blurInBackground ?? this.blurInBackground,
        downloadWifiOnly: downloadWifiOnly ?? this.downloadWifiOnly,
        downloadMaxConcurrent: downloadMaxConcurrent ?? this.downloadMaxConcurrent,
        downloadCustomDir: downloadCustomDir ?? this.downloadCustomDir,
        customFontPaths: customFontPaths ?? this.customFontPaths,
        searchHistory: searchHistory ?? this.searchHistory,
        serverCardStyles: serverCardStyles ?? this.serverCardStyles,
        serverCardLayout: serverCardLayout ?? this.serverCardLayout,
      );

  Map<String, dynamic> toJson() => {
        'skin_id': skinId,
        'theme_mode': themeMode,
        'dynamic_monet': dynamicMonet,
        'custom_accent_hex': customAccentHex,
        'tonal_chroma': tonalChroma,
        'auto_shrink_nav_on_scroll': autoShrinkNavOnScroll,
        'show_nav_labels': showNavLabels,
        'use_skin_geometry': useSkinGeometry,
        'custom_skins': customSkins.map((s) => s.toJson()).toList(),
        'skin_overrides': skinOverrides,
        'mobile_skin_overrides': mobileSkinOverrides,
        'hardware_profile_init_sig': hardwareProfileInitSig,
        'accent_id': accentId,
        'card_radius': cardRadius,
        'glass_intensity': glassIntensity,
        'reduce_motion': reduceMotion,
        'list_density': listDensity,
        'section_spacing': sectionSpacing,
        'poster_scale': posterScale,
        'show_ratings': showRatings,
        'show_year': showYear,
        'show_watched_badge': showWatchedBadge,
        'show_unplayed_count': showUnplayedCount,
        'show_multi_version_badge': showMultiVersionBadge,
        'default_sort': defaultSort,
        'show_spec_badges': showSpecBadges,
        'show_remaining_time': showRemainingTime,
        'confirm_exit_player': confirmExitPlayer,
        'confirm_exit_app': confirmExitApp,
        'incognito_mode': incognitoMode,
        'tv_mode_override': tvModeOverride,
        'ignored_update_version': ignoredUpdateVersion,
        'buffer_size_mb': bufferSizeMb,
        'auto_play_next': autoPlayNext,
        'auto_skip_intro': autoSkipIntro,
        'auto_skip_outro': autoSkipOutro,
        'custom_skip_intro_secs': customSkipIntroSecs,
        'custom_skip_outro_secs': customSkipOutroSecs,
        'remember_position': rememberPosition,
        'remember_brightness': rememberBrightness,
        'saved_brightness': savedBrightness,
        'remember_volume': rememberVolume,
        'saved_volume': savedVolume,
        'remember_speed': rememberSpeed,
        'remember_aspect': rememberAspect,
        'show_network_speed': showNetworkSpeed,
        'default_speed': defaultSpeed,
        'long_press_speed': longPressSpeed,
        'seek_step_secs': seekStepSecs,
        'pinch_to_zoom': pinchToZoom,
        'enable_pip': enablePip,
        'background_audio': backgroundAudio,
        'external_player': externalPlayer,
        'default_aspect': defaultAspect,
        'video_sync': videoSync,
        'hdr_compute_peak': hdrComputePeak,
        'anime4k_enabled': anime4kEnabled,
        'anime4k_mode': anime4kMode,
        'anime4k_only_anime': anime4kOnlyAnime,
        'custom_mpv_conf': customMpvConf,
        'preferred_audio_lang': preferredAudioLang,
        'max_volume_percent': maxVolumePercent,
        'audio_delay_ms': audioDelayMs,
        'preferred_sub_lang': preferredSubLang,
        'auto_load_external_subs': autoLoadExternalSubs,
        'force_ass_override': forceAssOverride,
        'subtitle_font_family': subtitleFontFamily,
        'subtitle_font_scale': subtitleFontScale,
        'subtitle_pos': subtitlePos,
        'subtitle_color_hex': subtitleColorHex,
        'subtitle_outline_width': subtitleOutlineWidth,
        'subtitle_bg_opacity': subtitleBgOpacity,
        'subtitle_delay_secs': subtitleDelaySecs,
        'danmaku_enabled': danmakuEnabled,
        'danmaku_opacity': danmakuOpacity,
        'danmaku_font_size': danmakuFontSize,
        'danmaku_speed_secs': danmakuSpeedSecs,
        'danmaku_area': danmakuArea,
        'danmaku_hide_top': danmakuHideTop,
        'danmaku_hide_bottom': danmakuHideBottom,
        'danmaku_api_url': danmakuApiUrl,
        'ai_enabled': aiEnabled,
        'ai_base_url': aiBaseUrl,
        'ai_api_key': aiApiKey,
        'ai_model': aiModel,
        'ai_target_lang': aiTargetLang,
        'ai_bilingual_subtitle': aiBilingualSubtitle,
        'ai_subtitle_mode': aiSubtitleMode,
        'ai_subtitle_font_scale': aiSubtitleFontScale,
        'ai_subtitle_batch_size': aiSubtitleBatchSize,
        'ai_subtitle_lookahead_secs': aiSubtitleLookaheadSecs,
        'ai_direct_client_ip': aiDirectClientIp,
        'ai_cached_models': aiCachedModels,
        'asr_enabled': asrEnabled,
        'asr_engine': asrEngine,
        'asr_use_china_mirror': asrUseChinaMirror,
        'asr_base_url': asrBaseUrl,
        'asr_api_key': asrApiKey,
        'asr_model': asrModel,
        'asr_source_lang': asrSourceLang,
        'asr_direct_client_ip': asrDirectClientIp,
        'beauty_filter_preset': beautyFilterPreset,
        'beauty_filter_strength': beautyFilterStrength,
        'passcode_enabled': passcodeEnabled,
        'passcode_hash': passcodeHash,
        'lock_timeout_secs': lockTimeoutSecs,
        'blur_in_background': blurInBackground,
        'download_wifi_only': downloadWifiOnly,
        'download_max_concurrent': downloadMaxConcurrent,
        'download_custom_dir': downloadCustomDir,
        'custom_font_paths': customFontPaths,
        'search_history': searchHistory,
        'server_card_styles': serverCardStyles.map((k, v) => MapEntry(k, v.toJson())),
        'server_card_layout': serverCardLayout,
      };

  factory VedroPreferences.fromJson(Map<String, dynamic> j) {
    return VedroPreferences(
        skinId: (j['skin_id'] ?? 'immersive_cinema').toString(),
        themeMode: (j['theme_mode'] ?? 'dark').toString(),
        dynamicMonet: j['dynamic_monet'] != false,
        customAccentHex: (j['custom_accent_hex'] ?? '').toString(),
        tonalChroma: (j['tonal_chroma'] ?? 'standard').toString(),
        autoShrinkNavOnScroll: j['auto_shrink_nav_on_scroll'] == true,
        showNavLabels: j['show_nav_labels'] != false,
        useSkinGeometry: j['use_skin_geometry'] != false,
        customSkins: ((j['custom_skins'] as List<dynamic>?) ?? const [])
            .map((e) => e is Map<String, dynamic>
                ? CustomSkinSpec.fromJson(e)
                : (e is Map ? CustomSkinSpec.fromJson(Map<String, dynamic>.from(e)) : null))
            .whereType<CustomSkinSpec>()
            .toList(),
        skinOverrides: j['skin_overrides'] is Map
            ? Map<String, dynamic>.from(j['skin_overrides'] as Map)
            : const {},
        mobileSkinOverrides: j['mobile_skin_overrides'] is Map
            ? Map<String, dynamic>.from(j['mobile_skin_overrides'] as Map)
            : const {},
        hardwareProfileInitSig: (j['hardware_profile_init_sig'] ?? '').toString(),
        accentId: (j['accent_id'] ?? 'blue').toString(),
        cardRadius: _finiteDouble(j['card_radius'], 12.0, 0.0, 28.0),
        glassIntensity: (j['glass_intensity'] ?? 'standard').toString(),
        reduceMotion: j['reduce_motion'] == true,
        listDensity: (j['list_density'] ?? 'comfortable').toString(),
        sectionSpacing: (j['section_spacing'] ?? 'compact').toString(),
        posterScale: _finiteDouble(j['poster_scale'], 1.0, 0.75, 1.25),
        showRatings: j['show_ratings'] != false,
        showYear: j['show_year'] != false,
        showWatchedBadge: j['show_watched_badge'] != false,
        showUnplayedCount: j['show_unplayed_count'] != false,
        showMultiVersionBadge: j['show_multi_version_badge'] == true,
        defaultSort: (j['default_sort'] ?? 'DateCreated').toString(),
        showSpecBadges: j['show_spec_badges'] != false,
        showRemainingTime: j['show_remaining_time'] == true,
        confirmExitPlayer: j['confirm_exit_player'] == true,
        confirmExitApp: j['confirm_exit_app'] != false,
        incognitoMode: j['incognito_mode'] == true,
        tvModeOverride: j['tv_mode_override'] == true,
        ignoredUpdateVersion: (j['ignored_update_version'] ?? '').toString(),
        bufferSizeMb: _clampedInt(j['buffer_size_mb'], 128, 16, 1024),
        autoPlayNext: j['auto_play_next'] != false,
        autoSkipIntro: j['auto_skip_intro'] == true,
        autoSkipOutro: j['auto_skip_outro'] == true,
        customSkipIntroSecs: _clampedInt(j['custom_skip_intro_secs'], 0, 0, 600),
        customSkipOutroSecs: _clampedInt(j['custom_skip_outro_secs'], 0, 0, 600),
        rememberPosition: j['remember_position'] != false,
        rememberBrightness: j['remember_brightness'] != false,
        savedBrightness: _finiteDouble(j['saved_brightness'], 1.0, 0.15, 1.0),
        rememberVolume: j['remember_volume'] != false,
        savedVolume: _finiteDouble(j['saved_volume'], 100.0, 0.0, 300.0),
        rememberSpeed: j['remember_speed'] != false,
        rememberAspect: j['remember_aspect'] != false,
        showNetworkSpeed: j['show_network_speed'] != false,
        defaultSpeed: _finiteDouble(j['default_speed'], 1.0, 0.25, 4.0),
        longPressSpeed: _finiteDouble(j['long_press_speed'], 2.0, 1.25, 4.0),
        seekStepSecs: _clampedInt(j['seek_step_secs'], 10, 3, 120),
        pinchToZoom: j['pinch_to_zoom'] != false,
        enablePip: j['enable_pip'] != false,
        backgroundAudio: j['background_audio'] == true,
        externalPlayer: (j['external_player'] ?? 'builtin').toString(),
        defaultAspect: (j['default_aspect'] ?? 'fit').toString(),
        videoSync: (j['video_sync'] ?? 'audio').toString(),
        hdrComputePeak: j['hdr_compute_peak'] != false,
        anime4kEnabled: j['anime4k_enabled'] == true,
        anime4kMode: (j['anime4k_mode'] ?? 'B').toString(),
        anime4kOnlyAnime: j['anime4k_only_anime'] != false,
        customMpvConf: (j['custom_mpv_conf'] ?? '').toString(),
        preferredAudioLang: (j['preferred_audio_lang'] ?? 'auto').toString(),
        maxVolumePercent: _clampedInt(j['max_volume_percent'], 150, 100, 300),
        audioDelayMs: _clampedInt(j['audio_delay_ms'], 0, -5000, 5000),
        preferredSubLang: (j['preferred_sub_lang'] ?? 'zh').toString(),
        autoLoadExternalSubs: j['auto_load_external_subs'] != false,
        forceAssOverride: j['force_ass_override'] == true,
        subtitleFontFamily: (j['subtitle_font_family'] ?? '').toString(),
        subtitleFontScale: _finiteDouble(j['subtitle_font_scale'], 1.0, 0.5, 2.5),
        subtitlePos: _clampedInt(j['subtitle_pos'], 96, 50, 110),
        subtitleColorHex: (j['subtitle_color_hex'] ?? '#FFFFFF').toString(),
        subtitleOutlineWidth: _finiteDouble(j['subtitle_outline_width'], 2.4, 0.0, 8.0),
        subtitleBgOpacity: _finiteDouble(j['subtitle_bg_opacity'], 0.0, 0.0, 1.0),
        subtitleDelaySecs: _finiteDouble(j['subtitle_delay_secs'], 0.0, -30.0, 30.0),
        danmakuEnabled: j['danmaku_enabled'] == true,
        danmakuOpacity: _finiteDouble(j['danmaku_opacity'], 0.82, 0.1, 1.0),
        danmakuFontSize: _finiteDouble(j['danmaku_font_size'], 18.0, 12.0, 32.0),
        danmakuSpeedSecs: _finiteDouble(j['danmaku_speed_secs'], 9.0, 4.0, 20.0),
        danmakuArea: _finiteDouble(j['danmaku_area'], 0.5, 0.15, 1.0),
        danmakuHideTop: j['danmaku_hide_top'] == true,
        danmakuHideBottom: j['danmaku_hide_bottom'] == true,
        danmakuApiUrl: (j['danmaku_api_url'] ?? '').toString(),
        aiEnabled: j['ai_enabled'] == true,
        aiBaseUrl: (j['ai_base_url'] ?? 'https://index-translate.bilibili.com/v1').toString(),
        aiApiKey: (j['ai_api_key'] ?? '').toString(),
        aiModel: (j['ai_model'] ?? 'Index-Translate-35B-A3B').toString(),
        aiTargetLang: (j['ai_target_lang'] ?? '简体中文').toString(),
        aiBilingualSubtitle: j['ai_bilingual_subtitle'] != false,
        aiSubtitleMode: (j['ai_subtitle_mode'] ?? 'bilingual_trans_top').toString(),
        aiSubtitleFontScale: _finiteDouble(j['ai_subtitle_font_scale'], 1.0, 0.6, 1.8),
        aiSubtitleBatchSize: _clampedInt(j['ai_subtitle_batch_size'], 18, 8, 32),
        aiSubtitleLookaheadSecs: _clampedInt(j['ai_subtitle_lookahead_secs'], 60, 30, 300),
        aiDirectClientIp: j['ai_direct_client_ip'] != false,
        aiCachedModels: ((j['ai_cached_models'] as List<dynamic>?) ?? const [])
            .map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .toList(),
        asrEnabled: j['asr_enabled'] == true,
        asrEngine: (j['asr_engine'] ?? 'local').toString(),
        asrUseChinaMirror: j['asr_use_china_mirror'] != false,
        asrBaseUrl: (j['asr_base_url'] ?? 'https://api.groq.com/openai/v1').toString(),
        asrApiKey: (j['asr_api_key'] ?? '').toString(),
        asrModel: (j['asr_model'] ?? 'whisper-large-v3-turbo').toString(),
        asrSourceLang: (j['asr_source_lang'] ?? 'auto').toString(),
        asrDirectClientIp: j['asr_direct_client_ip'] == true,
        beautyFilterPreset: (j['beauty_filter_preset'] ?? 'off').toString(),
        beautyFilterStrength: _finiteDouble(j['beauty_filter_strength'], 0.55, 0.15, 1.0),
        passcodeEnabled: j['passcode_enabled'] == true,
        passcodeHash: (j['passcode_hash'] ?? '').toString(),
        lockTimeoutSecs: _clampedInt(j['lock_timeout_secs'], 60, 0, 3600),
        blurInBackground: false,
        downloadWifiOnly: j['download_wifi_only'] != false,
        downloadMaxConcurrent: _clampedInt(j['download_max_concurrent'], 2, 1, 4),
        downloadCustomDir: (j['download_custom_dir'] ?? '').toString(),
        customFontPaths: ((j['custom_font_paths'] as List<dynamic>?) ?? const [])
            .map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .toList(),
        searchHistory: ((j['search_history'] as List<dynamic>?) ?? const [])
            .map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .take(15)
            .toList(),
        serverCardStyles: j['server_card_styles'] is Map
            ? (j['server_card_styles'] as Map).map(
                (k, v) => MapEntry(
                  k.toString(),
                  v is Map<String, dynamic>
                      ? ServerCardStyle.fromJson(v)
                      : (v is Map
                          ? ServerCardStyle.fromJson(Map<String, dynamic>.from(v))
                          : const ServerCardStyle()),
                ),
              )
            : const {},
        serverCardLayout: (j['server_card_layout'] ?? 'grid').toString(),
      );
  }
}
