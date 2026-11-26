import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/models/preferences.dart';
import '../core/platform/native_playback_channel.dart';
import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/admin_console_pane.dart';
import '../widgets/server_card_grid.dart';
import '../widgets/skin_studio_pane.dart';
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
  proxy,
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
  late _SettingsSection _active;
  final _filterCtrl = TextEditingController();
  final _detailScrollCtrl = ScrollController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _active = _SettingsSection.values.firstWhere(
      (s) => s.name == widget.appState.activeSettingsSection,
      orElse: () => _SettingsSection.servers,
    );
  }

  void _selectSection(_SettingsSection sec) {
    if (_active == sec) return;
    widget.appState.activeSettingsSection = sec.name;
    setState(() => _active = sec);
    if (_detailScrollCtrl.hasClients) {
      _detailScrollCtrl.jumpTo(0);
    }
  }

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
      section: _SettingsSection.proxy,
      title: '网络代理',
      icon: Icons.vpn_lock_rounded,
      tintTop: Color(0xFF38BDF8),
      tintBottom: Color(0xFF0284C7),
      group: '媒体源与管理',
      keywords: 'proxy singbox sing-box mihomo clash socks5 订阅 节点 代理',
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
      title: 'AI 翻译',
      icon: Icons.auto_awesome_rounded,
      tintTop: Color(0xFFC084FC),
      tintBottom: Color(0xFF9333EA),
      group: '智能与安全',
      keywords: 'openai deepseek bilibili translate 翻译 模型',
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
    _detailScrollCtrl.dispose();
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
      case _SettingsSection.proxy:
        return switch (p.inAppProxyMode) {
          'sub' => p.proxyNodes.isEmpty ? '节点订阅' : '${p.proxyNodes.length} 节点',
          'custom' => '本地端口',
          'singbox' => 'sing-box',
          'mihomo' => 'mihomo',
          _ => '关闭',
        };
      case _SettingsSection.downloads:
        return app.downloads.isEmpty ? '无任务' : '${app.downloads.length} 项';
      case _SettingsSection.fonts:
        return p.subtitleFontFamily.isEmpty ? '系统默认' : p.subtitleFontFamily;
      case _SettingsSection.style:
        return p.activeSkin.name;
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
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) => _buildSettingsBody(context),
    );
  }

  Widget _buildSettingsBody(BuildContext context) {
    final skin = VedroSkin.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final items = _visibleNavItems;
    if (!_canShowAdmin && _active == _SettingsSection.admin) {
      _active = _SettingsSection.servers;
    }

    if (wide) {
      return Scaffold(
        backgroundColor: skin.canvas,
        body: VedroSkinCanvas(
          child: Padding(
            padding: EdgeInsets.only(top: widget.topInset),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Skin-adaptive Sidebar
                Container(
                  width: 268,
                  decoration: BoxDecoration(
                    color: skin.unifiedPanelColor,
                    border: Border(right: BorderSide(color: skin.border, width: 0.8)),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                        child: Column(
                          children: [
                            Container(
                              height: 34,
                              decoration: BoxDecoration(
                                color: skin.unifiedTileColor(),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: skin.border, width: 0.7),
                              ),
                              child: TextField(
                                controller: _filterCtrl,
                                onChanged: (v) => setState(() => _filter = v),
                                style: TextStyle(color: skin.fg, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: '筛选设置…',
                                  hintStyle: TextStyle(color: skin.fg3, fontSize: 12.5),
                                  prefixIcon: Icon(Icons.search_rounded, size: 16, color: skin.fg3),
                                  prefixIconConstraints: const BoxConstraints(minWidth: 34),
                                  suffixIcon: _filter.isNotEmpty
                                      ? GestureDetector(
                                          onTap: () {
                                            _filterCtrl.clear();
                                            setState(() => _filter = '');
                                          },
                                          child: Icon(Icons.close_rounded, size: 15, color: skin.fg3),
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
                              onTap: () => _selectSection(_SettingsSection.servers),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: skin.border),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 28),
                          children: _buildGroupedSidebar(items, skin),
                        ),
                      ),
                    ],
                  ),
                ),

                // Right Detail Pane:
                // - When `应用风格` (`style`) is active, `SkinStudioPane` pins its Smart Preview Stage
                //   at the top and scrolls presets/options independently so the preview NEVER scrolls away!
                Expanded(
                  child: _active == _SettingsSection.style
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1180),
                              child: SkinStudioPane(
                                key: const ValueKey('desktop-sticky-skin-studio'),
                                appState: widget.appState,
                                stickyDesktop: true,
                              ),
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          controller: _detailScrollCtrl,
                          padding: const EdgeInsets.fromLTRB(36, 26, 36, 64),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 840),
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
              ],
            ),
          ),
        ),
      );
    }

    // Mobile: Grouped Inset Settings List
    final grouped = <String, List<_NavItemMeta>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.group, () => []).add(item);
    }

    return Scaffold(
      backgroundColor: skin.canvas,
      appBar: AppBar(title: const Text('设置')),
      body: VedroSkinCanvas(
        child: ListView(
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
                              style: TextStyle(
                                color: skin.fg,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            _summaryFor(meta.section),
                            style: TextStyle(color: skin.fg3, fontSize: 13),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded, size: 18, color: skin.fg3),
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
                style: TextStyle(color: skin.fg3, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGroupedSidebar(List<_NavItemMeta> items, VedroSkin skin) {
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
          style: TextStyle(
            color: skin.fg3,
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
              onTap: () => _selectSection(meta.section),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7.5),
                decoration: BoxDecoration(
                  color: selected ? skin.unifiedTileColor(selected: true) : Colors.transparent,
                  borderRadius: BorderRadius.circular(skin.cardRadius.clamp(6.0, 11.0)),
                  border: selected
                      ? Border.all(color: skin.borderStrong, width: 0.8)
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
                          color: selected ? skin.fg : skin.fg2,
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
        style: TextStyle(color: skin.fg3, fontSize: 11),
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
    final skin = VedroSkin.of(context);
    final signedIn = appState.isSignedIn;
    final activeSrv = appState.activeServer;
    final style = activeSrv != null ? appState.serverCardStyleFor(activeSrv.id) : const ServerCardStyle();
    final theme = activeSrv != null ? style.resolveTheme(activeSrv.id) : ServerCardTheme.all.first;
    final cardAccent = theme.cardAccent(skin);

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
              colors: [theme.cardBgTop(skin), theme.cardBgBottom(skin)],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? cardAccent.withValues(alpha: 0.7) : skin.border,
              width: 0.9,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: cardAccent.withValues(alpha: skin.isLight ? 0.14 : 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(style.iconData, size: 17, color: cardAccent),
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
                            style: TextStyle(
                              color: skin.fg,
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
                      style: TextStyle(color: skin.fg3, fontSize: 11),
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

class _MobileSettingsSubPage extends StatefulWidget {
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
  State<_MobileSettingsSubPage> createState() => _MobileSettingsSubPageState();
}

class _MobileSettingsSubPageState extends State<_MobileSettingsSubPage> {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.appState.activeSettingsSection = widget.section.name;
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final sysBrightness = View.of(context).platformDispatcher.platformBrightness;
        final skin = widget.appState.prefs.activeSkinFor(
          isMobile: true,
          systemBrightness: sysBrightness,
          dynamicSeedOverride: widget.appState.dynamicPageSeedColor,
        );
        return Theme(
          data: VedroTheme.fromSkin(skin),
          child: Scaffold(
            backgroundColor: skin.canvas,
            appBar: AppBar(title: Text(widget.title)),
            body: VedroSkinCanvas(
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
                child: _SettingsDetailPane(
                  section: widget.section,
                  appState: widget.appState,
                  onOpenServerHub: widget.onOpenServerHub,
                  onOpenAddServer: widget.onOpenAddServer,
                  hideHeading: true,
                ),
              ),
            ),
          ),
        );
      },
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
  final _proxyUrlCtrl = TextEditingController();
  final _proxyBinCtrl = TextEditingController();
  final _proxyCfgCtrl = TextEditingController();
  final _subNameCtrl = TextEditingController();
  final _subUrlCtrl = TextEditingController();
  final _nodeSearchCtrl = TextEditingController();
  bool _testingAi = false;
  bool _fetchingAiModels = false;
  String? _aiTestResult;
  bool _applyingProxy = false;
  bool _testingProxy = false;
  bool _fetchingSub = false;
  bool _addingNewSub = false;
  bool _pingingNodes = false;
  bool _installingCore = false;
  bool _needsSingboxCore = false;
  bool _showNodeSearch = false;
  String _nodeSearchQuery = '';
  String? _proxyStatusMsg;

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
    _proxyUrlCtrl.text = p.inAppProxyUrl.isEmpty ? 'socks5h://127.0.0.1:7890' : p.inAppProxyUrl;
    _proxyBinCtrl.text = p.inAppProxyCorePath;
    _proxyCfgCtrl.text = p.inAppProxyConfigText;
    if (p.proxySubscriptions.isEmpty) {
      _subUrlCtrl.text = p.proxySubscriptionUrl;
    }
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
    _proxyUrlCtrl.dispose();
    _proxyBinCtrl.dispose();
    _proxyCfgCtrl.dispose();
    _subNameCtrl.dispose();
    _subUrlCtrl.dispose();
    _nodeSearchCtrl.dispose();
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
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final app = widget.appState;
        final p = app.prefs;
        final s = app.settings;

        return switch (widget.section) {
          _SettingsSection.servers => _buildServers(app),
          _SettingsSection.proxy => _buildInAppProxy(app, p),
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
      },
    );
  }

  Widget _heading(String title, [String? subtitle, Widget? trailing]) {
    if (widget.hideHeading) return const SizedBox.shrink();
    final skin = VedroSkin.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: skin.applyHeadlineMood(
                    TextStyle(
                      color: skin.fg,
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(subtitle, style: TextStyle(color: skin.fg3, fontSize: 12.5)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing],
        ],
      ),
    );
  }

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

  // 1b. 网络代理（内置免内核多协议引擎 + 节点延迟排序 + 自动选择 + 按平台裁剪）
  Widget _buildInAppProxy(VedroAppState app, VedroPreferences p) {
    final skin = VedroSkin.of(context);
    final isMobileOs = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final isWindowsOs = !kIsWeb && Platform.isWindows;
    final mode = p.inAppProxyMode;
    final isCoreMode = !isMobileOs && (mode == 'singbox' || mode == 'mihomo');
    final isSubMode = mode == 'sub' || mode == 'node' || (isMobileOs && (mode == 'singbox' || mode == 'mihomo'));
    final uiMode = isCoreMode ? 'core' : (isSubMode ? 'sub' : mode);
    final userinfo = p.proxySubUserinfo;
    final usedBytes = ((userinfo?['used'] ?? userinfo?['used_bytes']) as num?)?.toInt() ?? 0;
    final totalBytes = ((userinfo?['total'] ?? userinfo?['total_bytes']) as num?)?.toInt() ?? 0;

    Future<void> selectProxyNode(Map<String, dynamic> node) async {
      setState(() {
        _applyingProxy = true;
        _needsSingboxCore = false;
        _proxyStatusMsg = null;
      });
      try {
        await app.activateProxyNode(node);
        if (mounted) {
          setState(() => _proxyStatusMsg = '已连接：${node['name']}');
        }
      } catch (e) {
        final msg = e.toString().replaceFirst('VedroCoreException: ', '');
        if (mounted) {
          setState(() {
            _needsSingboxCore = !isMobileOs && msg.contains('NEEDS_CORE:');
            _proxyStatusMsg = msg.replaceFirst('NEEDS_CORE:', '');
          });
        }
      } finally {
        if (mounted) setState(() => _applyingProxy = false);
      }
    }

    Future<void> selectAutoProxyNode({bool forcePing = false}) async {
      setState(() {
        _applyingProxy = true;
        _pingingNodes = forcePing || app.proxyNodeLatencies.isEmpty;
        _needsSingboxCore = false;
        _proxyStatusMsg = null;
      });
      try {
        final res = await app.autoSelectFastestProxyNode(forcePing: forcePing);
        final ms = res['latency_ms'];
        final msSuffix = ms != null ? ' ($ms ms)' : '';
        if (mounted) {
          setState(() => _proxyStatusMsg = '自动优选：${res['node_name']}$msSuffix');
        }
      } catch (e) {
        final msg = e
            .toString()
            .replaceFirst('VedroCoreException: ', '')
            .replaceFirst('Exception: ', '');
        if (mounted) {
          setState(() => _proxyStatusMsg = msg.replaceFirst('NEEDS_CORE:', ''));
        }
      } finally {
        if (mounted) {
          setState(() {
            _applyingProxy = false;
            _pingingNodes = false;
          });
        }
      }
    }

    final modeItems = <(String, String)>[
      ('off', '关闭'),
      ('sub', '节点订阅'),
      ('custom', '本地端口'),
      if (!isMobileOs) ('core', '高级内核'),
    ];

    final sortedNodes = app.sortedProxyNodes(searchQuery: _nodeSearchQuery);
    final autoSelected = p.selectedProxyNodeId == 'auto';
    Map<String, dynamic>? autoResolvedNode;
    if (app.autoProxyResolvedNodeId != null) {
      for (final n in p.proxyNodes) {
        if (n['id']?.toString() == app.autoProxyResolvedNodeId) {
          autoResolvedNode = n;
          break;
        }
      }
    }
    if (autoResolvedNode == null && sortedNodes.isNotEmpty) {
      final firstReachable = sortedNodes
          .where((n) => app.proxyNodeLatencies[(n['id'] ?? '').toString()] != null)
          .firstOrNull;
      autoResolvedNode = firstReachable;
    }
    final autoMs = autoResolvedNode != null
        ? app.proxyNodeLatencies[(autoResolvedNode['id'] ?? '').toString()]
        : null;

    const sortLabels = <String, String>{
      'latency': '按延迟',
      'default': '默认顺序',
      'name': '按名称',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('网络代理'),
        _GroupedCard(
          children: [
            _InlineSegmentedRow<String>(
              title: '模式',
              keyPrefix: 'proxy-mode',
              value: uiMode,
              items: modeItems,
              onChanged: (nextUi) async {
                if (nextUi == 'off') {
                  setState(() {
                    _applyingProxy = true;
                    _proxyStatusMsg = null;
                  });
                  try {
                    await app.configureInAppProxy(mode: 'off');
                    if (mounted) setState(() => _proxyStatusMsg = null);
                  } catch (e) {
                    if (mounted) setState(() => _proxyStatusMsg = '关闭失败：$e');
                  } finally {
                    if (mounted) setState(() => _applyingProxy = false);
                  }
                } else if (nextUi == 'core') {
                  await _updatePrefs(
                    p.copyWith(inAppProxyMode: isCoreMode ? mode : 'singbox'),
                  );
                } else {
                  await _updatePrefs(p.copyWith(inAppProxyMode: nextUi));
                }
              },
            ),
            if (isSubMode)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (p.proxySubscriptions.isNotEmpty) ...[
                      Row(
                        children: [
                          Text(
                            '已存订阅 (${p.proxySubscriptions.length})',
                            style: TextStyle(
                              color: skin.fg2,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          if (p.proxySubscriptions.length > 1) ...[
                            TextButton.icon(
                              key: const ValueKey('proxy-sub-refresh-all-btn'),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: _fetchingSub
                                  ? null
                                  : () async {
                                      setState(() {
                                        _fetchingSub = true;
                                        _proxyStatusMsg = null;
                                      });
                                      try {
                                        final cnt = await app.refreshAllProxySubscriptions();
                                        if (mounted) {
                                          setState(() => _proxyStatusMsg = '已刷新 $cnt 个订阅');
                                        }
                                      } finally {
                                        if (mounted) setState(() => _fetchingSub = false);
                                      }
                                    },
                              icon: const Icon(Icons.sync_rounded, size: 14),
                              label: const Text('全部更新', style: TextStyle(fontSize: 12)),
                            ),
                            const SizedBox(width: 4),
                          ],
                          SizedBox(
                            height: 30,
                            child: OutlinedButton.icon(
                              key: const ValueKey('proxy-sub-show-add-btn'),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                              ),
                              onPressed: () {
                                setState(() {
                                  _addingNewSub = !_addingNewSub;
                                  if (_addingNewSub) {
                                    _subNameCtrl.clear();
                                    _subUrlCtrl.clear();
                                  }
                                });
                              },
                              icon: Icon(
                                _addingNewSub ? Icons.expand_less_rounded : Icons.add_rounded,
                                size: 15,
                              ),
                              label: Text(
                                _addingNewSub ? '收起' : '添加订阅',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: p.proxySubscriptions.map((sub) {
                          final isActive = sub.id == p.activeProxySubId;
                          final subUsed =
                              ((sub.userinfo?['used'] ?? sub.userinfo?['used_bytes']) as num?)
                                      ?.toInt() ??
                                  0;
                          final subTotal =
                              ((sub.userinfo?['total'] ?? sub.userinfo?['total_bytes']) as num?)
                                      ?.toInt() ??
                                  0;
                          return PressableScale(
                            key: ValueKey('proxy-sub-card-${sub.id}'),
                            onTap: () => app.selectProxySubscription(sub.id),
                            hoverScale: 1.01,
                            pressScale: 0.98,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                              decoration: BoxDecoration(
                                color: skin.unifiedTileColor(selected: isActive),
                                borderRadius: BorderRadius.circular(skin.cardRadius.clamp(8.0, 13.0)),
                                border: Border.all(
                                  color: isActive ? skin.accent : skin.border,
                                  width: isActive ? 1.2 : 0.75,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.rss_feed_rounded,
                                    size: 15,
                                    color: isActive ? skin.accent : skin.fg3,
                                  ),
                                  const SizedBox(width: 7),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 165),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          sub.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: isActive ? skin.fg : skin.fg2,
                                            fontSize: 13,
                                            fontWeight:
                                                isActive ? FontWeight.w600 : FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          subTotal > 0
                                              ? '${sub.nodes.length} 节点 · ${fmtFileSize(subUsed)}/${fmtFileSize(subTotal)}'
                                              : '${sub.nodes.length} 节点',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: skin.fg3,
                                            fontSize: 10.5,
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: IconButton(
                                      key: ValueKey('proxy-sub-refresh-${sub.id}'),
                                      padding: EdgeInsets.zero,
                                      tooltip: '刷新订阅',
                                      icon: Icon(Icons.sync_rounded, size: 14, color: skin.fg3),
                                      onPressed: _fetchingSub
                                          ? null
                                          : () async {
                                              setState(() {
                                                _fetchingSub = true;
                                                _proxyStatusMsg = null;
                                              });
                                              try {
                                                final res = await app.fetchProxySubscription(
                                                  sub.url,
                                                  name: sub.name,
                                                  subscriptionId: sub.id,
                                                );
                                                if (mounted) {
                                                  setState(() => _proxyStatusMsg =
                                                      '${sub.name} 已更新 ${res['count']} 个节点');
                                                }
                                              } catch (e) {
                                                if (mounted) {
                                                  setState(() => _proxyStatusMsg = e
                                                      .toString()
                                                      .replaceFirst('VedroCoreException: ', '')
                                                      .replaceFirst('Exception: ', ''));
                                                }
                                              } finally {
                                                if (mounted) setState(() => _fetchingSub = false);
                                              }
                                            },
                                    ),
                                  ),
                                  SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: IconButton(
                                      key: ValueKey('proxy-sub-delete-${sub.id}'),
                                      padding: EdgeInsets.zero,
                                      tooltip: '删除订阅',
                                      icon: Icon(
                                        Icons.close_rounded,
                                        size: 14,
                                        color: skin.fg3,
                                      ),
                                      onPressed: () => app.deleteProxySubscription(sub.id),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    if (p.proxySubscriptions.isEmpty || _addingNewSub) ...[
                      if (p.proxySubscriptions.isNotEmpty) const SizedBox(height: 12),
                      Row(
                        children: [
                          SizedBox(
                            width: isMobileOs ? 104 : 148,
                            child: TextField(
                              key: const ValueKey('proxy-sub-name-field'),
                              controller: _subNameCtrl,
                              style: TextStyle(color: skin.fg, fontSize: 13),
                              decoration: const InputDecoration(
                                hintText: '名称（可选）',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              key: const ValueKey('proxy-sub-url-field'),
                              controller: _subUrlCtrl,
                              style: TextStyle(color: skin.fg, fontSize: 13),
                              decoration: const InputDecoration(
                                hintText: '订阅链接 https://... 或节点 URI / Clash',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            key: const ValueKey('proxy-sub-fetch-btn'),
                            onPressed: _fetchingSub
                                ? null
                                : () async {
                                    setState(() {
                                      _fetchingSub = true;
                                      _proxyStatusMsg = null;
                                    });
                                    try {
                                      final res = await app.fetchProxySubscription(
                                        _subUrlCtrl.text,
                                        name: _subNameCtrl.text,
                                      );
                                      if (mounted) {
                                        _subNameCtrl.clear();
                                        _subUrlCtrl.clear();
                                        setState(() {
                                          _addingNewSub = false;
                                          _proxyStatusMsg =
                                              '已保存「${res['subscription_name']}」（${res['count']} 个节点）';
                                        });
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        setState(() => _proxyStatusMsg = e
                                            .toString()
                                            .replaceFirst('VedroCoreException: ', '')
                                            .replaceFirst('Exception: ', ''));
                                      }
                                    } finally {
                                      if (mounted) setState(() => _fetchingSub = false);
                                    }
                                  },
                            icon: const Icon(Icons.add_link_rounded, size: 15),
                            label: Text(_fetchingSub ? '拉取中' : '保存订阅'),
                          ),
                        ],
                      ),
                    ],
                    if (totalBytes > 0) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: (usedBytes / totalBytes).clamp(0.0, 1.0),
                                minHeight: 4,
                                backgroundColor: skin.surface3,
                                color: skin.accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${fmtFileSize(usedBytes)} / ${fmtFileSize(totalBytes)}',
                            style: TextStyle(
                              color: skin.fg3,
                              fontSize: 11.5,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_needsSingboxCore && !isMobileOs) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonalIcon(
                          key: const ValueKey('install-singbox-core-btn'),
                          onPressed: _installingCore
                              ? null
                              : () async {
                                  setState(() => _installingCore = true);
                                  try {
                                    await app.installSingboxCore();
                                    if (mounted) {
                                      setState(() {
                                        _needsSingboxCore = false;
                                        _proxyStatusMsg = '桌面内核安装完成，请再次点击节点启用';
                                      });
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      setState(() => _proxyStatusMsg =
                                          e.toString().replaceFirst('VedroCoreException: ', ''));
                                    }
                                  } finally {
                                    if (mounted) setState(() => _installingCore = false);
                                  }
                                },
                          icon: const Icon(Icons.download_for_offline_rounded, size: 16),
                          label: Text(_installingCore ? '正在下载核心…' : '一键下载桌面内核'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (mode == 'custom')
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _proxyUrlCtrl,
                  style: TextStyle(color: skin.fg, fontSize: 13.5, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    labelText: '代理端口',
                    hintText: 'socks5h://127.0.0.1:7890',
                  ),
                ),
              ),
            if (isCoreMode) ...[
              _InlineSegmentedRow<String>(
                title: '内核类型',
                keyPrefix: 'proxy-core-kind',
                value: mode,
                items: const [
                  ('singbox', 'sing-box'),
                  ('mihomo', 'mihomo'),
                ],
                onChanged: (k) => _updatePrefs(p.copyWith(inAppProxyMode: k)),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _proxyBinCtrl,
                            style: TextStyle(color: skin.fg, fontSize: 13, fontFamily: 'monospace'),
                            decoration: InputDecoration(
                              labelText: '内核路径（可留空）',
                              hintText: isWindowsOs
                                  ? (mode == 'singbox' ? r'C:\Tools\sing-box.exe' : r'C:\Tools\mihomo.exe')
                                  : (mode == 'singbox' ? '/usr/local/bin/sing-box' : '/usr/local/bin/mihomo'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await NativePlaybackChannel.pickFiles(
                              extensions: isWindowsOs ? const ['exe'] : const [],
                              title: '选择内核文件',
                            );
                            if (picked.isNotEmpty) {
                              setState(() => _proxyBinCtrl.text = picked.first);
                            }
                          },
                          icon: const Icon(Icons.folder_open_rounded, size: 15),
                          label: const Text('浏览', style: TextStyle(fontSize: 12.5)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _proxyCfgCtrl,
                      minLines: 4,
                      maxLines: 8,
                      style: TextStyle(color: skin.fg, fontSize: 12, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        labelText: mode == 'singbox' ? 'JSON 配置' : 'YAML 配置',
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (mode == 'custom' || isCoreMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('apply-in-app-proxy-btn'),
                      onPressed: _applyingProxy
                          ? null
                          : () async {
                              setState(() {
                                _applyingProxy = true;
                                _proxyStatusMsg = null;
                              });
                              try {
                                final res = await app.configureInAppProxy(
                                  mode: mode,
                                  proxyUrl: _proxyUrlCtrl.text.trim(),
                                  binaryPath: _proxyBinCtrl.text.trim(),
                                  configText: _proxyCfgCtrl.text,
                                );
                                if (mounted) {
                                  setState(() => _proxyStatusMsg = '已启用 · ${res['proxy_url']}');
                                }
                              } catch (e) {
                                if (mounted) {
                                  setState(() => _proxyStatusMsg =
                                      e.toString().replaceFirst('VedroCoreException: ', ''));
                                }
                              } finally {
                                if (mounted) setState(() => _applyingProxy = false);
                              }
                            },
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: Text(_applyingProxy ? '启动中' : '启用'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _testingProxy
                          ? null
                          : () async {
                              setState(() {
                                _testingProxy = true;
                                _proxyStatusMsg = null;
                              });
                              try {
                                final res = await app.testInAppProxy(
                                  proxyUrl: mode == 'custom' ? _proxyUrlCtrl.text.trim() : null,
                                );
                                if (mounted) {
                                  setState(() => _proxyStatusMsg = '${res['latency_ms']} ms');
                                }
                              } catch (e) {
                                if (mounted) {
                                  setState(() => _proxyStatusMsg =
                                      e.toString().replaceFirst('VedroCoreException: ', ''));
                                }
                              } finally {
                                if (mounted) setState(() => _testingProxy = false);
                              }
                            },
                      icon: const Icon(Icons.speed_rounded, size: 15),
                      label: Text(_testingProxy ? '测速中' : '测速'),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (_proxyStatusMsg != null) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              _proxyStatusMsg!,
              style: TextStyle(
                color: (_proxyStatusMsg!.contains('失败') ||
                        _proxyStatusMsg!.contains('未检测到') ||
                        _proxyStatusMsg!.contains('暂不支持'))
                    ? VedroTheme.danger
                    : const Color(0xFF10B981),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        if (isSubMode && p.proxyNodes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    _nodeSearchQuery.isEmpty
                        ? '节点 (${p.proxyNodes.length})'
                        : '节点 (${sortedNodes.length}/${p.proxyNodes.length})',
                    style: TextStyle(
                      color: skin.fg3,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              // Search toggle icon
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  key: const ValueKey('proxy-node-search-toggle'),
                  padding: EdgeInsets.zero,
                  tooltip: '筛选节点',
                  icon: Icon(
                    _showNodeSearch ? Icons.close_rounded : Icons.search_rounded,
                    size: 16,
                    color: _showNodeSearch ? skin.accent : skin.fg2,
                  ),
                  onPressed: () {
                    setState(() {
                      _showNodeSearch = !_showNodeSearch;
                      if (!_showNodeSearch && _nodeSearchQuery.isNotEmpty) {
                        _nodeSearchCtrl.clear();
                        _nodeSearchQuery = '';
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 4),
              // Ping all button
              SizedBox(
                height: 32,
                child: OutlinedButton.icon(
                  key: const ValueKey('proxy-sub-ping-btn'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _pingingNodes
                      ? null
                      : () async {
                          setState(() => _pingingNodes = true);
                          try {
                            await app.pingProxyNodes();
                          } finally {
                            if (mounted) setState(() => _pingingNodes = false);
                          }
                        },
                  icon: const Icon(Icons.bolt_rounded, size: 14),
                  label: Text(
                    _pingingNodes ? '测速中' : '测速',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Sort pull-down menu (`按延迟` / `默认顺序` / `按名称`)
              VedroPullDownButton<String>(
                key: const ValueKey('proxy-node-sort-dropdown'),
                value: p.proxyNodeSort,
                prefixIcon: Icons.swap_vert_rounded,
                displayLabelOverride: sortLabels[p.proxyNodeSort] ?? '按延迟',
                height: 32,
                menuMinWidth: 168,
                items: const [
                  VedroDropdownItem(
                    value: 'latency',
                    label: '按延迟排序',
                    itemKey: ValueKey('proxy-sort-latency'),
                  ),
                  VedroDropdownItem(
                    value: 'default',
                    label: '默认顺序',
                    itemKey: ValueKey('proxy-sort-default'),
                  ),
                  VedroDropdownItem(
                    value: 'name',
                    label: '按名称排序',
                    itemKey: ValueKey('proxy-sort-name'),
                  ),
                ],
                onChanged: (sort) => _updatePrefs(p.copyWith(proxyNodeSort: sort)),
              ),
            ],
          ),
          if (_showNodeSearch) ...[
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('proxy-node-search-field'),
              controller: _nodeSearchCtrl,
              onChanged: (v) => setState(() => _nodeSearchQuery = v),
              style: TextStyle(color: skin.fg, fontSize: 13),
              decoration: InputDecoration(
                hintText: '搜索地区或协议（如 香港 / 日本 / VLESS）',
                prefixIcon: Icon(Icons.search_rounded, size: 17, color: skin.fg3),
                suffixIcon: _nodeSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded, size: 16, color: skin.fg3),
                        onPressed: () {
                          _nodeSearchCtrl.clear();
                          setState(() => _nodeSearchQuery = '');
                        },
                      )
                    : null,
              ),
            ),
          ],
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (ctx, c) {
              final cols = c.maxWidth >= 560 ? 2 : 1;
              const gap = 10.0;
              final cardW = (c.maxWidth - gap * (cols - 1)) / cols;

              // Pinned "⚡ 自动选择" smart card
              final autoSubtitle = autoResolvedNode != null
                  ? (autoSelected
                      ? '当前：${autoResolvedNode['name']}'
                      : '推荐：${autoResolvedNode['name']}')
                  : '自动测速并连接最低延迟节点';

              final autoCard = SizedBox(
                width: cardW,
                child: PressableScale(
                  key: const ValueKey('proxy-node-auto'),
                  onTap: _applyingProxy ? null : () => selectAutoProxyNode(forcePing: false),
                  hoverScale: 1.01,
                  pressScale: 0.98,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    decoration: BoxDecoration(
                      color: skin.unifiedTileColor(selected: autoSelected),
                      borderRadius: BorderRadius.circular(skin.cardRadius.clamp(8.0, 14.0)),
                      border: Border.all(
                        color: autoSelected ? skin.accent : skin.borderStrong,
                        width: autoSelected ? 1.25 : 0.85,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: skin.accent.withValues(alpha: autoSelected ? 0.22 : 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.auto_awesome_rounded, size: 15, color: skin.accent),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '自动选择',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: skin.fg,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                autoSubtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: autoSelected ? skin.accent : skin.fg3,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (autoMs != null)
                          Text(
                            '$autoMs ms',
                            style: TextStyle(
                              color: autoMs < 160
                                  ? const Color(0xFF10B981)
                                  : (autoMs < 360 ? const Color(0xFFF59E0B) : VedroTheme.danger),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  if (_nodeSearchQuery.isEmpty) autoCard,
                  ...sortedNodes.map((node) {
                    final id = (node['id'] ?? '').toString();
                    final name = (node['name'] ?? '').toString();
                    final proto = (node['protocol'] ?? '').toString().toUpperCase();
                    final supported = app.isProxyNodeSupportedOnCurrentOs(node);
                    final directSelected = p.selectedProxyNodeId == id;
                    final resolvedByAuto = autoSelected && app.autoProxyResolvedNodeId == id;
                    final highlighted = directSelected || resolvedByAuto;
                    final hasPing = app.proxyNodeLatencies.containsKey(id);
                    final ms = app.proxyNodeLatencies[id];
                    final msColor = ms == null
                        ? skin.fg3
                        : (ms < 160
                            ? const Color(0xFF10B981)
                            : (ms < 360 ? const Color(0xFFF59E0B) : VedroTheme.danger));
                    return SizedBox(
                      width: cardW,
                      child: Opacity(
                        opacity: supported ? 1.0 : 0.52,
                        child: PressableScale(
                          key: ValueKey('proxy-node-$id'),
                          onTap: (_applyingProxy || !supported) ? null : () => selectProxyNode(node),
                          hoverScale: 1.01,
                          pressScale: 0.98,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                            decoration: BoxDecoration(
                              color: skin.unifiedTileColor(selected: highlighted),
                              borderRadius: BorderRadius.circular(skin.cardRadius.clamp(8.0, 14.0)),
                              border: Border.all(
                                color: highlighted ? skin.accent : skin.border,
                                width: highlighted ? 1.2 : 0.75,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: highlighted
                                        ? skin.accent
                                        : skin.fg3.withValues(alpha: 0.35),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: highlighted ? skin.fg : skin.fg2,
                                          fontSize: 13.5,
                                          fontWeight:
                                              highlighted ? FontWeight.w600 : FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        supported ? proto : '$proto · 仅桌面端',
                                        style: TextStyle(
                                          color: skin.fg3,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (hasPing)
                                  Text(
                                    ms != null ? '$ms ms' : '超时',
                                    style: TextStyle(
                                      color: msColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  // 2. 下载管理
  Widget _buildDownloads(VedroAppState app, VedroPreferences p) {
    final skin = VedroSkin.of(context);
    final totalBytes = app.downloads.fold<int>(0, (sum, d) => sum + d.downloadedBytes);
    final dq = app.meQuota?.downloadQuota;
    final traffic = app.meQuota?.traffic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('下载管理'),
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
                            if (picked.isNotEmpty) {
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
                                  type: 'Movie',
                                ),
                                appState: app,
                                localFilePath: task.filePath,
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
                                  _fontPathCtrl.clear();
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
                  icon: Icon(Icons.delete_outline_rounded, size: 18, color: skin.fg3),
                  onPressed: () => app.removeSubtitleFont(path),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // 4. 应用风格 & 皮肤工坊
  Widget _buildStyle(VedroPreferences p) {
    return SkinStudioPane(
      appState: widget.appState,
      hideHeading: widget.hideHeading,
    );
  }

  // 5. 模块配置
  Widget _buildModules(VedroAppState app) {
    final sections = List<HomeSectionConfig>.from(app.homeSections);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('模块配置'),
        _GroupedCard(
          children: [
            _SwitchRow(
              title: '顶部巨幕轮播',
              value: app.showHomeHero,
              onChanged: (v) => app.saveHomeLayout(sections, showHero: v),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: _GroupHeader('板块排序')),
            TextButton(
              onPressed: app.resetHomeLayout,
              child: Text('恢复默认', style: TextStyle(color: VedroSkin.of(context).fg2, fontSize: 12.5)),
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
            final skin = VedroSkin.of(context);
            final sec = sections[idx];
            return Padding(
              key: ValueKey('mod_${sec.id}'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                decoration: BoxDecoration(
                  color: skin.surface,
                  borderRadius: BorderRadius.circular(skin.cardRadius.clamp(8.0, 16.0)),
                  border: skin.cardBorder(),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${idx + 1}',
                        style: TextStyle(
                          color: skin.fg3,
                          fontSize: 12.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
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
                              color: sec.visible ? skin.fg : skin.fg3,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(sec.subtitle, style: TextStyle(color: skin.fg3, fontSize: 11.5)),
                        ],
                      ),
                    ),
                    Transform.scale(
                      scale: 0.78,
                      child: CupertinoSwitch(
                        value: sec.visible,
                        activeTrackColor: skin.accent,
                        onChanged: (v) {
                          sections[idx] = sec.copyWith(visible: v);
                          app.saveHomeLayout(sections);
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    ReorderableDragStartListener(
                      index: idx,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(Icons.drag_handle_rounded, size: 19, color: skin.fg3),
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
    final pct = (p.posterScale * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('列表配置'),
        _GroupedCard(
          children: [
            _InlineSegmentedRow<String>(
              title: '海报墙密度',
              keyPrefix: 'list-density',
              value: p.listDensity,
              items: const [('compact', '紧凑'), ('comfortable', '标准'), ('spacious', '宽松')],
              onChanged: (v) => _updatePrefs(p.copyWith(listDensity: v)),
            ),
            _InlineSegmentedRow<String>(
              title: '分类与边距间距',
              keyPrefix: 'list-section-spacing',
              value: p.sectionSpacing,
              items: const [('compact', '紧凑'), ('standard', '标准'), ('spacious', '宽松')],
              onChanged: (v) => _updatePrefs(p.copyWith(sectionSpacing: v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: VedroPrecisionSlider(
                key: const ValueKey('poster-scale-slider'),
                label: '卡片与图标尺寸',
                valueText: '$pct%',
                value: p.posterScale,
                min: 0.75,
                max: 1.25,
                step: 0.05,
                defaultValue: 1.0,
                ticks: const [
                  (0.80, '80%'),
                  (0.90, '90%'),
                  (1.00, '100%'),
                  (1.10, '110%'),
                  (1.20, '120%'),
                ],
                onChanged: (v) => _updatePrefs(p.copyWith(posterScale: v)),
              ),
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
            _SwitchRow(
              key: const ValueKey('pref-show-multiversion-badge'),
              title: '显示多版本角标 (2×)',
              value: p.showMultiVersionBadge,
              onChanged: (v) => _updatePrefs(p.copyWith(showMultiVersionBadge: v)),
            ),
          ],
        ),
      ],
    );
  }

  // 7. 界面偏好
  Widget _buildUiPrefs(VedroPreferences p) {
    final showAndroidBackConfirm = kIsWeb || Platform.isAndroid || Platform.isLinux;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('界面偏好'),
        _GroupedCard(
          children: [
            if (showAndroidBackConfirm)
              _SwitchRow(
                key: const ValueKey('pref-confirm-exit-app'),
                title: '按返回键二次确认退出',
                value: p.confirmExitApp,
                onChanged: (v) => _updatePrefs(p.copyWith(confirmExitApp: v)),
              ),
            _SwitchRow(
              title: '显示画质与音频规格标识',
              value: p.showSpecBadges,
              onChanged: (v) => _updatePrefs(p.copyWith(showSpecBadges: v)),
            ),
            _SwitchRow(
              title: '进度条右侧显示剩余时长',
              value: p.showRemainingTime,
              onChanged: (v) => _updatePrefs(p.copyWith(showRemainingTime: v)),
            ),
            _SwitchRow(
              title: '退出播放前二次确认',
              value: p.confirmExitPlayer,
              onChanged: (v) => _updatePrefs(p.copyWith(confirmExitPlayer: v)),
            ),
            _SwitchRow(
              title: '无痕观影模式',
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
    final isMobileOs = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final supportsPip = !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);
    final playerChoices = <String, String>{
      'builtin': !kIsWeb && Platform.isIOS ? '内置播放核心（推荐）' : '内置 Rust + MPV（推荐）',
      if (!kIsWeb && Platform.isAndroid) ...{
        'mxplayer': 'MX Player',
        'vlc': 'VLC',
        'mpv': 'MPV-Android',
        'system': '系统外部播放器',
      } else if (!kIsWeb && Platform.isIOS) ...{
        'infuse': 'Infuse',
        'vlc': 'VLC',
        'outplayer': 'Outplayer',
        'nplayer': 'nPlayer',
      } else if (!kIsWeb && Platform.isMacOS) ...{
        'iina': 'IINA',
        'infuse': 'Infuse',
        'mpv': 'MPV',
        'vlc': 'VLC',
      } else if (!kIsWeb && Platform.isWindows) ...{
        'potplayer': 'PotPlayer',
        'vlc': 'VLC',
        'mpv': 'MPV',
      } else ...{
        'mpv': '外部 MPV',
        'vlc': 'VLC',
      },
    };
    if (!playerChoices.containsKey(p.externalPlayer)) {
      playerChoices[p.externalPlayer] = p.externalPlayer;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('播放设置'),
        const _GroupHeader('默认音轨与字幕'),
        KeyedSubtree(
          key: const ValueKey('settings-global-audio-sub-card'),
          child: _GroupedCard(
            children: [
              _InlineSegmentedRow<String>(
                title: '首选音轨语言',
                value: p.preferredAudioLang,
                items: const [
                  ('auto', '原声自动'),
                  ('zh', '中文/国语'),
                  ('yue', '粤语'),
                  ('ja', '日语'),
                  ('en', '英语'),
                ],
                onChanged: (v) => _updatePrefs(p.copyWith(preferredAudioLang: v)),
              ),
              _InlineSegmentedRow<String>(
                title: '首选字幕语言',
                value: p.preferredSubLang,
                items: const [
                  ('zh', '简中'),
                  ('zh-Hant', '繁中'),
                  ('en', '英语/双语'),
                  ('ja', '日语'),
                  ('off', '关闭'),
                ],
                onChanged: (v) => _updatePrefs(p.copyWith(preferredSubLang: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _GroupHeader('播放器与交互控制'),
        _GroupedCard(
          children: [
            _AppleMenuPickerRow<String>(
              title: '默认播放器引擎',
              value: p.externalPlayer,
              items: playerChoices,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: VedroPrecisionSlider(
                label: '默认播放倍速',
                valueText:
                    '${((p.defaultSpeed * 10 - (p.defaultSpeed * 10).round()).abs() < 0.001 ? p.defaultSpeed.toStringAsFixed(1) : p.defaultSpeed.toStringAsFixed(2))}×',
                value: p.defaultSpeed,
                min: 0.5,
                max: 3.0,
                step: 0.05,
                defaultValue: 1.0,
                ticks: const [
                  (0.5, '0.5×'),
                  (1.0, '1.0×'),
                  (1.25, '1.25×'),
                  (1.5, '1.5×'),
                  (2.0, '2.0×'),
                  (3.0, '3.0×'),
                ],
                onChanged: (v) => _updatePrefs(p.copyWith(defaultSpeed: v)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: VedroPrecisionSlider(
                label: '长按屏幕倍速',
                valueText:
                    '${((p.longPressSpeed * 10 - (p.longPressSpeed * 10).round()).abs() < 0.001 ? p.longPressSpeed.toStringAsFixed(1) : p.longPressSpeed.toStringAsFixed(2))}×',
                value: p.longPressSpeed,
                min: 1.25,
                max: 4.0,
                step: 0.25,
                defaultValue: 2.0,
                ticks: const [
                  (1.5, '1.5×'),
                  (2.0, '2.0×'),
                  (2.5, '2.5×'),
                  (3.0, '3.0×'),
                  (4.0, '4.0×'),
                ],
                onChanged: (v) => _updatePrefs(p.copyWith(longPressSpeed: v)),
              ),
            ),
            if (isMobileOs) ...[
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
            ],
            if (supportsPip)
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
        _heading('视频设置'),
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
              child: Builder(
                builder: (ctx) {
                  final skin = VedroSkin.of(ctx);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '自定义 mpv.conf 参数（每行一条 key=value，# 开头为注释）',
                        style: TextStyle(color: skin.fg2, fontSize: 12.5),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _mpvConfCtrl,
                        minLines: 3,
                        maxLines: 6,
                        style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: skin.fg),
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
                  );
                },
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
        _heading('音频设置'),
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
              items: const [
                ('auto', '原声自动'),
                ('zh', '中文/国语'),
                ('yue', '粤语'),
                ('ja', '日语'),
                ('en', '英语'),
              ],
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
    final skin = VedroSkin.of(context);
    const colors = [
      ('#FFFFFF', '纯白', Color(0xFFFFFFFF)),
      ('#FFE082', '暖黄', Color(0xFFFFE082)),
      ('#A7F3D0', '淡青', Color(0xFFA7F3D0)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('字幕设置'),
        _GroupedCard(
          children: [
            _InlineSegmentedRow<String>(
              title: '首选字幕语言',
              value: p.preferredSubLang,
              items: const [
                ('zh', '简中'),
                ('zh-Hant', '繁中'),
                ('en', '英语/双语'),
                ('ja', '日语'),
                ('off', '关闭'),
              ],
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
                  Expanded(
                    child: Text('字幕颜色', style: TextStyle(color: skin.fg, fontSize: 14)),
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
                            color: on ? skin.accent.withValues(alpha: 0.14) : skin.surface2,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: on ? skin.accent : skin.border,
                              width: on ? 1.1 : 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 11,
                                height: 11,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.black26, width: 0.6),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(label, style: TextStyle(color: skin.fg, fontSize: 12)),
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
        _heading('弹幕设置'),
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
                  Text('自定义弹幕源',
                      style: TextStyle(color: VedroSkin.of(context).fg2, fontSize: 12.5)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _danmakuApiCtrl,
                          decoration: const InputDecoration(
                            hintText: '留空使用内置多源匹配',
                          ),
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

  // 13. AI 翻译（极简零废话 UI + 模型列表一键拉取 + 直连/代理出口切换）
  Widget _buildAi(VedroAppState app, VedroPreferences p) {
    final isBili = p.aiBaseUrl.toLowerCase().contains('index-translate.bilibili.com');

    Future<void> applyPreset({
      required String baseUrl,
      required String model,
      required bool directIp,
      bool clearKey = false,
    }) async {
      _aiUrlCtrl.text = baseUrl;
      _aiModelCtrl.text = model;
      if (clearKey) _aiKeyCtrl.clear();
      await _updatePrefs(p.copyWith(
        aiEnabled: true,
        aiBaseUrl: baseUrl,
        aiModel: model,
        aiApiKey: clearKey ? '' : _aiKeyCtrl.text.trim(),
        aiDirectClientIp: directIp,
        aiCachedModels: const [],
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('AI 翻译'),
        _GroupedCard(
          children: [
            _SwitchRow(
              title: '启用翻译',
              value: p.aiEnabled,
              onChanged: (v) => _updatePrefs(p.copyWith(aiEnabled: v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    key: const ValueKey('ai-preset-bilibili'),
                    selected: isBili,
                    label: const Text('Bilibili'),
                    onSelected: (_) => applyPreset(
                      baseUrl: 'https://index-translate.bilibili.com/v1',
                      model: 'Index-Translate-35B-A3B',
                      directIp: true,
                      clearKey: true,
                    ),
                  ),
                  ChoiceChip(
                    selected: p.aiBaseUrl.contains('deepseek.com'),
                    label: const Text('DeepSeek'),
                    onSelected: (_) => applyPreset(
                      baseUrl: 'https://api.deepseek.com/v1',
                      model: 'deepseek-chat',
                      directIp: true,
                    ),
                  ),
                  ChoiceChip(
                    selected: p.aiBaseUrl.contains('openai.com'),
                    label: const Text('OpenAI'),
                    onSelected: (_) => applyPreset(
                      baseUrl: 'https://api.openai.com/v1',
                      model: 'gpt-4o-mini',
                      directIp: false,
                    ),
                  ),
                  ChoiceChip(
                    selected: p.aiBaseUrl.contains('11434'),
                    label: const Text('Ollama'),
                    onSelected: (_) => applyPreset(
                      baseUrl: 'http://127.0.0.1:11434/v1',
                      model: 'qwen2.5:7b',
                      directIp: true,
                      clearKey: true,
                    ),
                  ),
                ],
              ),
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
            _InlineSegmentedRow<bool>(
              title: '网络出口',
              keyPrefix: 'ai-egress',
              value: p.aiDirectClientIp,
              items: const [
                (true, '本机直连'),
                (false, '走代理'),
              ],
              onChanged: (v) => _updatePrefs(p.copyWith(aiDirectClientIp: v)),
            ),
            _SwitchRow(
              title: '双语对照',
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
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: isBili ? '免 Key' : 'sk-...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _aiModelCtrl,
                          decoration: const InputDecoration(
                            labelText: '模型',
                            hintText: 'gpt-4o-mini',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        key: const ValueKey('ai-fetch-models-btn'),
                        onPressed: _fetchingAiModels
                            ? null
                            : () async {
                                setState(() {
                                  _fetchingAiModels = true;
                                  _aiTestResult = null;
                                });
                                try {
                                  final models = await app.fetchAiModels(
                                    baseUrl: _aiUrlCtrl.text.trim(),
                                    apiKey: _aiKeyCtrl.text.trim(),
                                    directIp: p.aiDirectClientIp,
                                  );
                                  if (models.isNotEmpty) {
                                    _aiModelCtrl.text = app.prefs.aiModel;
                                  }
                                  if (mounted) {
                                    setState(() => _aiTestResult = '已获取 ${models.length} 个模型');
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    setState(() => _aiTestResult = e
                                        .toString()
                                        .replaceFirst('VedroCoreException: ', '')
                                        .replaceFirst('Exception: ', ''));
                                  }
                                } finally {
                                  if (mounted) setState(() => _fetchingAiModels = false);
                                }
                              },
                        icon: const Icon(Icons.list_alt_rounded, size: 15),
                        label: Text(_fetchingAiModels ? '获取中' : '获取模型'),
                      ),
                    ],
                  ),
                  if (p.aiCachedModels.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 132),
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: p.aiCachedModels.map((m) {
                            final selected = p.aiModel == m;
                            return ChoiceChip(
                              key: ValueKey('ai-model-chip-$m'),
                              selected: selected,
                              label: Text(m, style: const TextStyle(fontSize: 12)),
                              onSelected: (_) {
                                _aiModelCtrl.text = m;
                                _updatePrefs(p.copyWith(
                                  aiBaseUrl: _aiUrlCtrl.text.trim(),
                                  aiApiKey: _aiKeyCtrl.text.trim(),
                                  aiModel: m,
                                ));
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
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
                              const SnackBar(content: Text('已保存')),
                            );
                          }
                        },
                        child: const Text('保存', style: TextStyle(fontSize: 13)),
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
                                  if (mounted) {
                                    setState(() => _aiTestResult = res);
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    setState(() => _aiTestResult =
                                        e.toString().replaceFirst('VedroCoreException: ', ''));
                                  }
                                } finally {
                                  if (mounted) setState(() => _testingAi = false);
                                }
                              },
                        child: Text(_testingAi ? '测试中' : '测试', style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                  if (_aiTestResult != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _aiTestResult!,
                      style: TextStyle(
                        color: (_aiTestResult!.contains('失败') || _aiTestResult!.contains('HTTP'))
                            ? VedroTheme.danger
                            : const Color(0xFF10B981),
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
        _heading('隐私保护'),
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
                trailing: Icon(Icons.chevron_right_rounded, size: 18, color: VedroSkin.of(context).fg3),
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
    final skin = VedroSkin.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          color: skin.fg3,
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
    final skin = VedroSkin.of(context);
    return VedroAdaptiveSurface(
      borderRadius: skin.cardRadius.clamp(12.0, 22.0),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 16, endIndent: 16, color: skin.border),
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
    final skin = VedroSkin.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(child: Text(title, style: TextStyle(color: skin.fg, fontSize: 14))),
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
    final skin = VedroSkin.of(context);
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
                      color: selected ? skin.fg : skin.fg2,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: skin.fg3, fontSize: 11.5),
                    ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_rounded, size: 18, color: skin.accent),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

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
    final skin = VedroSkin.of(context);
    final safeValue = items.containsKey(value) ? value : items.keys.first;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          Expanded(child: Text(title, style: TextStyle(color: skin.fg, fontSize: 14))),
          const SizedBox(width: 12),
          VedroPullDownButton<T>(
            height: 34,
            value: safeValue,
            items: items.entries
                .map((e) => VedroDropdownItem<T>(value: e.key, label: e.value))
                .toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _InlineSegmentedRow<T> extends StatelessWidget {
  const _InlineSegmentedRow({
    required this.title,
    required this.value,
    required this.items,
    required this.onChanged,
    this.keyPrefix,
  });

  final String title;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final seg = Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: skin.surface2,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: skin.border, width: 0.7),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: items.map((entry) {
            final active = entry.$1 == value;
            return GestureDetector(
              key: keyPrefix != null ? ValueKey('$keyPrefix-${entry.$1}') : null,
              onTap: () => onChanged(entry.$1),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: active ? skin.activePillBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    entry.$2,
                    style: TextStyle(
                      color: active ? skin.activePillFg : skin.fg3,
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
                Text(title, style: TextStyle(color: skin.fg, fontSize: 14)),
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
              Expanded(child: Text(title, style: TextStyle(color: skin.fg, fontSize: 14))),
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
    super.key,
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
    final skin = VedroSkin.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: skin.fg, fontSize: 14)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: TextStyle(color: skin.fg3, fontSize: 12)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Transform.scale(
            scale: 0.78,
            child: CupertinoSwitch(
              value: value,
              activeTrackColor: skin.accent,
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
    final step = divisions > 0 ? (max - min) / divisions : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: VedroPrecisionSlider(
        label: title,
        valueText: valueText,
        value: value.clamp(min, max),
        min: min,
        max: max,
        step: step,
        onChanged: onChanged,
      ),
    );
  }
}
