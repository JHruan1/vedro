import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import 'vedro_ui.dart';

/// Unified iOS-Caliber Administrator Console (`服务器管理台`).
///
/// Adapts seamlessly to both 360px–430px portrait mobile screens and wide desktops,
/// inheriting all 4 Master Themes (`沉浸影院` / `iOS 毛玻璃` / `iOS 液态玻璃` / `Material 设计`)
/// via `VedroAdaptiveSurface` and `VedroPullDownButton`.
/// Strictly mounted ONLY when `appState.isSignedIn && appState.isAdmin`.
class AdminConsolePane extends StatefulWidget {
  const AdminConsolePane({super.key, required this.appState});
  final VedroAppState appState;

  @override
  State<AdminConsolePane> createState() => _AdminConsolePaneState();
}

class _AdminConsolePaneState extends State<AdminConsolePane> {
  String _tab = 'overview'; // overview | sessions | devices | users | tasks | activity
  bool _refreshing = false;
  bool _scanning = false;
  String? _loadError;
  String _userFilter = '';
  String _deviceFilter = '';
  final TextEditingController _userSearchCtrl = TextEditingController();
  final TextEditingController _deviceSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _userSearchCtrl.dispose();
    _deviceSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _refreshing = true;
      _loadError = null;
    });
    try {
      await widget.appState.loadEmbyGoAdminDashboard();
    } catch (e) {
      if (mounted) {
        _loadError = e.toString().replaceFirst('VedroCoreException: ', '');
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _triggerScan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      await widget.appState.triggerLibraryRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已触发全库扫描')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('触发扫描失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _openCreateUserDialog() async {
    final skin = VedroSkin.of(context);
    final nameCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: skin.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(skin.cardRadius.clamp(16.0, 22.0)),
          side: BorderSide(color: skin.borderStrong, width: 0.9),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '新建服务器用户',
                  style: TextStyle(color: skin.fg, fontSize: 16.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                _IosDialogField(
                  controller: nameCtrl,
                  hintText: '输入用户名',
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 10),
                _IosDialogField(
                  controller: passCtrl,
                  hintText: '初始密码（可留空）',
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => Navigator.pop(ctx, true),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('取消', style: TextStyle(color: skin.fg2)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: skin.primaryCtaBg,
                        foregroundColor: skin.primaryCtaFg,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('创建', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      try {
        await widget.appState.adminCreateUser(nameCtrl.text.trim(), passCtrl.text);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已创建用户：${nameCtrl.text.trim()}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败：$e')));
        }
      }
    }
    nameCtrl.dispose();
    passCtrl.dispose();
  }

  List<Map<String, dynamic>> _extractList(dynamic raw) {
    if (raw is Map && raw['Items'] is List) {
      return (raw['Items'] as List).whereType<Map<String, dynamic>>().toList();
    }
    if (raw is List) {
      return raw.whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.appState.isSignedIn || !widget.appState.isAdmin) {
      return const SizedBox.shrink();
    }

    final skin = VedroSkin.of(context);
    final data = widget.appState.embygoAdminDashboard;
    final status = data?['status'] as Map<String, dynamic>?;
    final sessions = _extractList(data?['sessions']);
    final devices = _extractList(data?['devices']);
    final users = _extractList(data?['users']);
    final tasks = _extractList(data?['tasks']);
    final cardR = skin.cardRadius.clamp(14.0, 22.0);

    final metaChips = <String>[
      'v${status?['version'] ?? widget.appState.capabilities?.advertisedVersion ?? '-'}',
      if (status != null) (status['postgres_catalog'] == true ? 'PostgreSQL' : 'SQLite'),
      if (status != null) (status['transcoding_enabled'] == true ? '硬件转码' : 'DirectPlay 直连'),
    ];

    return Column(
      key: const ValueKey('admin-console-pane'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Responsive Hero Server Identity Card (Portrait-safe 2-tier on narrow screens)
        VedroAdaptiveSurface(
          borderRadius: cardR,
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;

              final serverTitleBlock = Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: skin.accent.withValues(alpha: skin.isLight ? 0.14 : 0.20),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(CupertinoIcons.shield_lefthalf_fill, size: 20, color: skin.accent),
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
                                widget.appState.activeServerDisplayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: skin.fg,
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_loadError != null)
                              const _StatusDotBadge(label: '异常', color: VedroTheme.danger)
                            else if (data != null)
                              const _StatusDotBadge(label: '在线', color: Color(0xFF34D399))
                            else
                              _StatusDotBadge(label: _refreshing ? '连接中' : '离线', color: skin.fg3),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          metaChips.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: skin.fg3, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    serverTitleBlock,
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _CompactActionBtn(
                            icon: CupertinoIcons.arrow_2_circlepath,
                            label: _scanning ? '正在全库扫描…' : '全库扫描',
                            primary: true,
                            accent: skin.accent,
                            loading: _scanning,
                            expanded: true,
                            onTap: _triggerScan,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _CompactActionBtn(
                            icon: CupertinoIcons.refresh,
                            label: '刷新状态',
                            loading: _refreshing,
                            expanded: true,
                            onTap: _reload,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: serverTitleBlock),
                  const SizedBox(width: 12),
                  _CompactActionBtn(
                    icon: CupertinoIcons.arrow_2_circlepath,
                    label: _scanning ? '扫描中…' : '全库扫描',
                    primary: true,
                    accent: skin.accent,
                    loading: _scanning,
                    onTap: _triggerScan,
                  ),
                  const SizedBox(width: 8),
                  _CompactActionBtn(
                    icon: CupertinoIcons.refresh,
                    label: '刷新',
                    loading: _refreshing,
                    onTap: _reload,
                  ),
                ],
              );
            },
          ),
        ),

        const SizedBox(height: 14),

        // 2. Scrollable iOS Capsule Tab Strip (Zero crushing on 360px portrait phones!)
        _AdminTabStrip(
          selected: _tab,
          tabs: [
            const ('overview', '概览', null),
            ('sessions', '会话', sessions.length),
            ('devices', '设备', devices.isNotEmpty ? devices.length : null),
            ('users', '用户', users.length),
            ('tasks', '任务', tasks.length),
            const ('activity', '日志', null),
          ],
          onSelected: (v) => setState(() => _tab = v),
        ),

        const SizedBox(height: 16),

        if (data == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: _refreshing
                  ? CircularProgressIndicator(strokeWidth: 2, color: skin.fg2)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.exclamationmark_triangle, size: 28, color: skin.fg3),
                        const SizedBox(height: 10),
                        Text(
                          _loadError != null ? '加载管理面板失败：$_loadError' : '无法获取服务器管理数据',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: skin.fg2, fontSize: 13.5),
                        ),
                        const SizedBox(height: 14),
                        FilledButton(onPressed: _reload, child: const Text('重试')),
                      ],
                    ),
            ),
          )
        else
          switch (_tab) {
            'sessions' => _buildSessions(sessions),
            'devices' => _buildAdminDevices(devices, sessions),
            'users' => _buildUsers(users),
            'tasks' => _buildTasks(tasks),
            'activity' => _buildActivity(_extractList(data['activity'])),
            _ => _buildOverview(data, sessions),
          },
      ],
    );
  }

  Widget _buildOverview(Map<String, dynamic> data, List<Map<String, dynamic>> allSessions) {
    final status = data['status'] as Map<String, dynamic>?;
    final counts = data['counts'] as Map<String, dynamic>?;
    final playing = (data['playing_sessions'] as List?) ?? const [];
    final libs = _extractList(data['libraries']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 2x2 on Portrait Phone, 4-up on Wide Desktop
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 560 ? 4 : 2;
            const gap = 10.0;
            final w = (constraints.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                _BentoMetricCard(
                  width: w,
                  label: '电影',
                  value: '${counts?['MovieCount'] ?? 0}',
                  icon: CupertinoIcons.film,
                  tint: const Color(0xFF38BDF8),
                ),
                _BentoMetricCard(
                  width: w,
                  label: '剧集',
                  value: '${counts?['SeriesCount'] ?? 0}',
                  icon: CupertinoIcons.tv,
                  tint: const Color(0xFFA78BFA),
                ),
                _BentoMetricCard(
                  width: w,
                  label: '分集总数',
                  value: '${counts?['EpisodeCount'] ?? 0}',
                  icon: CupertinoIcons.rectangle_stack,
                  tint: const Color(0xFF60A5FA),
                ),
                _BentoMetricCard(
                  width: w,
                  label: '播放 / 在线',
                  value: '${playing.length} / ${allSessions.length}',
                  icon: CupertinoIcons.play_circle,
                  tint: const Color(0xFF34D399),
                ),
              ],
            );
          },
        ),

        if (status != null) ...[
          const SizedBox(height: 14),
          _ConsolePanel(
            title: '索引与引擎',
            icon: CupertinoIcons.chart_bar_square,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cols = constraints.maxWidth >= 500 ? 3 : 2;
                const gap = 14.0;
                final cellW = (constraints.maxWidth - gap * (cols - 1)) / cols;
                final facts = [
                  ('索引条目', '${status['items'] ?? 0}'),
                  ('媒体文件', '${status['files'] ?? 0}'),
                  ('外挂字幕', '${status['subtitle_files'] ?? 0}'),
                  if (status['last_scan_attempt_at'] != null)
                    (
                      '最近扫描',
                      status['last_scan_attempt_at']
                          .toString()
                          .replaceFirst('T', ' ')
                          .split('.')
                          .first,
                    ),
                  if (status['built_at'] != null)
                    ('构建日期', status['built_at'].toString().split('T').first),
                ];
                final skin = VedroSkin.of(context);
                return Wrap(
                  spacing: gap,
                  runSpacing: 12,
                  children: facts.map((f) {
                    return SizedBox(
                      width: cellW,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.$1, style: TextStyle(color: skin.fg3, fontSize: 11.5)),
                          const SizedBox(height: 3),
                          Text(
                            f.$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: skin.fg,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],

        if (libs.isNotEmpty) ...[
          const SizedBox(height: 14),
          _ConsolePanel(
            title: '媒体库 (${libs.length})',
            icon: CupertinoIcons.folder,
            child: Column(
              children: [
                for (var i = 0; i < libs.length; i++) ...[
                  if (i > 0) Divider(height: 20, color: VedroSkin.of(context).border),
                  _buildLibraryRow(libs[i]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLibraryRow(Map<String, dynamic> lib) {
    final skin = VedroSkin.of(context);
    final id = (lib['ItemId'] ?? lib['Id'] ?? '').toString();
    final name = (lib['Name'] ?? '未命名').toString();
    final ctype = (lib['CollectionType'] ?? '').toString();
    final locations = ((lib['Locations'] as List?) ?? const []).map((e) => e.toString()).toList();
    final genCovers = lib['GenerateCovers'] == true;
    final icon = switch (ctype.toLowerCase()) {
      'movies' => CupertinoIcons.film,
      'tvshows' => CupertinoIcons.tv,
      'music' => CupertinoIcons.music_note_2,
      _ => CupertinoIcons.folder,
    };

    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: skin.accent.withValues(alpha: skin.isLight ? 0.12 : 0.18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: skin.accent),
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
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: skin.fg, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (ctype.isNotEmpty) ...[
                    const SizedBox(width: 7),
                    _MetaBadge(ctype),
                  ],
                ],
              ),
              if (locations.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  locations.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: skin.fg3,
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ],
          ),
        ),
        if (id.isNotEmpty && widget.appState.capabilities?.isEmbyGo == true) ...[
          const SizedBox(width: 8),
          Text('自动封面', style: TextStyle(color: skin.fg3, fontSize: 12)),
          const SizedBox(width: 4),
          Transform.scale(
            scale: 0.80,
            child: CupertinoSwitch(
              value: genCovers,
              activeTrackColor: skin.accent,
              onChanged: (v) => widget.appState.adminSetLibraryCovers(id, v),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSessions(List<Map<String, dynamic>> sessions) {
    if (sessions.isEmpty) {
      return const _EmptyConsoleState(
        icon: CupertinoIcons.device_laptop,
        message: '当前没有活跃会话',
      );
    }
    return _ConsolePanel(
      title: '活跃会话 (${sessions.length})',
      icon: CupertinoIcons.dot_radiowaves_left_right,
      child: Column(
        children: [
          for (var i = 0; i < sessions.length; i++) ...[
            if (i > 0) Divider(height: 22, color: VedroSkin.of(context).border),
            _buildSessionRow(sessions[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionRow(Map<String, dynamic> s) {
    final id = (s['Id'] ?? '').toString();
    final user = (s['UserName'] ?? '未知用户').toString();
    final client = (s['Client'] ?? '').toString();
    final device = (s['DeviceName'] ?? '').toString();
    final nowPlaying = s['NowPlayingItem'] as Map<String, dynamic>?;
    final playState = s['PlayState'] as Map<String, dynamic>?;
    final itemTitle = nowPlaying?['Name']?.toString();
    final posTicks = (playState?['PositionTicks'] as num?)?.toInt() ?? 0;
    final runTicks = (nowPlaying?['RunTimeTicks'] as num?)?.toInt() ?? 0;
    final progress = (posTicks > 0 && runTicks > 0) ? (posTicks / runTicks).clamp(0.0, 1.0) : 0.0;
    final isPaused = playState?['IsPaused'] == true;
    final playMethod = playState?['PlayMethod']?.toString() ?? '';

    final skin = VedroSkin.of(context);
    final deviceLabel = [client, device].where((e) => e.isNotEmpty).join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: itemTitle != null ? const Color(0x2234D399) : skin.subtleChipBg,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                artworkInitials(user),
                style: TextStyle(
                  color: itemTitle != null ? const Color(0xFF10B981) : skin.fg2,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        user,
                        style: TextStyle(color: skin.fg, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      if (deviceLabel.isNotEmpty) _MetaBadge(deviceLabel),
                      if (playMethod.isNotEmpty) _MetaBadge(playMethod),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    itemTitle != null
                        ? '${isPaused ? '已暂停' : '正在播放'} · $itemTitle'
                        : '空闲在线',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: itemTitle != null ? skin.fg2 : skin.fg3,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            if (id.isNotEmpty)
              _CompactActionBtn(
                icon: CupertinoIcons.xmark_circle,
                label: '断开',
                danger: true,
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: skin.surface,
                      title: Text('断开 $user 的会话？',
                          style: TextStyle(color: skin.fg, fontSize: 16)),
                      content: Text(
                        itemTitle != null ? '将中断对方正在播放的「$itemTitle」。' : '将强制结束该客户端会话。',
                        style: TextStyle(color: skin.fg2, fontSize: 13.5),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: VedroTheme.danger),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('断开'),
                        ),
                      ],
                    ),
                  );
                  if (ok != true || !mounted) return;
                  try {
                    await widget.appState.adminEndSession(id);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('断开会话失败：$e')),
                      );
                    }
                  }
                },
              ),
          ],
        ),
        if (itemTitle != null && progress > 0) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3.5,
                    backgroundColor: skin.borderStrong,
                    color: const Color(0xFF34D399),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${(progress * 100).round()}%',
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
    );
  }

  Widget _buildAdminDevices(
    List<Map<String, dynamic>> rawDevices,
    List<Map<String, dynamic>> sessions,
  ) {
    final skin = VedroSkin.of(context);
    final grouped = <String, ({
      String deviceId,
      String name,
      String client,
      String version,
      Map<String, String> users,
      String last,
      int playing,
    })>{};

    for (final entry in rawDevices) {
      final key = (entry['DeviceId'] ?? entry['Id'] ?? '').toString().trim();
      if (key.isEmpty) continue;
      final prev = grouped[key];
      final usersMap = prev != null ? Map<String, String>.from(prev.users) : <String, String>{};
      final uid = (entry['LastUserId'] ?? '').toString().trim();
      if (uid.isNotEmpty) {
        final uname = (entry['LastUserName'] ?? uid).toString();
        usersMap[uid] = uname;
      }
      grouped[key] = (
        deviceId: key,
        name: (entry['Name'] ?? prev?.name ?? '').toString(),
        client: (entry['AppName'] ?? prev?.client ?? '').toString(),
        version: (entry['AppVersion'] ?? prev?.version ?? '').toString(),
        users: usersMap,
        last: (entry['DateLastActivity'] ?? prev?.last ?? '').toString(),
        playing: prev?.playing ?? 0,
      );
    }

    for (final s in sessions) {
      final key = (s['DeviceId'] ?? s['Id'] ?? '').toString().trim();
      if (key.isEmpty) continue;
      final prev = grouped[key];
      final usersMap = prev != null ? Map<String, String>.from(prev.users) : <String, String>{};
      final uid = (s['UserId'] ?? '').toString().trim();
      if (uid.isNotEmpty) {
        usersMap[uid] = (s['UserName'] ?? uid).toString();
      }
      grouped[key] = (
        deviceId: (s['DeviceId'] ?? prev?.deviceId ?? '').toString(),
        name: (prev != null && prev.name.isNotEmpty) ? prev.name : (s['DeviceName'] ?? '').toString(),
        client: (prev != null && prev.client.isNotEmpty) ? prev.client : (s['Client'] ?? '').toString(),
        version: (prev != null && prev.version.isNotEmpty)
            ? prev.version
            : (s['ApplicationVersion'] ?? '').toString(),
        users: usersMap,
        last: (s['LastActivityDate'] ?? prev?.last ?? '').toString(),
        playing: (prev?.playing ?? 0) + (s['NowPlayingItem'] != null ? 1 : 0),
      );
    }

    final allRows = grouped.values.toList()
      ..sort((a, b) => b.last.compareTo(a.last));
    final q = _deviceFilter.trim().toLowerCase();
    final filtered = q.isEmpty
        ? allRows
        : allRows.where((d) {
            final hay = '${d.name} ${d.client} ${d.deviceId} ${d.users.values.join(' ')}'
                .toLowerCase();
            return hay.contains(q);
          }).toList();

    return _ConsolePanel(
      title: '已登记设备 (${allRows.length})',
      icon: CupertinoIcons.device_phone_portrait,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (allRows.length > 3) ...[
            SizedBox(
              height: 36,
              child: TextField(
                controller: _deviceSearchCtrl,
                onChanged: (v) => setState(() => _deviceFilter = v),
                style: TextStyle(color: skin.fg, fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: '搜索设备 / 客户端 / 用户…',
                  hintStyle: TextStyle(color: skin.fg3, fontSize: 13),
                  prefixIcon: Icon(CupertinoIcons.search, size: 15.5, color: skin.fg3),
                  prefixIconConstraints: const BoxConstraints(minWidth: 34),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  filled: true,
                  fillColor: skin.isLight
                      ? Colors.black.withValues(alpha: 0.04)
                      : Colors.white.withValues(alpha: 0.07),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                allRows.isEmpty ? '暂无已登记设备' : '无匹配设备',
                textAlign: TextAlign.center,
                style: TextStyle(color: skin.fg3, fontSize: 13),
              ),
            )
          else
            for (var i = 0; i < filtered.length; i++) ...[
              if (i > 0) Divider(height: 18, color: skin.border),
              () {
                final d = filtered[i];
                final clientStr = [
                  if (d.client.isNotEmpty) d.client,
                  if (d.version.isNotEmpty) d.version,
                ].join(' · ');
                final userNames = d.users.values.join('、');
                return Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: d.playing > 0
                            ? const Color(0xFF34D399).withValues(alpha: 0.16)
                            : skin.subtleChipBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        CupertinoIcons.device_phone_portrait,
                        size: 17,
                        color: d.playing > 0 ? const Color(0xFF34D399) : skin.fg2,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                d.name.isEmpty ? '未知设备' : d.name,
                                style: TextStyle(
                                  color: skin.fg,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (d.playing > 0)
                                _StatusDotBadge(
                                  label: '${d.playing} 播放中',
                                  color: const Color(0xFF34D399),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (userNames.isNotEmpty) '用户: $userNames',
                              if (clientStr.isNotEmpty) clientStr,
                              if (d.deviceId.isNotEmpty && d.name.isEmpty) d.deviceId,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: skin.fg3, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (d.deviceId.isNotEmpty && d.users.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: VedroTheme.danger,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () async {
                          final firstUser = d.users.entries.first;
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: skin.surface,
                              title: Text('移除设备「${d.name.isEmpty ? d.deviceId : d.name}」？',
                                  style: TextStyle(color: skin.fg, fontSize: 16)),
                              content: Text('该设备将被迫退出登录并释放名额。',
                                  style: TextStyle(color: skin.fg2, fontSize: 13.5)),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('取消'),
                                ),
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
                            await widget.appState.removeUserDevice(
                              targetUserId: firstUser.key,
                              deviceId: d.deviceId,
                            );
                            await _reload();
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('移除设备失败：$e')),
                              );
                            }
                          }
                        },
                        child: const Text('移除', style: TextStyle(fontSize: 12.5)),
                      ),
                    ],
                  ],
                );
              }(),
            ],
        ],
      ),
    );
  }

  Future<void> _openUserDevicesDialog(String uid, String userName) async {
    final skin = VedroSkin.of(context);
    List<Map<String, dynamic>> list = const [];
    bool loading = true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          if (loading) {
            loading = false;
            widget.appState
                .loadUserDevices(targetUserId: uid)
                .then((loaded) {
                  if (ctx.mounted) setModal(() => list = loaded);
                })
                .catchError((_) {
                  if (ctx.mounted) setModal(() => list = const []);
                });
          }
          return AlertDialog(
            backgroundColor: skin.surface,
            title: Text(
              '$userName · 已登录设备 (${list.length})',
              style: TextStyle(color: skin.fg, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            content: SizedBox(
              width: 420,
              child: list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        '该账号暂无登记设备',
                        style: TextStyle(color: skin.fg3, fontSize: 13.5),
                      ),
                    )
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: list.length,
                        separatorBuilder: (_, __) => Divider(height: 14, color: skin.border),
                        itemBuilder: (_, idx) {
                          final item = list[idx];
                          final devId = (item['DeviceId'] ?? item['Id'] ?? '').toString();
                          final name =
                              (item['Name'] ?? item['AppName'] ?? devId).toString().trim();
                          final app = [item['AppName'], item['AppVersion']]
                              .where((e) => e != null && e.toString().isNotEmpty)
                              .join(' · ');
                          return Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: TextStyle(
                                        color: skin.fg,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (app.isNotEmpty)
                                      Text(app, style: TextStyle(color: skin.fg3, fontSize: 11.5)),
                                  ],
                                ),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(foregroundColor: VedroTheme.danger),
                                onPressed: () async {
                                  try {
                                    await widget.appState.removeUserDevice(
                                      targetUserId: uid,
                                      deviceId: devId,
                                    );
                                    final updated =
                                        await widget.appState.loadUserDevices(targetUserId: uid);
                                    if (ctx.mounted) setModal(() => list = updated);
                                    if (mounted) unawaited(_reload());
                                  } catch (_) {}
                                },
                                child: const Text('移除'),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUsers(List<Map<String, dynamic>> users) {
    final skin = VedroSkin.of(context);
    final q = _userFilter.trim().toLowerCase();
    final filtered = q.isEmpty
        ? users
        : users.where((u) => (u['Name'] ?? '').toString().toLowerCase().contains(q)).toList();

    return _ConsolePanel(
      title: '用户账户 (${users.length})',
      icon: CupertinoIcons.person_2,
      trailing: _CompactActionBtn(
        icon: CupertinoIcons.person_add,
        label: '新建用户',
        primary: true,
        accent: skin.accent,
        onTap: _openCreateUserDialog,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (users.length > 4) ...[
            SizedBox(
              height: 36,
              child: TextField(
                controller: _userSearchCtrl,
                onChanged: (v) => setState(() => _userFilter = v),
                style: TextStyle(color: skin.fg, fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: '搜索用户名…',
                  hintStyle: TextStyle(color: skin.fg3, fontSize: 13),
                  prefixIcon: Icon(CupertinoIcons.search, size: 15.5, color: skin.fg3),
                  prefixIconConstraints: const BoxConstraints(minWidth: 34),
                  suffixIcon: _userFilter.isNotEmpty
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(CupertinoIcons.clear_circled_solid, size: 15.5, color: skin.fg3),
                          onPressed: () {
                            _userSearchCtrl.clear();
                            setState(() => _userFilter = '');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  filled: true,
                  fillColor: skin.isLight
                      ? Colors.black.withValues(alpha: 0.04)
                      : Colors.white.withValues(alpha: 0.07),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                users.isEmpty ? '未获取到用户列表' : '无匹配用户',
                textAlign: TextAlign.center,
                style: TextStyle(color: skin.fg3, fontSize: 13),
              ),
            )
          else
            for (var i = 0; i < filtered.length; i++) ...[
              if (i > 0) Divider(height: 18, color: skin.border),
              _buildUserRow(filtered[i]),
            ],
        ],
      ),
    );
  }

  Future<void> _confirmDeleteUser(String uid, String name) async {
    final skin = VedroSkin.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: skin.surface,
        title: Text('删除用户 $name？', style: TextStyle(color: skin.fg, fontSize: 16)),
        content: Text('此操作不可撤销。', style: TextStyle(color: skin.fg2, fontSize: 13.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: VedroTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await widget.appState.adminDeleteUser(uid);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除用户失败：$e')),
          );
        }
      }
    }
  }

  Widget _buildUserRow(Map<String, dynamic> u) {
    final uid = (u['Id'] ?? '').toString();
    final name = (u['Name'] ?? '').toString();
    final policy = Map<String, dynamic>.from((u['Policy'] as Map?) ?? const {});
    final isAdm = policy['IsAdministrator'] == true;
    final isDisabled = policy['IsDisabled'] == true;
    final canDl = policy['EnableContentDownloading'] == true;
    final isSelf = uid == widget.appState.userId;
    final isEmbyGo = widget.appState.capabilities?.isEmbyGo == true;
    final skin = VedroSkin.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 500;

        final actionMenuItems = <VedroDropdownItem<String>>[
          if (isEmbyGo && uid.isNotEmpty)
            VedroDropdownItem(
              value: 'devices',
              label: '已登录设备',
              icon: CupertinoIcons.device_phone_portrait,
              onTapOverride: () => _openUserDevicesDialog(uid, name),
            ),
          if (isEmbyGo && uid.isNotEmpty)
            VedroDropdownItem(
              value: 'quota',
              label: '下载权限与流量额度',
              icon: CupertinoIcons.chart_pie,
              onTapOverride: () => _openUserQuotaDialog(uid, name, policy),
            ),
          if (!isSelf && uid.isNotEmpty)
            VedroDropdownItem(
              value: 'toggle_disable',
              label: isDisabled ? '启用该账号' : '禁用该账号',
              icon: isDisabled ? CupertinoIcons.checkmark_circle : CupertinoIcons.nosign,
              onTapOverride: () async {
                policy['IsDisabled'] = !isDisabled;
                await widget.appState.adminSetUserPolicy(uid, policy);
              },
            ),
          if (!isSelf && uid.isNotEmpty)
            VedroDropdownItem(
              value: 'delete',
              label: '删除用户',
              icon: CupertinoIcons.trash,
              isDestructive: true,
              onTapOverride: () => _confirmDeleteUser(uid, name),
            ),
        ];

        return Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isAdm
                    ? skin.accent.withValues(alpha: skin.isLight ? 0.14 : 0.22)
                    : skin.subtleChipBg,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                artworkInitials(name),
                style: TextStyle(
                  color: isAdm ? skin.accent : skin.fg2,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: isDisabled ? skin.fg3 : skin.fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isSelf) const _MetaBadge('当前'),
                  if (isAdm) _StatusDotBadge(label: '管理员', color: skin.accent),
                  if (!isAdm && canDl)
                    const _StatusDotBadge(label: '可下载', color: Color(0xFF34D399)),
                  if (isDisabled) const _StatusDotBadge(label: '已禁用', color: VedroTheme.danger),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // On compact portrait screens, collapse multi-button clutter into ONE sleek iOS Pull-Down!
            if (compact) ...[
              if (actionMenuItems.isNotEmpty)
                VedroPullDownButton<String>(
                  height: 32,
                  displayLabelOverride: '管理',
                  value: '__none__',
                  items: actionMenuItems,
                  onChanged: (_) {},
                ),
            ] else ...[
              if (isEmbyGo && uid.isNotEmpty) ...[
                _CompactActionBtn(
                  icon: CupertinoIcons.chart_pie,
                  label: '下载额度',
                  onTap: () => _openUserQuotaDialog(uid, name, policy),
                ),
                const SizedBox(width: 6),
              ],
              if (!isSelf && uid.isNotEmpty) ...[
                _CompactActionBtn(
                  icon: isDisabled ? CupertinoIcons.checkmark_circle : CupertinoIcons.nosign,
                  label: isDisabled ? '启用' : '禁用',
                  onTap: () async {
                    policy['IsDisabled'] = !isDisabled;
                    await widget.appState.adminSetUserPolicy(uid, policy);
                  },
                ),
                const SizedBox(width: 6),
                _CircleIconBtn(
                  icon: CupertinoIcons.trash,
                  danger: true,
                  tooltip: '删除用户',
                  onTap: () => _confirmDeleteUser(uid, name),
                ),
              ],
            ],
          ],
        );
      },
    );
  }

  Future<void> _openUserQuotaDialog(
    String uid,
    String name,
    Map<String, dynamic> initialPolicy,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _UserDownloadQuotaDialog(
        appState: widget.appState,
        userId: uid,
        userName: name,
        initialPolicy: initialPolicy,
        onPolicyUpdated: _reload,
      ),
    );
  }

  Widget _buildTasks(List<Map<String, dynamic>> tasks) {
    if (tasks.isEmpty) {
      return const _EmptyConsoleState(
        icon: CupertinoIcons.clock,
        message: '暂无定时任务',
      );
    }
    return _ConsolePanel(
      title: '定时任务 (${tasks.length})',
      icon: CupertinoIcons.clock,
      child: Column(
        children: [
          for (var i = 0; i < tasks.length; i++) ...[
            if (i > 0) Divider(height: 18, color: VedroSkin.of(context).border),
            _buildTaskRow(tasks[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildTaskRow(Map<String, dynamic> t) {
    final key = (t['Key'] ?? t['Id'] ?? t['key'] ?? '').toString();
    final name = (t['Name'] ?? t['name'] ?? key).toString();
    final desc = (t['Description'] ?? '').toString();
    final state = (t['State'] ?? t['state'] ?? 'Idle').toString();
    final running = state.toLowerCase() == 'running';

    final skin = VedroSkin.of(context);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: running ? const Color(0xFF34D399) : skin.fg3,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: skin.fg, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                running ? '运行中…' : (desc.isNotEmpty ? desc : '空闲'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: skin.fg3, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _CompactActionBtn(
          icon: CupertinoIcons.play_fill,
          label: running ? '运行中' : '执行',
          loading: running,
          onTap: running || key.isEmpty
              ? null
              : () async {
                  await widget.appState.adminRunTask(key);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已启动任务：$name')),
                    );
                  }
                },
        ),
      ],
    );
  }

  Widget _buildActivity(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return const _EmptyConsoleState(
        icon: CupertinoIcons.doc_text,
        message: '暂无活动日志',
      );
    }
    return _ConsolePanel(
      title: '活动日志 (${items.length})',
      icon: CupertinoIcons.doc_text,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 16, color: VedroSkin.of(context).border),
            _buildActivityRow(items[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildActivityRow(Map<String, dynamic> e) {
    final name = (e['Name'] ?? e['ShortOverview'] ?? '-').toString();
    final date = (e['Date'] ?? '').toString().replaceFirst('T', ' ').split('.').first;
    final sev = (e['Severity'] ?? 'Info').toString();
    final sevColor = sev.toLowerCase().contains('err')
        ? VedroTheme.danger
        : (sev.toLowerCase().contains('warn') ? const Color(0xFFFBBF24) : const Color(0xFF38BDF8));

    final skin = VedroSkin.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5.5),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: sevColor, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: TextStyle(color: skin.fg, fontSize: 13.5, height: 1.35)),
              if (date.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  date,
                  style: TextStyle(
                    color: skin.fg3,
                    fontSize: 11.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        _StatusDotBadge(label: sev, color: sevColor),
      ],
    );
  }
}

class _AdminTabStrip extends StatelessWidget {
  const _AdminTabStrip({
    required this.selected,
    required this.tabs,
    required this.onSelected,
  });

  final String selected;
  final List<(String id, String label, int? count)> tabs;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return VedroAdaptiveSurface(
      borderRadius: 999,
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 480;
          Widget buildPill((String id, String label, int? count) tab, {required bool expand}) {
            final active = tab.$1 == selected;
            final pill = PressableScale(
              onTap: () => onSelected(tab.$1),
              borderRadius: BorderRadius.circular(999),
              hoverScale: 1.01,
              pressScale: 0.97,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 170),
                height: 32,
                padding: EdgeInsets.symmetric(horizontal: expand ? 6 : 14),
                decoration: BoxDecoration(
                  color: active ? skin.activePillBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tab.$2,
                      style: TextStyle(
                        color: active ? skin.activePillFg : skin.fg2,
                        fontSize: 12.5,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (tab.$3 != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        '${tab.$3}',
                        style: TextStyle(
                          color: active
                              ? skin.activePillFg.withValues(alpha: 0.85)
                              : skin.fg3,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
            return expand ? Expanded(child: pill) : pill;
          }

          if (wide) {
            return Row(
              children: [for (final t in tabs) buildPill(t, expand: true)],
            );
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  buildPill(tabs[i], expand: false),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BentoMetricCard extends StatelessWidget {
  const _BentoMetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return SizedBox(
      width: width,
      child: VedroAdaptiveSurface(
        borderRadius: skin.cardRadius.clamp(14.0, 20.0),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 15, color: tint),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: skin.fg,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: skin.fg3, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ConsolePanel extends StatelessWidget {
  const _ConsolePanel({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return VedroAdaptiveSurface(
      borderRadius: skin.cardRadius.clamp(14.0, 22.0),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16.5, color: skin.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: skin.fg,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          Divider(height: 22, color: skin.border),
          child,
        ],
      ),
    );
  }
}

class _EmptyConsoleState extends StatelessWidget {
  const _EmptyConsoleState({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return VedroAdaptiveSurface(
      borderRadius: skin.cardRadius.clamp(14.0, 22.0),
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 28, color: skin.fg3),
          const SizedBox(height: 10),
          Text(message, style: TextStyle(color: skin.fg3, fontSize: 13.5)),
        ],
      ),
    );
  }
}

class _StatusDotBadge extends StatelessWidget {
  const _StatusDotBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 2),
      decoration: BoxDecoration(
        color: skin.subtleChipBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: skin.fg2, fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _CircleIconBtn extends StatelessWidget {
  const _CircleIconBtn({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final fg = danger ? VedroTheme.danger : skin.fg2;
    final btn = PressableScale(
      onTap: onTap,
      hoverScale: 1.05,
      pressScale: 0.93,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: danger
              ? VedroTheme.danger.withValues(alpha: 0.12)
              : (skin.isLight
                  ? Colors.black.withValues(alpha: 0.05)
                  : Colors.white.withValues(alpha: 0.08)),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 15, color: fg),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: btn) : btn;
  }
}

class _CompactActionBtn extends StatelessWidget {
  const _CompactActionBtn({
    required this.icon,
    required this.label,
    this.onTap,
    this.primary = false,
    this.danger = false,
    this.accent,
    this.loading = false,
    this.expanded = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool danger;
  final Color? accent;
  final bool loading;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final bg = danger
        ? VedroTheme.danger.withValues(alpha: 0.14)
        : (primary
            ? (skin.ctaStyle == 'contrast' && !skin.isLight
                ? Colors.white
                : (accent ?? skin.accent))
            : (skin.isLight
                ? Colors.black.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.09)));
    final fg = danger
        ? VedroTheme.danger
        : (primary ? VedroTheme.highContrastOn(bg) : skin.fg);

    final pill = PressableScale(
      onTap: loading ? null : onTap,
      hoverScale: 1.02,
      pressScale: 0.96,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null ? skin.subtleChipBg : bg,
          borderRadius: BorderRadius.circular(999),
          border: (primary || danger)
              ? null
              : Border.all(
                  color: skin.isLight ? skin.border : Colors.white.withValues(alpha: 0.12),
                  width: 0.7,
                ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 1.7, color: fg),
              )
            else
              Icon(icon, size: 14, color: onTap == null ? skin.fg3 : fg),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onTap == null ? skin.fg3 : fg,
                  fontSize: 12.5,
                  fontWeight: primary ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return expanded ? SizedBox(width: double.infinity, child: pill) : pill;
  }
}

class _IosDialogField extends StatelessWidget {
  const _IosDialogField({
    required this.controller,
    required this.hintText,
    this.autofocus = false,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final bool autofocus;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return SizedBox(
      height: 40,
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        style: TextStyle(color: skin.fg, fontSize: 13.5),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: skin.fg3, fontSize: 13),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          filled: true,
          fillColor: skin.isLight
              ? Colors.black.withValues(alpha: 0.045)
              : Colors.white.withValues(alpha: 0.08),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: BorderSide(color: skin.accent, width: 1.1),
          ),
        ),
      ),
    );
  }
}

class _UserDownloadQuotaDialog extends StatefulWidget {
  const _UserDownloadQuotaDialog({
    required this.appState,
    required this.userId,
    required this.userName,
    required this.initialPolicy,
    required this.onPolicyUpdated,
  });

  final VedroAppState appState;
  final String userId;
  final String userName;
  final Map<String, dynamic> initialPolicy;
  final VoidCallback onPolicyUpdated;

  @override
  State<_UserDownloadQuotaDialog> createState() => _UserDownloadQuotaDialogState();
}

class _UserDownloadQuotaDialogState extends State<_UserDownloadQuotaDialog> {
  static const int _bytesPerGiB = 1024 * 1024 * 1024;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _enableDownload = false;
  DownloadQuotaStatusModel? _quota;
  UserTrafficModel? _traffic;
  List<DownloadQuotaEventModel> _events = const [];

  final TextEditingController _packGiBCtrl = TextEditingController(text: '500');
  final TextEditingController _packNoteCtrl = TextEditingController();
  final TextEditingController _monthlyGiBCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _enableDownload = widget.initialPolicy['EnableContentDownloading'] == true;
    _load();
  }

  @override
  void dispose() {
    _packGiBCtrl.dispose();
    _packNoteCtrl.dispose();
    _monthlyGiBCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.appState.adminGetUserDetail(widget.userId);
      final events = await widget.appState.adminGetDownloadQuotaEvents(widget.userId, limit: 15);
      if (!mounted) return;
      final p = detail['Policy'] as Map<String, dynamic>?;
      if (p != null && p.containsKey('EnableContentDownloading')) {
        _enableDownload = p['EnableContentDownloading'] == true;
      }
      _quota = detail['DownloadQuota'] is Map<String, dynamic>
          ? DownloadQuotaStatusModel.fromJson(detail['DownloadQuota'] as Map<String, dynamic>)
          : null;
      _traffic = detail['Traffic'] is Map<String, dynamic>
          ? UserTrafficModel.fromJson(detail['Traffic'] as Map<String, dynamic>)
          : null;
      _events = events;
      if (_quota != null && _quota!.monthlyQuotaBytes > 0) {
        final gib = _quota!.monthlyQuotaBytes / _bytesPerGiB;
        _monthlyGiBCtrl.text =
            gib == gib.roundToDouble() ? '${gib.round()}' : gib.toStringAsFixed(1);
      }
    } catch (e) {
      if (mounted) _error = e.toString().replaceFirst('VedroCoreException: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleDownloadPermission(bool value) async {
    setState(() => _saving = true);
    try {
      await widget.appState.adminSetUserPolicy(
        widget.userId,
        {'EnableContentDownloading': value},
      );
      if (mounted) {
        setState(() => _enableDownload = value);
        widget.onPolicyUpdated();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '更新权限失败：$e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _adjustPackGiB(double gib) async {
    if (!gib.isFinite || gib.abs() > 1024 * 1024) {
      if (mounted) setState(() => _error = '请输入有效的 GiB 数值');
      return;
    }
    final bytes = (gib * _bytesPerGiB).round();
    if (bytes == 0) return;
    if (!mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.appState.adminAdjustDownloadPack(
        widget.userId,
        bytes,
        note: _packNoteCtrl.text.trim(),
      );
      if (!mounted) return;
      _packNoteCtrl.clear();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '调整流量包失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveMonthlyOverride(int? bytes) async {
    if (!mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.appState.adminSetMonthlyDownloadQuota(widget.userId, bytes);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '更新周期额度失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final dq = _quota;
    return Dialog(
      backgroundColor: skin.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(skin.cardRadius.clamp(16.0, 22.0)),
        side: BorderSide(color: skin.borderStrong, width: 0.9),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
              child: Row(
                children: [
                  Icon(CupertinoIcons.chart_pie_fill, size: 18, color: skin.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '下载额度 · ${widget.userName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: skin.fg, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: Icon(CupertinoIcons.xmark_circle_fill, size: 20, color: skin.fg3),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: skin.border),
            Flexible(
              child: _loading
                  ? Padding(
                      padding: const EdgeInsets.all(42),
                      child: CircularProgressIndicator(strokeWidth: 2, color: skin.fg2),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_error != null) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: VedroTheme.danger.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _error!,
                                style: const TextStyle(color: VedroTheme.danger, fontSize: 12.5),
                              ),
                            ),
                          ],

                          // Clean iOS Switch Row (Zero internal variable names!)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: skin.surface2,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '允许离线下载原文件',
                                    style: TextStyle(
                                      color: skin.fg,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Transform.scale(
                                  scale: 0.85,
                                  child: CupertinoSwitch(
                                    value: _enableDownload,
                                    activeTrackColor: skin.accent,
                                    onChanged: _saving ? null : _toggleDownloadPermission,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (dq != null) ...[
                            const SizedBox(height: 14),
                            // Visual 3-Column Summary Cards
                            Row(
                              children: [
                                Expanded(
                                  child: _MiniQuotaStat(
                                    label: '总可用',
                                    value: dq.adminExempt
                                        ? '不限'
                                        : fmtQuotaBytes(dq.totalRemainingBytes),
                                    accent: const Color(0xFF34D399),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _MiniQuotaStat(
                                    label: '周期剩余',
                                    value: fmtQuotaBytes(dq.monthlyRemainingBytes),
                                    accent: skin.accent,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _MiniQuotaStat(
                                    label: '永久流量包',
                                    value: fmtQuotaBytes(dq.packBytes),
                                    accent: const Color(0xFFA78BFA),
                                  ),
                                ),
                              ],
                            ),
                            if (_traffic != null || dq.activeDownloads > 0) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  _MetaBadge(
                                    '并发 ${dq.activeDownloads}/${dq.maxConcurrentDownloads > 0 ? dq.maxConcurrentDownloads : '∞'}',
                                  ),
                                  if (_traffic != null)
                                    _MetaBadge('累计已下载 ${fmtQuotaBytes(_traffic!.downloadBytes)}'),
                                ],
                              ),
                            ],

                            const SizedBox(height: 18),
                            Text(
                              '发放永久流量包',
                              style: TextStyle(
                                color: skin.fg2,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final preset in const [50.0, 100.0, 500.0, 1024.0])
                                  _CompactActionBtn(
                                    icon: CupertinoIcons.plus,
                                    label: preset >= 1024 ? '1 TB' : '${preset.round()} GB',
                                    primary: preset == 500.0,
                                    accent: skin.accent,
                                    loading: _saving,
                                    onTap: () => _adjustPackGiB(preset),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                SizedBox(
                                  width: 96,
                                  child: _IosDialogField(
                                    controller: _packGiBCtrl,
                                    hintText: 'GiB (±)',
                                    keyboardType: const TextInputType.numberWithOptions(
                                      signed: true,
                                      decimal: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _IosDialogField(
                                    controller: _packNoteCtrl,
                                    hintText: '备注（选填）',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _CompactActionBtn(
                                  icon: CupertinoIcons.checkmark_alt,
                                  label: '调整',
                                  primary: true,
                                  accent: skin.accent,
                                  loading: _saving,
                                  onTap: () {
                                    final v = double.tryParse(_packGiBCtrl.text.trim());
                                    if (v != null && v.isFinite && v != 0) _adjustPackGiB(v);
                                  },
                                ),
                              ],
                            ),

                            const SizedBox(height: 18),
                            Text(
                              '每 30 天免费额度 (GiB)',
                              style: TextStyle(
                                color: skin.fg2,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _IosDialogField(
                                    controller: _monthlyGiBCtrl,
                                    hintText: '留空跟随全局默认',
                                    keyboardType:
                                        const TextInputType.numberWithOptions(decimal: true),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _CompactActionBtn(
                                  icon: CupertinoIcons.checkmark_alt,
                                  label: '保存',
                                  primary: true,
                                  accent: skin.accent,
                                  loading: _saving,
                                  onTap: () {
                                    final v = double.tryParse(_monthlyGiBCtrl.text.trim());
                                    if (v != null && v.isFinite && v >= 0 && v <= 1024 * 1024) {
                                      _saveMonthlyOverride((v * _bytesPerGiB).round());
                                    }
                                  },
                                ),
                                const SizedBox(width: 6),
                                _CompactActionBtn(
                                  icon: CupertinoIcons.arrow_counterclockwise,
                                  label: '默认',
                                  loading: _saving,
                                  onTap: () => _saveMonthlyOverride(null),
                                ),
                              ],
                            ),
                          ],

                          if (_events.isNotEmpty) ...[
                            Divider(height: 28, color: skin.border),
                            Text(
                              '变更记录',
                              style: TextStyle(
                                color: skin.fg2,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ..._events.map((ev) {
                              final positive = ev.bytesDelta >= 0;
                              final sign = positive ? '+' : '-';
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${ev.kindLabel}${ev.note.isNotEmpty ? ' · ${ev.note}' : ''}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(color: skin.fg, fontSize: 12.5),
                                          ),
                                          if (ev.createdAt.isNotEmpty)
                                            Text(
                                              ev.createdAt.replaceFirst('T', ' ').split('.').first,
                                              style: TextStyle(color: skin.fg3, fontSize: 11),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '$sign${fmtQuotaBytes(ev.bytesDelta.abs())}',
                                      style: TextStyle(
                                        color: positive
                                            ? const Color(0xFF34D399)
                                            : VedroTheme.danger,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniQuotaStat extends StatelessWidget {
  const _MiniQuotaStat({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: skin.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: skin.fg3, fontSize: 11)),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
