import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/models/preferences.dart';
import '../core/platform/native_playback_channel.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/admin_console_pane.dart';
import '../widgets/server_card_grid.dart';
import '../widgets/vedro_ui.dart';
import 'player_screen.dart';

/// Authentic macOS Sequoia / iOS 18 System Settings caliber Settings Screen:
/// - Desktop: Translucent sidebar with live filter box, active server card, vibrant SF-style squircle icons
/// - Mobile: Clean iOS grouped inset list -> dedicated sub-pages
/// - Native CupertinoSwitch, custom Apple pop-up menu pickers (zero raw Material dropdowns), slim sliders
/// - Multi-Server Card Grid + Per-Server Card Settings integrated directly into 服务器与线路
/// - Admin Console strictly invisible to non-administrator accounts
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

enum _SettingsSection {
  servers,
  downloads,
  fonts,
  style,
  modules,
  lists,
  uiPrefs,
  playback,
  video,
  audio,
  subtitles,
  danmaku,
  ai,
  privacy,
  admin,
}

class _NavItemMeta {
  const _NavItemMeta({
    required this.section,
    required this.title,
    required this.icon,
    required this.tintTop,
    required this.tintBottom,
    required this.group,
    this.keywords = '',
  });

  final _SettingsSection section;
  final String title;
  final IconData icon;
  final Color tintTop;
  final Color tintBottom;
  final String group;
  final String keywords;
}

class _SettingsScreenState extends State<SettingsScreen> {
  _SettingsSection _active = _SettingsSection.servers;
  final _filterCtrl = TextEditingController();
  String _filter = '';

  static const _baseNavItems = <_NavItemMeta>[
    // 媒体源与管理
    _NavItemMeta(
      section: _SettingsSection.servers,
      title: '服务器与线路',
      icon: Icons.dns_rounded,
      tintTop: Color(0xFF4F8FF7),
      tintBottom: Color(0xFF2B65D9),
      group: '媒体源与管理',
      keywords: 'server route 线路 卡片 测速',
    ),
    _NavItemMeta(
      section: _SettingsSection.downloads,
      title: '下载管理',
      icon: Icons.download_rounded,
      tintTop: Color(0xFF34D399),
      tintBottom: Color(0xFF059669),
      group: '媒体源与管理',
      keywords: 'offline cache 离线 缓存',
    ),
    _NavItemMeta(
      section: _SettingsSection.fonts,
      title: '字体管理',
      icon: Icons.font_download_rounded,
      tintTop: Color(0xFF818CF8),
      tintBottom: Color(0xFF4F46E5),
      group: '媒体源与管理',
      keywords: 'font ttf otf 字幕字体',
    ),
    // 外观与布局
    _NavItemMeta(
      section: _SettingsSection.style,
      title: '应用风格',
      icon: Icons.palette_rounded,
      tintTop: Color(0xFFA78BFA),
      tintBottom: Color(0xFF7C3AED),
      group: '外观与布局',
      keywords: 'theme color accent 主题 强调色 圆角',
    ),
    _NavItemMeta(
      section: _SettingsSection.modules,
      title: '模块配置',
      icon: Icons.dashboard_customize_rounded,
      tintTop: Color(0xFF38BDF8),
      tintBottom: Color(0xFF0284C7),
      group: '外观与布局',
      keywords: 'home layout 首页 排序',
    ),
    _NavItemMeta(
      section: _SettingsSection.lists,
      title: '列表配置',
      icon: Icons.grid_view_rounded,
      tintTop: Color(0xFF22D3EE),
      tintBottom: Color(0xFF0891B2),
      group: '外观与布局',
      keywords: 'poster density sort 海报 密度 排序',
    ),
    _NavItemMeta(
      section: _SettingsSection.uiPrefs,
      title: '界面偏好',
      icon: Icons.tune_rounded,
      tintTop: Color(0xFF94A3B8),
      tintBottom: Color(0xFF475569),
      group: '外观与布局',
      keywords: 'badge incognito 无痕 规格 剩余时间',
    ),
    // 播放与视听
    _NavItemMeta(
      section: _SettingsSection.playback,
      title: '播放设置',
      icon: Icons.play_arrow_rounded,
      tintTop: Color(0xFF60A5FA),
      tintBottom: Color(0xFF2563EB),
      group: '播放与视听',
      keywords: 'buffer pip speed intro outro 外部播放器 iina infuse',
    ),
    _NavItemMeta(
      section: _SettingsSection.video,
      title: '视频设置',
      icon: Icons.hd_rounded,
      tintTop: Color(0xFFFB923C),
      tintBottom: Color(0xFFEA580C),
      group: '播放与视听',
      keywords: 'hdr dolby vision anime4k mpv.conf 硬解 杜比视界',
    ),
    _NavItemMeta(
      section: _SettingsSection.audio,
      title: '音频设置',
      icon: Icons.graphic_eq_rounded,
      tintTop: Color(0xFFF472B6),
      tintBottom: Color(0xFFDB2777),
      group: '播放与视听',
      keywords: 'atmos passthrough drc 杜比全景声 音量',
    ),
    _NavItemMeta(
      section: _SettingsSection.subtitles,
      title: '字幕设置',
      icon: Icons.subtitles_rounded,
      tintTop: Color(0xFF2DD4BF),
      tintBottom: Color(0xFF0D9488),
      group: '播放与视听',
      keywords: 'ass srt sub 外挂 颜色 字号',
    ),
    _NavItemMeta(
      section: _SettingsSection.danmaku,
      title: '弹幕设置',
      icon: Icons.comment_rounded,
      tintTop: Color(0xFFFBBF24),
      tintBottom: Color(0xFFD97706),
      group: '播放与视听',
      keywords: 'dandanplay bilibili 弹弹play 速度 区域',
    ),
    // 智能与安全
    _NavItemMeta(
      section: _SettingsSection.ai,
      title: 'AI 服务（翻译）',
      icon: Icons.auto_awesome_rounded,
      tintTop: Color(0xFFC084FC),
      tintBottom: Color(0xFF9333EA),
      group: '智能与安全',
      keywords: 'openai deepseek translate 翻译',
    ),
    _NavItemMeta(
      section: _SettingsSection.privacy,
      title: '隐私保护',
      icon: Icons.lock_rounded,
      tintTop: Color(0xFFFB7185),
      tintBottom: Color(0xFFE11D48),
      group: '智能与安全',
      keywords: 'pin passcode lock 密码 模糊',
    ),
  ];

  static const _adminNavItem = _NavItemMeta(
    section: _SettingsSection.admin,
    title: '服务器管理台',
    icon: Icons.admin_panel_settings_rounded,
    tintTop: Color(0xFFFBBF24),
    tintBottom: Color(0xFFD97706),
    group: '管理员',
    keywords: 'admin sessions users tasks 管理员 后台',
  );

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  bool get _canShowAdmin => widget.appState.isSignedIn && widget.appState.isAdmin;

  List<_NavItemMeta> get _visibleNavItems {
    final all = _canShowAdmin ? [..._baseNavItems, _adminNavItem] : _baseNavItems;
    final q = _filter.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where((item) =>
            item.title.toLowerCase().contains(q) ||
            item.group.toLowerCase().contains(q) ||
            item.keywords.toLowerCase().contains(q))
        .toList();
  }

  String _summaryFor(_SettingsSection sec) {
    final app = widget.appState;
    final p = app.prefs;
    switch (sec) {
      case _SettingsSection.servers:
        return app.isSignedIn ? app.activeServerDisplayName : '${app.savedServers.length} 个';
      case _SettingsSection.downloads:
        return app.downloads.isEmpty ? '无任务' : '${app.downloads.length} 项';
      case _SettingsSection.fonts:
        return p.subtitleFontFamily.isEmpty ? '系统默认' : p.subtitleFontFamily;
      case _SettingsSection.style:
        return p.accentPalette.label;
      case _SettingsSection.modules:
        return '${app.homeSections.where((s) => s.visible).length} 个板块';
      case _SettingsSection.lists:
        return switch (p.listDensity) {
          'compact' => '紧凑',
          'spacious' => '宽松',
          _ => '标准',
        };
      case _SettingsSection.uiPrefs:
        return p.incognitoMode ? '无痕模式' : '标准';
      case _SettingsSection.playback:
        return '${p.bufferSizeMb}MB';
      case _SettingsSection.video:
        return p.anime4kEnabled ? 'Anime4K ${p.anime4kMode}' : (app.settings['tone_mapping'] ?? 'BT.2446a').toString().toUpperCase();
      case _SettingsSection.audio:
        return (app.settings['audio_mode'] ?? 'auto').toString();
      case _SettingsSection.subtitles:
        return '${(p.subtitleFontScale * 100).round()}%';
      case _SettingsSection.danmaku:
        return p.danmakuEnabled ? '已开启' : '关闭';
      case _SettingsSection.ai:
        return p.isAiReady ? p.aiModel : '未启用';
      case _SettingsSection.privacy:
        return p.passcodeEnabled ? '已上锁' : '未锁定';
      case _SettingsSection.admin:
        return '管理员';
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final items = _visibleNavItems;
    if (!_canShowAdmin && _active == _SettingsSection.admin) {
      _active = _SettingsSection.servers;
    }

    if (wide) {
      return Scaffold(
        backgroundColor: VedroTheme.canvas,
        body: Padding(
          padding: EdgeInsets.only(top: widget.topInset),
          child: Row(
            children: [
              // macOS Sequoia translucent-feel Sidebar
              Container(
                width: 268,
                decoration: const BoxDecoration(
                  color: Color(0xFF0E0F14),
                  border: Border(right: BorderSide(color: Color(0x18FFFFFF), width: 0.8)),
                ),
                child: Column(
                  children: [
                    // Sidebar Header: Search box + Active Server Identity Pill
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                      child: Column(
                        children: [
                          Container(
                            height: 34,
                            decoration: BoxDecoration(
                              color: const Color(0xFF171820),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0x18FFFFFF), width: 0.7),
                            ),
                            child: TextField(
                              controller: _filterCtrl,
                              onChanged: (v) => setState(() => _filter = v),
                              style: const TextStyle(color: VedroTheme.fg, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: '筛选设置…',
                                hintStyle: const TextStyle(color: VedroTheme.fg3, fontSize: 12.5),
                                prefixIcon: const Icon(Icons.search_rounded, size: 16, color: VedroTheme.fg3),
                                prefixIconConstraints: const BoxConstraints(minWidth: 34),
                                suffixIcon: _filter.isNotEmpty
                                    ? GestureDetector(
                                        onTap: () {
                                          _filterCtrl.clear();
                                          setState(() => _filter = '');
                                        },
                                        child: const Icon(Icons.close_rounded, size: 15, color: VedroTheme.fg3),
                                      )
                                    : null,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _SidebarServerMiniCard(
                            appState: widget.appState,
                            selected: _active == _SettingsSection.servers,
                            onTap: () => setState(() => _active = _SettingsSection.servers),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 28),
                        children: _buildGroupedSidebar(items),
                      ),
                    ),
                  ],
                ),
              ),

              // Right Detail Pane
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(40, 28, 40, 64),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 780),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: KeyedSubtree(
                          key: ValueKey(_active),
                          child: _SettingsDetailPane(
                            section: _active,
                            appState: widget.appState,
                            onOpenServerHub: widget.onOpenServerHub,
                            onOpenAddServer: widget.onOpenAddServer,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Mobile: iOS 18 Grouped Inset Settings List
    final grouped = <String, List<_NavItemMeta>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.group, () => []).add(item);
    }

    return Scaffold(
      backgroundColor: VedroTheme.canvas,
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 112),
        children: [
          for (final entry in grouped.entries) ...[
            _GroupHeader(entry.key),
            _GroupedCard(
              children: entry.value.map((meta) {
                return InkWell(
                  onTap: () => Navigator.of(context).push(
                    vedroRoute(_MobileSettingsSubPage(
                      title: meta.title,
                      section: meta.section,
                      appState: widget.appState,
                      onOpenServerHub: widget.onOpenServerHub,
                      onOpenAddServer: widget.onOpenAddServer,
                    )),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Row(
                      children: [
                        _AppleSquircleIcon(
                          icon: meta.icon,
                          top: meta.tintTop,
                          bottom: meta.tintBottom,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            meta.title,
                            style: const TextStyle(
                              color: VedroTheme.fg,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          _summaryFor(meta.section),
                          style: const TextStyle(color: VedroTheme.fg3, fontSize: 13),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right_rounded, size: 18, color: VedroTheme.fg3),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 22),
          Center(
            child: Text(
              'Vedro v${widget.appState.core.coreVersion}',
              style: const TextStyle(color: VedroTheme.fg3, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGroupedSidebar(List<_NavItemMeta> items) {
    final grouped = <String, List<_NavItemMeta>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.group, () => []).add(item);
    }
    final out = <Widget>[];
    for (final entry in grouped.entries) {
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
        child: Text(
          entry.key,
          style: const TextStyle(
            color: VedroTheme.fg3,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ));
      for (final meta in entry.value) {
        final selected = meta.section == _active;
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => setState(() => _active = meta.section),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7.5),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFF21232D) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: selected
                      ? Border.all(color: const Color(0x1EFFFFFF), width: 0.7)
                      : null,
                ),
                child: Row(
                  children: [
                    _AppleSquircleIcon(
                      icon: meta.icon,
                      top: meta.tintTop,
                      bottom: meta.tintBottom,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        meta.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? Colors.white : const Color(0xFFC4C7D0),
                          fontSize: 13.5,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ));
      }
    }
    out.add(Padding(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
      child: Text(
        'Vedro Core v${widget.appState.core.coreVersion}',
        style: const TextStyle(color: VedroTheme.fg3, fontSize: 11),
      ),
    ));
    return out;
  }
}

class _SidebarServerMiniCard extends StatelessWidget {
  const _SidebarServerMiniCard({
    required this.appState,
    required this.selected,
    required this.onTap,
  });

  final VedroAppState appState;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final signedIn = appState.isSignedIn;
    final activeSrv = appState.activeServer;
    final style = activeSrv != null ? appState.serverCardStyleFor(activeSrv.id) : const ServerCardStyle();
    final theme = activeSrv != null ? style.resolveTheme(activeSrv.id) : ServerCardTheme.all.first;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [theme.bgTop, theme.bgBottom],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? theme.accent.withValues(alpha: 0.7) : const Color(0x1EFFFFFF),
              width: 0.9,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: theme.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(style.iconData, size: 17, color: theme.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            signedIn ? appState.activeServerDisplayName : '未连接服务器',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (signedIn) ...[
                          const SizedBox(width: 5),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF34D399),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      signedIn
                          ? '${appState.username ?? ''} · ${appState.activeRouteDisplayName ?? '默认线路'}'
                          : '点击管理 ${appState.savedServers.length} 个服务器',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0x9CFFFFFF), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileSettingsSubPage extends StatelessWidget {
  const _MobileSettingsSubPage({
    required this.title,
    required this.section,
    required this.appState,
    required this.onOpenServerHub,
    required this.onOpenAddServer,
  });

  final String title;
  final _SettingsSection section;
  final VedroAppState appState;
  final VoidCallback onOpenServerHub;
  final void Function([String? initialUrl]) onOpenAddServer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VedroTheme.canvas,
      appBar: AppBar(title: Text(title)),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
          child: _SettingsDetailPane(
            section: section,
            appState: appState,
            onOpenServerHub: onOpenServerHub,
            onOpenAddServer: onOpenAddServer,
            hideHeading: true,
          ),
        ),
      ),
    );
  }
}

class _SettingsDetailPane extends StatefulWidget {
  const _SettingsDetailPane({
    required this.section,
    required this.appState,
    required this.onOpenServerHub,
    required this.onOpenAddServer,
    this.hideHeading = false,
  });

  final _SettingsSection section;
  final VedroAppState appState;
  final VoidCallback onOpenServerHub;
  final void Function([String? initialUrl]) onOpenAddServer;
  final bool hideHeading;

  @override
  State<_SettingsDetailPane> createState() => _SettingsDetailPaneState();
}

class _SettingsDetailPaneState extends State<_SettingsDetailPane> {
  final _aiUrlCtrl = TextEditingController();
  final _aiKeyCtrl = TextEditingController();
  final _aiModelCtrl = TextEditingController();
  final _danmakuApiCtrl = TextEditingController();
  final _fontPathCtrl = TextEditingController();
  final _downloadDirCtrl = TextEditingController();
  final _mpvConfCtrl = TextEditingController();
  bool _testingAi = false;
  String? _aiTestResult;

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant _SettingsDetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) _syncControllers();
  }

  void _syncControllers() {
    final p = widget.appState.prefs;
    _aiUrlCtrl.text = p.aiBaseUrl;
    _aiKeyCtrl.text = p.aiApiKey;
    _aiModelCtrl.text = p.aiModel;
    _danmakuApiCtrl.text = p.danmakuApiUrl;
    _downloadDirCtrl.text = p.downloadCustomDir;
    _mpvConfCtrl.text = p.customMpvConf;
  }

  @override
  void dispose() {
    _aiUrlCtrl.dispose();
    _aiKeyCtrl.dispose();
    _aiModelCtrl.dispose();
    _danmakuApiCtrl.dispose();
    _fontPathCtrl.dispose();
    _downloadDirCtrl.dispose();
    _mpvConfCtrl.dispose();
    super.dispose();
  }

  Future<void> _updateRustSetting(String key, dynamic value) async {
    final copy = Map<String, dynamic>.from(widget.appState.settings);
    copy[key] = value;
    await widget.appState.saveSettings(copy);
  }

  Future<void> _updatePrefs(VedroPreferences next) => widget.appState.updatePrefs(next);

  @override
  Widget build(BuildContext context) {
    final app = widget.appState;
    final p = app.prefs;
    final s = app.settings;

    return switch (widget.section) {
      _SettingsSection.servers => _buildServers(app),
      _SettingsSection.downloads => _buildDownloads(app, p),
      _SettingsSection.fonts => _buildFonts(app, p),
      _SettingsSection.style => _buildStyle(p),
      _SettingsSection.modules => _buildModules(app),
      _SettingsSection.lists => _buildLists(p),
      _SettingsSection.uiPrefs => _buildUiPrefs(p),
      _SettingsSection.playback => _buildPlayback(p),
      _SettingsSection.video => _buildVideo(s, p),
      _SettingsSection.audio => _buildAudio(s, p),
      _SettingsSection.subtitles => _buildSubtitles(p),
      _SettingsSection.danmaku => _buildDanmaku(p),
      _SettingsSection.ai => _buildAi(app, p),
      _SettingsSection.privacy => _buildPrivacy(p),
      _SettingsSection.admin => AdminConsolePane(appState: app),
    };
  }

  Widget _heading(String title, String subtitle, {Widget? trailing}) {
    if (widget.hideHeading) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: VedroTheme.fg3, fontSize: 13)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing],
        ],
      ),
    );
  }

  // 1. 服务器与线路 — Full Multi-Server Card Grid & Per-Server Card Settings right here!
  Widget _buildServers(VedroAppState app) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          '服务器与线路',
          '自定义每个服务器的卡片配色、图标、别名与多线路延迟测速（点击卡片右上角 ⚙ 进入卡片设置）',
          trailing: app.isSignedIn
              ? TextButton(
                  onPressed: app.logout,
                  child: const Text('断开当前连接', style: TextStyle(color: VedroTheme.danger, fontSize: 13)),
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

  // 2. 下载管理
  Widget _buildDownloads(VedroAppState app, VedroPreferences p) {
    final totalBytes = app.downloads.fold<int>(0, (sum, d) => sum + d.downloadedBytes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('下载管理', '离线缓存影片与本地文件管理（详情页点击下载图标即可加入队列）'),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '下载目录（已占用 ${fmtFileSize(totalBytes).isEmpty ? '0 B' : fmtFileSize(totalBytes)}）',
                    style: const TextStyle(color: VedroTheme.fg2, fontSize: 12.5),
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
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: () => _updatePrefs(
                          p.copyWith(downloadCustomDir: _downloadDirCtrl.text.trim()),
                        ),
                        child: const Text('保存路径', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _GroupHeader('下载队列 (${app.downloads.length})'),
        if (app.downloads.isEmpty)
          _GroupedCard(
            children: const [
              Padding(
                padding: EdgeInsets.all(28),
                child: Center(
                  child: Text('暂无离线下载任务', style: TextStyle(color: VedroTheme.fg3, fontSize: 13)),
                ),
              ),
            ],
          )
        else
          _GroupedCard(
            children: app.downloads.map((task) {
              final done = task.status == 'completed';
              final failed = task.status == 'failed';
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
                              Text(
                                task.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: VedroTheme.fg, fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                done
                                    ? '已完成 · ${fmtFileSize(task.downloadedBytes)}'
                                    : (failed
                                        ? '失败：${task.error ?? '网络错误'}'
                                        : '下载中 ${(task.progress * 100).round()}% · ${fmtFileSize(task.downloadedBytes)}'),
                                style: TextStyle(
                                  color: failed ? VedroTheme.danger : VedroTheme.fg3,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (done && task.filePath.isNotEmpty)
                          IconButton(
                            tooltip: '播放离线文件',
                            icon: const Icon(Icons.play_arrow_rounded, color: VedroTheme.fg),
                            onPressed: () => Navigator.of(context).push(
                              vedroRoute(PlayerScreen(
                                item: MediaItemModel(id: task.itemId, name: task.title, type: 'Movie'),
                                appState: app,
                                localFilePath: task.filePath,
                              )),
                            ),
                          ),
                        IconButton(
                          tooltip: '删除',
                          icon: const Icon(Icons.delete_outline_rounded, size: 19, color: VedroTheme.fg3),
                          onPressed: () => app.deleteDownload(task.id),
                        ),
                      ],
                    ),
                    if (!done && !failed) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: task.progress > 0 ? task.progress : null,
                          minHeight: 3,
                          backgroundColor: VedroTheme.surface3,
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

  // 3. 字体管理
  Widget _buildFonts(VedroAppState app, VedroPreferences p) {
    const builtIn = [
      ('', '系统默认字体'),
      ('PingFang SC', '苹方简体 (PingFang SC)'),
      ('Hiragino Sans GB', '冬青黑体 (Hiragino Sans GB)'),
      ('Noto Sans CJK SC', '思源黑体 (Noto Sans CJK)'),
      ('SF Pro Display', 'SF Pro Display'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('字体管理', '管理外挂/内封 ASS & SRT 字幕渲染字体（自动注入 libmpv sub-fonts-dir）'),
        _GroupedCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('导入本地字体 (.ttf / .otf / .ttc)', style: TextStyle(color: VedroTheme.fg, fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _fontPathCtrl,
                          decoration: const InputDecoration(hintText: '/path/to/MySubtitleFont.ttf'),
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
                                  SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
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
                            final name = await app.importSubtitleFont(_fontPathCtrl.text.trim());
                            _fontPathCtrl.clear();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('已导入并选用字体：$name')),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
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
              _CheckRow(
                title: path.split('/').last,
                subtitle: path,
                selected: p.subtitleFontFamily ==
                    path.split('/').last.replaceAll(RegExp(r'\.(ttf|otf|ttc)$', caseSensitive: false), ''),
                onTap: () {
                  final stem = path.split('/').last.replaceAll(RegExp(r'\.(ttf|otf|ttc)$', caseSensitive: false), '');
                  _updatePrefs(p.copyWith(subtitleFontFamily: stem));
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: VedroTheme.fg3),
                  onPressed: () => app.removeSubtitleFont(path),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // 4. 应用风格
  Widget _buildStyle(VedroPreferences p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('应用风格', '定制全局强调色、海报圆角、毛玻璃强度与动效'),
        _GroupedCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('全局强调色', style: TextStyle(color: VedroTheme.fg, fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: AccentPalette.all.map((pal) {
                      final active = p.accentId == pal.id;
                      return PressableScale(
                        onTap: () => _updatePrefs(p.copyWith(accentId: pal.id)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: active ? pal.accent.withValues(alpha: 0.18) : const Color(0xFF1C1E26),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: active ? pal.accent : const Color(0x1CFFFFFF),
                              width: active ? 1.3 : 0.7,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 13,
                                height: 13,
                                decoration: BoxDecoration(color: pal.accent, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                pal.label,
                                style: TextStyle(
                                  color: active ? Colors.white : VedroTheme.fg2,
                                  fontSize: 13,
                                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            _InlineSegmentedRow<double>(
              title: '海报卡片圆角',
              value: p.cardRadius,
              items: const [(8.0, '干练 8px'), (12.0, '标准 12px'), (16.0, '柔和 16px')],
              onChanged: (v) => _updatePrefs(p.copyWith(cardRadius: v)),
            ),
            _InlineSegmentedRow<String>(
              title: '毛玻璃通透度',
              value: p.glassIntensity,
              items: const [('subtle', '微雾'), ('standard', '标准'), ('rich', '浓郁')],
              onChanged: (v) => _updatePrefs(p.copyWith(glassIntensity: v)),
            ),
            _SwitchRow(
              title: '减弱动态效果',
              subtitle: '降低页面切换动效幅度以获得更干脆的响应',
              value: p.reduceMotion,
              onChanged: (v) => _updatePrefs(p.copyWith(reduceMotion: v)),
            ),
          ],
        ),
      ],
    );
  }

  // 5. 模块配置
  Widget _buildModules(VedroAppState app) {
    final sections = List<HomeSectionConfig>.from(app.homeSections);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('模块配置', '拖拽调整首页各模块的上下顺序，并自由控制显示或隐藏'),
        _GroupedCard(
          children: [
            _SwitchRow(
              title: '顶部横幅轮播',
              subtitle: '仅自动筛选带横版背景图的影片，拒绝竖图拉伸',
              value: app.showHomeHero,
              onChanged: (v) => app.saveHomeLayout(sections, showHero: v),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: _GroupHeader('首页板块顺序（拖拽手柄排序）')),
            TextButton(
              onPressed: app.resetHomeLayout,
              child: const Text('恢复默认', style: TextStyle(color: VedroTheme.fg2, fontSize: 12.5)),
            ),
          ],
        ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: sections.length,
          onReorder: (oldIdx, newIdx) {
            if (newIdx > oldIdx) newIdx -= 1;
            final item = sections.removeAt(oldIdx);
            sections.insert(newIdx, item);
            app.saveHomeLayout(sections);
          },
          itemBuilder: (context, idx) {
            final sec = sections[idx];
            return Padding(
              key: ValueKey('mod_${sec.id}'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF13141A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x1DFFFFFF), width: 0.85),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${idx + 1}',
                        style: const TextStyle(
                          color: VedroTheme.fg3,
                          fontSize: 12.5,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sec.title,
                            style: TextStyle(
                              color: sec.visible ? VedroTheme.fg : VedroTheme.fg3,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(sec.subtitle, style: const TextStyle(color: VedroTheme.fg3, fontSize: 11.5)),
                        ],
                      ),
                    ),
                    Transform.scale(
                      scale: 0.78,
                      child: CupertinoSwitch(
                        value: sec.visible,
                        activeTrackColor: Theme.of(context).colorScheme.primary,
                        onChanged: (v) {
                          sections[idx] = sec.copyWith(visible: v);
                          app.saveHomeLayout(sections);
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    ReorderableDragStartListener(
                      index: idx,
                      child: const MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.drag_handle_rounded, size: 19, color: VedroTheme.fg3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // 6. 列表配置
  Widget _buildLists(VedroPreferences p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('列表配置', '调整海报墙排版密度、角标信息与默认排序'),
        _GroupedCard(
          children: [
            _InlineSegmentedRow<String>(
              title: '海报墙密度',
              value: p.listDensity,
              items: const [('compact', '紧凑'), ('comfortable', '标准'), ('spacious', '宽松')],
              onChanged: (v) => _updatePrefs(p.copyWith(listDensity: v)),
            ),
            _AppleMenuPickerRow<String>(
              title: '媒体库默认排序',
              value: p.defaultSort,
              items: const {
                'DateCreated': '按入库时间',
                'SortName': '按片名 A–Z',
                'CommunityRating': '按社区评分',
                'PremiereDate': '按发行年份',
              },
              onChanged: (v) => _updatePrefs(p.copyWith(defaultSort: v)),
            ),
            _SwitchRow(
              title: '显示已看角标',
              value: p.showWatchedBadge,
              onChanged: (v) => _updatePrefs(p.copyWith(showWatchedBadge: v)),
            ),
            _SwitchRow(
              title: '显示未看集数角标',
              value: p.showUnplayedCount,
              onChanged: (v) => _updatePrefs(p.copyWith(showUnplayedCount: v)),
            ),
            _SwitchRow(
              title: '显示评分信息',
              value: p.showRatings,
              onChanged: (v) => _updatePrefs(p.copyWith(showRatings: v)),
            ),
            _SwitchRow(
              title: '显示发行年份',
              value: p.showYear,
              onChanged: (v) => _updatePrefs(p.copyWith(showYear: v)),
            ),
          ],
        ),
      ],
    );
  }

  // 7. 界面偏好
  Widget _buildUiPrefs(VedroPreferences p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('界面偏好', '控制详情页与播放器内的信息呈现与交互提示'),
        _GroupedCard(
          children: [
            _SwitchRow(
              title: '显示画质与音频规格标识',
              subtitle: '在详情页与播放器顶部展示 4K / Dolby Vision / Atmos 细线标签',
              value: p.showSpecBadges,
              onChanged: (v) => _updatePrefs(p.copyWith(showSpecBadges: v)),
            ),
            _SwitchRow(
              title: '进度条右侧默认显示剩余时长',
              subtitle: '例如显示 -01:12:08，播放时也可点击时间切换',
              value: p.showRemainingTime,
              onChanged: (v) => _updatePrefs(p.copyWith(showRemainingTime: v)),
            ),
            _SwitchRow(
              title: '退出播放前二次确认',
              subtitle: '防止误触 Esc 或返回键中断观影',
              value: p.confirmExitPlayer,
              onChanged: (v) => _updatePrefs(p.copyWith(confirmExitPlayer: v)),
            ),
            _SwitchRow(
              title: '无痕观影模式',
              subtitle: '开启后不向服务器回传播放进度与观看历史',
              value: p.incognitoMode,
              onChanged: (v) => _updatePrefs(p.copyWith(incognitoMode: v)),
            ),
          ],
        ),
      ],
    );
  }

  // 8. 播放设置
  Widget _buildPlayback(VedroPreferences p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('播放设置', '默认播放引擎、内存缓存、倍速、手势、片头片尾跳过与画中画'),
        _GroupedCard(
          children: [
            _AppleMenuPickerRow<String>(
              title: '默认播放器引擎',
              value: p.externalPlayer,
              items: const {
                'builtin': '内置 Rust + MPV（推荐）',
                'iina': 'IINA (macOS)',
                'infuse': 'Infuse (macOS / iOS)',
                'mpv': '外部 MPV',
                'vlc': 'VLC',
                'potplayer': 'PotPlayer (Windows)',
              },
              onChanged: (v) => _updatePrefs(p.copyWith(externalPlayer: v)),
            ),
            _AppleMenuPickerRow<int>(
              title: '播放器内存缓存大小',
              value: p.bufferSizeMb,
              items: const {
                32: '32 MB（省内存）',
                64: '64 MB',
                128: '128 MB（推荐）',
                256: '256 MB（4K Remux）',
                512: '512 MB（超大缓存）',
              },
              onChanged: (v) => _updatePrefs(p.copyWith(bufferSizeMb: v)),
            ),
            _InlineSegmentedRow<int>(
              title: '快进 / 快退步长',
              value: p.seekStepSecs,
              items: const [(5, '5s'), (10, '10s'), (15, '15s'), (30, '30s')],
              onChanged: (v) => _updatePrefs(p.copyWith(seekStepSecs: v)),
            ),
            _AppleMenuPickerRow<double>(
              title: '默认播放倍速',
              value: p.defaultSpeed,
              items: {0.75: '0.75×', 1.0: '1.0×', 1.25: '1.25×', 1.5: '1.5×', 2.0: '2.0×'},
              onChanged: (v) => _updatePrefs(p.copyWith(defaultSpeed: v)),
            ),
            _InlineSegmentedRow<double>(
              title: '长按屏幕倍速',
              value: p.longPressSpeed,
              items: const [(1.5, '1.5×'), (2.0, '2.0×'), (2.5, '2.5×'), (3.0, '3.0×')],
              onChanged: (v) => _updatePrefs(p.copyWith(longPressSpeed: v)),
            ),
            _SwitchRow(
              title: '双指捏合缩放画面',
              subtitle: '播放时支持双指自由缩放，松手保持比例',
              value: p.pinchToZoom,
              onChanged: (v) => _updatePrefs(p.copyWith(pinchToZoom: v)),
            ),
            _SwitchRow(
              title: '记忆播放器亮度',
              subtitle: '下次进入播放时自动恢复上次调节的画面亮度',
              value: p.rememberBrightness,
              onChanged: (v) => _updatePrefs(p.copyWith(rememberBrightness: v)),
            ),
            _SwitchRow(
              title: '启用画中画 (PiP)',
              subtitle: '在播放器顶栏显示画中画入口',
              value: p.enablePip,
              onChanged: (v) => _updatePrefs(p.copyWith(enablePip: v)),
            ),
            _SwitchRow(
              title: '后台继续播放音频',
              value: p.backgroundAudio,
              onChanged: (v) => _updatePrefs(p.copyWith(backgroundAudio: v)),
            ),
            _SwitchRow(
              title: '自动连播下一集',
              value: p.autoPlayNext,
              onChanged: (v) => _updatePrefs(p.copyWith(autoPlayNext: v)),
            ),
            _SwitchRow(
              title: '记住播放进度续播',
              value: p.rememberPosition,
              onChanged: (v) => _updatePrefs(p.copyWith(rememberPosition: v)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _GroupHeader('片头与片尾跳过'),
        _GroupedCard(
          children: [
            _SwitchRow(
              title: '自动跳过片头',
              subtitle: '服务端提供标记或设置自定义片头时长时自动跳转',
              value: p.autoSkipIntro,
              onChanged: (v) => _updatePrefs(p.copyWith(autoSkipIntro: v)),
            ),
            _SliderRow(
              title: '自定义跳过片头时长',
              valueText: p.customSkipIntroSecs == 0 ? '关闭' : '${p.customSkipIntroSecs} 秒',
              value: p.customSkipIntroSecs.toDouble(),
              min: 0,
              max: 180,
              divisions: 18,
              onChanged: (v) => _updatePrefs(p.copyWith(customSkipIntroSecs: v.round())),
            ),
            _SwitchRow(
              title: '自动跳过片尾',
              value: p.autoSkipOutro,
              onChanged: (v) => _updatePrefs(p.copyWith(autoSkipOutro: v)),
            ),
            _SliderRow(
              title: '自定义跳过片尾时长',
              valueText: p.customSkipOutroSecs == 0 ? '关闭' : '${p.customSkipOutroSecs} 秒',
              value: p.customSkipOutroSecs.toDouble(),
              min: 0,
              max: 180,
              divisions: 18,
              onChanged: (v) => _updatePrefs(p.copyWith(customSkipOutroSecs: v.round())),
            ),
          ],
        ),
      ],
    );
  }

  // 9. 视频设置
  Widget _buildVideo(Map<String, dynamic> s, VedroPreferences p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('视频设置', '硬件解码、杜比视界直出、HDR 色调映射、Anime4K 与自定义 mpv.conf'),
        _GroupedCard(
          children: [
            _AppleMenuPickerRow<String>(
              title: '硬件解码模式',
              value: (s['hwdec'] ?? 'auto_zero_copy').toString(),
              items: const {
                'auto_zero_copy': '零拷贝硬解（推荐）',
                'auto_copy': 'Copy-Back 硬解',
                'software': '纯软件解码',
              },
              onChanged: (v) => _updateRustSetting('hwdec', v),
            ),
            _SwitchRow(
              title: '优先原生杜比视界',
              subtitle: '支持原生 HDR/DoVi 的屏幕直出，否则自动 Tone-Mapping',
              value: s['prefer_native_dolby_vision'] != false,
              onChanged: (v) => _updateRustSetting('prefer_native_dolby_vision', v),
            ),
            _AppleMenuPickerRow<String>(
              title: 'HDR 色调映射算法',
              value: (s['tone_mapping'] ?? 'bt2446a').toString(),
              items: const {
                'bt2446a': 'BT.2446a（自然高光）',
                'spline': 'Spline（动态曲线）',
                'st2094_40': 'ST.2094-40',
                'reinhard': 'Reinhard',
                'clip': 'Clip（直通）',
              },
              onChanged: (v) => _updateRustSetting('tone_mapping', v),
            ),
            _SwitchRow(
              title: '动态峰值亮度计算',
              subtitle: '实时分析每帧 HDR 峰值以防过曝',
              value: p.hdrComputePeak,
              onChanged: (v) => _updatePrefs(p.copyWith(hdrComputePeak: v)),
            ),
            _SwitchRow(
              title: '去色带 (Deband)',
              subtitle: '平滑暗场渐变断层（适合动漫与低码率片源）',
              value: s['deband'] == true,
              onChanged: (v) => _updateRustSetting('deband', v),
            ),
            _AppleMenuPickerRow<String>(
              title: '默认画面比例',
              value: p.defaultAspect,
              items: const {
                'fit': '原始比例（适应）',
                'fill': '铺满屏幕（裁切黑边）',
                '16:9': '16:9',
                '21:9': '21:9',
                '4:3': '4:3',
              },
              onChanged: (v) => _updatePrefs(p.copyWith(defaultAspect: v)),
            ),
            _AppleMenuPickerRow<String>(
              title: '帧率同步策略',
              value: p.videoSync,
              items: const {
                'audio': '音画同步（标准）',
                'display-resample': '显示器刷新率重采样（防微卡顿）',
              },
              onChanged: (v) => _updatePrefs(p.copyWith(videoSync: v)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _GroupHeader('Anime4K 超分与高级 MPV 参数'),
        _GroupedCard(
          children: [
            _SwitchRow(
              title: '启用 Anime4K 动漫超分锐化',
              subtitle: '自动启用 LanczosSharp 升频、暗场去色带与线条增强',
              value: p.anime4kEnabled,
              onChanged: (v) => _updatePrefs(p.copyWith(anime4kEnabled: v)),
            ),
            _AppleMenuPickerRow<String>(
              title: 'Anime4K 锐化等级',
              value: p.anime4kMode,
              items: const {
                'A': 'Mode A（高锐度修复）',
                'B': 'Mode B（均衡推荐）',
                'C': 'Mode C（柔和自然）',
                'A+A': 'Mode A+A（强效超分）',
                'B+B': 'Mode B+B（高质感均衡）',
              },
              onChanged: (v) => _updatePrefs(p.copyWith(anime4kMode: v)),
            ),
            _SwitchRow(
              title: '仅对动漫 / 动画片源生效',
              subtitle: '电影与实拍剧集保持原片质感，不额外锐化',
              value: p.anime4kOnlyAnime,
              onChanged: (v) => _updatePrefs(p.copyWith(anime4kOnlyAnime: v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '自定义 mpv.conf 参数（每行一条 key=value，# 开头为注释）',
                    style: TextStyle(color: VedroTheme.fg2, fontSize: 12.5),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _mpvConfCtrl,
                    minLines: 3,
                    maxLines: 6,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: VedroTheme.fg),
                    decoration: const InputDecoration(
                      hintText: '# 示例：\ninterpolation=yes\ntscale=oversample\ndither-depth=auto',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton(
                      onPressed: () async {
                        await _updatePrefs(p.copyWith(customMpvConf: _mpvConfCtrl.text.trim()));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已保存自定义 mpv.conf，下次播放生效')),
                          );
                        }
                      },
                      child: const Text('保存 mpv.conf', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 10. 音频设置
  Widget _buildAudio(Map<String, dynamic> s, VedroPreferences p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('音频设置', '杜比全景声直通、空间音频、夜间模式与音量增益上限'),
        _GroupedCard(
          children: [
            _AppleMenuPickerRow<String>(
              title: '音频输出模式',
              value: (s['audio_mode'] ?? 'auto').toString(),
              items: const {
                'auto': '自动（推荐）',
                'passthrough_bitstream': 'HDMI 源码直通 (Atmos / DTS:X)',
                'spatial_audio': '系统空间音频',
                'headphone_binaural': '耳机双耳空间化',
                'pcm_stereo': '32-bit 立体声 PCM',
              },
              onChanged: (v) => _updateRustSetting('audio_mode', v),
            ),
            _InlineSegmentedRow<String>(
              title: '首选音轨语言',
              value: p.preferredAudioLang,
              items: const [('auto', '默认'), ('zh', '中文'), ('en', '英语'), ('ja', '日语')],
              onChanged: (v) => _updatePrefs(p.copyWith(preferredAudioLang: v)),
            ),
            _InlineSegmentedRow<int>(
              title: '最大音量增益',
              value: p.maxVolumePercent,
              items: const [(100, '100%'), (150, '150%'), (200, '200%')],
              onChanged: (v) => _updatePrefs(p.copyWith(maxVolumePercent: v)),
            ),
            _SwitchRow(
              title: '夜间模式 (DRC 动态范围压缩)',
              subtitle: '降低爆炸声动态峰值，深夜观影更温和',
              value: s['night_mode'] == true,
              onChanged: (v) => _updateRustSetting('night_mode', v),
            ),
            _SwitchRow(
              title: '人声对白增强',
              value: s['dialogue_boost'] == true,
              onChanged: (v) => _updateRustSetting('dialogue_boost', v),
            ),
          ],
        ),
      ],
    );
  }

  // 11. 字幕设置
  Widget _buildSubtitles(VedroPreferences p) {
    const colors = [
      ('#FFFFFF', '纯白', Color(0xFFFFFFFF)),
      ('#FFE082', '暖黄', Color(0xFFFFE082)),
      ('#A7F3D0', '淡青', Color(0xFFA7F3D0)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('字幕设置', '默认字幕语言、字号缩放、垂直位置、颜色与外挂加载'),
        _GroupedCard(
          children: [
            _InlineSegmentedRow<String>(
              title: '首选字幕语言',
              value: p.preferredSubLang,
              items: const [('zh', '中文'), ('en', '英文'), ('ja', '日文'), ('off', '关闭')],
              onChanged: (v) => _updatePrefs(p.copyWith(preferredSubLang: v)),
            ),
            _SwitchRow(
              title: '自动加载服务器外挂字幕',
              value: p.autoLoadExternalSubs,
              onChanged: (v) => _updatePrefs(p.copyWith(autoLoadExternalSubs: v)),
            ),
            _SwitchRow(
              title: '强制覆盖 ASS 字幕样式',
              subtitle: '使用下方统一字体与字号覆盖特效字幕原有样式',
              value: p.forceAssOverride,
              onChanged: (v) => _updatePrefs(p.copyWith(forceAssOverride: v)),
            ),
            _SliderRow(
              title: '默认字号缩放',
              valueText: '${(p.subtitleFontScale * 100).round()}%',
              value: p.subtitleFontScale,
              min: 0.6,
              max: 1.8,
              divisions: 12,
              onChanged: (v) => _updatePrefs(p.copyWith(subtitleFontScale: v)),
            ),
            _SliderRow(
              title: '默认垂直位置',
              valueText: '${p.subtitlePos}%',
              value: p.subtitlePos.toDouble(),
              min: 65,
              max: 100,
              divisions: 7,
              onChanged: (v) => _updatePrefs(p.copyWith(subtitlePos: v.round())),
            ),
            _SliderRow(
              title: '背景遮罩不透明度',
              valueText: '${(p.subtitleBgOpacity * 100).round()}%',
              value: p.subtitleBgOpacity,
              min: 0.0,
              max: 0.8,
              divisions: 8,
              onChanged: (v) => _updatePrefs(p.copyWith(subtitleBgOpacity: v)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('字幕颜色', style: TextStyle(color: VedroTheme.fg, fontSize: 14)),
                  ),
                  ...colors.map((entry) {
                    final (hex, label, c) = entry;
                    final on = p.subtitleColorHex == hex;
                    return Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: GestureDetector(
                        onTap: () => _updatePrefs(p.copyWith(subtitleColorHex: hex)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5.5),
                          decoration: BoxDecoration(
                            color: on ? const Color(0x24FFFFFF) : const Color(0xFF1C1E26),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: on ? Colors.white : const Color(0x1EFFFFFF),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Text(label, style: const TextStyle(color: VedroTheme.fg, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 12. 弹幕设置
  Widget _buildDanmaku(VedroPreferences p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('弹幕设置', '控制播放器内 60fps 弹幕渲染开关、透明度、显示区域与自定义弹幕源'),
        _GroupedCard(
          children: [
            _SwitchRow(
              title: '默认开启弹幕层',
              value: p.danmakuEnabled,
              onChanged: (v) => _updatePrefs(p.copyWith(danmakuEnabled: v)),
            ),
            _SliderRow(
              title: '弹幕不透明度',
              valueText: '${(p.danmakuOpacity * 100).round()}%',
              value: p.danmakuOpacity,
              min: 0.2,
              max: 1.0,
              divisions: 8,
              onChanged: (v) => _updatePrefs(p.copyWith(danmakuOpacity: v)),
            ),
            _SliderRow(
              title: '弹幕字号',
              valueText: '${p.danmakuFontSize.round()} pt',
              value: p.danmakuFontSize,
              min: 14,
              max: 28,
              divisions: 7,
              onChanged: (v) => _updatePrefs(p.copyWith(danmakuFontSize: v)),
            ),
            _SliderRow(
              title: '弹幕滚动时长（越小越快）',
              valueText: '${p.danmakuSpeedSecs.round()} 秒/屏',
              value: p.danmakuSpeedSecs,
              min: 5,
              max: 15,
              divisions: 10,
              onChanged: (v) => _updatePrefs(p.copyWith(danmakuSpeedSecs: v)),
            ),
            _InlineSegmentedRow<double>(
              title: '弹幕显示区域',
              value: p.danmakuArea,
              items: const [(0.25, '1/4 屏'), (0.5, '半屏'), (0.75, '3/4 屏'), (1.0, '全屏')],
              onChanged: (v) => _updatePrefs(p.copyWith(danmakuArea: v)),
            ),
            _SwitchRow(
              title: '屏蔽顶部固定弹幕',
              value: p.danmakuHideTop,
              onChanged: (v) => _updatePrefs(p.copyWith(danmakuHideTop: v)),
            ),
            _SwitchRow(
              title: '屏蔽底部固定弹幕',
              value: p.danmakuHideBottom,
              onChanged: (v) => _updatePrefs(p.copyWith(danmakuHideBottom: v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('自定义弹幕源接口（支持弹弹play 兼容 API 或 B站 XML 链接）',
                      style: TextStyle(color: VedroTheme.fg2, fontSize: 12.5)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _danmakuApiCtrl,
                          decoration: const InputDecoration(hintText: 'https://api.dandanplay.net'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: () => _updatePrefs(
                          p.copyWith(danmakuApiUrl: _danmakuApiCtrl.text.trim()),
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
      ],
    );
  }

  // 13. AI 服务（翻译）
  Widget _buildAi(VedroAppState app, VedroPreferences p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('AI 服务（翻译）', '配置 OpenAI 兼容接口（OpenAI / DeepSeek / Ollama），用于详情页简介翻译'),
        _GroupedCard(
          children: [
            _SwitchRow(
              title: '启用 AI 翻译服务',
              subtitle: '开启后详情页将出现「AI 翻译简介」按钮',
              value: p.aiEnabled,
              onChanged: (v) => _updatePrefs(p.copyWith(aiEnabled: v)),
            ),
            _InlineSegmentedRow<String>(
              title: '目标语言',
              value: p.aiTargetLang,
              items: const [
                ('简体中文', '简中'),
                ('繁體中文', '繁中'),
                ('English', 'EN'),
                ('日本語', '日文'),
              ],
              onChanged: (v) => _updatePrefs(p.copyWith(aiTargetLang: v)),
            ),
            _SwitchRow(
              title: '双语对照模式',
              value: p.aiBilingualSubtitle,
              onChanged: (v) => _updatePrefs(p.copyWith(aiBilingualSubtitle: v)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _aiUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'API Base URL',
                      hintText: 'https://api.openai.com/v1',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _aiKeyCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'API Key', hintText: 'sk-...'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _aiModelCtrl,
                    decoration: const InputDecoration(
                      labelText: '模型名称',
                      hintText: 'gpt-4o-mini / deepseek-chat',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: () async {
                          await _updatePrefs(p.copyWith(
                            aiBaseUrl: _aiUrlCtrl.text.trim(),
                            aiApiKey: _aiKeyCtrl.text.trim(),
                            aiModel: _aiModelCtrl.text.trim(),
                          ));
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('AI 配置已保存')),
                            );
                          }
                        },
                        child: const Text('保存配置', style: TextStyle(fontSize: 13)),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: _testingAi
                            ? null
                            : () async {
                                await _updatePrefs(p.copyWith(
                                  aiEnabled: true,
                                  aiBaseUrl: _aiUrlCtrl.text.trim(),
                                  aiApiKey: _aiKeyCtrl.text.trim(),
                                  aiModel: _aiModelCtrl.text.trim(),
                                ));
                                setState(() {
                                  _testingAi = true;
                                  _aiTestResult = null;
                                });
                                try {
                                  final res = await app.translateText('Hello Cinema World');
                                  if (mounted) setState(() => _aiTestResult = '连接成功：$res');
                                } catch (e) {
                                  if (mounted) setState(() => _aiTestResult = '测试失败：$e');
                                } finally {
                                  if (mounted) setState(() => _testingAi = false);
                                }
                              },
                        child: Text(_testingAi ? '测试中…' : '测试连通性', style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                  if (_aiTestResult != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _aiTestResult!,
                      style: TextStyle(
                        color: _aiTestResult!.startsWith('连接成功')
                            ? const Color(0xFF34D399)
                            : VedroTheme.danger,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 14. 隐私保护
  Widget _buildPrivacy(VedroPreferences p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('隐私保护', '设置应用进入密码锁与后台切换模糊遮罩'),
        _GroupedCard(
          children: [
            _SwitchRow(
              title: '启用密码解锁应用',
              subtitle: '启动或从后台切回时需要输入 4 位数字密码',
              value: p.passcodeEnabled,
              onChanged: (v) async {
                if (v) {
                  await _openSetPinDialog(p);
                } else {
                  await _updatePrefs(p.copyWith(passcodeEnabled: false));
                }
              },
            ),
            if (p.passcodeEnabled)
              _ActionRow(
                title: '修改 4 位解锁密码',
                trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: VedroTheme.fg3),
                onTap: () => _openSetPinDialog(p),
              ),
            _InlineSegmentedRow<int>(
              title: '自动锁定时间',
              value: p.lockTimeoutSecs,
              items: const [(0, '立即'), (60, '1 分'), (300, '5 分'), (900, '15 分')],
              onChanged: (v) => _updatePrefs(p.copyWith(lockTimeoutSecs: v)),
            ),
            _SwitchRow(
              title: '切至后台时模糊应用画面',
              subtitle: '防止在多任务切换器中露出正在浏览的片库内容',
              value: p.blurInBackground,
              onChanged: (v) => _updatePrefs(p.copyWith(blurInBackground: v)),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openSetPinDialog(VedroPreferences p) async {
    final pin1 = TextEditingController();
    final pin2 = TextEditingController();
    String? err;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          title: const Text('设置 4 位应用密码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pin1,
                autofocus: true,
                obscureText: true,
                maxLength: 4,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '输入 4 位数字密码', counterText: ''),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pin2,
                obscureText: true,
                maxLength: 4,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '再次确认密码', counterText: ''),
              ),
              if (err != null) ...[
                const SizedBox(height: 10),
                Text(err!, style: const TextStyle(color: VedroTheme.danger, fontSize: 12.5)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final a = pin1.text.trim();
                final b = pin2.text.trim();
                if (!RegExp(r'^\d{4}$').hasMatch(a)) {
                  setModal(() => err = '请输入 4 位纯数字');
                  return;
                }
                if (a != b) {
                  setModal(() => err = '两次输入的密码不一致');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('保存密码'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      await _updatePrefs(p.copyWith(
        passcodeEnabled: true,
        passcodeHash: hashPasscode(pin1.text.trim()),
      ));
    }
    pin1.dispose();
    pin2.dispose();
  }
}

/// Genuine macOS / iOS System Settings vibrant gradient squircle icon tile.
class _AppleSquircleIcon extends StatelessWidget {
  const _AppleSquircleIcon({
    required this.icon,
    required this.top,
    required this.bottom,
    this.size = 26,
  });

  final IconData icon;
  final Color top;
  final Color bottom;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ),
        borderRadius: BorderRadius.circular(size * 0.27),
        boxShadow: [
          BoxShadow(
            color: bottom.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, size: size * 0.58, color: Colors.white),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Text(
        text,
        style: const TextStyle(
          color: VedroTheme.fg3,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
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
        color: const Color(0xFF13141A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1DFFFFFF), width: 0.85),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0x14FFFFFF)),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.title,
    required this.onTap,
    this.trailing,
  });

  final String title;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(color: VedroTheme.fg, fontSize: 14))),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: selected ? Colors.white : VedroTheme.fg,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: VedroTheme.fg3, fontSize: 11.5),
                    ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_rounded, size: 18, color: accent),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// Sleek Apple pop-up menu picker pill (replaces raw Material DropdownButton).
class _AppleMenuPickerRow<T> extends StatelessWidget {
  const _AppleMenuPickerRow({
    required this.title,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String title;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final safeValue = items.containsKey(value) ? value : items.keys.first;
    final label = items[safeValue] ?? '';
    final accent = Theme.of(context).colorScheme.secondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(color: VedroTheme.fg, fontSize: 14))),
          const SizedBox(width: 12),
          PopupMenuButton<T>(
            initialValue: safeValue,
            onSelected: onChanged,
            color: const Color(0xFF1C1E27),
            elevation: 16,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0x28FFFFFF), width: 0.8),
            ),
            itemBuilder: (_) => items.entries.map((e) {
              final selected = e.key == safeValue;
              return PopupMenuItem<T>(
                value: e.key,
                height: 38,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.value,
                        style: TextStyle(
                          color: selected ? Colors.white : const Color(0xFFC8CCD6),
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (selected) Icon(Icons.check_rounded, size: 16, color: accent),
                  ],
                ),
              );
            }).toList(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6.5),
              decoration: BoxDecoration(
                color: const Color(0xFF1D1F28),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0x24FFFFFF), width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 210),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(Icons.unfold_more_rounded, size: 15, color: VedroTheme.fg3),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Clean macOS inline segmented control row for compact 2–4 option settings.
class _InlineSegmentedRow<T> extends StatelessWidget {
  const _InlineSegmentedRow({
    required this.title,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String title;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final seg = Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C24),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0x1DFFFFFF), width: 0.7),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: items.map((entry) {
            final active = entry.$1 == value;
            return GestureDetector(
              onTap: () => onChanged(entry.$1),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFF2D303E) : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    entry.$2,
                    style: TextStyle(
                      color: active ? Colors.white : VedroTheme.fg3,
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 460) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: VedroTheme.fg, fontSize: 14)),
                const SizedBox(height: 8),
                seg,
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(color: VedroTheme.fg, fontSize: 14))),
              const SizedBox(width: 10),
              seg,
            ],
          ),
        );
      },
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
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
          const SizedBox(width: 12),
          Transform.scale(
            scale: 0.78,
            child: CupertinoSwitch(
              value: value,
              activeTrackColor: Theme.of(context).colorScheme.primary,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.title,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String title;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(color: VedroTheme.fg, fontSize: 14))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF1D1F28),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  valueText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.0,
              activeTrackColor: accent,
              inactiveTrackColor: const Color(0x28FFFFFF),
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
