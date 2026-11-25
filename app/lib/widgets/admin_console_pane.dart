import 'package:flutter/material.dart';

import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import 'vedro_ui.dart';

/// Complete Administrator Console — strictly mounted ONLY when `appState.isSignedIn && appState.isAdmin`.
/// Never rendered or linked for regular users.
class AdminConsolePane extends StatefulWidget {
  const AdminConsolePane({super.key, required this.appState});
  final VedroAppState appState;

  @override
  State<AdminConsolePane> createState() => _AdminConsolePaneState();
}

class _AdminConsolePaneState extends State<AdminConsolePane> {
  String _tab = 'overview'; // overview | sessions | users | tasks | activity
  bool _refreshing = false;

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

  Future<void> _openCreateUserDialog() async {
    final nameCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建用户'),
        content: Column(
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('创建失败：$e')),
          );
        }
      }
    }
    nameCtrl.dispose();
    passCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Hard safety guard: never display admin controls unless server verified IsAdministrator == true.
    if (!widget.appState.isSignedIn || !widget.appState.isAdmin) {
      return const SizedBox.shrink();
    }

    final data = widget.appState.embygoAdminDashboard;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '服务器管理台',
                    style: TextStyle(
                      color: VedroTheme.fg,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    '仅当前服务器管理员可见 · 实时媒体库、会话、用户与任务管理',
                    style: TextStyle(color: VedroTheme.fg3, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: VedroTheme.fg,
                side: const BorderSide(color: VedroTheme.lineStrong, width: 0.8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _refreshing ? null : _reload,
              icon: _refreshing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.8, color: VedroTheme.fg),
                    )
                  : const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('刷新', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        VedroSegmentedControl<String>(
          items: const [
            ('overview', '概览与库'),
            ('sessions', '在线会话'),
            ('users', '用户管理'),
            ('tasks', '定时任务'),
            ('activity', '活动日志'),
          ],
          selected: _tab,
          onSelected: (v) => setState(() => _tab = v),
        ),
        const SizedBox(height: 18),
        if (data == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: VedroTheme.fg2),
            ),
          )
        else
          switch (_tab) {
            'sessions' => _buildSessions(data),
            'users' => _buildUsers(data),
            'tasks' => _buildTasks(data),
            'activity' => _buildActivity(data),
            _ => _buildOverview(data),
          },
      ],
    );
  }

  Widget _buildOverview(Map<String, dynamic> data) {
    final status = data['status'] as Map<String, dynamic>?;
    final counts = data['counts'] as Map<String, dynamic>?;
    final playing = (data['playing_sessions'] as List?) ?? const [];
    final allSessions = (data['sessions'] as List?) ?? const [];
    final libsRaw = data['libraries'];
    final libs = libsRaw is List ? libsRaw.whereType<Map<String, dynamic>>().toList() : const <Map<String, dynamic>>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _StatTile(label: '电影', value: '${counts?['MovieCount'] ?? 0}', icon: Icons.movie_outlined),
            _StatTile(label: '剧集', value: '${counts?['SeriesCount'] ?? 0}', icon: Icons.tv_rounded),
            _StatTile(label: '分集', value: '${counts?['EpisodeCount'] ?? 0}', icon: Icons.video_library_outlined),
            _StatTile(label: '正在播放', value: '${playing.length} / ${allSessions.length}', icon: Icons.play_circle_outline_rounded),
          ],
        ),
        const SizedBox(height: 18),
        _AdminCard(
          title: '系统状态',
          trailing: FilledButton.icon(
            onPressed: () async {
              await widget.appState.triggerLibraryRefresh();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已触发全库扫描')),
                );
              }
            },
            icon: const Icon(Icons.sync_rounded, size: 16),
            label: const Text('扫描媒体库', style: TextStyle(fontSize: 12.5)),
          ),
          child: Column(
            children: [
              _KvRow('服务器', widget.appState.activeServerDisplayName),
              _KvRow('服务端版本', '${status?['version'] ?? widget.appState.capabilities?.advertisedVersion ?? '-'}'),
              if (status != null) ...[
                _KvRow('索引条目', '${status['items'] ?? 0} 条目 · ${status['files'] ?? 0} 文件 · ${status['subtitle_files'] ?? 0} 外挂字幕'),
                _KvRow('目录后端', status['postgres_catalog'] == true ? 'PostgreSQL' : '内嵌存储'),
                _KvRow('转码状态', status['transcoding_enabled'] == true ? '已启用' : '纯直连 DirectPlay'),
                if (status['last_scan_attempt_at'] != null)
                  _KvRow('最近扫描', status['last_scan_attempt_at'].toString()),
              ],
            ],
          ),
        ),
        if (libs.isNotEmpty) ...[
          const SizedBox(height: 16),
          _AdminCard(
            title: '媒体库列表 (${libs.length})',
            child: Column(
              children: libs.map((lib) {
                final id = (lib['ItemId'] ?? lib['Id'] ?? '').toString();
                final name = (lib['Name'] ?? '未命名').toString();
                final ctype = (lib['CollectionType'] ?? '').toString();
                final locations = ((lib['Locations'] as List?) ?? const []).join(', ');
                final genCovers = lib['GenerateCovers'] == true;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$name${ctype.isNotEmpty ? ' · $ctype' : ''}',
                              style: const TextStyle(
                                color: VedroTheme.fg,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (locations.isNotEmpty)
                              Text(
                                locations,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: VedroTheme.fg3, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      if (id.isNotEmpty && widget.appState.capabilities?.isEmbyGo == true)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('自动封面', style: TextStyle(color: VedroTheme.fg3, fontSize: 12)),
                            const SizedBox(width: 6),
                            Switch(
                              value: genCovers,
                              onChanged: (v) => widget.appState.adminSetLibraryCovers(id, v),
                            ),
                          ],
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSessions(Map<String, dynamic> data) {
    final sessions = ((data['sessions'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (sessions.isEmpty) {
      return const _EmptyAdminCard('当前没有活跃会话');
    }
    return _AdminCard(
      title: '活跃会话 (${sessions.length})',
      child: Column(
        children: sessions.map((s) {
          final id = (s['Id'] ?? '').toString();
          final user = (s['UserName'] ?? '未知用户').toString();
          final client = (s['Client'] ?? '').toString();
          final device = (s['DeviceName'] ?? '').toString();
          final nowPlaying = s['NowPlayingItem'] as Map<String, dynamic>?;
          final itemTitle = nowPlaying?['Name']?.toString();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: itemTitle != null ? const Color(0x2234D399) : VedroTheme.surface2,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    itemTitle != null ? Icons.play_arrow_rounded : Icons.devices_rounded,
                    size: 18,
                    color: itemTitle != null ? const Color(0xFF34D399) : VedroTheme.fg2,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$user · $client ($device)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: VedroTheme.fg,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        itemTitle != null ? '正在播放：$itemTitle' : '空闲在线',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: VedroTheme.fg3, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (id.isNotEmpty)
                  TextButton(
                    onPressed: () => widget.appState.adminEndSession(id),
                    child: const Text('断开', style: TextStyle(color: VedroTheme.danger, fontSize: 12.5)),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildUsers(Map<String, dynamic> data) {
    final raw = data['users'];
    final List<Map<String, dynamic>> users;
    if (raw is Map && raw['Items'] is List) {
      users = (raw['Items'] as List).whereType<Map<String, dynamic>>().toList();
    } else if (raw is List) {
      users = raw.whereType<Map<String, dynamic>>().toList();
    } else {
      users = const [];
    }

    return _AdminCard(
      title: '用户列表 (${users.length})',
      trailing: FilledButton.icon(
        onPressed: _openCreateUserDialog,
        icon: const Icon(Icons.person_add_outlined, size: 16),
        label: const Text('新建用户', style: TextStyle(fontSize: 12.5)),
      ),
      child: users.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('未获取到用户列表', style: TextStyle(color: VedroTheme.fg3, fontSize: 13)),
            )
          : Column(
              children: users.map((u) {
                final uid = (u['Id'] ?? '').toString();
                final name = (u['Name'] ?? '').toString();
                final policy = Map<String, dynamic>.from((u['Policy'] as Map?) ?? const {});
                final isAdm = policy['IsAdministrator'] == true;
                final isDisabled = policy['IsDisabled'] == true;
                final isSelf = uid == widget.appState.userId;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                color: isDisabled ? VedroTheme.fg3 : VedroTheme.fg,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (isAdm) ...[
                              const SizedBox(width: 8),
                              _PillTag('管理员', const Color(0xFF5B9BFF)),
                            ],
                            if (isDisabled) ...[
                              const SizedBox(width: 6),
                              _PillTag('已禁用', VedroTheme.danger),
                            ],
                          ],
                        ),
                      ),
                      if (!isSelf && uid.isNotEmpty) ...[
                        TextButton(
                          onPressed: () async {
                            policy['IsDisabled'] = !isDisabled;
                            await widget.appState.adminSetUserPolicy(uid, policy);
                          },
                          child: Text(
                            isDisabled ? '启用' : '禁用',
                            style: const TextStyle(color: VedroTheme.fg2, fontSize: 12.5),
                          ),
                        ),
                        IconButton(
                          tooltip: '删除用户',
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
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildTasks(Map<String, dynamic> data) {
    final raw = data['tasks'];
    final tasks = raw is List ? raw.whereType<Map<String, dynamic>>().toList() : const <Map<String, dynamic>>[];
    if (tasks.isEmpty) {
      return const _EmptyAdminCard('没有可运行的定时任务');
    }
    return _AdminCard(
      title: '定时任务 (${tasks.length})',
      child: Column(
        children: tasks.map((t) {
          final key = (t['Key'] ?? t['Id'] ?? t['key'] ?? '').toString();
          final name = (t['Name'] ?? t['name'] ?? key).toString();
          final state = (t['State'] ?? t['state'] ?? 'Idle').toString();
          final running = state.toLowerCase() == 'running';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: VedroTheme.fg,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        running ? '运行中…' : '状态：$state',
                        style: const TextStyle(color: VedroTheme.fg3, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: VedroTheme.fg,
                    side: const BorderSide(color: VedroTheme.lineStrong, width: 0.8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: running || key.isEmpty
                      ? null
                      : () async {
                          await widget.appState.adminRunTask(key);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('已启动任务：$name')),
                            );
                          }
                        },
                  child: const Text('立即运行', style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActivity(Map<String, dynamic> data) {
    final raw = data['activity'];
    final List<Map<String, dynamic>> items;
    if (raw is Map && raw['Items'] is List) {
      items = (raw['Items'] as List).whereType<Map<String, dynamic>>().toList();
    } else if (raw is List) {
      items = raw.whereType<Map<String, dynamic>>().toList();
    } else {
      items = const [];
    }
    if (items.isEmpty) {
      return const _EmptyAdminCard('暂无活动日志');
    }
    return _AdminCard(
      title: '最近活动日志 (${items.length})',
      child: Column(
        children: items.map((e) {
          final name = (e['Name'] ?? e['ShortOverview'] ?? '-').toString();
          final date = (e['Date'] ?? '').toString().replaceFirst('T', ' ').split('.').first;
          final sev = (e['Severity'] ?? 'Info').toString();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(color: VedroTheme.fg, fontSize: 13.5)),
                      if (date.isNotEmpty)
                        Text(date, style: const TextStyle(color: VedroTheme.fg3, fontSize: 11.5)),
                    ],
                  ),
                ),
                _PillTag(sev, sev.toLowerCase().contains('err') ? VedroTheme.danger : VedroTheme.fg2),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 152,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VedroTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VedroTheme.line, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: VedroTheme.fg3),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: VedroTheme.fg,
              fontSize: 22,
              fontWeight: FontWeight.w600,
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

class _AdminCard extends StatelessWidget {
  const _AdminCard({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VedroTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VedroTheme.line, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: VedroTheme.fg,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const Divider(height: 22),
          child,
        ],
      ),
    );
  }
}

class _EmptyAdminCard extends StatelessWidget {
  const _EmptyAdminCard(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: VedroTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VedroTheme.line, width: 0.8),
      ),
      child: Center(
        child: Text(text, style: const TextStyle(color: VedroTheme.fg3, fontSize: 13.5)),
      ),
    );
  }
}

class _KvRow extends StatelessWidget {
  const _KvRow(this.k, this.v);
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(k, style: const TextStyle(color: VedroTheme.fg3, fontSize: 13)),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(color: VedroTheme.fg, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _PillTag extends StatelessWidget {
  const _PillTag(this.text, this.color);
  final String text;
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
        text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
