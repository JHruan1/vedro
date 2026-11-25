// Core data models mirroring `core/vedro-protocol`, `core/vedro-stream`, and `core/vedro-playback`.

const int kEmbyTicksPerSecond = 10000000;

/// Deterministic low-chroma hue pair matching embygo Web's `GeneratedArt`,
/// so an item without cover art gets a calm, permanent two-tone gradient.
(double, double) deterministicHues(String seed) {
  final s = seed.isEmpty ? '?' : seed;
  var hash = 0;
  for (var i = 0; i < s.length; i++) {
    hash = ((hash * 31) + s.codeUnitAt(i)) & 0xFFFFFFFF;
  }
  return ((hash % 360).toDouble(), ((hash >> 9) % 360).toDouble());
}

/// Clean display initials for missing artwork (2 CJK chars or 2 latin/number tokens).
String artworkInitials(String? name) {
  final trimmed = (name ?? '?').trim();
  if (trimmed.isEmpty) return '?';
  if (RegExp(r'[\u3400-\u9FFF]').hasMatch(trimmed)) {
    return trimmed.length > 2 ? trimmed.substring(0, 2) : trimmed;
  }
  final words = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).toList();
  final buf = StringBuffer();
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    if (i > 0 && RegExp(r'^\d+$').hasMatch(w)) {
      buf.write(w);
    } else if (w.isNotEmpty) {
      buf.write(w[0]);
    }
  }
  final out = buf.toString().toUpperCase();
  return out.isEmpty ? '?' : out;
}

String fmtDurationTicks(int? ticks) {
  if (ticks == null || ticks <= 0) return '';
  final minutes = (ticks / kEmbyTicksPerSecond / 60).round();
  if (minutes <= 0) return '';
  if (minutes < 60) return '$minutes 分钟';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m > 0 ? '$h 小时 $m 分' : '$h 小时';
}

String fmtFileSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value < 10 && unit > 0 ? value.toStringAsFixed(1) : value.round()} ${units[unit]}';
}

class ResolvedArt {
  const ResolvedArt({required this.url, required this.isPoster});
  final String url;

  /// True when only a 2:3 portrait poster exists for a 16:9 slot —
  /// callers render it with a blurred ambient backdrop + framed poster instead of cropping.
  final bool isPoster;
}

class ServerCapabilitiesModel {
  ServerCapabilitiesModel({
    required this.dialect,
    required this.serverId,
    required this.serverName,
    required this.advertisedVersion,
    required this.supportsTranscoding,
    required this.supportsPopular,
    required this.supportsSuggestions,
    required this.supportsHideFromResume,
    required this.usesStreamTickets,
    this.embygoBuildVersion,
  });

  final String dialect;
  final String serverId;
  final String serverName;
  final String advertisedVersion;
  final String? embygoBuildVersion;
  final bool supportsTranscoding;
  final bool supportsPopular;
  final bool supportsSuggestions;
  final bool supportsHideFromResume;
  final bool usesStreamTickets;

  bool get isEmbyGo => dialect == 'embygo';

  factory ServerCapabilitiesModel.fromJson(Map<String, dynamic> j) {
    return ServerCapabilitiesModel(
      dialect: (j['dialect'] ?? 'unknown').toString(),
      serverId: (j['server_id'] ?? '').toString(),
      serverName: (j['server_name'] ?? '').toString(),
      advertisedVersion: (j['advertised_version'] ?? '').toString(),
      embygoBuildVersion: j['embygo_build_version']?.toString(),
      supportsTranscoding: j['supports_transcoding'] == true,
      supportsPopular: j['supports_popular'] == true,
      supportsSuggestions: j['supports_suggestions'] != false,
      supportsHideFromResume: j['supports_hide_from_resume'] != false,
      usesStreamTickets: j['uses_stream_tickets'] == true,
    );
  }
}

class SavedServerProfile {
  SavedServerProfile({
    required this.id,
    required this.name,
    required this.url,
    required this.dialect,
    this.userId,
    this.username,
    this.accessToken,
    this.isAdmin = false,
    this.lastConnectedAt = 0,
  });

  final String id;
  final String name;
  final String url;
  final String dialect;
  final String? userId;
  final String? username;
  final String? accessToken;
  final bool isAdmin;
  final int lastConnectedAt;

  factory SavedServerProfile.fromJson(Map<String, dynamic> j) => SavedServerProfile(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
        dialect: (j['dialect'] ?? 'unknown').toString(),
        userId: j['user_id']?.toString(),
        username: j['username']?.toString(),
        accessToken: j['access_token']?.toString(),
        isAdmin: j['is_admin'] == true,
        lastConnectedAt: (j['last_connected_at'] as num?)?.toInt() ?? 0,
      );
}

class MediaStreamModel {
  MediaStreamModel({
    required this.index,
    required this.type,
    this.codec,
    this.language,
    this.title,
    this.displayTitle,
    this.isDefault = false,
    this.isForced = false,
    this.isExternal = false,
    this.channels,
    this.channelLayout,
    this.width,
    this.height,
  });

  final int index;
  final String type;
  final String? codec;
  final String? language;
  final String? title;
  final String? displayTitle;
  final bool isDefault;
  final bool isForced;
  final bool isExternal;
  final int? channels;
  final String? channelLayout;
  final int? width;
  final int? height;

  String get label {
    if (displayTitle != null && displayTitle!.trim().isNotEmpty) return displayTitle!.trim();
    final parts = <String>[
      if (title != null && title!.trim().isNotEmpty) title!.trim(),
      if (language != null && language!.trim().isNotEmpty) language!.trim().toUpperCase(),
      if (codec != null && codec!.trim().isNotEmpty) codec!.trim().toUpperCase(),
      if (channelLayout != null && channelLayout!.trim().isNotEmpty) channelLayout!.trim(),
    ];
    return parts.isEmpty ? '#$index' : parts.join(' · ');
  }

  factory MediaStreamModel.fromJson(Map<String, dynamic> j) => MediaStreamModel(
        index: (j['Index'] as num?)?.toInt() ?? 0,
        type: (j['Type'] ?? '').toString(),
        codec: j['Codec']?.toString(),
        language: j['Language']?.toString(),
        title: j['Title']?.toString(),
        displayTitle: j['DisplayTitle']?.toString(),
        isDefault: j['IsDefault'] == true,
        isForced: j['IsForced'] == true,
        isExternal: j['IsExternal'] == true,
        channels: (j['Channels'] as num?)?.toInt(),
        channelLayout: j['ChannelLayout']?.toString(),
        width: (j['Width'] as num?)?.toInt(),
        height: (j['Height'] as num?)?.toInt(),
      );
}

class MediaSourceModel {
  MediaSourceModel({
    required this.id,
    this.name,
    this.container,
    this.size,
    this.bitrate,
    this.runTimeTicks,
    this.directStreamUrl,
    this.supportsDirectPlay = true,
    this.mediaStreams = const [],
  });

  final String id;
  final String? name;
  final String? container;
  final int? size;
  final int? bitrate;
  final int? runTimeTicks;
  final String? directStreamUrl;
  final bool supportsDirectPlay;
  final List<MediaStreamModel> mediaStreams;

  List<MediaStreamModel> get audioStreams =>
      mediaStreams.where((s) => s.type.toLowerCase() == 'audio').toList();

  List<MediaStreamModel> get subtitleStreams =>
      mediaStreams.where((s) => s.type.toLowerCase() == 'subtitle').toList();

  List<String> get factChips {
    final chips = <String>[];
    if (name != null) {
      for (final seg in name!.split(' · ')) {
        final t = seg.trim();
        if (t.isNotEmpty && t != 'Preferred') chips.add(t);
      }
    }
    if (container != null && container!.isNotEmpty) {
      final c = container!.toUpperCase();
      if (!chips.contains(c)) chips.add(c);
    }
    final sz = fmtFileSize(size);
    if (sz.isNotEmpty) chips.add(sz);
    return chips;
  }

  String get displayLabel {
    final parts = <String>[];
    if (name != null && name!.isNotEmpty) {
      parts.add(name!);
    } else if (container != null) {
      parts.add(container!.toUpperCase());
    }
    final sz = fmtFileSize(size);
    if (sz.isNotEmpty) parts.add(sz);
    if (bitrate != null && bitrate! > 0) {
      parts.add('${(bitrate! / 1000000).toStringAsFixed(1)} Mbps');
    }
    return parts.join(' · ');
  }

  factory MediaSourceModel.fromJson(Map<String, dynamic> j) => MediaSourceModel(
        id: (j['Id'] ?? '').toString(),
        name: j['Name']?.toString(),
        container: j['Container']?.toString(),
        size: (j['Size'] as num?)?.toInt(),
        bitrate: (j['Bitrate'] as num?)?.toInt(),
        runTimeTicks: (j['RunTimeTicks'] as num?)?.toInt(),
        directStreamUrl: j['DirectStreamUrl']?.toString(),
        supportsDirectPlay: j['SupportsDirectPlay'] != false,
        mediaStreams: ((j['MediaStreams'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MediaStreamModel.fromJson)
            .toList(),
      );
}

class MediaSegmentModel {
  MediaSegmentModel({
    required this.type,
    required this.startTicks,
    required this.endTicks,
  });

  final String type; // Intro, Outro, Recap, Preview
  final int startTicks;
  final int endTicks;

  double get startSecs => startTicks / kEmbyTicksPerSecond;
  double get endSecs => endTicks / kEmbyTicksPerSecond;

  String get buttonLabel {
    switch (type.toLowerCase()) {
      case 'intro':
        return '跳过片头';
      case 'outro':
        return '跳过片尾';
      case 'recap':
        return '跳过前情';
      default:
        return '跳过片段';
    }
  }

  factory MediaSegmentModel.fromJson(Map<String, dynamic> j) => MediaSegmentModel(
        type: (j['Type'] ?? 'Intro').toString(),
        startTicks: (j['StartTicks'] as num?)?.toInt() ?? 0,
        endTicks: (j['EndTicks'] as num?)?.toInt() ?? 0,
      );
}

class PersonCreditModel {
  PersonCreditModel({
    required this.id,
    required this.name,
    this.role,
    this.type,
    this.primaryImageTag,
  });

  final String id;
  final String name;
  final String? role;
  final String? type;
  final String? primaryImageTag;

  factory PersonCreditModel.fromJson(Map<String, dynamic> j) => PersonCreditModel(
        id: (j['Id'] ?? '').toString(),
        name: (j['Name'] ?? '').toString(),
        role: j['Role']?.toString(),
        type: j['Type']?.toString(),
        primaryImageTag: j['PrimaryImageTag']?.toString(),
      );
}

class MediaItemModel {
  MediaItemModel({
    required this.id,
    required this.name,
    required this.type,
    this.originalTitle,
    this.collectionType,
    this.overview,
    this.productionYear,
    this.communityRating,
    this.officialRating,
    this.runTimeTicks,
    this.seriesId,
    this.seriesName,
    this.seasonId,
    this.seasonName,
    this.parentIndexNumber,
    this.indexNumber,
    this.indexNumberEnd,
    this.childCount,
    this.recursiveItemCount,
    this.mediaSourceCount,
    this.sourceFolderCount,
    this.played = false,
    this.playedPercentage,
    this.playbackPositionTicks = 0,
    this.unplayedItemCount,
    this.isFavorite = false,
    this.primaryImageTag,
    this.thumbImageTag,
    this.logoImageTag,
    this.backdropImageTag,
    this.seriesPrimaryImageTag,
    this.parentPrimaryImageItemId,
    this.parentPrimaryImageTag,
    this.parentThumbItemId,
    this.parentThumbImageTag,
    this.parentLogoItemId,
    this.parentLogoImageTag,
    this.parentBackdropItemId,
    this.parentBackdropImageTag,
    this.genres = const [],
    this.tags = const [],
    this.people = const [],
    this.mediaSources = const [],
    this.playlistItemId,
  });

  final String id;
  final String name;
  final String type;
  final String? originalTitle;
  final String? collectionType;
  final String? overview;
  final int? productionYear;
  final double? communityRating;
  final String? officialRating;
  final int? runTimeTicks;
  final String? seriesId;
  final String? seriesName;
  final String? seasonId;
  final String? seasonName;
  final int? parentIndexNumber;
  final int? indexNumber;
  final int? indexNumberEnd;
  final int? childCount;
  final int? recursiveItemCount;
  final int? mediaSourceCount;
  final int? sourceFolderCount;
  final bool played;
  final double? playedPercentage;
  final int playbackPositionTicks;
  final int? unplayedItemCount;
  final bool isFavorite;
  final String? primaryImageTag;
  final String? thumbImageTag;
  final String? logoImageTag;
  final String? backdropImageTag;
  final String? seriesPrimaryImageTag;
  final String? parentPrimaryImageItemId;
  final String? parentPrimaryImageTag;
  final String? parentThumbItemId;
  final String? parentThumbImageTag;
  final String? parentLogoItemId;
  final String? parentLogoImageTag;
  final String? parentBackdropItemId;
  final String? parentBackdropImageTag;
  final List<String> genres;
  final List<String> tags;
  final List<PersonCreditModel> people;
  final List<MediaSourceModel> mediaSources;
  final String? playlistItemId;

  bool get isPlayable => type == 'Movie' || type == 'Episode' || type == 'Video';
  bool get isSeries => type == 'Series';
  bool get isFolderish => type == 'Series' || type == 'Season';
  int get versionCount => mediaSourceCount ?? mediaSources.length;

  /// Localises scraper fallback `"Episode 3"` into `"第 3 集"` just like embygo Web.
  String get displayName {
    final m = RegExp(r'^Episode (\d+)$').firstMatch(name);
    return m != null ? '第 ${m.group(1)} 集' : name;
  }

  String get cardTitle => type == 'Episode' ? (seriesName ?? displayName) : name;

  String get cardSubtitle {
    switch (type) {
      case 'Episode':
        return [if (episodeCode != null) episodeCode!, displayName].join(' · ');
      case 'Season':
        return seriesName ?? '';
      case 'Series':
        return [
          if (productionYear != null) '$productionYear',
          if (childCount != null && childCount! > 0) '$childCount 季',
          if (recursiveItemCount != null && recursiveItemCount! > 0) '$recursiveItemCount 集',
        ].join(' · ');
      default:
        return [
          if (productionYear != null) '$productionYear',
          if (communityRating != null) '★ ${communityRating!.toStringAsFixed(1)}',
        ].join(' · ');
    }
  }

  String? get episodeCode {
    if (type != 'Episode') return null;
    final s = parentIndexNumber != null ? 'S${parentIndexNumber!.toString().padLeft(2, '0')}' : '';
    final e = indexNumber != null ? 'E${indexNumber!.toString().padLeft(2, '0')}' : '';
    final end = (indexNumberEnd != null && indexNumber != null && indexNumberEnd! > indexNumber!)
        ? '-${indexNumberEnd!.toString().padLeft(2, '0')}'
        : '';
    final code = '$s$e$end';
    return code.isEmpty ? null : code;
  }

  double get resumeProgress {
    if (played) return 0.0;
    if (playedPercentage != null && playedPercentage! > 0.5 && playedPercentage! < 99) {
      return (playedPercentage! / 100.0).clamp(0.0, 1.0);
    }
    if (runTimeTicks != null && runTimeTicks! > 0 && playbackPositionTicks > 0) {
      final p = (playbackPositionTicks / runTimeTicks!).clamp(0.0, 1.0);
      return p > 0.005 && p < 0.99 ? p : 0.0;
    }
    return 0.0;
  }

  String get remainingText {
    if (playbackPositionTicks <= 0) return '';
    if (runTimeTicks == null || runTimeTicks! <= 0) {
      final watched = fmtDurationTicks(playbackPositionTicks);
      return watched.isNotEmpty ? '已看 $watched' : '';
    }
    final left = runTimeTicks! - playbackPositionTicks;
    if (left <= 60 * kEmbyTicksPerSecond) return '即将看完';
    final text = fmtDurationTicks(left);
    return text.isNotEmpty ? '剩余 $text' : '';
  }

  List<String> get inferredBadges {
    final badges = <String>[];
    final hay = mediaSources.map((s) => s.name ?? '').join(' ').toLowerCase();
    if (hay.contains('2160p') || hay.contains('4k') || hay.contains('uhd')) badges.add('4K');
    if (hay.contains('dovi') || hay.contains('.dv.') || hay.contains('dolby vision')) {
      badges.add('Dolby Vision');
    } else if (hay.contains('hdr10+')) {
      badges.add('HDR10+');
    } else if (hay.contains('hdr')) {
      badges.add('HDR10');
    }
    if (hay.contains('atmos')) badges.add('Dolby Atmos');
    if (hay.contains('truehd') && !badges.contains('Dolby Atmos')) badges.add('TrueHD');
    if (hay.contains('dts:x') || hay.contains('dts-x')) badges.add('DTS:X');
    if (hay.contains('remux')) badges.add('REMUX');
    if (versionCount > 1) badges.add('$versionCount 版本');
    return badges;
  }

  factory MediaItemModel.fromJson(Map<String, dynamic> j) {
    final userData = (j['UserData'] as Map<String, dynamic>?) ?? const {};
    final imageTags = (j['ImageTags'] as Map<String, dynamic>?) ?? const {};
    final backdrops = (j['BackdropImageTags'] as List<dynamic>?) ?? const [];
    final parentBackdrops = (j['ParentBackdropImageTags'] as List<dynamic>?) ?? const [];
    final sources = ((j['MediaSources'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MediaSourceModel.fromJson)
        .toList();
    final people = ((j['People'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PersonCreditModel.fromJson)
        .toList();

    return MediaItemModel(
      id: (j['Id'] ?? '').toString(),
      name: (j['Name'] ?? '').toString(),
      type: (j['Type'] ?? 'Movie').toString(),
      originalTitle: j['OriginalTitle']?.toString(),
      collectionType: j['CollectionType']?.toString(),
      overview: j['Overview']?.toString(),
      productionYear: (j['ProductionYear'] as num?)?.toInt(),
      communityRating: (j['CommunityRating'] as num?)?.toDouble(),
      officialRating: j['OfficialRating']?.toString(),
      runTimeTicks: (j['RunTimeTicks'] as num?)?.toInt(),
      seriesId: j['SeriesId']?.toString(),
      seriesName: j['SeriesName']?.toString(),
      seasonId: j['SeasonId']?.toString(),
      seasonName: j['SeasonName']?.toString(),
      parentIndexNumber:
          (j['ParentIndexNumber'] as num?)?.toInt() ?? (j['SeasonNumber'] as num?)?.toInt(),
      indexNumber: (j['IndexNumber'] as num?)?.toInt(),
      indexNumberEnd: (j['IndexNumberEnd'] as num?)?.toInt(),
      childCount: (j['ChildCount'] as num?)?.toInt(),
      recursiveItemCount: (j['RecursiveItemCount'] as num?)?.toInt(),
      mediaSourceCount: (j['MediaSourceCount'] as num?)?.toInt(),
      sourceFolderCount: (j['SourceFolderCount'] as num?)?.toInt(),
      played: userData['Played'] == true,
      playedPercentage: (userData['PlayedPercentage'] as num?)?.toDouble(),
      playbackPositionTicks: (userData['PlaybackPositionTicks'] as num?)?.toInt() ?? 0,
      unplayedItemCount: (userData['UnplayedItemCount'] as num?)?.toInt(),
      isFavorite: userData['IsFavorite'] == true,
      primaryImageTag: imageTags['Primary']?.toString(),
      thumbImageTag: imageTags['Thumb']?.toString(),
      logoImageTag: imageTags['Logo']?.toString(),
      backdropImageTag: backdrops.isNotEmpty ? backdrops.first.toString() : null,
      seriesPrimaryImageTag: j['SeriesPrimaryImageTag']?.toString(),
      parentPrimaryImageItemId: j['ParentPrimaryImageItemId']?.toString(),
      parentPrimaryImageTag: j['ParentPrimaryImageTag']?.toString(),
      parentThumbItemId: j['ParentThumbItemId']?.toString(),
      parentThumbImageTag: j['ParentThumbImageTag']?.toString(),
      parentLogoItemId: j['ParentLogoItemId']?.toString(),
      parentLogoImageTag: j['ParentLogoImageTag']?.toString(),
      parentBackdropItemId: j['ParentBackdropItemId']?.toString(),
      parentBackdropImageTag: parentBackdrops.isNotEmpty ? parentBackdrops.first.toString() : null,
      genres: ((j['Genres'] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList(),
      tags: ((j['Tags'] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList(),
      people: people,
      mediaSources: sources,
      playlistItemId: j['PlaylistItemId']?.toString(),
    );
  }
}

class PreparedPlaybackModel {
  PreparedPlaybackModel({
    required this.itemId,
    required this.mediaSourceId,
    required this.playSessionId,
    required this.proxyUrl,
    required this.usesStreamTicket,
    required this.hdrExplanation,
    required this.audioSummary,
    required this.backend,
    required this.mpvOptions,
    required this.externalSubtitles,
    required this.allSources,
    this.inspectedJson,
    this.dolbyVisionLabel,
    this.spatialAudioLabel,
  });

  final String itemId;
  final String mediaSourceId;
  final String playSessionId;
  final String proxyUrl;
  final bool usesStreamTicket;
  final String hdrExplanation;
  final String audioSummary;
  final String backend;
  final Map<String, String> mpvOptions;
  final List<Map<String, dynamic>> externalSubtitles;
  final List<MediaSourceModel> allSources;
  final Map<String, dynamic>? inspectedJson;
  final String? dolbyVisionLabel;
  final String? spatialAudioLabel;

  factory PreparedPlaybackModel.fromJson(Map<String, dynamic> j) {
    final hdr = (j['hdr_decision'] as Map<String, dynamic>?) ?? const {};
    final audio = (j['audio_decision'] as Map<String, dynamic>?) ?? const {};
    final inspected = j['inspected'] as Map<String, dynamic>?;
    final mpvOpts = <String, String>{};
    if (j['mpv_options'] is List) {
      for (final pair in (j['mpv_options'] as List)) {
        if (pair is List && pair.length >= 2) {
          mpvOpts[pair[0].toString()] = pair[1].toString();
        }
      }
    }
    String? dvLabel;
    if (inspected != null && inspected['dolby_vision'] is Map<String, dynamic>) {
      final dv = inspected['dolby_vision'] as Map<String, dynamic>;
      final p = dv['dv_profile'];
      final c = dv['bl_signal_compatibility_id'];
      dvLabel = c != null && c != 0 ? 'Dolby Vision P$p.$c' : 'Dolby Vision P$p';
    }
    String? spLabel;
    if (inspected != null && inspected['spatial_audio'] != null) {
      final sa = inspected['spatial_audio'].toString();
      if (sa.contains('atmos')) spLabel = 'Dolby Atmos';
      if (sa.contains('dts_x')) spLabel = 'DTS:X';
    }
    return PreparedPlaybackModel(
      itemId: (j['item_id'] ?? '').toString(),
      mediaSourceId: (j['media_source_id'] ?? '').toString(),
      playSessionId: (j['play_session_id'] ?? '').toString(),
      proxyUrl: (j['proxy_url'] ?? '').toString(),
      usesStreamTicket: j['uses_stream_ticket'] == true,
      hdrExplanation: (hdr['explanation'] ?? 'Direct Play').toString(),
      audioSummary: (audio['summary'] ?? 'Auto Audio').toString(),
      backend: (hdr['backend'] ?? 'libmpv_gpu_next').toString(),
      mpvOptions: mpvOpts,
      externalSubtitles: ((j['external_subtitles'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(),
      allSources: ((j['all_sources'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MediaSourceModel.fromJson)
          .toList(),
      inspectedJson: inspected,
      dolbyVisionLabel: dvLabel,
      spatialAudioLabel: spLabel,
    );
  }
}
