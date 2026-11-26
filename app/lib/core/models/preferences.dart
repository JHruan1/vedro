import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/vedro_skin.dart';

/// Deterministic lightweight hash for local app passcode verification (no plain PIN on disk).
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
    AccentPalette(id: 'blue', label: '经典蓝', accent: Color(0xFF5B9BFF), fill: Color(0xFF2F6FE6)),
    AccentPalette(id: 'silver', label: '曜石白', accent: Color(0xFFE5E7EB), fill: Color(0xFF4B5563)),
    AccentPalette(id: 'emerald', label: '翡翠绿', accent: Color(0xFF34D399), fill: Color(0xFF10B981)),
    AccentPalette(id: 'amber', label: '琥珀金', accent: Color(0xFFFBBF24), fill: Color(0xFFD97706)),
    AccentPalette(id: 'rose', label: '玫瑰红', accent: Color(0xFFFB7185), fill: Color(0xFFE11D48)),
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
    // 应用风格 & 皮肤引擎
    this.skinId = 'obsidian',
    this.useSkinGeometry = true,
    this.customSkins = const [],
    this.skinOverrides = const {},
    this.accentId = 'blue',
    this.cardRadius = 12.0,
    this.glassIntensity = 'standard',
    this.reduceMotion = false,
    // 列表配置
    this.listDensity = 'comfortable', // compact | comfortable | spacious
    this.showRatings = true,
    this.showYear = true,
    this.showWatchedBadge = true,
    this.showUnplayedCount = true,
    this.defaultSort = 'DateCreated',
    // 界面偏好
    this.showSpecBadges = true,
    this.showRemainingTime = false,
    this.confirmExitPlayer = false,
    this.incognitoMode = false,
    // 播放设置
    this.bufferSizeMb = 128,
    this.autoPlayNext = true,
    this.autoSkipIntro = false,
    this.autoSkipOutro = false,
    this.customSkipIntroSecs = 0,
    this.customSkipOutroSecs = 0,
    this.rememberPosition = true,
    this.rememberBrightness = false,
    this.savedBrightness = 1.0,
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
    // AI 服务（翻译）
    this.aiEnabled = false,
    this.aiBaseUrl = 'https://api.openai.com/v1',
    this.aiApiKey = '',
    this.aiModel = 'gpt-4o-mini',
    this.aiTargetLang = '简体中文',
    this.aiBilingualSubtitle = true,
    // 隐私保护
    this.passcodeEnabled = false,
    this.passcodeHash = '',
    this.lockTimeoutSecs = 60,
    this.blurInBackground = true,
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
  final bool useSkinGeometry;
  final List<CustomSkinSpec> customSkins;
  final Map<String, dynamic> skinOverrides;
  final String accentId;
  final double cardRadius;
  final String glassIntensity;
  final bool reduceMotion;

  final String listDensity;
  final bool showRatings;
  final bool showYear;
  final bool showWatchedBadge;
  final bool showUnplayedCount;
  final String defaultSort;

  final bool showSpecBadges;
  final bool showRemainingTime;
  final bool confirmExitPlayer;
  final bool incognitoMode;

  final int bufferSizeMb;
  final bool autoPlayNext;
  final bool autoSkipIntro;
  final bool autoSkipOutro;
  final int customSkipIntroSecs;
  final int customSkipOutroSecs;
  final bool rememberPosition;
  final bool rememberBrightness;
  final double savedBrightness;
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

  VedroSkin get activeSkin {
    var base = VedroSkin.byId(skinId, customSkins: customSkins);
    if (skinId == 'obsidian' && accentId != 'blue') {
      final pal = accentPalette;
      base = base.copyWith(accent: pal.accent, accentSecondary: pal.fill);
    }
    if (skinOverrides.isNotEmpty) {
      base = base.applyOverrides(skinOverrides);
    }
    if (!useSkinGeometry) {
      base = base.copyWith(cardRadius: cardRadius);
    }
    return base;
  }

  double effectiveCardRadius(VedroSkin skin) =>
      useSkinGeometry ? skin.cardRadius : cardRadius;

  bool get isAiReady =>
      aiEnabled && aiBaseUrl.trim().isNotEmpty && aiModel.trim().isNotEmpty;

  double posterCardWidth(bool wide) {
    final effDensity = skinOverrides['grid_density']?.toString() ?? listDensity;
    switch (effDensity) {
      case 'compact':
        return wide ? 136.0 : 112.0;
      case 'spacious':
        return wide ? 182.0 : 150.0;
      default:
        return wide ? 158.0 : 132.0;
    }
  }

  VedroPreferences copyWith({
    String? skinId,
    bool? useSkinGeometry,
    List<CustomSkinSpec>? customSkins,
    Map<String, dynamic>? skinOverrides,
    String? accentId,
    double? cardRadius,
    String? glassIntensity,
    bool? reduceMotion,
    String? listDensity,
    bool? showRatings,
    bool? showYear,
    bool? showWatchedBadge,
    bool? showUnplayedCount,
    String? defaultSort,
    bool? showSpecBadges,
    bool? showRemainingTime,
    bool? confirmExitPlayer,
    bool? incognitoMode,
    int? bufferSizeMb,
    bool? autoPlayNext,
    bool? autoSkipIntro,
    bool? autoSkipOutro,
    int? customSkipIntroSecs,
    int? customSkipOutroSecs,
    bool? rememberPosition,
    bool? rememberBrightness,
    double? savedBrightness,
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
        useSkinGeometry: useSkinGeometry ?? this.useSkinGeometry,
        customSkins: customSkins ?? this.customSkins,
        skinOverrides: skinOverrides ?? this.skinOverrides,
        accentId: accentId ?? this.accentId,
        cardRadius: cardRadius ?? this.cardRadius,
        glassIntensity: glassIntensity ?? this.glassIntensity,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        listDensity: listDensity ?? this.listDensity,
        showRatings: showRatings ?? this.showRatings,
        showYear: showYear ?? this.showYear,
        showWatchedBadge: showWatchedBadge ?? this.showWatchedBadge,
        showUnplayedCount: showUnplayedCount ?? this.showUnplayedCount,
        defaultSort: defaultSort ?? this.defaultSort,
        showSpecBadges: showSpecBadges ?? this.showSpecBadges,
        showRemainingTime: showRemainingTime ?? this.showRemainingTime,
        confirmExitPlayer: confirmExitPlayer ?? this.confirmExitPlayer,
        incognitoMode: incognitoMode ?? this.incognitoMode,
        bufferSizeMb: bufferSizeMb ?? this.bufferSizeMb,
        autoPlayNext: autoPlayNext ?? this.autoPlayNext,
        autoSkipIntro: autoSkipIntro ?? this.autoSkipIntro,
        autoSkipOutro: autoSkipOutro ?? this.autoSkipOutro,
        customSkipIntroSecs: customSkipIntroSecs ?? this.customSkipIntroSecs,
        customSkipOutroSecs: customSkipOutroSecs ?? this.customSkipOutroSecs,
        rememberPosition: rememberPosition ?? this.rememberPosition,
        rememberBrightness: rememberBrightness ?? this.rememberBrightness,
        savedBrightness: savedBrightness ?? this.savedBrightness,
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
        'use_skin_geometry': useSkinGeometry,
        'custom_skins': customSkins.map((s) => s.toJson()).toList(),
        'skin_overrides': skinOverrides,
        'accent_id': accentId,
        'card_radius': cardRadius,
        'glass_intensity': glassIntensity,
        'reduce_motion': reduceMotion,
        'list_density': listDensity,
        'show_ratings': showRatings,
        'show_year': showYear,
        'show_watched_badge': showWatchedBadge,
        'show_unplayed_count': showUnplayedCount,
        'default_sort': defaultSort,
        'show_spec_badges': showSpecBadges,
        'show_remaining_time': showRemainingTime,
        'confirm_exit_player': confirmExitPlayer,
        'incognito_mode': incognitoMode,
        'buffer_size_mb': bufferSizeMb,
        'auto_play_next': autoPlayNext,
        'auto_skip_intro': autoSkipIntro,
        'auto_skip_outro': autoSkipOutro,
        'custom_skip_intro_secs': customSkipIntroSecs,
        'custom_skip_outro_secs': customSkipOutroSecs,
        'remember_position': rememberPosition,
        'remember_brightness': rememberBrightness,
        'saved_brightness': savedBrightness,
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

  factory VedroPreferences.fromJson(Map<String, dynamic> j) => VedroPreferences(
        skinId: (j['skin_id'] ?? 'obsidian').toString(),
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
        accentId: (j['accent_id'] ?? 'blue').toString(),
        cardRadius: (j['card_radius'] as num?)?.toDouble() ?? 12.0,
        glassIntensity: (j['glass_intensity'] ?? 'standard').toString(),
        reduceMotion: j['reduce_motion'] == true,
        listDensity: (j['list_density'] ?? 'comfortable').toString(),
        showRatings: j['show_ratings'] != false,
        showYear: j['show_year'] != false,
        showWatchedBadge: j['show_watched_badge'] != false,
        showUnplayedCount: j['show_unplayed_count'] != false,
        defaultSort: (j['default_sort'] ?? 'DateCreated').toString(),
        showSpecBadges: j['show_spec_badges'] != false,
        showRemainingTime: j['show_remaining_time'] == true,
        confirmExitPlayer: j['confirm_exit_player'] == true,
        incognitoMode: j['incognito_mode'] == true,
        bufferSizeMb: (j['buffer_size_mb'] as num?)?.toInt() ?? 128,
        autoPlayNext: j['auto_play_next'] != false,
        autoSkipIntro: j['auto_skip_intro'] == true,
        autoSkipOutro: j['auto_skip_outro'] == true,
        customSkipIntroSecs: (j['custom_skip_intro_secs'] as num?)?.toInt() ?? 0,
        customSkipOutroSecs: (j['custom_skip_outro_secs'] as num?)?.toInt() ?? 0,
        rememberPosition: j['remember_position'] != false,
        rememberBrightness: j['remember_brightness'] == true,
        savedBrightness: (j['saved_brightness'] as num?)?.toDouble() ?? 1.0,
        defaultSpeed: (j['default_speed'] as num?)?.toDouble() ?? 1.0,
        longPressSpeed: (j['long_press_speed'] as num?)?.toDouble() ?? 2.0,
        seekStepSecs: (j['seek_step_secs'] as num?)?.toInt() ?? 10,
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
        maxVolumePercent: (j['max_volume_percent'] as num?)?.toInt() ?? 150,
        audioDelayMs: (j['audio_delay_ms'] as num?)?.toInt() ?? 0,
        preferredSubLang: (j['preferred_sub_lang'] ?? 'zh').toString(),
        autoLoadExternalSubs: j['auto_load_external_subs'] != false,
        forceAssOverride: j['force_ass_override'] == true,
        subtitleFontFamily: (j['subtitle_font_family'] ?? '').toString(),
        subtitleFontScale: (j['subtitle_font_scale'] as num?)?.toDouble() ?? 1.0,
        subtitlePos: (j['subtitle_pos'] as num?)?.toInt() ?? 96,
        subtitleColorHex: (j['subtitle_color_hex'] ?? '#FFFFFF').toString(),
        subtitleOutlineWidth: (j['subtitle_outline_width'] as num?)?.toDouble() ?? 2.4,
        subtitleBgOpacity: (j['subtitle_bg_opacity'] as num?)?.toDouble() ?? 0.0,
        subtitleDelaySecs: (j['subtitle_delay_secs'] as num?)?.toDouble() ?? 0.0,
        danmakuEnabled: j['danmaku_enabled'] == true,
        danmakuOpacity: (j['danmaku_opacity'] as num?)?.toDouble() ?? 0.82,
        danmakuFontSize: (j['danmaku_font_size'] as num?)?.toDouble() ?? 18.0,
        danmakuSpeedSecs: (j['danmaku_speed_secs'] as num?)?.toDouble() ?? 9.0,
        danmakuArea: (j['danmaku_area'] as num?)?.toDouble() ?? 0.5,
        danmakuHideTop: j['danmaku_hide_top'] == true,
        danmakuHideBottom: j['danmaku_hide_bottom'] == true,
        danmakuApiUrl: (j['danmaku_api_url'] ?? '').toString(),
        aiEnabled: j['ai_enabled'] == true,
        aiBaseUrl: (j['ai_base_url'] ?? 'https://api.openai.com/v1').toString(),
        aiApiKey: (j['ai_api_key'] ?? '').toString(),
        aiModel: (j['ai_model'] ?? 'gpt-4o-mini').toString(),
        aiTargetLang: (j['ai_target_lang'] ?? '简体中文').toString(),
        aiBilingualSubtitle: j['ai_bilingual_subtitle'] != false,
        passcodeEnabled: j['passcode_enabled'] == true,
        passcodeHash: (j['passcode_hash'] ?? '').toString(),
        lockTimeoutSecs: (j['lock_timeout_secs'] as num?)?.toInt() ?? 60,
        blurInBackground: j['blur_in_background'] != false,
        downloadWifiOnly: j['download_wifi_only'] != false,
        downloadMaxConcurrent: (j['download_max_concurrent'] as num?)?.toInt() ?? 2,
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
