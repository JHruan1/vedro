import 'package:flutter/material.dart';

import '../core/theme/prism_theme.dart';
import '../state/app_state.dart';
import '../widgets/badge_strip.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.appState});
  final PrismAppState appState;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.appState.isAdmin) {
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

    return Scaffold(
      appBar: AppBar(title: const Text('播放引擎与服务器设置')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Connected Server Summary
          Card(
            child: ListTile(
              leading: const Icon(Icons.dns_rounded, color: PrismTheme.embygoGreen),
              title: Text(caps?.serverName ?? widget.appState.connectedUrl ?? '未连接'),
              subtitle: Text(
                '用户: ${widget.appState.username ?? '-'} • 后端: ${caps?.dialect ?? '-'} (${caps?.advertisedVersion ?? '-'}) • Rust Core v${widget.appState.core.coreVersion}',
              ),
              trailing: TextButton(
                onPressed: widget.appState.logout,
                child: const Text('退出登录', style: TextStyle(color: Colors.redAccent)),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Hardware Decoding & Dolby Vision
          const Text('硬件解码 & 杜比视界 (Dolby Vision)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('硬件解码策略'),
                  subtitle: const Text('Android MediaCodec / Apple VideoToolbox / Windows D3D11VA+NVDEC'),
                  trailing: DropdownButton<String>(
                    value: (s['hwdec'] ?? 'auto_zero_copy').toString(),
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'auto_zero_copy', child: Text('零拷贝硬解 (推荐)')),
                      DropdownMenuItem(value: 'auto_copy', child: Text('Copy-Back 硬解')),
                      DropdownMenuItem(value: 'software', child: Text('纯软解')),
                    ],
                    onChanged: (v) => v != null ? _updateSetting('hwdec', v) : null,
                  ),
                ),
                SwitchListTile(
                  title: const Text('优先原生杜比视界显示层'),
                  subtitle: const Text('在支持 DoVi 的 Apple XDR / Android 屏幕上使用原生管线，否则自动走 libplacebo RPU 渲染'),
                  value: s['prefer_native_dolby_vision'] != false,
                  onChanged: (v) => _updateSetting('prefer_native_dolby_vision', v),
                ),
                ListTile(
                  title: const Text('HDR / 杜比视界色调映射算法'),
                  trailing: DropdownButton<String>(
                    value: (s['tone_mapping'] ?? 'bt2446a').toString(),
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'bt2446a', child: Text('BT.2446a')),
                      DropdownMenuItem(value: 'spline', child: Text('Spline')),
                      DropdownMenuItem(value: 'st2094_40', child: Text('ST.2094-40')),
                      DropdownMenuItem(value: 'reinhard', child: Text('Reinhard')),
                      DropdownMenuItem(value: 'clip', child: Text('Clip (直通)')),
                    ],
                    onChanged: (v) => v != null ? _updateSetting('tone_mapping', v) : null,
                  ),
                ),
                SwitchListTile(
                  title: const Text('去色带 (Deband)'),
                  value: s['deband'] == true,
                  onChanged: (v) => _updateSetting('deband', v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Dolby Atmos & Spatial Audio
          const Text('杜比全景声 (Dolby Atmos) & 音频', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('音频输出模式'),
                  subtitle: const Text('支持 TrueHD Atmos / E-AC-3 JOC / DTS:X 源码直通与空间音频'),
                  trailing: DropdownButton<String>(
                    value: (s['audio_mode'] ?? 'auto').toString(),
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'auto', child: Text('自动')),
                      DropdownMenuItem(value: 'passthrough_bitstream', child: Text('源码直通 (WASAPI/IEC61937)')),
                      DropdownMenuItem(value: 'spatial_audio', child: Text('系统空间音频')),
                      DropdownMenuItem(value: 'headphone_binaural', child: Text('耳机双耳空间化')),
                      DropdownMenuItem(value: 'pcm_stereo', child: Text('32-bit PCM 立体声')),
                    ],
                    onChanged: (v) => v != null ? _updateSetting('audio_mode', v) : null,
                  ),
                ),
                SwitchListTile(
                  title: const Text('夜间模式 (DRC)'),
                  value: s['night_mode'] == true,
                  onChanged: (v) => _updateSetting('night_mode', v),
                ),
                SwitchListTile(
                  title: const Text('人声对白增强'),
                  value: s['dialogue_boost'] == true,
                  onChanged: (v) => _updateSetting('dialogue_boost', v),
                ),
              ],
            ),
          ),

          // EmbyGo Admin Diagnostics (shown automatically for embygo admins!)
          if (widget.appState.isAdmin && caps?.isEmbyGo == true) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                const Text('embygo 管理员诊断', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                const BadgeStrip(compact: true, badges: ['embygo Admin']),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: widget.appState.triggerLibraryRefresh,
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('触发全库扫描'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: admin == null
                    ? const Text('正在获取 embygo 运行状态...', style: TextStyle(color: PrismTheme.textSecondary))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('embygo 构建版本: ${admin['status']?['version'] ?? '-'}'),
                          Text('索引条目: ${admin['status']?['items'] ?? '-'} • 文件: ${admin['status']?['files'] ?? '-'} • 外挂字幕: ${admin['status']?['subtitle_files'] ?? '-'}'),
                          Text('电影: ${admin['counts']?['MovieCount'] ?? 0} • 剧集: ${admin['counts']?['SeriesCount'] ?? 0} • 分集: ${admin['counts']?['EpisodeCount'] ?? 0}'),
                          Text('当前在线播放会话: ${(admin['playing_sessions'] as List?)?.length ?? 0}'),
                        ],
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
