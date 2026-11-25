// Core data models mirroring `core/prism-protocol`, `core/prism-stream`, and `core/prism-playback`.

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
  });

  final String id;
  final String name;
  final String url;
  final String dialect;
  final String? userId;
  final String? username;
  final String? accessToken;
  final bool isAdmin;

  factory SavedServerProfile.fromJson(Map<String, dynamic> j) => SavedServerProfile(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
        dialect: (j['dialect'] ?? 'unknown').toString(),
        userId: j['user_id']?.toString(),
        username: j['username']?.toString(),
        accessToken: j['access_token']?.toString(),
        isAdmin: j['is_admin'] == true,
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
  });

  final String id;
  final String? name;
  final String? container;
  final int? size;
  final int? bitrate;
  final int? runTimeTicks;
  final String? directStreamUrl;
  final bool supportsDirectPlay;

  String get displayLabel {
    final parts = <String>[];
    if (name != null && name!.isNotEmpty) {
      parts.add(name!);
    } else if (container != null) {
      parts.add(container!.toUpperCase());
    }
    if (size != null && size! > 0) {
      final gb = size! / (1024 * 1024 * 1024);
      parts.add(gb >= 1.0 ? '${gb.toStringAsFixed(2)} GB' : '${(size! / (1024 * 1024)).toStringAsFixed(0)} MB');
    }
    if (bitrate != null && bitrate! > 0) {
      parts.add('${(bitrate! / 1000000).toStringAsFixed(1)} Mbps');
    }
    return parts.join(' • ');
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
    this.collectionType,
    this.overview,
    this.productionYear,
    this.communityRating,
    this.officialRating,
    this.runTimeTicks,
    this.seriesId,
    this.seriesName,
    this.parentIndexNumber,
    this.indexNumber,
    this.indexNumberEnd,
    this.played = false,
    this.playedPercentage,
    this.playbackPositionTicks = 0,
    this.unplayedItemCount,
    this.isFavorite = false,
    this.primaryImageTag,
    this.backdropImageTag,
    this.genres = const [],
    this.tags = const [],
    this.people = const [],
    this.mediaSources = const [],
    this.playlistItemId,
  });

  final String id;
  final String name;
  final String type;
  final String? collectionType;
  final String? overview;
  final int? productionYear;
  final double? communityRating;
  final String? officialRating;
  final int? runTimeTicks;
  final String? seriesId;
  final String? seriesName;
  final int? parentIndexNumber;
  final int? indexNumber;
  final int? indexNumberEnd;
  final bool played;
  final double? playedPercentage;
  final int playbackPositionTicks;
  final int? unplayedItemCount;
  final bool isFavorite;
  final String? primaryImageTag;
  final String? backdropImageTag;
  final List<String> genres;
  final List<String> tags;
  final List<PersonCreditModel> people;
  final List<MediaSourceModel> mediaSources;
  final String? playlistItemId;

  bool get isPlayable => type == 'Movie' || type == 'Episode' || type == 'Video';
  bool get isSeries => type == 'Series';

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
    if (playedPercentage != null && playedPercentage! > 0) {
      return (playedPercentage! / 100.0).clamp(0.0, 1.0);
    }
    if (runTimeTicks != null && runTimeTicks! > 0 && playbackPositionTicks > 0) {
      return (playbackPositionTicks / runTimeTicks!).clamp(0.0, 1.0);
    }
    return 0.0;
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
    if (mediaSources.length > 1) badges.add('${mediaSources.length} 版本');
    return badges;
  }

  factory MediaItemModel.fromJson(Map<String, dynamic> j) {
    final userData = (j['UserData'] as Map<String, dynamic>?) ?? const {};
    final imageTags = (j['ImageTags'] as Map<String, dynamic>?) ?? const {};
    final backdrops = (j['BackdropImageTags'] as List<dynamic>?) ?? const [];
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
      collectionType: j['CollectionType']?.toString(),
      overview: j['Overview']?.toString(),
      productionYear: (j['ProductionYear'] as num?)?.toInt(),
      communityRating: (j['CommunityRating'] as num?)?.toDouble(),
      officialRating: j['OfficialRating']?.toString(),
      runTimeTicks: (j['RunTimeTicks'] as num?)?.toInt(),
      seriesId: j['SeriesId']?.toString(),
      seriesName: j['SeriesName']?.toString(),
      parentIndexNumber: (j['ParentIndexNumber'] as num?)?.toInt(),
      indexNumber: (j['IndexNumber'] as num?)?.toInt(),
      indexNumberEnd: (j['IndexNumberEnd'] as num?)?.toInt(),
      played: userData['Played'] == true,
      playedPercentage: (userData['PlayedPercentage'] as num?)?.toDouble(),
      playbackPositionTicks: (userData['PlaybackPositionTicks'] as num?)?.toInt() ?? 0,
      unplayedItemCount: (userData['UnplayedItemCount'] as num?)?.toInt(),
      isFavorite: userData['IsFavorite'] == true,
      primaryImageTag: imageTags['Primary']?.toString() ?? j['SeriesPrimaryImageTag']?.toString(),
      backdropImageTag: backdrops.isNotEmpty ? backdrops.first.toString() : null,
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
  final List<Map<String, dynamic>> externalSubtitles;
  final List<MediaSourceModel> allSources;
  final Map<String, dynamic>? inspectedJson;
  final String? dolbyVisionLabel;
  final String? spatialAudioLabel;

  factory PreparedPlaybackModel.fromJson(Map<String, dynamic> j) {
    final hdr = (j['hdr_decision'] as Map<String, dynamic>?) ?? const {};
    final audio = (j['audio_decision'] as Map<String, dynamic>?) ?? const {};
    final inspected = j['inspected'] as Map<String, dynamic>?;
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
