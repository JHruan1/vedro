import 'package:flutter/material.dart';

import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.appState,
    required this.onOpenServerHub,
    required this.onOpenAddServer,
    this.topInset = 0,
  });

  final VedroAppState appState;
  final VoidCallback onOpenServerHub;
  final void Function([String? initialUrl]) onOpenAddServer;
  final double topInset;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.appState.isAdmin && widget.appState.isSignedIn) {
      widget.appState.loadEmbyGoAdminDashboard();
    }
  }

  Future<void> _updateSetting(String key, dynamic value) async {
    final copy = Map<String, dynamic>.from(widget.appState.settings);
    copy[key] = value;
    await widget.appState.saveSettings(copy);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.appState.settings;
    final caps = widget.appState.capabilities;
    final admin = widget.appState.embygoAdminDashboard;
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final signedIn = widget.appState.isSignedIn;
    final routeName = widget.appState.activeRouteDisplayName;

    return Scaffold(
      backgroundColor: VedroTheme.canvas,
      appBar: !wide ? AppBar(title: const Text('设置')) : null,
      body: Padding(
        padding: EdgeInsets.only(top: widget.topInset),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: EdgeInsets.fromLTRB(20, wide ? 20 : 8, 20, wide ? 52 : 112),
              children: [
                if (wide)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text(
                      '设置',
                      style: TextStyle(
                        color: VedroTheme.fg,
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),

                const _SectionLabel('服务器与多线路'),
                _GroupedCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  signedIn
                                      ? widget.appState.activeServerDisplayName
                                      : '未连接媒体服务器',
                                  style: const TextStyle(
                                    color: VedroTheme.fg,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  signedIn
                                      ? [
                                          widget.appState.username ?? '-',
                                          if (routeName != null) routeName,
                                          '${widget.appState.savedServers.length} 个服务器',
                                        ].join(' · ')
                                      : '已保存 ${widget.appState.savedServers.length} 个服务器 · 内核 v${widget.appState.core.coreVersion}',
                                  style: const TextStyle(color: VedroTheme.fg3, fontSize: 12.5),
                                ),
                              ],
                            ),
                          ),
                          if (signedIn)
                            TextButton(
                              onPressed: widget.appState.logout,
                              child: const Text(
                                '断开连接',
                                style: TextStyle(color: VedroTheme.danger, fontSize: 13.5),
                              ),
                            )
                          else
                            FilledButton(
                              onPressed: () => widget.onOpenAddServer(),
                              child: const Text('添加服务器', style: TextStyle(fontSize: 13)),
                            ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: widget.onOpenServerHub,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '管理服务器与线路测速',
                                style: TextStyle(color: VedroTheme.fg, fontSize: 14),
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, size: 18, color: VedroTheme.fg3),
                          ],
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => widget.onOpenAddServer(),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '添加新的媒体服务器',
                                style: TextStyle(color: VedroTheme.accent, fontSize: 14),
                              ),
                            ),
                            Icon(Icons.add_rounded, size: 18, color: VedroTheme.accent),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const _SectionLabel('播放器与画面'),
                _GroupedCard(
                  children: [
                    _DropdownRow(
                      title: '硬件解码',
                      value: (s['hwdec'] ?? 'auto_zero_copy').toString(),
                      items: const {
                        'auto_zero_copy': '零拷贝硬解',
                        'auto_copy': 'Copy-Back 硬解',
                        'software': '软件解码',
                      },
                      onChanged: (v) => _updateSetting('hwdec', v),
                    ),
                    _SwitchRow(
                      title: '优先原生杜比视界',
                      subtitle: '支持原生显示的屏幕直出，否则自动 Tone-Mapping',
                      value: s['prefer_native_dolby_vision'] != false,
                      onChanged: (v) => _updateSetting('prefer_native_dolby_vision', v),
                    ),
                    _DropdownRow(
                      title: 'HDR 色调映射',
                      value: (s['tone_mapping'] ?? 'bt2446a').toString(),
                      items: const {
                        'bt2446a': 'BT.2446a',
                        'spline': 'Spline',
                        'st2094_40': 'ST.2094-40',
                        'reinhard': 'Reinhard',
                        'clip': 'Clip',
                      },
                      onChanged: (v) => _updateSetting('tone_mapping', v),
                    ),
                    _SwitchRow(
                      title: '去色带 (Deband)',
                      value: s['deband'] == true,
                      onChanged: (v) => _updateSetting('deband', v),
                    ),
                  ],
                ),

                const _SectionLabel('音频与杜比全景声'),
                _GroupedCard(
                  children: [
                    _DropdownRow(
                      title: '输出模式',
                      value: (s['audio_mode'] ?? 'auto').toString(),
                      items: const {
                        'auto': '自动',
                        'passthrough_bitstream': '源码直通',
                        'spatial_audio': '系统空间音频',
                        'headphone_binaural': '耳机空间化',
                        'pcm_stereo': '32-bit PCM',
                      },
                      onChanged: (v) => _updateSetting('audio_mode', v),
                    ),
                    _SwitchRow(
                      title: '夜间模式 (DRC)',
                      value: s['night_mode'] == true,
                      onChanged: (v) => _updateSetting('night_mode', v),
                    ),
                    _SwitchRow(
                      title: '人声增强',
                      value: s['dialogue_boost'] == true,
                      onChanged: (v) => _updateSetting('dialogue_boost', v),
                    ),
                  ],
                ),

                if (signedIn && widget.appState.isAdmin && caps?.isEmbyGo == true) ...[
                  const _SectionLabel('媒体库管理'),
                  _GroupedCard(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (admin == null)
                              const Text(
                                '正在同步服务器状态…',
                                style: TextStyle(color: VedroTheme.fg3, fontSize: 13),
                              )
                            else ...[
                              _InfoLine('版本', '${admin['status']?['version'] ?? '-'}'),
                              _InfoLine(
                                '索引',
                                '${admin['status']?['items'] ?? 0} 条目 · ${admin['status']?['files'] ?? 0} 文件 · ${admin['status']?['subtitle_files'] ?? 0} 字幕',
                              ),
                              _InfoLine(
                                '媒体',
                                '${admin['counts']?['MovieCount'] ?? 0} 电影 · ${admin['counts']?['SeriesCount'] ?? 0} 剧集 · ${admin['counts']?['EpisodeCount'] ?? 0} 分集',
                              ),
                              _InfoLine(
                                '在线会话',
                                '${(admin['playing_sessions'] as List?)?.length ?? 0}',
                              ),
                            ],
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 36,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: VedroTheme.fg,
                                  side: const BorderSide(color: VedroTheme.lineStrong, width: 0.8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: widget.appState.triggerLibraryRefresh,
                                child: const Text('刷新媒体库', style: TextStyle(fontSize: 13)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        text,
        style: const TextStyle(
          color: VedroTheme.fg3,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _GroupedCard extends StatelessWidget {
  const _GroupedCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: VedroTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VedroTheme.line, width: 0.7),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _DropdownRow extends StatelessWidget {
  const _DropdownRow({
    required this.title,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String title;
  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final safeValue = items.containsKey(value) ? value : items.keys.first;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(color: VedroTheme.fg, fontSize: 14)),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: safeValue,
              dropdownColor: VedroTheme.surface2,
              style: const TextStyle(color: VedroTheme.fg2, fontSize: 13.5),
              items: items.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: VedroTheme.fg, fontSize: 14)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: const TextStyle(color: VedroTheme.fg3, fontSize: 12)),
                ],
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.k, this.v);
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 68,
            child: Text(k, style: const TextStyle(color: VedroTheme.fg3, fontSize: 13)),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(color: VedroTheme.fg2, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
