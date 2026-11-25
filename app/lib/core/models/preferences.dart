import 'dart:convert';

import 'package:flutter/material.dart';

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

class DownloadTaskModel {
  const DownloadTaskModel({
    required this.id,
    required this.itemId,
    required this.title,
    this.subtitle = '',
    this.filePath = '',
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.status = 'queued', // queued | downloading | completed | failed | paused
    this.error,
    this.createdAt = 0,
  });

  final String id;
  final String itemId;
  final String title;
  final String subtitle;
  final String filePath;
  final int totalBytes;
  final int downloadedBytes;
  final String status;
  final String? error;
  final int createdAt;

  double get progress =>
      totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : (status == 'completed' ? 1.0 : 0.0);

  DownloadTaskModel copyWith({
    String? filePath,
    int? totalBytes,
    int? downloadedBytes,
    String? status,
    String? error,
  }) =>
      DownloadTaskModel(
        id: id,
        itemId: itemId,
        title: title,
        subtitle: subtitle,
        filePath: filePath ?? this.filePath,
        totalBytes: totalBytes ?? this.totalBytes,
        downloadedBytes: downloadedBytes ?? this.downloadedBytes,
        status: status ?? this.status,
        error: error,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'item_id': itemId,
        'title': title,
        'subtitle': subtitle,
        'file_path': filePath,
        'total_bytes': totalBytes,
        'downloaded_bytes': downloadedBytes,
        'status': status,
        if (error != null) 'error': error,
        'created_at': createdAt,
      };

  factory DownloadTaskModel.fromJson(Map<String, dynamic> j) => DownloadTaskModel(
        id: (j['id'] ?? '').toString(),
        itemId: (j['item_id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        subtitle: (j['subtitle'] ?? '').toString(),
        filePath: (j['file_path'] ?? '').toString(),
        totalBytes: (j['total_bytes'] as num?)?.toInt() ?? 0,
        downloadedBytes: (j['downloaded_bytes'] as num?)?.toInt() ?? 0,
        status: (j['status'] ?? 'queued').toString(),
        error: j['error']?.toString(),
        createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
      );
}

class VedroPreferences {
  const VedroPreferences({
    // 应用风格
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
    this.rememberPosition = true,
    this.defaultSpeed = 1.0,
    this.seekStepSecs = 10,
    this.enablePip = true,
    this.backgroundAudio = false,
    // 视频设置
    this.defaultAspect = 'fit',
    this.videoSync = 'audio',
    this.hdrComputePeak = true,
    // 音频设置
    this.preferredAudioLang = 'auto',
    this.maxVolumePercent = 150,
    this.audioDelayMs = 0,
    // 字幕设置
    this.preferredSubLang = 'zh',
    this.autoLoadExternalSubs = true,
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
    // 字体管理 (imported custom font file paths)
    this.customFontPaths = const [],
  });

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
  final bool rememberPosition;
  final double defaultSpeed;
  final int seekStepSecs;
  final bool enablePip;
  final bool backgroundAudio;

  final String defaultAspect;
  final String videoSync;
  final bool hdrComputePeak;

  final String preferredAudioLang;
  final int maxVolumePercent;
  final int audioDelayMs;

  final String preferredSubLang;
  final bool autoLoadExternalSubs;
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

  AccentPalette get accentPalette => AccentPalette.byId(accentId);

  bool get isAiReady =>
      aiEnabled && aiBaseUrl.trim().isNotEmpty && aiModel.trim().isNotEmpty;

  double posterCardWidth(bool wide) {
    switch (listDensity) {
      case 'compact':
        return wide ? 136.0 : 112.0;
      case 'spacious':
        return wide ? 182.0 : 150.0;
      default:
        return wide ? 158.0 : 132.0;
    }
  }

  VedroPreferences copyWith({
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
    bool? rememberPosition,
    double? defaultSpeed,
    int? seekStepSecs,
    bool? enablePip,
    bool? backgroundAudio,
    String? defaultAspect,
    String? videoSync,
    bool? hdrComputePeak,
    String? preferredAudioLang,
    int? maxVolumePercent,
    int? audioDelayMs,
    String? preferredSubLang,
    bool? autoLoadExternalSubs,
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
  }) =>
      VedroPreferences(
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
        rememberPosition: rememberPosition ?? this.rememberPosition,
        defaultSpeed: defaultSpeed ?? this.defaultSpeed,
        seekStepSecs: seekStepSecs ?? this.seekStepSecs,
        enablePip: enablePip ?? this.enablePip,
        backgroundAudio: backgroundAudio ?? this.backgroundAudio,
        defaultAspect: defaultAspect ?? this.defaultAspect,
        videoSync: videoSync ?? this.videoSync,
        hdrComputePeak: hdrComputePeak ?? this.hdrComputePeak,
        preferredAudioLang: preferredAudioLang ?? this.preferredAudioLang,
        maxVolumePercent: maxVolumePercent ?? this.maxVolumePercent,
        audioDelayMs: audioDelayMs ?? this.audioDelayMs,
        preferredSubLang: preferredSubLang ?? this.preferredSubLang,
        autoLoadExternalSubs: autoLoadExternalSubs ?? this.autoLoadExternalSubs,
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
      );

  Map<String, dynamic> toJson() => {
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
        'remember_position': rememberPosition,
        'default_speed': defaultSpeed,
        'seek_step_secs': seekStepSecs,
        'enable_pip': enablePip,
        'background_audio': backgroundAudio,
        'default_aspect': defaultAspect,
        'video_sync': videoSync,
        'hdr_compute_peak': hdrComputePeak,
        'preferred_audio_lang': preferredAudioLang,
        'max_volume_percent': maxVolumePercent,
        'audio_delay_ms': audioDelayMs,
        'preferred_sub_lang': preferredSubLang,
        'auto_load_external_subs': autoLoadExternalSubs,
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
      };

  factory VedroPreferences.fromJson(Map<String, dynamic> j) => VedroPreferences(
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
        rememberPosition: j['remember_position'] != false,
        defaultSpeed: (j['default_speed'] as num?)?.toDouble() ?? 1.0,
        seekStepSecs: (j['seek_step_secs'] as num?)?.toInt() ?? 10,
        enablePip: j['enable_pip'] != false,
        backgroundAudio: j['background_audio'] == true,
        defaultAspect: (j['default_aspect'] ?? 'fit').toString(),
        videoSync: (j['video_sync'] ?? 'audio').toString(),
        hdrComputePeak: j['hdr_compute_peak'] != false,
        preferredAudioLang: (j['preferred_audio_lang'] ?? 'auto').toString(),
        maxVolumePercent: (j['max_volume_percent'] as num?)?.toInt() ?? 150,
        audioDelayMs: (j['audio_delay_ms'] as num?)?.toInt() ?? 0,
        preferredSubLang: (j['preferred_sub_lang'] ?? 'zh').toString(),
        autoLoadExternalSubs: j['auto_load_external_subs'] != false,
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
      );
}
