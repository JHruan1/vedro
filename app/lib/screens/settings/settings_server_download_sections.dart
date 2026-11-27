part of '../settings_screen.dart';

/// Servers, EmbyGo SpeedTest, Devices, Downloads & Subtitle Fonts settings sections.
extension _SettingsServerDownloadSectionsExt on _SettingsDetailPaneState {
  // 1. 服务器与线路
  Widget _buildServers(VedroAppState app) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          '服务器与线路',
          null,
          app.isSignedIn
              ? TextButton(
                  onPressed: app.logout,
                  child: const Text('断开连接', style: TextStyle(color: VedroTheme.danger, fontSize: 13)),
                )
              : null,
        ),
        ServerCardGrid(
          appState: app,
          onSelectServer: (srv) => app.restoreSavedServer(srv),
          onAddServer: () => widget.onOpenAddServer(),
        ),
      ],
    );
  }

  static String _speedRouteLabel(String raw) {
    return switch (raw) {
      'cdn' => '自建 CDN',
      'cloudflare' => 'Cloudflare',
      'entry' => '主入口',
      'direct' => '直连',
      '' => '默认',
      _ => raw,
    };
  }

  // 1a. 播放测速 (EmbyGo /emby-compat/speedtest)
  Widget _buildSpeedTest(VedroAppState app) {
    return ListenableBuilder(
      listenable: app.speedtestTickNotifier,
      builder: (context, _) => _buildSpeedTestInner(app),
    );
  }

  Widget _buildSpeedTestInner(VedroAppState app) {
    final skin = VedroSkin.of(context);
    final res = app.lastSpeedTestResult;
    final running = app.isSpeedTesting;
    final liveMbps = app.liveSpeedTestMbps;
    final effectiveMbps = (res?['effective_mbps'] as num?)?.toDouble();
    final measuredMbps = (res?['measured_mbps'] as num?)?.toDouble();
    final latencyMs =
        running ? app.speedTestLatencyMs : ((res?['latency_ms'] as num?)?.toDouble() ?? app.speedTestLatencyMs);
    final clientIp = running
        ? (app.speedTestClientIp ?? '').trim()
        : (res?['client_ip']?.toString() ?? app.speedTestClientIp ?? '').trim();
    final accountLimitBps = (res?['account_limit_bps'] as num?)?.toInt() ?? 0;
    final remHour = (res?['remaining_this_hour'] as num?)?.toInt() ?? -1;
    final remDay = (res?['remaining_today'] as num?)?.toInt() ?? -1;

    const tiers = <(String label, double mbps)>[
      ('720p', 5),
      ('1080p', 10),
      ('1080p 高码率 / 4K 压制', 25),
      ('4K 高码率', 60),
      ('4K 原盘 REMUX', 100),
    ];

    final quotaFooter = app.isAdmin
        ? '管理员不限测速次数'
        : [
            '每小时可测 6 次 · 每天 20 次',
            if (remHour >= 0) '本小时剩余 $remHour 次',
            if (remDay >= 0) '今日剩余 $remDay 次',
          ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('播放测速'),
        if (!app.isSignedIn)
          _GroupedCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  '请先连接媒体服务器后再运行线路测速',
                  style: TextStyle(color: skin.fg3, fontSize: 13.5),
                ),
              ),
            ],
          )
        else ...[
          _GroupedCard(
            key: const ValueKey('settings-speedtest-card'),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('speedtest-action-btn'),
                      style: FilledButton.styleFrom(
                        backgroundColor: running ? skin.surface3 : skin.primaryCtaBg,
                        foregroundColor: running ? skin.fg : skin.primaryCtaFg,
                      ),
                      onPressed: () {
                        if (running) {
                          app.cancelEmbyGoSpeedTest();
                        } else {
                          app.runEmbyGoSpeedTest();
                        }
                      },
                      icon: running
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: skin.fg,
                              ),
                            )
                          : const Icon(Icons.speed_rounded, size: 17),
                      label: Text(running ? '停止' : '开始测速'),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: running
                          ? Text(
                              liveMbps != null
                                  ? '${liveMbps.toStringAsFixed(1)} Mbps'
                                  : (latencyMs != null
                                      ? '延迟 ${latencyMs.round()} ms · 下载采样中…'
                                      : '正在连接视频流线路…'),
                              style: TextStyle(
                                color: skin.accent,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            )
                          : Text(
                              quotaFooter,
                              style: TextStyle(color: skin.fg3, fontSize: 12),
                            ),
                    ),
                  ],
                ),
              ),
              if (app.speedTestError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    app.speedTestError!,
                    style: const TextStyle(color: VedroTheme.danger, fontSize: 12.5),
                  ),
                ),
              if (res != null) ...[
                _InfoKVRow('线路', _speedRouteLabel(res['route']?.toString() ?? '')),
                _InfoKVRow('播放出口 IP', clientIp.isEmpty ? '—' : clientIp, mono: true),
                _InfoKVRow('网络延迟', latencyMs == null ? '—' : '${latencyMs.round()} ms'),
                _InfoKVRow(
                  '实测带宽',
                  measuredMbps == null ? '—' : '${measuredMbps.toStringAsFixed(1)} Mbps',
                ),
                _InfoKVRow(
                  '账号限速',
                  accountLimitBps > 0
                      ? '${(accountLimitBps / 1e6).toStringAsFixed(1)} Mbps'
                      : '不限',
                ),
                _InfoKVRow(
                  '预计播放速度',
                  effectiveMbps == null ? '—' : '${effectiveMbps.toStringAsFixed(1)} Mbps',
                  highlight: true,
                ),
              ],
            ],
          ),
          if (res != null) ...[
            const SizedBox(height: 16),
            _GroupedCard(
              children: [
                for (final (label, needMbps) in tiers)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              color: skin.fg,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              (effectiveMbps != null && effectiveMbps >= needMbps)
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_outlined,
                              size: 16,
                              color: (effectiveMbps != null && effectiveMbps >= needMbps)
                                  ? const Color(0xFF10B981)
                                  : skin.fg3,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              (effectiveMbps != null && effectiveMbps >= needMbps)
                                  ? '可流畅播放'
                                  : '可能卡顿',
                              style: TextStyle(
                                color: (effectiveMbps != null && effectiveMbps >= needMbps)
                                    ? const Color(0xFF10B981)
                                    : skin.fg3,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  // 1b. 设备管理 (EmbyGo /emby-compat/devices)
  Widget _buildDevices(VedroAppState app) {
    final skin = VedroSkin.of(context);
    final devices = app.userDevices;
    final curDevId = app.currentClientDeviceId;
    final quota = app.meQuota;
    final maxDevs = quota?.maxDevices ?? 10;
    final regCount = devices.isNotEmpty ? devices.length : (quota?.registeredDevices ?? 0);

    Future<void> confirmRemove(String devId, String label, bool isCurrent) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: skin.surface,
          title: Text('移除设备', style: TextStyle(color: skin.fg, fontSize: 16)),
          content: Text(
            isCurrent
                ? '确定移除当前设备「$label」？移除后本机将退出登录。'
                : '确定移除设备「$label」？该设备将退出登录并腾出名额。',
            style: TextStyle(color: skin.fg2, fontSize: 13.5),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: VedroTheme.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('移除'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      try {
        await app.removeUserDevice(deviceId: devId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('设备已移除')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('移除失败：${e.toString().replaceFirst('VedroCoreException: ', '')}')),
          );
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          '设备管理',
          app.isSignedIn
              ? '已登记 $regCount / ${app.isAdmin || maxDevs == 0 ? '不限制' : '$maxDevs 台'}'
              : null,
          app.isSignedIn
              ? IconButton(
                  key: const ValueKey('devices-refresh-btn'),
                  tooltip: '刷新设备列表',
                  icon: Icon(Icons.refresh_rounded, size: 19, color: skin.fg2),
                  onPressed: app.isLoadingDevices ? null : () => app.loadUserDevices(),
                )
              : null,
        ),
        if (!app.isSignedIn)
          _GroupedCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  '请先连接媒体服务器后查看已登录设备',
                  style: TextStyle(color: skin.fg3, fontSize: 13.5),
                ),
              ),
            ],
          )
        else
          _GroupedCard(
            key: const ValueKey('settings-devices-card'),
            children: [
              if (curDevId != null && curDevId.isNotEmpty)
                _InfoKVRow('本机设备 ID', curDevId, mono: true),
              if (app.isLoadingDevices && devices.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: skin.fg2),
                    ),
                  ),
                )
              else if (devices.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    '暂无已登记设备记录',
                    style: TextStyle(color: skin.fg3, fontSize: 13.5),
                  ),
                )
              else
                for (final d in devices)
                  () {
                    final devId = (d['DeviceId'] ?? d['Id'] ?? '').toString();
                    final label = (d['Name'] ?? d['DeviceName'] ?? d['AppName'] ?? devId)
                        .toString()
                        .trim();
                    final appName = (d['AppName'] ?? d['Client'] ?? '').toString().trim();
                    final appVer =
                        (d['AppVersion'] ?? d['ApplicationVersion'] ?? '').toString().trim();
                    final rawLast =
                        (d['DateLastActivity'] ?? d['LastActivityDate'] ?? '').toString().trim();
                    final lastStr = rawLast.isNotEmpty
                        ? rawLast.replaceFirst('T', ' ').split('.').first.replaceAll('Z', '')
                        : '';
                    final isCurrent = curDevId != null && devId == curDevId;
                    final meta = [
                      if (appName.isNotEmpty) appName,
                      if (appVer.isNotEmpty) appVer,
                      if (lastStr.isNotEmpty) lastStr,
                    ].join(' · ');

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? skin.accent.withValues(alpha: skin.isLight ? 0.14 : 0.20)
                                  : skin.subtleChipBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.devices_rounded,
                              size: 18,
                              color: isCurrent ? skin.accent : skin.fg2,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        label.isEmpty ? devId : label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: skin.fg,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (isCurrent) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: skin.accent
                                              .withValues(alpha: skin.isLight ? 0.14 : 0.22),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '当前设备',
                                          style: TextStyle(
                                            color: skin.isLight ? skin.accent : Colors.white,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  meta.isEmpty ? devId : meta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: skin.fg3,
                                    fontSize: 12,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (devId.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            TextButton(
                              key: ValueKey('remove-device-$devId'),
                              style: TextButton.styleFrom(
                                foregroundColor: VedroTheme.danger,
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () =>
                                  confirmRemove(devId, label.isEmpty ? devId : label, isCurrent),
                              child: const Text('移除', style: TextStyle(fontSize: 12.5)),
                            ),
                          ],
                        ],
                      ),
                    );
                  }(),
            ],
          ),
      ],
    );
  }

  // 2. 下载与缓存
  Widget _buildDownloads(VedroAppState app, VedroPreferences p) {
    return ListenableBuilder(
      listenable: app.downloadsTickNotifier,
      builder: (context, _) => _buildDownloadsInner(app, p),
    );
  }

  Widget _buildDownloadsInner(VedroAppState app, VedroPreferences p) {
    final skin = VedroSkin.of(context);
    final totalBytes = app.downloads.fold<int>(0, (sum, d) => sum + d.downloadedBytes);
    final dq = app.meQuota?.downloadQuota;
    final traffic = app.meQuota?.traffic;
    final imgStats = app.imageCacheStats;
    final imgFiles = (imgStats?['disk_files'] as num?)?.toInt() ?? 0;
    final imgBytes = (imgStats?['disk_bytes'] as num?)?.toInt() ?? 0;
    final imgMemEntries = (imgStats?['memory_entries'] as num?)?.toInt() ?? 0;
    final imgSizeLabel = fmtFileSize(imgBytes).isEmpty ? '0 B' : fmtFileSize(imgBytes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('下载与缓存'),
        const _GroupHeader('本地图片缓存'),
        KeyedSubtree(
          key: const ValueKey('settings-image-cache-card'),
          child: _GroupedCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.photo_library_outlined,
                            size: 19,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      '海报与剧照本地缓存',
                                      style: TextStyle(
                                        color: skin.fg,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      imgSizeLabel,
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.secondary,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  app.isLoadingImageCacheStats
                                      ? '正在统计缓存占用…'
                                      : '已缓存 $imgFiles 张本地图片 · 内存热缓存 $imgMemEntries 张（避免重复网络加载）',
                                  style: TextStyle(color: skin.fg3, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '刷新缓存统计',
                          visualDensity: VisualDensity.compact,
                          icon: app.isLoadingImageCacheStats
                              ? SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(strokeWidth: 1.8, color: skin.fg2),
                                )
                              : Icon(Icons.refresh_rounded, size: 18, color: skin.fg2),
                          onPressed:
                              app.isLoadingImageCacheStats ? null : () => app.loadImageCacheStats(),
                        ),
                        const SizedBox(width: 4),
                        OutlinedButton.icon(
                          key: const ValueKey('clear-image-cache-btn'),
                          onPressed: app.isClearingImageCache
                              ? null
                              : () async {
                                  final res = await app.clearImageCache();
                                  if (!mounted) return;
                                  final removed = (res['removed_files'] as num?)?.toInt() ?? 0;
                                  final freed = (res['freed_bytes'] as num?)?.toInt() ?? 0;
                                  final freedLabel =
                                      fmtFileSize(freed).isEmpty ? '0 B' : fmtFileSize(freed);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        removed > 0
                                            ? '已清理 $removed 张缓存图片，释放 $freedLabel'
                                            : '本地图片缓存已清空',
                                      ),
                                    ),
                                  );
                                },
                          icon: app.isClearingImageCache
                              ? const SizedBox(
                                  width: 13,
                                  height: 13,
                                  child: CircularProgressIndicator(strokeWidth: 1.8),
                                )
                              : const Icon(Icons.cleaning_services_rounded, size: 15),
                          label: const Text('清理缓存', style: TextStyle(fontSize: 12.5)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (dq != null && dq.enabled) ...[
          _buildDownloadQuotaCard(app, dq, traffic),
          const SizedBox(height: 18),
        ] else if (app.isSignedIn && !app.canDownloadAccount) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 18),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: skin.surface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: skin.border, width: 0.8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 17, color: skin.fg3),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '当前服务器账号未开放下载权限，详情页已隐藏下载按钮（仅支持管理本地已有离线缓存）。',
                    style: TextStyle(color: skin.fg2, fontSize: 12.5, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ],
        _GroupedCard(
          children: [
            _SwitchRow(
              title: '仅在 Wi-Fi 下下载',
              subtitle: '避免移动网络消耗流量',
              value: p.downloadWifiOnly,
              onChanged: (v) => _updatePrefs(p.copyWith(downloadWifiOnly: v)),
            ),
            _AppleMenuPickerRow<int>(
              title: '最大同时下载任务',
              value: p.downloadMaxConcurrent,
              items: const {1: '1 个任务', 2: '2 个任务', 3: '3 个任务'},
              onChanged: (v) => _updatePrefs(p.copyWith(downloadMaxConcurrent: v)),
            ),
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '离线缓存空间',
                        style: TextStyle(color: skin.fg, fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ),
                    Text(
                      fmtFileSize(totalBytes).isEmpty ? '0 B' : fmtFileSize(totalBytes),
                      style: TextStyle(
                        color: skin.fg2,
                        fontSize: 13,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '下载目录（已占用 ${fmtFileSize(totalBytes).isEmpty ? '0 B' : fmtFileSize(totalBytes)}）',
                      style: TextStyle(color: skin.fg2, fontSize: 12.5),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _downloadDirCtrl,
                            decoration: InputDecoration(hintText: app.downloadsDirectoryPath),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await NativePlaybackChannel.pickFiles(
                              allowDirectory: true,
                              title: '选择离线下载目录',
                            );
                            if (picked.isNotEmpty && mounted) {
                              _downloadDirCtrl.text = picked.first;
                              await _updatePrefs(
                                p.copyWith(downloadCustomDir: picked.first.trim()),
                              );
                            }
                          },
                          icon: const Icon(Icons.folder_open_rounded, size: 15),
                          label: const Text('浏览', style: TextStyle(fontSize: 13)),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => _updatePrefs(
                            p.copyWith(downloadCustomDir: _downloadDirCtrl.text.trim()),
                          ),
                          child: const Text('保存', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: _GroupHeader('下载队列 (${app.downloads.length})')),
            if (app.downloads.any((d) => d.status == 'downloading' || d.status == 'queued'))
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: skin.fg2,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: app.pauseAllDownloads,
                icon: const Icon(Icons.pause_rounded, size: 15),
                label: const Text('全部暂停', style: TextStyle(fontSize: 12)),
              ),
            if (app.downloads.any((d) => d.status == 'paused' || d.status == 'failed'))
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.secondary,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: app.resumeAllDownloads,
                icon: const Icon(Icons.play_arrow_rounded, size: 15),
                label: const Text('全部继续', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        if (app.downloads.isEmpty)
          _GroupedCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(28),
                child: Center(
                  child: Text('暂无离线下载任务', style: TextStyle(color: skin.fg3, fontSize: 13)),
                ),
              ),
            ],
          )
        else
          _GroupedCard(
            children: app.downloads.map((task) {
              final done = task.status == 'completed';
              final failed = task.status == 'failed';
              final paused = task.status == 'paused';
              final queued = task.status == 'queued';
              final downloading = task.status == 'downloading';
              final totalLabel = task.totalBytes > 0 ? ' / ${fmtFileSize(task.totalBytes)}' : '';
              final dlLabel = fmtFileSize(task.downloadedBytes).isEmpty
                  ? '0 B'
                  : fmtFileSize(task.downloadedBytes);
              final speedLabel = downloading && task.speedBytesPerSec > 0
                  ? ' · ${fmtFileSize(task.speedBytesPerSec)}/s'
                  : '';
              final statusText = done
                  ? '已完成 · ${fmtFileSize(task.downloadedBytes)}'
                  : failed
                      ? '失败：${task.error ?? '网络错误'}${task.downloadedBytes > 0 ? '（已保留 $dlLabel，可继续）' : ''}'
                      : paused
                          ? '已暂停 · $dlLabel$totalLabel（支持断点续传）'
                          : queued
                              ? '排队等待中${task.totalBytes > 0 ? ' · ${fmtFileSize(task.totalBytes)}' : ''}'
                              : (task.error != null && task.error!.isNotEmpty)
                                  ? '${task.error} · $dlLabel$totalLabel'
                                  : '下载中 ${(task.progress * 100).round()}% · $dlLabel$totalLabel$speedLabel';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      task.subtitle.isNotEmpty
                                          ? '${task.title} · ${task.subtitle}'
                                          : task.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: skin.fg,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  if (task.versionLabel.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: skin.subtleChipBg,
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(color: skin.border, width: 0.7),
                                      ),
                                      child: Text(
                                        task.versionLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: skin.fg2,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                statusText,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: failed
                                      ? VedroTheme.danger
                                      : (paused
                                          ? const Color(0xFFD97706)
                                          : (done ? const Color(0xFF059669) : skin.fg3)),
                                  fontSize: 12,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (downloading || queued)
                          IconButton(
                            tooltip: '暂停下载（保留进度）',
                            icon: Icon(Icons.pause_rounded, color: skin.fg2),
                            onPressed: () => app.pauseDownload(task.id),
                          ),
                        if (paused || failed)
                          IconButton(
                            tooltip: '断点续传 / 重试',
                            icon: Icon(
                              failed ? Icons.refresh_rounded : Icons.play_arrow_rounded,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                            onPressed: () => app.resumeDownload(task.id),
                          ),
                        if (done && task.filePath.isNotEmpty)
                          IconButton(
                            tooltip: '播放离线文件',
                            icon: Icon(Icons.play_arrow_rounded, color: skin.fg),
                            onPressed: () => Navigator.of(context).push(
                              vedroRoute(PlayerScreen(
                                item: MediaItemModel(
                                  id: task.itemId,
                                  name: task.subtitle.isNotEmpty
                                      ? '${task.title} · ${task.subtitle}'
                                      : task.title,
                                  seriesName: task.subtitle.isNotEmpty ? task.title : null,
                                  type: task.subtitle.isNotEmpty ? 'Episode' : 'Movie',
                                ),
                                appState: app,
                                localFilePath: task.filePath,
                                localPlaylistPaths: [task.filePath],
                              )),
                            ),
                          ),
                        IconButton(
                          tooltip: '删除',
                          icon: Icon(Icons.delete_outline_rounded, size: 19, color: skin.fg3),
                          onPressed: () => app.deleteDownload(task.id),
                        ),
                      ],
                    ),
                    if (!done) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: (task.progress > 0 || paused || failed || queued)
                              ? task.progress
                              : null,
                          minHeight: 3.5,
                          backgroundColor: skin.surface3,
                          color: failed
                              ? VedroTheme.danger
                              : (paused ? const Color(0xFFD97706) : null),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildDownloadQuotaCard(
    VedroAppState app,
    DownloadQuotaStatusModel dq,
    UserTrafficModel? traffic,
  ) {
    final skin = VedroSkin.of(context);
    final accent = Theme.of(context).colorScheme.secondary;
    final usedRatio = dq.monthlyUsedRatio;
    return Container(
      key: const ValueKey('settings-download-quota-card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: skin.surface,
        borderRadius: BorderRadius.circular(16),
        border: skin.cardBorder(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0x2234D399),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.cloud_download_outlined, size: 18, color: Color(0xFF10B981)),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '下载流量包',
                      style: TextStyle(color: skin.fg, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '仅限原文件下载，在线播放不限流量',
                      style: TextStyle(color: skin.fg3, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '刷新额度',
                visualDensity: VisualDensity.compact,
                icon: app.isLoadingQuota
                    ? SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 1.8, color: skin.fg2),
                      )
                    : Icon(Icons.refresh_rounded, size: 18, color: skin.fg2),
                onPressed: app.isLoadingQuota ? null : () => app.refreshMeQuota(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (dq.adminExempt)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0x1E34D399),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x4534D399), width: 0.8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified_user_outlined, size: 16, color: Color(0xFF10B981)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '管理员不限下载流量与并发数 · 在线播放不限流量',
                      style: TextStyle(color: Color(0xFF10B981), fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  fmtQuotaBytes(dq.totalRemainingBytes),
                  style: TextStyle(
                    color: skin.fg,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
                Text('当前总可用下载额度', style: TextStyle(color: skin.fg3, fontSize: 12.5)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '30 天周期免费额度${dq.monthlyOverride ? '（自定义）' : ''}',
                    style: TextStyle(color: skin.fg2, fontSize: 12.5),
                  ),
                ),
                Text(
                  '剩 ${fmtQuotaBytes(dq.monthlyRemainingBytes)} / ${fmtQuotaBytes(dq.monthlyQuotaBytes)}',
                  style: TextStyle(
                    color: skin.fg,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: 1.0 - usedRatio,
                minHeight: 5,
                backgroundColor: skin.surface3,
                color: dq.monthlyRemainingBytes > 0 ? accent : skin.fg3,
              ),
            ),
            if ((dq.cycleEnd ?? '').isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                '当前周期：${dq.cycleStart ?? '-'} 至 ${dq.cycleEnd}（到期自动重置）',
                style: TextStyle(
                  color: skin.fg3,
                  fontSize: 11.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: skin.surface2,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: skin.border, width: 0.7),
              ),
              child: Column(
                children: [
                  _quotaKvRow(
                    '一次性永久下载流量包',
                    fmtQuotaBytes(dq.packBytes),
                    subtitle: '一次性 · 永不过期 · 用完即止（优先消耗周期免费额度）',
                    valueColor: dq.packBytes > 0 ? skin.accent : skin.fg2,
                  ),
                  Divider(height: 16, color: skin.border),
                  _quotaKvRow(
                    '同时下载限制',
                    dq.maxConcurrentDownloads > 0
                        ? '进行中 ${dq.activeDownloads} / 最多 ${dq.maxConcurrentDownloads} 个文件'
                        : '不限制',
                    valueColor: dq.isConcurrencyFull ? const Color(0xFFD97706) : skin.fg,
                  ),
                  if (dq.inFlightBytes > 0) ...[
                    Divider(height: 16, color: skin.border),
                    _quotaKvRow(
                      '当前在途预占',
                      fmtQuotaBytes(dq.inFlightBytes),
                      subtitle: '下载结束后按实际传输字节结算并释放多余预占',
                      valueColor: const Color(0xFFD97706),
                    ),
                  ],
                  Divider(height: 16, color: skin.border),
                  _quotaKvRow(
                    '在线播放流量限制',
                    '不限制',
                    valueColor: const Color(0xFF10B981),
                  ),
                ],
              ),
            ),
          ],
          if (traffic != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                Text(
                  '本周期已下载 ${fmtQuotaBytes(dq.cycleDownloadBytes)}',
                  style: TextStyle(
                    color: skin.fg3,
                    fontSize: 11.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  '累计已下载 ${fmtQuotaBytes(traffic.downloadBytes)}',
                  style: TextStyle(
                    color: skin.fg3,
                    fontSize: 11.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  '累计在线播放 ${fmtQuotaBytes(traffic.streamBytes)}（不计费）',
                  style: TextStyle(
                    color: skin.fg3,
                    fontSize: 11.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _quotaKvRow(
    String label,
    String value, {
    String? subtitle,
    Color? valueColor,
  }) {
    final skin = VedroSkin.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: skin.fg2, fontSize: 12.5)),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: skin.fg3, fontSize: 11)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? skin.fg,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  // 3. 字体管理（内置实时字幕与界面排版预览窗 + 按系统匹配内置字体！）
  Widget _buildFonts(VedroAppState app, VedroPreferences p) {
    final skin = VedroSkin.of(context);
    final isMobileOs = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final previewFamily = p.subtitleFontFamily.isEmpty ? null : p.subtitleFontFamily;
    final builtIn = <(String, String)>[
      ('', '系统默认字体'),
      if (!kIsWeb && (Platform.isMacOS || Platform.isIOS)) ...[
        ('PingFang SC', '苹方简体 (PingFang SC)'),
        ('Hiragino Sans GB', '冬青黑体 (Hiragino Sans GB)'),
        ('SF Pro Display', 'SF Pro Display'),
      ] else if (!kIsWeb && Platform.isWindows) ...[
        ('Microsoft YaHei UI', '微软雅黑 (Microsoft YaHei UI)'),
        ('SimHei', '中易黑体 (SimHei)'),
      ] else ...[
        ('Roboto', 'Roboto'),
      ],
      ('Noto Sans CJK SC', '思源黑体 (Noto Sans CJK)'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('字体管理'),
        // Live Font Specimen & Cinema Subtitle Preview Card
        VedroAdaptiveSurface(
          key: const ValueKey('font-live-preview-card'),
          padding: const EdgeInsets.all(18),
          borderRadius: skin.cardRadius.clamp(10.0, 18.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.font_download_outlined, size: 16, color: skin.accent),
                  const SizedBox(width: 7),
                  Text(
                    p.subtitleFontFamily.isEmpty ? '系统默认' : p.subtitleFontFamily,
                    style: TextStyle(color: skin.fg, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '星际穿越 · Interstellar (2014)',
                style: TextStyle(
                  color: skin.fg,
                  fontFamily: previewFamily,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '4K UHD BluRay REMUX · Dolby Vision P7 · TrueHD 7.1 Atmos · 02:49:04',
                style: TextStyle(
                  color: skin.fg2,
                  fontFamily: previewFamily,
                  fontSize: 12.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF141826), Color(0xFF0A0D16)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      '不要温顺地走进那个良夜',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: previewFamily,
                        fontSize: (16 * p.subtitleFontScale).clamp(12.0, 26.0),
                        fontWeight: FontWeight.w600,
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 6, offset: Offset(0, 1.5)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Do not go gentle into that good night.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFFDDE3F0),
                        fontFamily: previewFamily,
                        fontSize: (13 * p.subtitleFontScale).clamp(10.0, 22.0),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _GroupedCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: isMobileOs
                  ? Row(
                      children: [
                        Expanded(
                          child: Text(
                            '导入字体文件 (.ttf / .otf / .ttc)',
                            style: TextStyle(
                              color: skin.fg,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            final picked = await NativePlaybackChannel.pickFiles(
                              extensions: const ['ttf', 'otf', 'ttc'],
                              title: '选择字幕字体文件',
                            );
                            if (picked.isNotEmpty) {
                              try {
                                final name = await app.importSubtitleFont(picked.first);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('已导入并选用字体：$name')),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(e.toString().replaceFirst('Exception: ', '')),
                                    ),
                                  );
                                }
                              }
                            }
                          },
                          icon: const Icon(Icons.folder_open_rounded, size: 15),
                          label: const Text('选择文件', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '导入本地字体 (.ttf / .otf / .ttc)',
                          style: TextStyle(
                            color: skin.fg,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _fontPathCtrl,
                                decoration: const InputDecoration(
                                  hintText: '/path/to/MySubtitleFont.ttf',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await NativePlaybackChannel.pickFiles(
                                  extensions: const ['ttf', 'otf', 'ttc'],
                                  title: '选择字幕字体文件',
                                );
                                if (picked.isNotEmpty) {
                                  try {
                                    final name = await app.importSubtitleFont(picked.first);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('已导入并选用字体：$name')),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content:
                                              Text(e.toString().replaceFirst('Exception: ', '')),
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                              icon: const Icon(Icons.folder_open_rounded, size: 15),
                              label: const Text('选择文件', style: TextStyle(fontSize: 13)),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () async {
                                if (_fontPathCtrl.text.trim().isEmpty) return;
                                try {
                                  final name =
                                      await app.importSubtitleFont(_fontPathCtrl.text.trim());
                                  if (mounted) {
                                    _fontPathCtrl.clear();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('已导入并选用字体：$name')),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(e.toString().replaceFirst('Exception: ', '')),
                                      ),
                                    );
                                  }
                                }
                              },
                              child: const Text('导入', style: TextStyle(fontSize: 13)),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _GroupHeader('可用字幕字体'),
        _GroupedCard(
          children: [
            for (final (family, label) in builtIn)
              _CheckRow(
                title: label,
                selected: p.subtitleFontFamily == family,
                onTap: () => _updatePrefs(p.copyWith(subtitleFontFamily: family)),
              ),
            for (final path in p.customFontPaths)
              () {
                final base = path.replaceAll('\\', '/').split('/').last;
                final stem = base.replaceAll(RegExp(r'\.(ttf|otf|ttc)$', caseSensitive: false), '');
                return _CheckRow(
                  title: base,
                  subtitle: path,
                  selected: p.subtitleFontFamily == stem,
                  onTap: () => _updatePrefs(p.copyWith(subtitleFontFamily: stem)),
                  trailing: IconButton(
                    icon: Icon(Icons.delete_outline_rounded, size: 18, color: skin.fg3),
                    onPressed: () => app.removeSubtitleFont(path),
                  ),
                );
              }(),
          ],
        ),
      ],
    );
  }
}
