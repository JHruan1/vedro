// Server profiles, route entries, capabilities, home section layout & aggregated search models.

import 'json_helpers.dart';

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
