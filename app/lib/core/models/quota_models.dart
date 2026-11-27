// EmbyGo account limits, traffic cycle & download quota models.

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
