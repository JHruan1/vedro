// Core data models mirroring `core/vedro-protocol`, `core/vedro-stream`, and `core/vedro-playback`.

const int kEmbyTicksPerSecond = 10000000;

Map<String, dynamic> asJsonMap(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const {};
}

Map<String, dynamic>? asJsonMapOrNull(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

List<dynamic> asJsonList(dynamic raw) => raw is List ? raw : const [];

int? asJsonInt(dynamic raw) {
  if (raw is int) return raw;
  if (raw is num && raw.isFinite) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim());
  return null;
}

double? asJsonDouble(dynamic raw) {
  if (raw is num && raw.isFinite) return raw.toDouble();
  if (raw is String) {
    final parsed = double.tryParse(raw.trim());
    if (parsed != null && parsed.isFinite) return parsed;
  }
  return null;
}

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

/// High-precision binary-unit formatter for download quota balances (e.g. `30.00 GB`, `500.00 GB`, `1.25 TB`).
String fmtQuotaBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  if (unit == 0) return '${value.round()} B';
  if (unit >= 3) return '${value.toStringAsFixed(2)} ${units[unit]}';
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}

String fmtTicksClock(int ticks) {
  if (ticks <= 0) return '00:00';
  final total = (ticks / kEmbyTicksPerSecond).floor();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  return h > 0
      ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
      : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String fmtCurrencyUsd(int? amount) {
  if (amount == null || amount <= 0) return '';
  if (amount >= 100000000) {
    return '\$${(amount / 100000000).toStringAsFixed(2)} 亿';
  }
  if (amount >= 10000) {
    return '\$${(amount / 10000).toStringAsFixed(1)} 万';
  }
  return '\$$amount';
}

String fmtCompactCount(int n) {
  if (n >= 10000) {
    return '${(n / 10000).toStringAsFixed(1)}w';
  }
  return '$n';
}

String localizeAirDay(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'monday':
      return '周一';
    case 'tuesday':
      return '周二';
    case 'wednesday':
      return '周三';
    case 'thursday':
      return '周四';
    case 'friday':
      return '周五';
    case 'saturday':
      return '周六';
    case 'sunday':
      return '周日';
    default:
      return raw.trim();
  }
}

String localizePersonRole(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  switch (raw.trim().toLowerCase()) {
    case 'actor':
      return '演员';
    case 'director':
      return '导演';
    case 'writer':
      return '编剧';
    case 'producer':
      return '制片人';
    case 'composer':
      return '配乐';
    case 'gueststar':
    case 'guest star':
      return '客串';
    case 'creator':
      return '主创';
    case 'conductor':
      return '指挥';
    case 'lyricist':
      return '作词';
    default:
      return raw.trim();
  }
}

class ServerLiveStatus {
  const ServerLiveStatus({
    required this.serverId,
    required this.online,
    this.latencyMs,
    this.version,
    this.movieCount,
    this.seriesCount,
    this.episodeCount,
    this.error,
  });

  final String serverId;
  final bool online;
  final int? latencyMs;
  final String? version;
  final int? movieCount;
  final int? seriesCount;
  final int? episodeCount;
  final String? error;

  factory ServerLiveStatus.fromJson(String id, Map<String, dynamic> j) => ServerLiveStatus(
        serverId: id,
        online: j['online'] == true,
        latencyMs: (j['latency_ms'] as num?)?.toInt(),
        version: j['version']?.toString(),
        movieCount: (j['movie_count'] as num?)?.toInt(),
        seriesCount: (j['series_count'] as num?)?.toInt(),
        episodeCount: (j['episode_count'] as num?)?.toInt(),
        error: j['error']?.toString(),
      );
}

class ResolvedArt {
  const ResolvedArt({required this.url, required this.isPoster, this.tinyUrl});
  final String url;

  /// True when only a 2:3 portrait poster exists for a 16:9 slot —
  /// callers render it with a blurred ambient backdrop + framed poster instead of cropping.
  final bool isPoster;

  /// Optional compact thumbnail (`maxWidth=140`) used for blurred ambient fill in `FramedPoster`.
  final String? tinyUrl;
}

class HomeSectionConfig {
  const HomeSectionConfig({
    required this.id,
    required this.visible,
  });

  final String id;
  final bool visible;

  String get title {
    switch (id) {
      case 'libraries':
        return '媒体库';
      case 'resume':
        return '继续播放';
      case 'next_up':
        return '接下来播放';
      case 'favorites':
        return '我的收藏';
      case 'latest':
        return '最新加入';
      case 'suggestions':
        return '猜你喜欢';
      default:
        return id;
    }
  }

  String get subtitle {
    switch (id) {
      case 'libraries':
        return '服务器上的全部媒体库入口与封面';
      case 'resume':
        return '未看完的影片与剧集进度';
      case 'next_up':
        return '追剧下一集自动衔接';
      case 'favorites':
        return '已收藏的电影与剧集';
      case 'latest':
        return '各媒体库近期入库内容';
      case 'suggestions':
        return '根据观影记录生成的推荐（默认关闭）';
      default:
        return '';
    }
  }

  HomeSectionConfig copyWith({bool? visible}) =>
      HomeSectionConfig(id: id, visible: visible ?? this.visible);

  Map<String, dynamic> toJson() => {'id': id, 'visible': visible};

  static const List<HomeSectionConfig> defaults = [
    HomeSectionConfig(id: 'libraries', visible: true),
    HomeSectionConfig(id: 'resume', visible: true),
    HomeSectionConfig(id: 'next_up', visible: true),
    HomeSectionConfig(id: 'favorites', visible: true),
    HomeSectionConfig(id: 'latest', visible: true),
    HomeSectionConfig(id: 'suggestions', visible: false),
  ];

  static List<HomeSectionConfig> normalize(List<dynamic>? raw) {
    final known = {for (final d in defaults) d.id: d};
    if (raw == null || raw.isEmpty) {
      return List<HomeSectionConfig>.from(defaults);
    }
    final seen = <String>{};
    final out = <HomeSectionConfig>[];
    for (final entry in raw) {
      if (entry is Map) {
        final id = entry['id']?.toString() ?? '';
        if (known.containsKey(id) && seen.add(id)) {
          out.add(HomeSectionConfig(
            id: id,
            visible: entry['visible'] == true,
          ));
        }
      }
    }
    for (final d in defaults) {
      if (seen.add(d.id)) out.add(d);
    }
    return out;
  }
}

/// Strip HTML tags & collapse messy scraper line breaks so overviews read cleanly.
String cleanOverviewText(String? raw) {
  if (raw == null) return '';
  var s = raw
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  return s;
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

class ServerRouteModel {
  ServerRouteModel({
    required this.id,
    required this.name,
    required this.url,
    this.proxyUrl,
    this.acceptInvalidCerts = false,
  });

  final String id;
  final String name;
  final String url;
  final String? proxyUrl;
  final bool acceptInvalidCerts;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        if (proxyUrl != null && proxyUrl!.trim().isNotEmpty) 'proxy_url': proxyUrl!.trim(),
        'accept_invalid_certs': acceptInvalidCerts,
      };

  factory ServerRouteModel.fromJson(Map<String, dynamic> j) => ServerRouteModel(
        id: (j['id'] ?? 'default').toString(),
        name: (j['name'] ?? '默认线路').toString(),
        url: (j['url'] ?? '').toString(),
        proxyUrl: j['proxy_url']?.toString(),
        acceptInvalidCerts: j['accept_invalid_certs'] == true,
      );
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
    this.routes = const [],
    this.activeRouteId,
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
  final List<ServerRouteModel> routes;
  final String? activeRouteId;

  ServerRouteModel? get activeRoute {
    if (routes.isEmpty) return null;
    if (activeRouteId != null) {
      for (final r in routes) {
        if (r.id == activeRouteId) return r;
      }
    }
    return routes.first;
  }

  factory SavedServerProfile.fromJson(Map<String, dynamic> j) {
    final parsedRoutes = ((j['routes'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ServerRouteModel.fromJson)
        .toList();
    final urlStr = (j['url'] ?? '').toString();
    final routes = parsedRoutes.isNotEmpty
        ? parsedRoutes
        : (urlStr.isNotEmpty
            ? [ServerRouteModel(id: 'default', name: '默认线路', url: urlStr)]
            : const <ServerRouteModel>[]);
    return SavedServerProfile(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      url: urlStr,
      dialect: (j['dialect'] ?? 'unknown').toString(),
      userId: j['user_id']?.toString(),
      username: j['username']?.toString(),
      accessToken: j['access_token']?.toString(),
      isAdmin: j['is_admin'] == true,
      lastConnectedAt: (j['last_connected_at'] as num?)?.toInt() ?? 0,
      routes: routes,
      activeRouteId: j['active_route_id']?.toString(),
    );
  }
}

class AggregatedSearchHit {
  AggregatedSearchHit({
    required this.serverId,
    required this.serverName,
    required this.id,
    required this.name,
    required this.type,
    this.productionYear,
    this.primaryImageTag,
    this.series,
  });

  final String serverId;
  final String serverName;
  final String id;
  final String name;
  final String type;
  final int? productionYear;
  final String? primaryImageTag;
  final String? series;

  factory AggregatedSearchHit.fromJson(Map<String, dynamic> j) => AggregatedSearchHit(
        serverId: (j['server_id'] ?? '').toString(),
        serverName: (j['server_name'] ?? '').toString(),
        id: (j['id'] ?? j['ItemId'] ?? j['Id'] ?? '').toString(),
        name: (j['name'] ?? j['Name'] ?? '').toString(),
        type: (j['type'] ?? j['Type'] ?? 'Movie').toString(),
        productionYear: asJsonInt(j['production_year'] ?? j['ProductionYear']),
        primaryImageTag: (j['primary_image_tag'] ?? j['PrimaryImageTag'])?.toString(),
        series: (j['series'] ?? j['Series'])?.toString(),
      );
}

class MediaStreamModel {
  MediaStreamModel({
    required this.index,
    required this.type,
    this.codec,
    this.profile,
    this.language,
    this.title,
    this.displayTitle,
    this.isDefault = false,
    this.isForced = false,
    this.isExternal = false,
    this.channels,
    this.channelLayout,
    this.sampleRate,
    this.bitDepth,
    this.bitRate,
    this.width,
    this.height,
    this.videoRange,
    this.videoRangeType,
    this.videoDoViTitle,
    this.dvProfile,
    this.colorSpace,
    this.colorTransfer,
    this.colorPrimaries,
    this.realFrameRate,
    this.averageFrameRate,
    this.pixelFormat,
    this.aspectRatio,
    this.level,
  });

  final int index;
  final String type;
  final String? codec;
  final String? profile;
  final String? language;
  final String? title;
  final String? displayTitle;
  final bool isDefault;
  final bool isForced;
  final bool isExternal;
  final int? channels;
  final String? channelLayout;
  final int? sampleRate;
  final int? bitDepth;
  final int? bitRate;
  final int? width;
  final int? height;
  final String? videoRange;
  final String? videoRangeType;
  final String? videoDoViTitle;
  final int? dvProfile;
  final String? colorSpace;
  final String? colorTransfer;
  final String? colorPrimaries;
  final double? realFrameRate;
  final double? averageFrameRate;
  final String? pixelFormat;
  final String? aspectRatio;
  final double? level;

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

  String get detailedSpec {
    final parts = <String>[];
    if (type.toLowerCase() == 'video') {
      if (width != null && height != null) parts.add('$width×$height');
      if (aspectRatio != null && aspectRatio!.isNotEmpty) parts.add(aspectRatio!);
      final fps = realFrameRate ?? averageFrameRate;
      if (fps != null && fps > 0) {
        parts.add('${fps.toStringAsFixed(fps == fps.roundToDouble() ? 0 : 2)} fps');
      }
      if (codec != null && codec!.isNotEmpty) parts.add(codec!.toUpperCase());
      if (profile != null && profile!.isNotEmpty) parts.add(profile!);
      if (bitDepth != null && bitDepth! > 0) parts.add('${bitDepth}bit');
      if (pixelFormat != null && pixelFormat!.isNotEmpty) parts.add(pixelFormat!);
      if (dvProfile != null) {
        parts.add('Dolby Vision P$dvProfile');
      } else if (videoDoViTitle != null && videoDoViTitle!.isNotEmpty) {
        parts.add(videoDoViTitle!);
      } else if (videoRangeType != null && videoRangeType!.isNotEmpty) {
        parts.add(videoRangeType!);
      } else if (videoRange != null && videoRange!.isNotEmpty) {
        parts.add(videoRange!);
      }
      if (colorSpace != null && colorSpace!.isNotEmpty) parts.add(colorSpace!);
      if (colorTransfer != null && colorTransfer!.isNotEmpty) parts.add(colorTransfer!);
      if (colorPrimaries != null && colorPrimaries!.isNotEmpty) parts.add(colorPrimaries!);
      if (bitRate != null && bitRate! > 0) {
        parts.add('${(bitRate! / 1000000).toStringAsFixed(1)} Mbps');
      }
    } else if (type.toLowerCase() == 'audio') {
      if (language != null && language!.isNotEmpty) parts.add(language!.toUpperCase());
      if (codec != null && codec!.isNotEmpty) parts.add(codec!.toUpperCase());
      if (channelLayout != null && channelLayout!.isNotEmpty) {
        parts.add(channelLayout!);
      } else if (channels != null && channels! > 0) {
        parts.add('${channels}ch');
      }
      if (sampleRate != null && sampleRate! > 0) {
        parts.add('${(sampleRate! / 1000).toStringAsFixed(1)} kHz');
      }
      if (bitRate != null && bitRate! > 0) {
        parts.add('${(bitRate! / 1000).round()} kbps');
      }
      if (isDefault) parts.add('默认');
    } else {
      if (language != null && language!.isNotEmpty) parts.add(language!.toUpperCase());
      if (title != null && title!.isNotEmpty) parts.add(title!);
      if (codec != null && codec!.isNotEmpty) parts.add(codec!.toUpperCase());
      if (isExternal) parts.add('外挂');
      if (isForced) parts.add('强制');
      if (isDefault) parts.add('默认');
    }
    return parts.isEmpty ? label : parts.join(' · ');
  }

  factory MediaStreamModel.fromJson(Map<String, dynamic> j) => MediaStreamModel(
        index: (j['Index'] as num?)?.toInt() ?? 0,
        type: (j['Type'] ?? '').toString(),
        codec: j['Codec']?.toString(),
        profile: j['Profile']?.toString(),
        language: j['Language']?.toString(),
        title: j['Title']?.toString(),
        displayTitle: j['DisplayTitle']?.toString(),
        isDefault: j['IsDefault'] == true,
        isForced: j['IsForced'] == true,
        isExternal: j['IsExternal'] == true,
        channels: (j['Channels'] as num?)?.toInt(),
        channelLayout: j['ChannelLayout']?.toString(),
        sampleRate: (j['SampleRate'] as num?)?.toInt(),
        bitDepth: (j['BitDepth'] as num?)?.toInt(),
        bitRate: (j['BitRate'] as num?)?.toInt(),
        width: (j['Width'] as num?)?.toInt(),
        height: (j['Height'] as num?)?.toInt(),
        videoRange: j['VideoRange']?.toString(),
        videoRangeType: j['VideoRangeType']?.toString(),
        videoDoViTitle: j['VideoDoViTitle']?.toString(),
        dvProfile: (j['DvProfile'] as num?)?.toInt(),
        colorSpace: j['ColorSpace']?.toString(),
        colorTransfer: j['ColorTransfer']?.toString(),
        colorPrimaries: j['ColorPrimaries']?.toString(),
        realFrameRate: (j['RealFrameRate'] as num?)?.toDouble(),
        averageFrameRate: (j['AverageFrameRate'] as num?)?.toDouble(),
        pixelFormat: j['PixelFormat']?.toString(),
        aspectRatio: j['AspectRatio']?.toString(),
        level: (j['Level'] as num?)?.toDouble(),
      );
}

class ResolvedMediaVersion {
  const ResolvedMediaVersion({
    required this.index,
    required this.source,
    required this.selectionKey,
    required this.seriesMatchSignature,
    required this.displayTitle,
    this.folderBadge,
  });

  final int index;
  final MediaSourceModel source;
  final String selectionKey;
  final String seriesMatchSignature;
  final String displayTitle;
  final String? folderBadge;
}

class MediaSourceModel {
  MediaSourceModel({
    required this.id,
    this.name,
    this.path,
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
  final String? path;
  final String? container;
  final int? size;
  final int? bitrate;
  final int? runTimeTicks;
  final String? directStreamUrl;
  final bool supportsDirectPlay;
  final List<MediaStreamModel> mediaStreams;

  List<MediaStreamModel> get videoStreams =>
      mediaStreams.where((s) => s.type.toLowerCase() == 'video').toList();

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

  /// Resolve a list of `MediaSourceModel`s into strictly unique, human-disambiguated version items.
  /// Fixes duplicate/empty `Name` or `Id` collisions when 4+ versions exist across folders on Emby/embygo,
  /// and strips noisy `'Preferred'` tokens plus leading `S01E01` prefixes on Series-level version pickers.
  static List<ResolvedMediaVersion> resolveVersions(
    List<MediaSourceModel> sources, {
    bool stripEpisodePrefix = false,
  }) {
    if (sources.isEmpty) return const [];

    final bareEpRe = RegExp(
      r'^(s\d{1,2}e\d{1,4}(-\d{1,4})?|ep?\s*\d{1,4}|第\s*\d{1,4}\s*[集话篇])$',
      caseSensitive: false,
    );

    String cleanVersionName(String raw, {required bool dropEpToken}) {
      if (raw.isEmpty) return '';
      final parts = raw
          .split(RegExp(r'\s*·\s*'))
          .map((e) => e.trim())
          .where((t) =>
              t.isNotEmpty &&
              t.toLowerCase() != 'preferred' &&
              t.toLowerCase() != 'default')
          .toList();
      if (dropEpToken) {
        while (parts.isNotEmpty && bareEpRe.hasMatch(parts.first)) {
          parts.removeAt(0);
        }
      }
      var joined = parts.join(' · ').trim();
      if (dropEpToken) {
        joined = joined
            .replaceFirst(
              RegExp(
                r'^(s\d{1,2}e\d{1,4}(-\d{1,4})?|ep?\s*\d{1,4}|第\s*\d{1,4}\s*[集话篇])\s*[\-·:|/]\s*',
                caseSensitive: false,
              ),
              '',
            )
            .trim();
      }
      return joined;
    }

    final rawInfos = List.generate(sources.length, (idx) {
      final s = sources[idx];
      final pathNorm = (s.path ?? '').replaceAll('\\', '/').trim();
      final segments = pathNorm.split('/').where((seg) => seg.trim().isNotEmpty).toList();
      final fileName = segments.isNotEmpty ? segments.last : '';
      final dotIdx = fileName.lastIndexOf('.');
      final fileStem = dotIdx > 0 ? fileName.substring(0, dotIdx) : fileName;

      String meaningfulFolder = '';
      String parentDirKey = '';
      if (segments.length >= 2) {
        final parent = segments[segments.length - 2];
        parentDirKey = segments.sublist(0, segments.length - 1).join('/').toLowerCase();
        final genericSeasonRe = RegExp(
          r'^(season\s*\d+|s\d+|specials|sp|ova|bdmv|stream|video_ts|disc\s*\d+)$',
          caseSensitive: false,
        );
        if (genericSeasonRe.hasMatch(parent.trim()) && segments.length >= 3) {
          meaningfulFolder = segments[segments.length - 3].trim();
        } else {
          meaningfulFolder = parent.trim();
        }
      }

      final rawNameRaw = (s.name ?? '').trim();
      final cleanedDisplayRaw = cleanVersionName(rawNameRaw, dropEpToken: stripEpisodePrefix);
      final cleanedSeriesRaw = cleanVersionName(rawNameRaw, dropEpToken: true);
      final nameIsGeneric = cleanedDisplayRaw.isEmpty || bareEpRe.hasMatch(cleanedDisplayRaw);

      // Extract quality / release group tokens from path when `name` is missing or generic
      final extractedTags = _extractReleaseSummary(
        fileStem: fileStem,
        folderName: meaningfulFolder,
        source: s,
      );

      final primaryCandidate = !nameIsGeneric
          ? cleanedDisplayRaw
          : (extractedTags.isNotEmpty
              ? extractedTags
              : (meaningfulFolder.isNotEmpty && stripEpisodePrefix
                  ? meaningfulFolder
                  : (fileStem.isNotEmpty
                      ? fileStem
                      : (s.container?.toUpperCase() ?? '版本 ${idx + 1}'))));

      // Episode-agnostic signature for matching the SAME version across all episodes of a Series
      final strippedStem = fileStem
          .toLowerCase()
          .replaceAll(RegExp(r's\d{1,2}e\d{1,4}(-\d{1,4})?'), '')
          .replaceAll(RegExp(r'\bep?\s*\d{1,4}\b'), '')
          .replaceAll(RegExp(r'[\[\(]\d{1,4}[\]\)]'), '')
          .replaceAll(RegExp(r'-\s*\d{1,4}\b'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final sigParts = <String>[
        if (parentDirKey.isNotEmpty) 'dir:$parentDirKey',
        if (cleanedSeriesRaw.isNotEmpty && !bareEpRe.hasMatch(cleanedSeriesRaw))
          'name:${cleanedSeriesRaw.toLowerCase()}',
        if (strippedStem.isNotEmpty && parentDirKey.isEmpty) 'stem:$strippedStem',
        if (s.videoStreams.isNotEmpty && s.videoStreams.first.height != null)
          'h:${s.videoStreams.first.height}',
        if (s.container != null && s.container!.isNotEmpty)
          'c:${s.container!.toLowerCase()}',
      ];
      final seriesSig = sigParts.isNotEmpty ? sigParts.join('|') : 'idx:$idx|id:${s.id}';

      return (
        idx: idx,
        source: s,
        primary: primaryCandidate,
        folder: meaningfulFolder,
        fileStem: fileStem,
        extractedTags: extractedTags,
        seriesSig: seriesSig,
      );
    });

    // Count collisions on primary title so 4+ versions with identical short `Name`s get disambiguated!
    final counts = <String, int>{};
    for (final info in rawInfos) {
      final k = info.primary.toLowerCase();
      counts[k] = (counts[k] ?? 0) + 1;
    }

    final usedTitles = <String, int>{};
    return rawInfos.map((info) {
      var title = info.primary;
      final isDuplicate = (counts[title.toLowerCase()] ?? 0) > 1;
      String? folderBadge;

      if (isDuplicate) {
        if (info.extractedTags.isNotEmpty &&
            info.extractedTags.toLowerCase() != title.toLowerCase()) {
          title = '$title · ${info.extractedTags}';
        } else if (info.folder.isNotEmpty &&
            info.folder.toLowerCase() != title.toLowerCase()) {
          title = '$title · ${info.folder}';
        } else if (info.fileStem.isNotEmpty &&
            info.fileStem.toLowerCase() != title.toLowerCase()) {
          title = info.fileStem;
        } else if (fmtFileSize(info.source.size).isNotEmpty) {
          title = '$title (${fmtFileSize(info.source.size)})';
        }
      } else if (info.folder.isNotEmpty &&
          !title.toLowerCase().contains(info.folder.toLowerCase()) &&
          sources.length > 3) {
        folderBadge = info.folder;
      }

      // Final guarantee: no two versions in the same selector can EVER display the exact same string!
      final seenCount = (usedTitles[title.toLowerCase()] ?? 0) + 1;
      usedTitles[title.toLowerCase()] = seenCount;
      if (seenCount > 1) {
        title = '$title · 版本 ${info.idx + 1}';
      }

      return ResolvedMediaVersion(
        index: info.idx,
        source: info.source,
        selectionKey: 'v${info.idx}::${info.source.id}::${info.source.path ?? title}',
        seriesMatchSignature: info.seriesSig,
        displayTitle: title,
        folderBadge: folderBadge,
      );
    }).toList();
  }

  static String _extractReleaseSummary({
    required String fileStem,
    required String folderName,
    required MediaSourceModel source,
  }) {
    final hay = '$folderName $fileStem';
    final lower = hay.toLowerCase();
    final tags = <String>[];

    // Release / subtitle group in leading `[Group]`
    final bracketGroup = RegExp(r'\[([^\[\]]{2,20})\]').firstMatch(hay)?.group(1)?.trim();
    if (bracketGroup != null &&
        !RegExp(r'^(1080p|2160p|720p|4k|hevc|x265|x264|aac|flac|chs|cht|mp4|mkv)$',
                caseSensitive: false)
            .hasMatch(bracketGroup)) {
      tags.add(bracketGroup);
    }

    final vHeight = source.videoStreams.isNotEmpty ? source.videoStreams.first.height : null;
    if (lower.contains('2160p') || lower.contains('4k') || lower.contains('uhd') || (vHeight != null && vHeight >= 2000)) {
      tags.add('4K');
    } else if (lower.contains('1080p') || (vHeight != null && vHeight >= 1000)) {
      tags.add('1080p');
    } else if (lower.contains('720p') || (vHeight != null && vHeight >= 700)) {
      tags.add('720p');
    }

    if (lower.contains('dovi') || lower.contains('.dv.') || lower.contains('dolby vision') || lower.contains('杜比')) {
      tags.add('Dolby Vision');
    } else if (lower.contains('hdr10+')) {
      tags.add('HDR10+');
    } else if (lower.contains('hdr')) {
      tags.add('HDR');
    }

    if (lower.contains('remux')) {
      tags.add('REMUX');
    } else if (lower.contains('bluray') || lower.contains('blu-ray') || lower.contains('bdrip')) {
      tags.add('BluRay');
    } else if (lower.contains('web-dl') || lower.contains('webdl')) {
      tags.add('WEB-DL');
    }

    if (lower.contains('atmos') || lower.contains('全景声')) {
      tags.add('Atmos');
    } else if (lower.contains('truehd')) {
      tags.add('TrueHD');
    } else if (lower.contains('dts')) {
      tags.add('DTS');
    }

    if (lower.contains('hevc') || lower.contains('x265') || lower.contains('h265')) {
      tags.add('HEVC');
    } else if (lower.contains('av1')) {
      tags.add('AV1');
    } else if (lower.contains('x264') || lower.contains('h264')) {
      tags.add('H.264');
    }

    if (lower.contains('国粤') || lower.contains('多音轨')) {
      tags.add('多音轨');
    } else if (lower.contains('国语') || lower.contains('mandarin')) {
      tags.add('国语');
    } else if (lower.contains('粤语') || lower.contains('cantonese')) {
      tags.add('粤语');
    }

    if (lower.contains('双语') || lower.contains('chs&eng')) {
      tags.add('中英双字');
    } else if (lower.contains('简繁')) {
      tags.add('简繁');
    } else if (lower.contains('chs') || lower.contains('简日') || lower.contains('简体')) {
      tags.add('简中');
    } else if (lower.contains('cht') || lower.contains('繁日') || lower.contains('繁体')) {
      tags.add('繁中');
    }

    if (tags.isNotEmpty) return tags.join(' · ');
    if (folderName.isNotEmpty) return folderName;
    return '';
  }

  factory MediaSourceModel.fromJson(Map<String, dynamic> j) => MediaSourceModel(
        id: (j['Id'] ?? '').toString(),
        name: j['Name']?.toString(),
        path: j['Path']?.toString(),
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

class ExternalLinkModel {
  const ExternalLinkModel({required this.name, required this.url});
  final String name;
  final String url;

  factory ExternalLinkModel.fromJson(Map<String, dynamic> j) => ExternalLinkModel(
        name: (j['Name'] ?? '').toString(),
        url: (j['Url'] ?? '').toString(),
      );
}

class ChapterModel {
  const ChapterModel({required this.startPositionTicks, required this.name});
  final int startPositionTicks;
  final String name;

  factory ChapterModel.fromJson(Map<String, dynamic> j) => ChapterModel(
        startPositionTicks: (j['StartPositionTicks'] as num?)?.toInt() ?? 0,
        name: (j['Name'] ?? '').toString().trim(),
      );
}

/// Format an ISO-8601 date string (`2024-03-01T00:00:00Z`) into clean `2024-03-01`.
String fmtIsoDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  final s = raw.trim();
  final tIdx = s.indexOf('T');
  final datePart = tIdx > 0 ? s.substring(0, tIdx) : s;
  if (datePart.length >= 10) return datePart.substring(0, 10);
  return datePart;
}

class MediaItemModel {
  MediaItemModel({
    required this.id,
    required this.name,
    required this.type,
    this.sortName,
    this.originalTitle,
    this.collectionType,
    this.overview,
    this.taglines = const [],
    this.productionYear,
    this.premiereDate,
    this.endDate,
    this.status,
    this.dateCreated,
    this.path,
    this.airTime,
    this.airDays = const [],
    this.productionLocations = const [],
    this.providerIds = const {},
    this.externalUrls = const [],
    this.remoteTrailers = const [],
    this.chapters = const [],
    this.aspectRatio,
    this.customRating,
    this.budget,
    this.revenue,
    this.awardSummary,
    this.airsBeforeSeasonNumber,
    this.airsBeforeEpisodeNumber,
    this.communityRating,
    this.criticRating,
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
    this.studios = const [],
    this.people = const [],
    this.mediaSources = const [],
    this.canDownload,
    this.playlistItemId,
  });

  final String id;
  final String name;
  final String type;
  final String? sortName;
  final String? originalTitle;
  final String? collectionType;
  final String? overview;
  final List<String> taglines;
  final int? productionYear;
  final String? premiereDate;
  final String? endDate;
  final String? status;
  final String? dateCreated;
  final String? path;
  final String? airTime;
  final List<String> airDays;
  final List<String> productionLocations;
  final Map<String, String> providerIds;
  final List<ExternalLinkModel> externalUrls;
  final List<ExternalLinkModel> remoteTrailers;
  final List<ChapterModel> chapters;
  final String? aspectRatio;
  final String? customRating;
  final int? budget;
  final int? revenue;
  final String? awardSummary;
  final int? airsBeforeSeasonNumber;
  final int? airsBeforeEpisodeNumber;
  final double? communityRating;
  final double? criticRating;
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
  final List<String> studios;
  final List<PersonCreditModel> people;
  final List<MediaSourceModel> mediaSources;
  final bool? canDownload;
  final String? playlistItemId;

  String get cleanOverview => cleanOverviewText(overview);

  bool get isPlayable =>
      type == 'Movie' || type == 'Episode' || type == 'Video' || type == 'MusicVideo';
  bool get isSeries => type == 'Series';
  bool get isFolderish =>
      type == 'Series' || type == 'Season' || type == 'BoxSet' || type == 'Folder';
  int get versionCount => mediaSourceCount ?? mediaSources.length;

  /// Localises scraper fallback `"Episode 3"` into `"第 3 集"` just like embygo Web.
  String get displayName {
    final m = RegExp(r'^Episode (\d+)$').firstMatch(name);
    return m != null ? '第 ${m.group(1)} 集' : name;
  }

  String get cardTitle => type == 'Episode' ? (seriesName ?? displayName) : name;

  String get cardSubtitle => cardSubtitleFor();

  String cardSubtitleFor({bool showYear = true, bool showRatingInText = true}) {
    switch (type) {
      case 'Episode':
        return [if (episodeCode != null) episodeCode!, displayName].join(' · ');
      case 'Season':
        return seriesName ?? '';
      case 'Series':
        return [
          if (showYear && productionYear != null) '$productionYear',
          if (childCount != null && childCount! > 0) '$childCount 季',
          if (recursiveItemCount != null && recursiveItemCount! > 0) '$recursiveItemCount 集',
          if (showRatingInText && communityRating != null && communityRating! > 0)
            '★ ${communityRating!.toStringAsFixed(1)}',
        ].join(' · ');
      default:
        return [
          if (showYear && productionYear != null) '$productionYear',
          if (showRatingInText && communityRating != null && communityRating! > 0)
            '★ ${communityRating!.toStringAsFixed(1)}',
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
    final userData = asJsonMap(j['UserData']);
    final imageTags = asJsonMap(j['ImageTags']);
    final backdrops = asJsonList(j['BackdropImageTags']);
    final parentBackdrops = asJsonList(j['ParentBackdropImageTags']);
    final sources = asJsonList(j['MediaSources'])
        .map(asJsonMapOrNull)
        .whereType<Map<String, dynamic>>()
        .map(MediaSourceModel.fromJson)
        .toList();
    final people = asJsonList(j['People'])
        .map(asJsonMapOrNull)
        .whereType<Map<String, dynamic>>()
        .map(PersonCreditModel.fromJson)
        .toList();

    return MediaItemModel(
      id: (j['Id'] ?? '').toString(),
      name: (j['Name'] ?? '').toString(),
      type: (j['Type'] ?? 'Movie').toString(),
      sortName: j['SortName']?.toString(),
      originalTitle: j['OriginalTitle']?.toString(),
      collectionType: j['CollectionType']?.toString(),
      overview: j['Overview']?.toString(),
      taglines: asJsonList(j['Taglines'])
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      productionYear: asJsonInt(j['ProductionYear']),
      premiereDate: j['PremiereDate']?.toString(),
      endDate: j['EndDate']?.toString(),
      status: j['Status']?.toString(),
      dateCreated: j['DateCreated']?.toString(),
      path: j['Path']?.toString(),
      airTime: j['AirTime']?.toString(),
      airDays: asJsonList(j['AirDays']).map((e) => e.toString()).toList(),
      productionLocations: asJsonList(j['ProductionLocations'])
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      providerIds: j['ProviderIds'] is Map
          ? (j['ProviderIds'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))
          : const {},
      externalUrls: asJsonList(j['ExternalUrls'])
          .map(asJsonMapOrNull)
          .whereType<Map<String, dynamic>>()
          .map(ExternalLinkModel.fromJson)
          .where((e) => e.url.isNotEmpty)
          .toList(),
      remoteTrailers: asJsonList(j['RemoteTrailers'])
          .map(asJsonMapOrNull)
          .whereType<Map<String, dynamic>>()
          .map(ExternalLinkModel.fromJson)
          .where((e) => e.url.isNotEmpty)
          .toList(),
      chapters: asJsonList(j['Chapters'])
          .map(asJsonMapOrNull)
          .whereType<Map<String, dynamic>>()
          .map(ChapterModel.fromJson)
          .toList(),
      aspectRatio: j['AspectRatio']?.toString(),
      customRating: j['CustomRating']?.toString(),
      budget: asJsonInt(j['Budget']),
      revenue: asJsonInt(j['Revenue']),
      awardSummary: j['AwardSummary']?.toString(),
      airsBeforeSeasonNumber: asJsonInt(j['AirsBeforeSeasonNumber']),
      airsBeforeEpisodeNumber: asJsonInt(j['AirsBeforeEpisodeNumber']),
      communityRating: asJsonDouble(j['CommunityRating']),
      criticRating: asJsonDouble(j['CriticRating']),
      officialRating: j['OfficialRating']?.toString(),
      runTimeTicks: asJsonInt(j['RunTimeTicks']),
      seriesId: j['SeriesId']?.toString(),
      seriesName: j['SeriesName']?.toString(),
      seasonId: j['SeasonId']?.toString(),
      seasonName: j['SeasonName']?.toString(),
      parentIndexNumber: asJsonInt(j['ParentIndexNumber']) ?? asJsonInt(j['SeasonNumber']),
      indexNumber: asJsonInt(j['IndexNumber']),
      indexNumberEnd: asJsonInt(j['IndexNumberEnd']),
      childCount: asJsonInt(j['ChildCount']),
      recursiveItemCount: asJsonInt(j['RecursiveItemCount']),
      mediaSourceCount: asJsonInt(j['MediaSourceCount']),
      sourceFolderCount: asJsonInt(j['SourceFolderCount']),
      played: userData['Played'] == true,
      playedPercentage: asJsonDouble(userData['PlayedPercentage']),
      playbackPositionTicks: asJsonInt(userData['PlaybackPositionTicks']) ?? 0,
      unplayedItemCount: asJsonInt(userData['UnplayedItemCount']),
      isFavorite: userData['IsFavorite'] == true,
      primaryImageTag: imageTags['Primary']?.toString(),
      thumbImageTag: imageTags['Thumb']?.toString(),
      logoImageTag: imageTags['Logo']?.toString(),
      backdropImageTag: backdrops.isNotEmpty
          ? backdrops.first.toString()
          : imageTags['Backdrop']?.toString(),
      seriesPrimaryImageTag: j['SeriesPrimaryImageTag']?.toString(),
      parentPrimaryImageItemId: j['ParentPrimaryImageItemId']?.toString(),
      parentPrimaryImageTag: j['ParentPrimaryImageTag']?.toString(),
      parentThumbItemId: j['ParentThumbItemId']?.toString(),
      parentThumbImageTag: j['ParentThumbImageTag']?.toString(),
      parentLogoItemId: j['ParentLogoItemId']?.toString(),
      parentLogoImageTag: j['ParentLogoImageTag']?.toString(),
      parentBackdropItemId: j['ParentBackdropItemId']?.toString(),
      parentBackdropImageTag: parentBackdrops.isNotEmpty ? parentBackdrops.first.toString() : null,
      genres: asJsonList(j['Genres']).map((e) => e.toString()).toList(),
      tags: asJsonList(j['Tags']).map((e) => e.toString()).toList(),
      studios: asJsonList(j['Studios'])
          .map((e) => e is Map ? (e['Name']?.toString() ?? '') : e.toString())
          .where((s) => s.isNotEmpty)
          .toList(),
      people: people,
      mediaSources: sources,
      canDownload: j['CanDownload'] is bool ? j['CanDownload'] as bool : null,
      playlistItemId: j['PlaylistItemId']?.toString(),
    );
  }
}

/// EmbyGo account limits returned by `GET /emby-compat/me/quota`.
class AccountLimitsModel {
  const AccountLimitsModel({
    this.isAdmin = false,
    this.maxActiveSessions = 0,
    this.maxDevices = 0,
    this.registeredDevices = 0,
    this.maxStreamConnections = 0,
    this.effectiveStreamConnections = 0,
    this.remoteClientBitrateLimit = 0,
    this.allowDownloads = false,
    this.enableAllFolders = false,
    this.enabledLibraryCount = 0,
    this.totalLibraryCount = 0,
  });

  final bool isAdmin;
  final int maxActiveSessions;
  final int maxDevices;
  final int registeredDevices;
  final int maxStreamConnections;
  final int effectiveStreamConnections;
  final int remoteClientBitrateLimit;
  final bool allowDownloads;
  final bool enableAllFolders;
  final int enabledLibraryCount;
  final int totalLibraryCount;

  factory AccountLimitsModel.fromJson(Map<String, dynamic> j) => AccountLimitsModel(
        isAdmin: j['is_admin'] == true,
        maxActiveSessions: (j['max_active_sessions'] as num?)?.toInt() ?? 0,
        maxDevices: (j['max_devices'] as num?)?.toInt() ?? 0,
        registeredDevices: (j['registered_devices'] as num?)?.toInt() ?? 0,
        maxStreamConnections: (j['max_stream_connections'] as num?)?.toInt() ?? 0,
        effectiveStreamConnections: (j['effective_stream_connections'] as num?)?.toInt() ?? 0,
        remoteClientBitrateLimit: (j['remote_client_bitrate_limit'] as num?)?.toInt() ?? 0,
        allowDownloads: j['allow_downloads'] == true,
        enableAllFolders: j['enable_all_folders'] == true,
        enabledLibraryCount: (j['enabled_library_count'] as num?)?.toInt() ?? 0,
        totalLibraryCount: (j['total_library_count'] as num?)?.toInt() ?? 0,
      );
}

class TrafficCycleModel {
  const TrafficCycleModel({
    this.anchorDate = '',
    this.anchorSet = false,
    this.anchorSource = '',
    this.cycleStart = '',
    this.cycleEnd = '',
    this.streamBytes = 0,
    this.downloadBytes = 0,
  });

  final String anchorDate;
  final bool anchorSet;
  final String anchorSource;
  final String cycleStart;
  final String cycleEnd;
  final int streamBytes;
  final int downloadBytes;

  factory TrafficCycleModel.fromJson(Map<String, dynamic> j) => TrafficCycleModel(
        anchorDate: (j['AnchorDate'] ?? '').toString(),
        anchorSet: j['AnchorSet'] == true,
        anchorSource: (j['AnchorSource'] ?? '').toString(),
        cycleStart: (j['CycleStart'] ?? '').toString(),
        cycleEnd: (j['CycleEnd'] ?? '').toString(),
        streamBytes: (j['StreamBytes'] as num?)?.toInt() ?? 0,
        downloadBytes: (j['DownloadBytes'] as num?)?.toInt() ?? 0,
      );
}

class UserTrafficModel {
  const UserTrafficModel({
    this.streamBytes = 0,
    this.downloadBytes = 0,
    this.updatedAt,
    this.cycle,
  });

  final int streamBytes;
  final int downloadBytes;
  final String? updatedAt;
  final TrafficCycleModel? cycle;

  factory UserTrafficModel.fromJson(Map<String, dynamic> j) => UserTrafficModel(
        streamBytes: (j['StreamBytes'] as num?)?.toInt() ?? 0,
        downloadBytes: (j['DownloadBytes'] as num?)?.toInt() ?? 0,
        updatedAt: j['UpdatedAt']?.toString(),
        cycle: j['Cycle'] is Map<String, dynamic>
            ? TrafficCycleModel.fromJson(j['Cycle'] as Map<String, dynamic>)
            : null,
      );
}

/// EmbyGo metered original-file download quota status (`DownloadQuotaStatus`).
/// Online streaming is never metered by this quota.
class DownloadQuotaStatusModel {
  const DownloadQuotaStatusModel({
    this.enabled = false,
    this.adminExempt = false,
    this.monthlyQuotaBytes = 0,
    this.monthlyOverride = false,
    this.monthlyUsedBytes = 0,
    this.monthlyRemainingBytes = 0,
    this.packBytes = 0,
    this.inFlightBytes = 0,
    this.activeDownloads = 0,
    this.maxConcurrentDownloads = 0,
    this.totalRemainingBytes = 0,
    this.cycleDownloadBytes = 0,
    this.cycleStart,
    this.cycleEnd,
    this.anchorDate,
    this.anchorSource,
  });

  final bool enabled;
  final bool adminExempt;
  final int monthlyQuotaBytes;
  final bool monthlyOverride;
  final int monthlyUsedBytes;
  final int monthlyRemainingBytes;
  final int packBytes;
  final int inFlightBytes;
  final int activeDownloads;
  final int maxConcurrentDownloads;
  final int totalRemainingBytes;
  final int cycleDownloadBytes;
  final String? cycleStart;
  final String? cycleEnd;
  final String? anchorDate;
  final String? anchorSource;

  bool get isUnlimited => !enabled || adminExempt;

  bool get isConcurrencyFull =>
      enabled && !adminExempt && maxConcurrentDownloads > 0 && activeDownloads >= maxConcurrentDownloads;

  bool canFitBytes(int? bytes) =>
      isUnlimited || bytes == null || bytes <= 0 || totalRemainingBytes >= bytes;

  double get monthlyUsedRatio =>
      monthlyQuotaBytes > 0 ? (monthlyUsedBytes / monthlyQuotaBytes).clamp(0.0, 1.0) : 0.0;

  factory DownloadQuotaStatusModel.fromJson(Map<String, dynamic> j) => DownloadQuotaStatusModel(
        enabled: j['Enabled'] == true,
        adminExempt: j['AdminExempt'] == true,
        monthlyQuotaBytes: (j['MonthlyQuotaBytes'] as num?)?.toInt() ?? 0,
        monthlyOverride: j['MonthlyOverride'] == true,
        monthlyUsedBytes: (j['MonthlyUsedBytes'] as num?)?.toInt() ?? 0,
        monthlyRemainingBytes: (j['MonthlyRemainingBytes'] as num?)?.toInt() ?? 0,
        packBytes: (j['PackBytes'] as num?)?.toInt() ?? 0,
        inFlightBytes: (j['InFlightBytes'] as num?)?.toInt() ?? 0,
        activeDownloads: (j['ActiveDownloads'] as num?)?.toInt() ?? 0,
        maxConcurrentDownloads: (j['MaxConcurrentDownloads'] as num?)?.toInt() ?? 0,
        totalRemainingBytes: (j['TotalRemainingBytes'] as num?)?.toInt() ?? 0,
        cycleDownloadBytes: (j['CycleDownloadBytes'] as num?)?.toInt() ?? 0,
        cycleStart: j['CycleStart']?.toString(),
        cycleEnd: j['CycleEnd']?.toString(),
        anchorDate: j['AnchorDate']?.toString(),
        anchorSource: j['AnchorSource']?.toString(),
      );
}

class MeQuotaModel {
  const MeQuotaModel({
    required this.limits,
    this.traffic,
    this.downloadQuota,
  });

  final AccountLimitsModel limits;
  final UserTrafficModel? traffic;
  final DownloadQuotaStatusModel? downloadQuota;

  int get maxDevices => limits.maxDevices;
  int get registeredDevices => limits.registeredDevices;

  factory MeQuotaModel.fromJson(Map<String, dynamic> j) => MeQuotaModel(
        limits: j['limits'] is Map<String, dynamic>
            ? AccountLimitsModel.fromJson(j['limits'] as Map<String, dynamic>)
            : const AccountLimitsModel(),
        traffic: j['traffic'] is Map<String, dynamic>
            ? UserTrafficModel.fromJson(j['traffic'] as Map<String, dynamic>)
            : null,
        downloadQuota: j['download_quota'] is Map<String, dynamic>
            ? DownloadQuotaStatusModel.fromJson(j['download_quota'] as Map<String, dynamic>)
            : null,
      );
}

class DownloadQuotaEventModel {
  const DownloadQuotaEventModel({
    required this.eventId,
    required this.kind,
    required this.bytesDelta,
    this.monthlyUsedBytes = 0,
    this.packUsedBytes = 0,
    this.note = '',
    this.createdAt = '',
  });

  final int eventId;
  final String kind;
  final int bytesDelta;
  final int monthlyUsedBytes;
  final int packUsedBytes;
  final String note;
  final String createdAt;

  String get kindLabel {
    switch (kind) {
      case 'download_settle':
        return '下载扣费';
      case 'pack_purchase':
        return '流量包购入';
      case 'admin_grant':
        return '管理员发放';
      case 'admin_adjust':
        return '管理员调整';
      default:
        return kind;
    }
  }

  factory DownloadQuotaEventModel.fromJson(Map<String, dynamic> j) => DownloadQuotaEventModel(
        eventId: (j['EventId'] as num?)?.toInt() ?? 0,
        kind: (j['Kind'] ?? '').toString(),
        bytesDelta: (j['BytesDelta'] as num?)?.toInt() ?? 0,
        monthlyUsedBytes: (j['MonthlyUsedBytes'] as num?)?.toInt() ?? 0,
        packUsedBytes: (j['PackUsedBytes'] as num?)?.toInt() ?? 0,
        note: (j['Note'] ?? '').toString(),
        createdAt: (j['CreatedAt'] ?? '').toString(),
      );
}

class PreparedPlaybackModel {
  PreparedPlaybackModel({
    required this.itemId,
    required this.mediaSourceId,
    required this.playSessionId,
    this.streamId,
    required this.proxyUrl,
    required this.usesStreamTicket,
    required this.hdrExplanation,
    required this.audioSummary,
    required this.backend,
    required this.mpvOptions,
    required this.externalSubtitles,
    this.textSubtitles = const [],
    required this.allSources,
    this.inspectedJson,
    this.dolbyVisionLabel,
    this.spatialAudioLabel,
  });

  final String itemId;
  final String mediaSourceId;
  final String playSessionId;
  final String? streamId;
  final String proxyUrl;
  final bool usesStreamTicket;
  final String hdrExplanation;
  final String audioSummary;
  final String backend;
  final Map<String, String> mpvOptions;
  final List<Map<String, dynamic>> externalSubtitles;
  final List<Map<String, dynamic>> textSubtitles;
  final List<MediaSourceModel> allSources;
  final Map<String, dynamic>? inspectedJson;
  final String? dolbyVisionLabel;
  final String? spatialAudioLabel;

  factory PreparedPlaybackModel.fromJson(Map<String, dynamic> j) {
    final hdr = asJsonMap(j['hdr_decision']);
    final audio = asJsonMap(j['audio_decision']);
    final inspected = asJsonMapOrNull(j['inspected']);
    final mpvOpts = <String, String>{};
    if (j['mpv_options'] is List) {
      for (final pair in (j['mpv_options'] as List)) {
        if (pair is List && pair.length >= 2) {
          mpvOpts[pair[0].toString()] = pair[1].toString();
        }
      }
    }
    String? dvLabel;
    if (inspected != null) {
      final dv = asJsonMapOrNull(inspected['dolby_vision']);
      if (dv != null) {
        final p = dv['dv_profile'];
        final c = dv['bl_signal_compatibility_id'];
        dvLabel = c != null && c != 0 ? 'Dolby Vision P$p.$c' : 'Dolby Vision P$p';
      }
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
      streamId: j['stream_id']?.toString(),
      proxyUrl: (j['proxy_url'] ?? '').toString(),
      usesStreamTicket: j['uses_stream_ticket'] == true,
      hdrExplanation: (hdr['explanation'] ?? 'Direct Play').toString(),
      audioSummary: (audio['summary'] ?? 'Auto Audio').toString(),
      backend: (hdr['backend'] ?? 'libmpv_gpu_next').toString(),
      mpvOptions: mpvOpts,
      externalSubtitles: asJsonList(j['external_subtitles'])
          .map(asJsonMapOrNull)
          .whereType<Map<String, dynamic>>()
          .toList(),
      textSubtitles: (() {
        final raw = asJsonList(j['text_subtitles'])
            .map(asJsonMapOrNull)
            .whereType<Map<String, dynamic>>()
            .toList();
        if (raw.isNotEmpty) return raw;
        return asJsonList(j['external_subtitles'])
            .map(asJsonMapOrNull)
            .whereType<Map<String, dynamic>>()
            .toList();
      })(),
      allSources: asJsonList(j['all_sources'])
          .map(asJsonMapOrNull)
          .whereType<Map<String, dynamic>>()
          .map(MediaSourceModel.fromJson)
          .toList(),
      inspectedJson: inspected,
      dolbyVisionLabel: dvLabel,
      spatialAudioLabel: spLabel,
    );
  }
}
