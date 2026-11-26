import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import 'vedro_ui.dart';

/// Linear / Apple Server Console caliber Administrator Dashboard.
/// Strictly mounted ONLY when `appState.isSignedIn && appState.isAdmin`.
class AdminConsolePane extends StatefulWidget {
  const AdminConsolePane({super.key, required this.appState});
  final VedroAppState appState;

  @override
  State<AdminConsolePane> createState() => _AdminConsolePaneState();
}

class _AdminConsolePaneState extends State<AdminConsolePane> {
  String _tab = 'overview'; // overview | sessions | users | tasks | activity
  bool _refreshing = false;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _refreshing = true);
    try {
      await widget.appState.loadEmbyGoAdminDashboard();
    } catch (_) {} finally {
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
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _openCreateUserDialog() async {
    final nameCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建服务器用户'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '初始密码'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
        ],
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

    final data = widget.appState.embygoAdminDashboard;
    final status = data?['status'] as Map<String, dynamic>?;
    final sessions = _extractList(data?['sessions']);
    final users = _extractList(data?['users']);
    final tasks = _extractList(data?['tasks']);
    final accent = Theme.of(context).colorScheme.secondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hero Server Identity & Quick Controls Banner
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF171A24), Color(0xFF12131A)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x22FFFFFF), width: 0.9),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0x20F59E0B),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: const Color(0x45F59E0B), width: 0.8),
                ),
                child: const Icon(Icons.admin_panel_settings_rounded, size: 22, color: Color(0xFFFBBF24)),
              ),
              const SizedBox(width: 14),
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
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const _StatusDotBadge(label: '在线运行', color: Color(0xFF34D399)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _MetaBadge(
                          '版本 ${status?['version'] ?? widget.appState.capabilities?.advertisedVersion ?? '-'}',
                        ),
                        if (status != null)
                          _MetaBadge(
                            status['postgres_catalog'] == true ? 'PostgreSQL' : 'SQLite 存储',
                          ),
                        if (status != null)
                          _MetaBadge(
                            status['transcoding_enabled'] == true ? '已启转码' : 'DirectPlay 直连',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CompactActionBtn(
                    icon: Icons.sync_rounded,
                    label: _scanning ? '扫描中…' : '全库扫描',
                    primary: true,
                    accent: accent,
                    loading: _scanning,
                    onTap: _triggerScan,
                  ),
                  _CompactActionBtn(
                    icon: Icons.refresh_rounded,
                    label: '刷新',
                    loading: _refreshing,
                    onTap: _reload,
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Clean Segmented Navigation with live counts
        VedroSegmentedControl<String>(
          items: [
            const ('overview', '概览与媒体库'),
            ('sessions', '会话 (${sessions.length})'),
            ('users', '用户 (${users.length})'),
            ('tasks', '任务 (${tasks.length})'),
            const ('activity', '活动日志'),
          ],
          selected: _tab,
          onSelected: (v) => setState(() => _tab = v),
        ),

        const SizedBox(height: 18),

        if (data == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: VedroTheme.fg2),
            ),
          )
        else
          switch (_tab) {
            'sessions' => _buildSessions(sessions),
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
        // Full-width Responsive 4-Column Bento Metrics
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 560 ? 4 : 2;
            const gap = 12.0;
            final w = (constraints.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                _BentoMetricCard(
                  width: w,
                  label: '电影',
                  value: '${counts?['MovieCount'] ?? 0}',
                  icon: Icons.movie_outlined,
                  tint: const Color(0xFF60A5FA),
                ),
                _BentoMetricCard(
                  width: w,
                  label: '剧集',
                  value: '${counts?['SeriesCount'] ?? 0}',
                  icon: Icons.live_tv_rounded,
                  tint: const Color(0xFFA78BFA),
                ),
                _BentoMetricCard(
                  width: w,
                  label: '分集总数',
                  value: '${counts?['EpisodeCount'] ?? 0}',
                  icon: Icons.video_library_outlined,
                  tint: const Color(0xFF38BDF8),
                ),
                _BentoMetricCard(
                  width: w,
                  label: '正在播放 / 在线',
                  value: '${playing.length} / ${allSessions.length}',
                  icon: Icons.play_circle_outline_rounded,
                  tint: const Color(0xFF34D399),
                ),
              ],
            );
          },
        ),

        if (status != null) ...[
          const SizedBox(height: 16),
          _ConsolePanel(
            title: '索引与引擎状态',
            icon: Icons.analytics_outlined,
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
                    ('最近扫描', status['last_scan_attempt_at'].toString().replaceFirst('T', ' ').split('.').first),
                  if (status['built_at'] != null)
                    ('构建时间', status['built_at'].toString().split('T').first),
                ];
                return Wrap(
                  spacing: gap,
                  runSpacing: 12,
                  children: facts.map((f) {
                    return SizedBox(
                      width: cellW,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.$1, style: const TextStyle(color: VedroTheme.fg3, fontSize: 11.5)),
                          const SizedBox(height: 3),
                          Text(
                            f.$2,
                            style: const TextStyle(
                              color: VedroTheme.fg,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              fontFeatures: [FontFeature.tabularFigures()],
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
          const SizedBox(height: 16),
          _ConsolePanel(
            title: '媒体库管理 (${libs.length})',
            icon: Icons.folder_copy_outlined,
            child: Column(
              children: [
                for (var i = 0; i < libs.length; i++) ...[
                  if (i > 0) const Divider(height: 20),
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
    final id = (lib['ItemId'] ?? lib['Id'] ?? '').toString();
    final name = (lib['Name'] ?? '未命名').toString();
    final ctype = (lib['CollectionType'] ?? '').toString();
    final locations = ((lib['Locations'] as List?) ?? const []).map((e) => e.toString()).toList();
    final genCovers = lib['GenerateCovers'] == true;
    final icon = switch (ctype.toLowerCase()) {
      'movies' => Icons.movie_outlined,
      'tvshows' => Icons.live_tv_rounded,
      'music' => Icons.music_note_rounded,
      _ => Icons.folder_outlined,
    };

    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0x165B9BFF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF5B9BFF)),
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
                      style: const TextStyle(color: VedroTheme.fg, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (ctype.isNotEmpty) ...[
                    const SizedBox(width: 8),
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
                  style: const TextStyle(
                    color: VedroTheme.fg3,
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ],
          ),
        ),
        if (id.isNotEmpty && widget.appState.capabilities?.isEmbyGo == true) ...[
          const SizedBox(width: 10),
          const Text('自动封面', style: TextStyle(color: VedroTheme.fg3, fontSize: 12)),
          const SizedBox(width: 6),
          Transform.scale(
            scale: 0.78,
            child: CupertinoSwitch(
              value: genCovers,
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
        icon: Icons.devices_other_rounded,
        message: '当前没有活跃的客户端会话',
      );
    }
    return _ConsolePanel(
      title: '活跃会话 (${sessions.length})',
      icon: Icons.cast_connected_rounded,
      child: Column(
        children: [
          for (var i = 0; i < sessions.length; i++) ...[
            if (i > 0) const Divider(height: 22),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: itemTitle != null ? const Color(0x2234D399) : const Color(0x16FFFFFF),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                artworkInitials(user),
                style: TextStyle(
                  color: itemTitle != null ? const Color(0xFF34D399) : VedroTheme.fg2,
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
                  Row(
                    children: [
                      Text(
                        user,
                        style: const TextStyle(color: VedroTheme.fg, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      _MetaBadge([client, device].where((e) => e.isNotEmpty).join(' · ')),
                      if (playMethod.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _MetaBadge(playMethod),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    itemTitle != null
                        ? '${isPaused ? '已暂停' : '正在播放'}：$itemTitle'
                        : '空闲在线',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: itemTitle != null ? const Color(0xFFD6DAE4) : VedroTheme.fg3,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            if (id.isNotEmpty)
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: VedroTheme.danger,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                onPressed: () => widget.appState.adminEndSession(id),
                child: const Text('断开', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
              ),
          ],
        ),
        if (itemTitle != null && progress > 0) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3.5,
                    backgroundColor: const Color(0x20FFFFFF),
                    color: const Color(0xFF34D399),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(
                  color: VedroTheme.fg3,
                  fontSize: 11.5,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildUsers(List<Map<String, dynamic>> users) {
    final accent = Theme.of(context).colorScheme.secondary;
    return _ConsolePanel(
      title: '用户账户 (${users.length})',
      icon: Icons.people_outline_rounded,
      trailing: _CompactActionBtn(
        icon: Icons.person_add_outlined,
        label: '新建用户',
        primary: true,
        accent: accent,
        onTap: _openCreateUserDialog,
      ),
      child: users.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('未获取到用户列表', style: TextStyle(color: VedroTheme.fg3, fontSize: 13)),
            )
          : Column(
              children: [
                for (var i = 0; i < users.length; i++) ...[
                  if (i > 0) const Divider(height: 20),
                  _buildUserRow(users[i]),
                ],
              ],
            ),
    );
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

    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isAdm ? const Color(0x225B9BFF) : const Color(0x16FFFFFF),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            artworkInitials(name),
            style: TextStyle(
              color: isAdm ? const Color(0xFF5B9BFF) : VedroTheme.fg2,
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
                    name,
                    style: TextStyle(
                      color: isDisabled ? VedroTheme.fg3 : VedroTheme.fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isSelf) const _MetaBadge('当前账号'),
                  if (isAdm) const _StatusDotBadge(label: '管理员', color: Color(0xFF5B9BFF)),
                  if (!isAdm && canDl)
                    const _StatusDotBadge(label: '可下载', color: Color(0xFF34D399)),
                  if (isDisabled) const _StatusDotBadge(label: '已禁用', color: VedroTheme.danger),
                ],
              ),
            ],
          ),
        ),
        if (isEmbyGo && uid.isNotEmpty) ...[
          _CompactActionBtn(
            icon: Icons.data_usage_rounded,
            label: '下载额度',
            onTap: () => _openUserQuotaDialog(uid, name, policy),
          ),
          const SizedBox(width: 6),
        ],
        if (!isSelf && uid.isNotEmpty) ...[
          _CompactActionBtn(
            icon: isDisabled ? Icons.check_circle_outline_rounded : Icons.block_rounded,
            label: isDisabled ? '启用' : '禁用',
            onTap: () async {
              policy['IsDisabled'] = !isDisabled;
              await widget.appState.adminSetUserPolicy(uid, policy);
            },
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: '删除用户',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: VedroTheme.danger),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('删除用户 $name？'),
                  content: const Text('此操作不可撤销。'),
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
                await widget.appState.adminDeleteUser(uid);
              }
            },
          ),
        ],
      ],
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
        icon: Icons.schedule_rounded,
        message: '暂无定时任务',
      );
    }
    return _ConsolePanel(
      title: '定时任务 (${tasks.length})',
      icon: Icons.schedule_rounded,
      child: Column(
        children: [
          for (var i = 0; i < tasks.length; i++) ...[
            if (i > 0) const Divider(height: 20),
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

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: running ? const Color(0xFF34D399) : VedroTheme.fg3,
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
                style: const TextStyle(color: VedroTheme.fg, fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                running ? '运行中…' : (desc.isNotEmpty ? desc : '空闲 ($state)'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: VedroTheme.fg3, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _CompactActionBtn(
          icon: Icons.play_arrow_rounded,
          label: running ? '运行中' : '运行',
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
        icon: Icons.receipt_long_rounded,
        message: '暂无服务器活动日志',
      );
    }
    return _ConsolePanel(
      title: '最近活动日志 (${items.length})',
      icon: Icons.receipt_long_rounded,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 16),
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
        : (sev.toLowerCase().contains('warn') ? const Color(0xFFFBBF24) : const Color(0xFF60A5FA));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: sevColor, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(color: VedroTheme.fg, fontSize: 13.5)),
              if (date.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  date,
                  style: const TextStyle(
                    color: VedroTheme.fg3,
                    fontSize: 11.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
        _StatusDotBadge(label: sev, color: sevColor),
      ],
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
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF13141A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1DFFFFFF), width: 0.85),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: tint),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: VedroTheme.fg3, fontSize: 12)),
        ],
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF13141A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1DFFFFFF), width: 0.85),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: VedroTheme.fg2),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const Divider(height: 24),
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF13141A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1DFFFFFF), width: 0.85),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: VedroTheme.fg3),
          const SizedBox(height: 10),
          Text(message, style: const TextStyle(color: VedroTheme.fg3, fontSize: 13.5)),
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0x15FFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(color: VedroTheme.fg2, fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _CompactActionBtn extends StatelessWidget {
  const _CompactActionBtn({
    required this.icon,
    required this.label,
    this.onTap,
    this.primary = false,
    this.accent,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final Color? accent;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final bg = primary ? (accent ?? VedroTheme.accentFill) : const Color(0xFF1D1E26);
    return PressableScale(
      onTap: loading ? null : onTap,
      hoverScale: 1.03,
      pressScale: 0.96,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: onTap == null ? const Color(0xFF1A1B22) : bg,
          borderRadius: BorderRadius.circular(9),
          border: primary ? null : Border.all(color: const Color(0x22FFFFFF), width: 0.7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 1.7, color: Colors.white),
              )
            else
              Icon(icon, size: 15, color: onTap == null ? VedroTheme.fg3 : Colors.white),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: onTap == null ? VedroTheme.fg3 : Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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
        _monthlyGiBCtrl.text = gib == gib.roundToDouble() ? '${gib.round()}' : gib.toStringAsFixed(1);
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
        setState(() => _error = '更新下载权限失败：$e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _adjustPackGiB(double gib) async {
    final bytes = (gib * _bytesPerGiB).round();
    if (bytes == 0) return;
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
      _packNoteCtrl.clear();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '调整流量包失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveMonthlyOverride(int? bytes) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.appState.adminSetMonthlyDownloadQuota(widget.userId, bytes);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '更新周期额度失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dq = _quota;
    return Dialog(
      backgroundColor: const Color(0xFF151720),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0x28FFFFFF), width: 0.9),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.data_usage_rounded, size: 19, color: Color(0xFF34D399)),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '下载权限与流量包 · ${widget.userName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: VedroTheme.fg2),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(42),
                      child: CircularProgressIndicator(strokeWidth: 2, color: VedroTheme.fg2),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_error != null) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: const Color(0x28EF4444),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(_error!, style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12.5)),
                            ),
                          ],
                          Row(
                            children: [
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('允许原文件下载', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                                    SizedBox(height: 2),
                                    Text('User.Policy.EnableContentDownloading', style: TextStyle(color: VedroTheme.fg3, fontSize: 11.5)),
                                  ],
                                ),
                              ),
                              Transform.scale(
                                scale: 0.82,
                                child: CupertinoSwitch(
                                  value: _enableDownload,
                                  onChanged: _saving ? null : _toggleDownloadPermission,
                                ),
                              ),
                            ],
                          ),
                          if (dq != null) ...[
                            const Divider(height: 24),
                            Wrap(
                              spacing: 12,
                              runSpacing: 10,
                              children: [
                                _MetaBadge('总可用：${dq.adminExempt ? '管理员不限' : fmtQuotaBytes(dq.totalRemainingBytes)}'),
                                _MetaBadge('30天免费剩：${fmtQuotaBytes(dq.monthlyRemainingBytes)} / ${fmtQuotaBytes(dq.monthlyQuotaBytes)}'),
                                _MetaBadge('永久流量包：${fmtQuotaBytes(dq.packBytes)}'),
                                _MetaBadge('并发：${dq.activeDownloads}/${dq.maxConcurrentDownloads > 0 ? dq.maxConcurrentDownloads : '∞'}'),
                                if (dq.inFlightBytes > 0) _MetaBadge('在途预占：${fmtQuotaBytes(dq.inFlightBytes)}'),
                                if (_traffic != null) _MetaBadge('累计下载：${fmtQuotaBytes(_traffic!.downloadBytes)}'),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '一次性永久下载流量包（永不过期 · 用完即止）',
                              style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _CompactActionBtn(
                                  icon: Icons.add_rounded,
                                  label: '+500 GiB',
                                  primary: true,
                                  loading: _saving,
                                  onTap: () => _adjustPackGiB(500),
                                ),
                                _CompactActionBtn(
                                  icon: Icons.add_rounded,
                                  label: '+100 GiB',
                                  loading: _saving,
                                  onTap: () => _adjustPackGiB(100),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                SizedBox(
                                  width: 110,
                                  child: TextField(
                                    controller: _packGiBCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                                    decoration: const InputDecoration(labelText: 'GiB (±)', isDense: true),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _packNoteCtrl,
                                    decoration: const InputDecoration(labelText: '备注（可选）', isDense: true),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: _saving
                                      ? null
                                      : () {
                                          final v = double.tryParse(_packGiBCtrl.text.trim());
                                          if (v != null && v != 0) _adjustPackGiB(v);
                                        },
                                  child: const Text('调整'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '30 天周期免费下载额度覆写',
                              style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _monthlyGiBCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(labelText: '每 30 天免费 GiB', isDense: true),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: _saving
                                      ? null
                                      : () {
                                          final v = double.tryParse(_monthlyGiBCtrl.text.trim());
                                          if (v != null && v >= 0) {
                                            _saveMonthlyOverride((v * _bytesPerGiB).round());
                                          }
                                        },
                                  child: const Text('保存'),
                                ),
                                const SizedBox(width: 6),
                                TextButton(
                                  onPressed: _saving ? null : () => _saveMonthlyOverride(null),
                                  child: const Text('恢复默认'),
                                ),
                              ],
                            ),
                          ],
                          if (_events.isNotEmpty) ...[
                            const Divider(height: 24),
                            const Text(
                              '最近下载额度流水',
                              style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
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
                                            style: const TextStyle(color: VedroTheme.fg, fontSize: 12.5),
                                          ),
                                          if (ev.createdAt.isNotEmpty)
                                            Text(
                                              ev.createdAt.replaceFirst('T', ' ').split('.').first,
                                              style: const TextStyle(color: VedroTheme.fg3, fontSize: 11),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '$sign${fmtQuotaBytes(ev.bytesDelta.abs())}',
                                      style: TextStyle(
                                        color: positive ? const Color(0xFF34D399) : const Color(0xFFFCA5A5),
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
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
