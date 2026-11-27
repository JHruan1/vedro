import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../core/models/models.dart';
import '../core/models/preferences.dart';
import '../core/platform/native_playback_channel.dart';
import '../core/platform/platform_perf.dart';
import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/admin_console_pane.dart';
import '../widgets/app_lock_gate.dart' show PinLockoutController;
import '../widgets/beauty_filter.dart';
import '../core/services/local_asr_engine.dart';
import '../widgets/server_card_grid.dart';
import '../widgets/skin_studio_pane.dart';
import '../widgets/update_checker.dart';
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
  speedtest,
  devices,
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
  about,
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
  final FocusScopeNode _sidebarScope = FocusScopeNode(debugLabel: 'settings-sidebar-scope');
  final FocusScopeNode _detailScope = FocusScopeNode(debugLabel: 'settings-detail-scope');
  bool _detailFocused = false;
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
      keywords: 'server route 线路 卡片',
    ),
    _NavItemMeta(
      section: _SettingsSection.speedtest,
      title: '播放测速',
      icon: Icons.speed_rounded,
      tintTop: Color(0xFF10B981),
      tintBottom: Color(0xFF059669),
      group: '媒体源与管理',
      keywords: 'speedtest 测速 带宽 码率 延迟 线路 embygo',
    ),
    _NavItemMeta(
      section: _SettingsSection.devices,
      title: '设备管理',
      icon: Icons.devices_rounded,
      tintTop: Color(0xFF6366F1),
      tintBottom: Color(0xFF4338CA),
      group: '媒体源与管理',
      keywords: 'devices 设备 登录 名额 移除 embygo',
    ),
    _NavItemMeta(
      section: _SettingsSection.downloads,
      title: '下载与缓存',
      icon: Icons.download_rounded,
      tintTop: Color(0xFF34D399),
      tintBottom: Color(0xFF059669),
      group: '媒体源与管理',
      keywords: 'offline cache image 离线 下载 图片 缓存 清理 存储',
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
      keywords: 'hdr dolby vision anime4k mpv.conf beauty 硬解 杜比视界 美颜 磨皮 滤镜',
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
      keywords: 'pin passcode lock 密码 锁',
    ),
    _NavItemMeta(
      section: _SettingsSection.about,
      title: '备份与关于',
      icon: Icons.info_outline_rounded,
      tintTop: Color(0xFF60A5FA),
      tintBottom: Color(0xFF4F46E5),
      group: '系统与关于',
      keywords: 'backup restore export import reset about license diagnostics 备份 恢复 重置 关于 诊断 开源 版本',
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
    _sidebarScope.dispose();
    _detailScope.dispose();
    _filterCtrl.dispose();
    _detailScrollCtrl.dispose();
    super.dispose();
  }

  bool get _canShowAdmin => widget.appState.isSignedIn && widget.appState.isAdmin;

  bool get _canShowEmbyGoTools =>
      !widget.appState.isSignedIn ||
      widget.appState.capabilities == null ||
      widget.appState.capabilities!.isEmbyGo;

  List<_NavItemMeta> get _visibleNavItems {
    final base = _canShowEmbyGoTools
        ? _baseNavItems
        : _baseNavItems
            .where((i) => i.section != _SettingsSection.speedtest && i.section != _SettingsSection.devices)
            .toList();
    final all = _canShowAdmin ? [...base, _adminNavItem] : base;
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
      case _SettingsSection.speedtest:
        final eff = (app.lastSpeedTestResult?['effective_mbps'] as num?)?.toDouble();
        return app.isSpeedTesting
            ? '测速中'
            : (eff != null ? '${eff.toStringAsFixed(0)} Mbps' : '测试线路');
      case _SettingsSection.devices:
        final reg = app.meQuota?.registeredDevices ?? app.userDevices.length;
        return reg > 0 ? '$reg 台' : '管理设备';
      case _SettingsSection.downloads:
        if (app.downloads.isNotEmpty) return '${app.downloads.length} 项';
        final imgBytes = (app.imageCacheStats?['disk_bytes'] as num?)?.toInt() ?? 0;
        return imgBytes > 0 ? fmtFileSize(imgBytes) : '无任务';
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
        return switch ((app.settings['audio_mode'] ?? 'auto').toString()) {
          'passthrough_bitstream' => '源码直通',
          'spatial_audio' => '空间音频',
          'headphone_binaural' => '双耳空间化',
          'pcm_stereo' => '立体声 PCM',
          _ => '自动',
        };
      case _SettingsSection.subtitles:
        return '${(p.subtitleFontScale * 100).round()}%';
      case _SettingsSection.danmaku:
        return p.danmakuEnabled ? '已开启' : '关闭';
      case _SettingsSection.ai:
        return p.isAiReady ? p.aiModel : '未启用';
      case _SettingsSection.privacy:
        return p.passcodeEnabled ? '已上锁' : '未锁定';
      case _SettingsSection.about:
        return 'v${app.core.coreVersion}';
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
    if ((!_canShowAdmin && _active == _SettingsSection.admin) ||
        (!_canShowEmbyGoTools &&
            (_active == _SettingsSection.speedtest || _active == _SettingsSection.devices))) {
      _active = _SettingsSection.servers;
    }

    if (wide) {
      return PopScope(
        canPop: !(PlatformPerfProfile.isTv && _detailFocused),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && PlatformPerfProfile.isTv && _detailFocused) {
            _sidebarScope.requestFocus();
          }
        },
        child: Scaffold(
          backgroundColor: skin.canvas,
          body: VedroSkinCanvas(
            child: Padding(
              padding: EdgeInsets.only(top: widget.topInset),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Skin-adaptive Sidebar
                  FocusScope(
                    node: _sidebarScope,
                    child: Container(
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
                                    textInputAction: TextInputAction.search,
                                    onChanged: (v) => setState(() => _filter = v),
                                    style: TextStyle(color: skin.fg, fontSize: 13),
                                    decoration: InputDecoration(
                                      hintText: '筛选设置…',
                                      hintStyle: TextStyle(color: skin.fg3, fontSize: 12.5),
                                      prefixIcon: Icon(Icons.search_rounded, size: 16, color: skin.fg3),
                                      prefixIconConstraints: const BoxConstraints(minWidth: 34),
                                      suffixIcon: _filter.isNotEmpty
                                          ? IconButton(
                                              tooltip: '清除筛选',
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                              onPressed: () {
                                                _filterCtrl.clear();
                                                setState(() => _filter = '');
                                              },
                                              icon: Icon(Icons.close_rounded, size: 15, color: skin.fg3),
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
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                              children: _buildGroupedSidebar(items, skin),
                            ),
                          ),
                          Divider(height: 1, color: skin.border),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                            child: UpdateCheckBadgeTile(
                              currentVersion: widget.appState.core.coreVersion,
                              compact: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Right Detail Pane:
                  // - When `应用风格` (`style`) is active, `SkinStudioPane` pins its Smart Preview Stage
                  //   at the top and scrolls presets/options independently so the preview NEVER scrolls away!
                  Expanded(
                    child: FocusScope(
                      node: _detailScope,
                      child: Focus(
                        canRequestFocus: false,
                        onFocusChange: (focused) {
                          if (_detailFocused != focused && mounted) {
                            setState(() => _detailFocused = focused);
                          }
                        },
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
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Mobile: Grouped Inset Settings List (with live search filter)
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
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: skin.unifiedTileColor(),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: skin.border, width: 0.7),
                ),
                child: TextField(
                  controller: _filterCtrl,
                  textInputAction: TextInputAction.search,
                  onChanged: (v) => setState(() => _filter = v),
                  style: TextStyle(color: skin.fg, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: '搜索设置项…',
                    hintStyle: TextStyle(color: skin.fg3, fontSize: 13),
                    prefixIcon: Icon(Icons.search_rounded, size: 17, color: skin.fg3),
                    prefixIconConstraints: const BoxConstraints(minWidth: 36),
                    suffixIcon: _filter.isNotEmpty
                        ? IconButton(
                            tooltip: '清除搜索',
                            padding: EdgeInsets.zero,
                            icon: Icon(Icons.close_rounded, size: 16, color: skin.fg3),
                            onPressed: () {
                              _filterCtrl.clear();
                              setState(() => _filter = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
            ),
            if (grouped.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Center(
                  child: Text('未找到匹配的设置项', style: TextStyle(color: skin.fg3, fontSize: 13.5)),
                ),
              ),
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
            const SizedBox(height: 16),
            _GroupedCard(
              children: [
                UpdateCheckBadgeTile(currentVersion: widget.appState.core.coreVersion),
              ],
            ),
            const SizedBox(height: 18),
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
        final itemR = skin.cardRadius.clamp(6.0, 11.0);
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: PressableScale(
            onTap: () => _selectSection(meta.section),
            hoverScale: 1.01,
            pressScale: 0.98,
            borderRadius: BorderRadius.circular(itemR),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7.5),
              decoration: BoxDecoration(
                color: selected ? skin.unifiedTileColor(selected: true) : Colors.transparent,
                borderRadius: BorderRadius.circular(itemR),
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
        ));
      }
    }
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

    return PressableScale(
      onTap: onTap,
      hoverScale: 1.01,
      pressScale: 0.98,
      borderRadius: BorderRadius.circular(12),
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
  VedroSkin? _cachedSkin;
  ThemeData? _cachedTheme;

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
        if (_cachedTheme == null || _cachedSkin != skin) {
          _cachedSkin = skin;
          _cachedTheme = VedroTheme.fromSkin(skin);
        }
        return Theme(
          data: _cachedTheme!,
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
  final _asrUrlCtrl = TextEditingController();
  final _asrKeyCtrl = TextEditingController();
  final _asrModelCtrl = TextEditingController();
  final _danmakuApiCtrl = TextEditingController();
  final _fontPathCtrl = TextEditingController();
  final _downloadDirCtrl = TextEditingController();
  final _mpvConfCtrl = TextEditingController();
  bool _testingAi = false;
  bool _fetchingAiModels = false;
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
    _asrUrlCtrl.text = p.asrBaseUrl;
    _asrKeyCtrl.text = p.asrApiKey;
    _asrModelCtrl.text = p.asrModel;
    _danmakuApiCtrl.text = p.danmakuApiUrl;
    _downloadDirCtrl.text = p.downloadCustomDir;
    _mpvConfCtrl.text = p.customMpvConf;
    if (widget.section == _SettingsSection.devices && widget.appState.isSignedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          widget.appState.loadUserDevices().catchError((_) => const <Map<String, dynamic>>[]),
        );
        unawaited(widget.appState.refreshMeQuota());
      });
    } else if (widget.section == _SettingsSection.downloads) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(widget.appState.loadImageCacheStats());
      });
    } else if (widget.section == _SettingsSection.ai) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(LocalAsrManager.instance.refreshStatus());
      });
    }
  }

  @override
  void dispose() {
    _aiUrlCtrl.dispose();
    _aiKeyCtrl.dispose();
    _aiModelCtrl.dispose();
    _asrUrlCtrl.dispose();
    _asrKeyCtrl.dispose();
    _asrModelCtrl.dispose();
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
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final app = widget.appState;
        final p = app.prefs;
        final s = app.settings;

        return switch (widget.section) {
          _SettingsSection.servers => _buildServers(app),
          _SettingsSection.speedtest => _buildSpeedTest(app),
          _SettingsSection.devices => _buildDevices(app),
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
          _SettingsSection.about => _buildAboutAndBackup(app),
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
                    if (PlatformPerfProfile.isTv) ...[
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: '上移',
                        icon: Icon(Icons.keyboard_arrow_up_rounded, size: 19, color: skin.fg2),
                        onPressed: idx == 0
                            ? null
                            : () {
                                final moved = sections.removeAt(idx);
                                sections.insert(idx - 1, moved);
                                app.saveHomeLayout(sections);
                              },
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: '下移',
                        icon: Icon(Icons.keyboard_arrow_down_rounded, size: 19, color: skin.fg2),
                        onPressed: idx == sections.length - 1
                            ? null
                            : () {
                                final moved = sections.removeAt(idx);
                                sections.insert(idx + 1, moved);
                                app.saveHomeLayout(sections);
                              },
                      ),
                    ] else ...[
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
            _SwitchRow(
              title: 'TV 遥控器大屏模式',
              subtitle: '强制启用大屏遥控器焦点高亮、方向键操作与安全边距（Android TV 默认自动开启）',
              value: p.tvModeOverride,
              onChanged: (v) => _updatePrefs(p.copyWith(tvModeOverride: v)),
            ),
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
    final isMobileOs = !kIsWeb && (Platform.isAndroid || Platform.isIOS) && !PlatformPerfProfile.isTv;
    final supportsPip = NativePlaybackChannel.supportsNativePip;
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
            if (isMobileOs)
              _SwitchRow(
                title: '双指捏合缩放画面',
                subtitle: '播放时支持双指自由缩放，松手保持比例',
                value: p.pinchToZoom,
                onChanged: (v) => _updatePrefs(p.copyWith(pinchToZoom: v)),
              ),
            _SwitchRow(
              key: const ValueKey('pref-show-network-speed'),
              title: '显示播放网速',
              subtitle: '播放与缓冲时实时显示当前下载网速',
              value: p.showNetworkSpeed,
              onChanged: (v) => _updatePrefs(p.copyWith(showNetworkSpeed: v)),
            ),
            _SwitchRow(
              key: const ValueKey('pref-remember-brightness'),
              title: '记忆播放器亮度',
              subtitle: '下次进入播放时自动恢复上次调节的画面亮度',
              value: p.rememberBrightness,
              onChanged: (v) => _updatePrefs(p.copyWith(rememberBrightness: v)),
            ),
            _SwitchRow(
              key: const ValueKey('pref-remember-volume'),
              title: '记忆播放器音量',
              subtitle: '下次进入播放时自动恢复上次调节的音量与静音状态',
              value: p.rememberVolume,
              onChanged: (v) => _updatePrefs(p.copyWith(rememberVolume: v)),
            ),
            _SwitchRow(
              key: const ValueKey('pref-remember-speed'),
              title: '记忆播放倍速',
              subtitle: '下次进入播放时自动恢复上次选择的倍速',
              value: p.rememberSpeed,
              onChanged: (v) => _updatePrefs(p.copyWith(rememberSpeed: v)),
            ),
            _SwitchRow(
              key: const ValueKey('pref-remember-aspect'),
              title: '记忆画面比例',
              subtitle: '下次进入播放时自动恢复上次选择的画面比例',
              value: p.rememberAspect,
              onChanged: (v) => _updatePrefs(p.copyWith(rememberAspect: v)),
            ),
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
                'hable': 'Hable（电影感曲线）',
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
                'stretch': '拉伸铺满',
                '16:9': '16:9',
                '21:9': '21:9',
                '2.35:1': '2.35:1',
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
        const _GroupHeader('人像美颜相机（可叠加 GPU）'),
        KeyedSubtree(
          key: const ValueKey('settings-beauty-filter-card'),
          child: _GroupedCard(
            children: [
              Builder(
                builder: (context) {
                  final bp = BeautyFilterEngine.resolveParams(
                    presetId: p.beautyFilterPreset,
                    strength: p.beautyFilterStrength,
                    smooth: p.beautySmooth,
                    whiten: p.beautyWhiten,
                    rosy: p.beautyRosy,
                    clarity: p.beautyClarity,
                  );
                  void saveChannel(BeautyFilterParams next) {
                    _updatePrefs(p.copyWith(
                      beautyFilterPreset: next.isActive ? 'custom' : 'off',
                      beautySmooth: next.smooth,
                      beautyWhiten: next.whiten,
                      beautyRosy: next.rosy,
                      beautyClarity: next.clarity,
                    ));
                  }

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bp.isActive
                              ? '当前效果：${BeautyFilterPreset.displayLabelFor(p.beautyFilterPreset, bp)} · ${bp.summaryLabel()}'
                              : '当前效果：原画关闭 · 可点选综合预设或直接拉动下方维度自由叠加',
                          style: TextStyle(color: VedroSkin.of(context).fg2, fontSize: 12.5),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: BeautyFilterPreset.all.map((preset) {
                            final selected = preset.id == 'off'
                                ? !bp.isActive
                                : (p.beautyFilterPreset == preset.id && bp.isActive);
                            return ChoiceChip(
                              selected: selected,
                              label: Text(preset.label, style: const TextStyle(fontSize: 12.5)),
                              onSelected: (_) => _updatePrefs(p.copyWith(
                                beautyFilterPreset: preset.id,
                                beautySmooth: preset.smooth,
                                beautyWhiten: preset.whiten,
                                beautyRosy: preset.rosy,
                                beautyClarity: preset.clarity,
                              )),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 10),
                        VedroPrecisionSlider(
                          label: '磨皮（肤质保边）',
                          value: bp.smooth,
                          min: 0.0,
                          max: 1.0,
                          step: 0.05,
                          defaultValue: 0.58,
                          snapValues: const [0.0, 0.35, 0.60, 0.85],
                          valueText: '${(bp.smooth * 100).round()}%',
                          onChanged: (v) => saveChannel(bp.copyWith(smooth: v)),
                        ),
                        const SizedBox(height: 8),
                        VedroPrecisionSlider(
                          label: '美白（仅提亮肤色）',
                          value: bp.whiten,
                          min: 0.0,
                          max: 1.0,
                          step: 0.05,
                          defaultValue: 0.42,
                          snapValues: const [0.0, 0.35, 0.60, 0.85],
                          valueText: '${(bp.whiten * 100).round()}%',
                          onChanged: (v) => saveChannel(bp.copyWith(whiten: v)),
                        ),
                        const SizedBox(height: 8),
                        VedroPrecisionSlider(
                          label: '粉嫩（气色与润唇）',
                          value: bp.rosy,
                          min: 0.0,
                          max: 1.0,
                          step: 0.05,
                          defaultValue: 0.30,
                          snapValues: const [0.0, 0.30, 0.55, 0.80],
                          valueText: '${(bp.rosy * 100).round()}%',
                          onChanged: (v) => saveChannel(bp.copyWith(rosy: v)),
                        ),
                        const SizedBox(height: 8),
                        VedroPrecisionSlider(
                          label: '亮眼清晰（五官立体）',
                          value: bp.clarity,
                          min: 0.0,
                          max: 1.0,
                          step: 0.05,
                          defaultValue: 0.40,
                          snapValues: const [0.0, 0.35, 0.60, 0.85],
                          valueText: '${(bp.clarity * 100).round()}%',
                          onChanged: (v) => saveChannel(bp.copyWith(clarity: v)),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0x1CF59E0B),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0x45F59E0B), width: 0.7),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.local_fire_department_outlined,
                                size: 15,
                                color: Color(0xFFD97706),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  '${BeautyFilterEngine.thermalNotice}（播放时也可直接点击底栏「美颜」按钮实时叠加调节）',
                                  style: TextStyle(
                                    color: VedroSkin.of(context).fg2,
                                    fontSize: 11.5,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
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
              value: p.maxVolumePercent <= 112
                  ? 100
                  : (p.maxVolumePercent <= 137 ? 125 : 150),
              items: const [(100, '100%'), (125, '125%'), (150, '150%')],
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
              title: '字幕描边宽度',
              valueText: p.subtitleOutlineWidth.toStringAsFixed(1),
              value: p.subtitleOutlineWidth,
              min: 0.0,
              max: 5.0,
              divisions: 10,
              onChanged: (v) => _updatePrefs(p.copyWith(subtitleOutlineWidth: v)),
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final chips = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: colors.map((entry) {
                      final (hex, label, c) = entry;
                      final on = p.subtitleColorHex == hex;
                      return PressableScale(
                        onTap: () => _updatePrefs(p.copyWith(subtitleColorHex: hex)),
                        borderRadius: BorderRadius.circular(8),
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
                      );
                    }).toList(),
                  );
                  if (constraints.maxWidth < 380) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('字幕颜色', style: TextStyle(color: skin.fg, fontSize: 14)),
                        const SizedBox(height: 8),
                        chips,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: Text('字幕颜色', style: TextStyle(color: skin.fg, fontSize: 14)),
                      ),
                      chips,
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
      final oldHost = Uri.tryParse(p.aiBaseUrl)?.host.toLowerCase() ?? '';
      final newHost = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
      final shouldClearKey = clearKey || (oldHost.isNotEmpty && newHost.isNotEmpty && oldHost != newHost);
      _aiUrlCtrl.text = baseUrl;
      _aiModelCtrl.text = model;
      if (shouldClearKey) _aiKeyCtrl.clear();
      await _updatePrefs(p.copyWith(
        aiEnabled: true,
        aiBaseUrl: baseUrl,
        aiModel: model,
        aiApiKey: shouldClearKey ? '' : _aiKeyCtrl.text.trim(),
        aiDirectClientIp: directIp,
        aiCachedModels: const [],
      ));
    }

    Future<void> applyAsrPreset({
      required String baseUrl,
      required String model,
      required bool directIp,
      bool clearKey = false,
    }) async {
      final oldHost = Uri.tryParse(p.asrBaseUrl)?.host.toLowerCase() ?? '';
      final newHost = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
      final shouldClearKey = clearKey || (oldHost.isNotEmpty && newHost.isNotEmpty && oldHost != newHost);
      _asrUrlCtrl.text = baseUrl;
      _asrModelCtrl.text = model;
      if (shouldClearKey) _asrKeyCtrl.clear();
      await _updatePrefs(p.copyWith(
        asrEnabled: true,
        asrBaseUrl: baseUrl,
        asrModel: model,
        asrApiKey: shouldClearKey ? '' : _asrKeyCtrl.text.trim(),
        asrDirectClientIp: directIp,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'AI 翻译',
          '支持影片简介翻译、播放器 YouTube 式双语字幕预读翻译，以及无字幕视频 AI 语音识别转译',
        ),
        const _GroupHeader('文本与双语字幕翻译'),
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
            if (isBili)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: VedroSkin.of(context).accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: VedroSkin.of(context).accent.withValues(alpha: 0.28),
                      width: 0.7,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 15, color: VedroSkin.of(context).accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bilibili 公共免费接口已自动启用礼貌限流保护：单线程请求、≥2.4 秒间隔、预读上限 55 秒且本地持久化缓存译文，不重复轰炸公共服务；如需更快并发可切换 DeepSeek / OpenAI / Ollama。',
                          style: TextStyle(
                            color: VedroSkin.of(context).fg2,
                            fontSize: 11.5,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
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
                (false, '跟随系统'),
              ],
              onChanged: (v) => _updatePrefs(p.copyWith(aiDirectClientIp: v)),
            ),
            _SwitchRow(
              title: '双语对照',
              value: p.aiBilingualSubtitle,
              onChanged: (v) => _updatePrefs(p.copyWith(aiBilingualSubtitle: v)),
            ),
            _InlineSegmentedRow<String>(
              title: '双语字幕默认排版',
              keyPrefix: 'pref-ai-subtitle-mode',
              value: p.aiSubtitleMode,
              items: const [
                ('bilingual_trans_top', '译文在上'),
                ('bilingual_orig_top', '原文在上'),
                ('translated_only', '仅译文'),
              ],
              onChanged: (v) => _updatePrefs(p.copyWith(aiSubtitleMode: v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: VedroPrecisionSlider(
                key: const ValueKey('pref-ai-subtitle-font-scale'),
                label: '翻译字幕默认字号',
                valueText: '${(p.aiSubtitleFontScale * 100).round()}%',
                value: p.aiSubtitleFontScale,
                min: 0.6,
                max: 1.8,
                step: 0.05,
                defaultValue: 1.0,
                snapValues: const [0.8, 1.0, 1.25, 1.5],
                onChanged: (v) => _updatePrefs(p.copyWith(aiSubtitleFontScale: v)),
              ),
            ),
            _InlineSegmentedRow<int>(
              title: '字幕预读批量',
              keyPrefix: 'pref-ai-subtitle-batch',
              value: p.aiSubtitleBatchSize,
              items: const [
                (12, '12 句'),
                (16, '16 句'),
                (24, '24 句'),
              ],
              onChanged: (v) => _updatePrefs(p.copyWith(aiSubtitleBatchSize: v)),
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
                                  if (!mounted) return;
                                  if (models.isNotEmpty) {
                                    _aiModelCtrl.text = app.prefs.aiModel;
                                  }
                                  setState(() => _aiTestResult = '已获取 ${models.length} 个模型');
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
                                if (!mounted) return;
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
        const SizedBox(height: 18),
        const _GroupHeader('AI 语音识别转字幕 (ASR · 无字幕视频自动听音转译)'),
        KeyedSubtree(
          key: const ValueKey('settings-asr-card'),
          child: _GroupedCard(
            children: [
              _InlineSegmentedRow<String>(
                title: '语音识别引擎',
                keyPrefix: 'asr-engine',
                value: p.asrEngine,
                items: const [
                  ('local', '本地离线模型（推荐）'),
                  ('cloud', '云端 / 自建 API'),
                ],
                onChanged: (v) => _updatePrefs(p.copyWith(asrEngine: v)),
              ),
              _InlineSegmentedRow<String>(
                title: '视频原声语言',
                keyPrefix: 'asr-lang',
                value: p.asrSourceLang,
                items: const [
                  ('auto', '自动'),
                  ('ja', '日语'),
                  ('en', '英语'),
                  ('zh', '中文'),
                  ('ko', '韩语'),
                ],
                onChanged: (v) => _updatePrefs(p.copyWith(asrSourceLang: v)),
              ),
              if (p.asrEngine == 'local')
                ListenableBuilder(
                  listenable: LocalAsrManager.instance,
                  builder: (context, _) {
                    final mgr = LocalAsrManager.instance;
                    final skin = VedroSkin.of(context);
                    final accent = Theme.of(context).colorScheme.secondary;
                    final sizeStr = mgr.downloadedBytes > 0
                        ? fmtFileSize(mgr.downloadedBytes)
                        : '约 229 MB';
                    return Padding(
                      key: const ValueKey('settings-local-asr-panel'),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: (mgr.isModelDownloaded
                                          ? const Color(0xFF10B981)
                                          : accent)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  mgr.isModelDownloaded
                                      ? Icons.check_circle_outline_rounded
                                      : Icons.downloading_rounded,
                                  size: 18,
                                  color: mgr.isModelDownloaded
                                      ? const Color(0xFF10B981)
                                      : accent,
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            LocalAsrModelSpec.displayName,
                                            style: TextStyle(
                                              color: skin.fg,
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          mgr.isModelDownloaded ? '已就绪 · $sizeStr' : sizeStr,
                                          style: TextStyle(
                                            color: mgr.isModelDownloaded
                                                ? const Color(0xFF10B981)
                                                : skin.fg3,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      LocalAsrModelSpec.languagesLabel,
                                      style: TextStyle(color: skin.fg3, fontSize: 11.5),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text('下载源：', style: TextStyle(color: skin.fg2, fontSize: 12)),
                              ChoiceChip(
                                selected: p.asrUseChinaMirror,
                                label: const Text('国内镜像加速', style: TextStyle(fontSize: 12)),
                                onSelected: (_) =>
                                    _updatePrefs(p.copyWith(asrUseChinaMirror: true)),
                              ),
                              ChoiceChip(
                                selected: !p.asrUseChinaMirror,
                                label: const Text('HuggingFace 官方', style: TextStyle(fontSize: 12)),
                                onSelected: (_) =>
                                    _updatePrefs(p.copyWith(asrUseChinaMirror: false)),
                              ),
                            ],
                          ),
                          if (mgr.isDownloading) ...[
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: mgr.downloadProgress > 0 ? mgr.downloadProgress : null,
                                minHeight: 5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    mgr.downloadStage,
                                    style: TextStyle(color: skin.fg2, fontSize: 12),
                                  ),
                                ),
                                TextButton(
                                  onPressed: mgr.cancelDownload,
                                  child: const Text('取消', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ],
                          if (mgr.downloadError != null && mgr.downloadError!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              mgr.downloadError!,
                              style: const TextStyle(color: VedroTheme.danger, fontSize: 12),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              if (!mgr.isModelDownloaded)
                                FilledButton.icon(
                                  key: const ValueKey('download-local-asr-btn'),
                                  onPressed: mgr.isDownloading
                                      ? null
                                      : () => mgr.downloadModel(
                                            useChinaMirror: p.asrUseChinaMirror,
                                          ),
                                  icon: const Icon(Icons.download_rounded, size: 16),
                                  label: Text(
                                    mgr.isDownloading ? '正在下载…' : '一键下载离线模型 (~229 MB)',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                )
                              else
                                OutlinedButton.icon(
                                  key: const ValueKey('delete-local-asr-btn'),
                                  onPressed: mgr.isDownloading
                                      ? null
                                      : () async {
                                          final messenger = ScaffoldMessenger.of(context);
                                          await mgr.deleteModel();
                                          if (mounted) {
                                            messenger.showSnackBar(
                                              const SnackBar(content: Text('已删除本地离线语音模型')),
                                            );
                                          }
                                        },
                                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                  label: const Text('删除模型释放空间', style: TextStyle(fontSize: 12.5)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '内置 sherpa-onnx + Silero VAD 直接从视频流提取音轨，无需录屏/麦克风权限弹窗；完全本地离线免费识别，中高端手机可流畅运行（长时间识别会有轻微功耗与温热，建议搭配上方 AI 翻译生成双语字幕）。',
                            style: TextStyle(color: skin.fg3, fontSize: 11.5, height: 1.45),
                          ),
                        ],
                      ),
                    );
                  },
                )
              else ...[
                _SwitchRow(
                  key: const ValueKey('pref-asr-enabled'),
                  title: '启用云端 / 自建语音识别',
                  subtitle: '零本地模型占用，通过 OpenAI 兼容接口切片识别音频并生成双语字幕',
                  value: p.asrEnabled,
                  onChanged: (v) => _updatePrefs(p.copyWith(asrEnabled: v)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        key: const ValueKey('asr-preset-groq'),
                        selected: p.asrBaseUrl.contains('groq.com'),
                        label: const Text('Groq Whisper（极速）'),
                        onSelected: (_) => applyAsrPreset(
                          baseUrl: 'https://api.groq.com/openai/v1',
                          model: 'whisper-large-v3-turbo',
                          directIp: false,
                        ),
                      ),
                      ChoiceChip(
                        key: const ValueKey('asr-preset-siliconflow'),
                        selected: p.asrBaseUrl.contains('siliconflow.cn'),
                        label: const Text('硅基流动 SenseVoice'),
                        onSelected: (_) => applyAsrPreset(
                          baseUrl: 'https://api.siliconflow.cn/v1',
                          model: 'FunAudioLLM/SenseVoiceSmall',
                          directIp: true,
                        ),
                      ),
                      ChoiceChip(
                        selected: p.asrBaseUrl.contains('openai.com'),
                        label: const Text('OpenAI Whisper'),
                        onSelected: (_) => applyAsrPreset(
                          baseUrl: 'https://api.openai.com/v1',
                          model: 'whisper-1',
                          directIp: false,
                        ),
                      ),
                      ChoiceChip(
                        selected: p.asrBaseUrl.contains('127.0.0.1') ||
                            p.asrBaseUrl.contains('localhost'),
                        label: const Text('本地 / NAS Whisper'),
                        onSelected: (_) => applyAsrPreset(
                          baseUrl: 'http://127.0.0.1:8000/v1',
                          model: 'whisper-large-v3-turbo',
                          directIp: true,
                          clearKey: true,
                        ),
                      ),
                    ],
                  ),
                ),
                _InlineSegmentedRow<bool>(
                  title: 'ASR 网络出口',
                  value: p.asrDirectClientIp,
                  items: const [
                    (true, '本机直连'),
                    (false, '跟随系统'),
                  ],
                  onChanged: (v) => _updatePrefs(p.copyWith(asrDirectClientIp: v)),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _asrUrlCtrl,
                        decoration: const InputDecoration(
                          labelText: 'ASR API Base URL（OpenAI /audio/transcriptions 兼容）',
                          hintText: 'https://api.groq.com/openai/v1',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _asrKeyCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'ASR API Key',
                          hintText: 'gsk_... / sk-...（本地自建可留空）',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _asrModelCtrl,
                        decoration: const InputDecoration(
                          labelText: '语音识别模型',
                          hintText: 'whisper-large-v3-turbo',
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          FilledButton(
                            onPressed: () async {
                              await _updatePrefs(p.copyWith(
                                asrEnabled: true,
                                asrBaseUrl: _asrUrlCtrl.text.trim(),
                                asrApiKey: _asrKeyCtrl.text.trim(),
                                asrModel: _asrModelCtrl.text.trim(),
                              ));
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('语音识别 (ASR) 配置已保存')),
                                );
                              }
                            },
                            child: const Text('保存语音识别配置', style: TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
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
                  final verified = await _verifyCurrentPin(p, title: '输入当前密码以关闭应用锁');
                  if (verified && mounted) {
                    await _updatePrefs(p.copyWith(passcodeEnabled: false, passcodeHash: ''));
                  }
                }
              },
            ),
            if (p.passcodeEnabled)
              _ActionRow(
                title: '修改 4 位解锁密码',
                trailing: Icon(Icons.chevron_right_rounded, size: 18, color: VedroSkin.of(context).fg3),
                onTap: () async {
                  final verified = await _verifyCurrentPin(p, title: '验证当前密码');
                  if (verified && mounted) {
                    await _openSetPinDialog(p);
                  }
                },
              ),
            _InlineSegmentedRow<int>(
              title: '自动锁定时间',
              value: p.lockTimeoutSecs,
              items: const [(0, '立即'), (60, '1 分'), (300, '5 分'), (900, '15 分')],
              onChanged: (v) => _updatePrefs(p.copyWith(lockTimeoutSecs: v)),
            ),
          ],
        ),
      ],
    );
  }

  // 15. 备份与关于
  Widget _buildAboutAndBackup(VedroAppState app) {
    final skin = VedroSkin.of(context);
    final version = app.core.coreVersion;

    Future<void> exportBackup() async {
      final jsonText = app.exportConfigJson();
      await Clipboard.setData(ClipboardData(text: jsonText));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: skin.surface,
          title: Text('已导出配置备份', style: TextStyle(color: skin.fg, fontSize: 16)),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '已自动复制到剪贴板（已自动剔除 API Key、应用密码哈希与登录令牌等敏感字段）。',
                  style: TextStyle(color: skin.fg2, fontSize: 12.5, height: 1.45),
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: skin.surface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: skin.border, width: 0.7),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        jsonText,
                        style: TextStyle(color: skin.fg2, fontFamily: 'monospace', fontSize: 11.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: jsonText));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('再次复制'),
            ),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('完成'),
            ),
          ],
        ),
      );
    }

    Future<void> importBackup() async {
      String? err;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => VedroControllerScope<TextEditingController>(
          create: () => TextEditingController(),
          dispose: (c) => c.dispose(),
          builder: (ctx, ctrl) => StatefulBuilder(
            builder: (ctx, setModal) => AlertDialog(
              backgroundColor: skin.surface,
              title: Text('导入配置备份', style: TextStyle(color: skin.fg, fontSize: 16)),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '粘贴由 Vedro 导出的 JSON 配置，将恢复外观、播放、字幕、弹幕及首页布局（不影响已登录服务器与安全密码）。',
                      style: TextStyle(color: skin.fg2, fontSize: 12.5, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: ctrl,
                      minLines: 4,
                      maxLines: 8,
                      style: TextStyle(color: skin.fg, fontFamily: 'monospace', fontSize: 12),
                      decoration: const InputDecoration(hintText: '{"format":"vedro-backup-v1", ...}'),
                    ),
                    if (err != null) ...[
                      const SizedBox(height: 8),
                      Text(err!, style: const TextStyle(color: VedroTheme.danger, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (ctx.mounted && data?.text != null) {
                      ctrl.text = data!.text!;
                      setModal(() => err = null);
                    }
                  },
                  child: const Text('从剪贴板粘贴'),
                ),
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                FilledButton(
                  onPressed: () async {
                    try {
                      await app.importConfigJson(ctrl.text);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      if (ctx.mounted) setModal(() => err = VedroErrorFormatter.friendly(e));
                    }
                  },
                  child: const Text('导入'),
                ),
              ],
            ),
          ),
        ),
      );
      if (ok == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已成功导入配置备份')),
        );
      }
    }

    Future<void> confirmResetPrefs() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: skin.surface,
          title: Text('恢复默认偏好设置？', style: TextStyle(color: skin.fg, fontSize: 16)),
          content: Text(
            '将重置外观皮肤、播放、视频、字幕、弹幕及界面偏好为出厂默认值，不会删除已保存的服务器、账号或离线下载文件。',
            style: TextStyle(color: skin.fg2, fontSize: 13),
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: VedroTheme.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('恢复默认'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await app.resetPreferencesToDefaults();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已恢复默认偏好设置')),
          );
        }
      }
    }

    Future<void> copyDiagnostics() async {
      final diag = [
        'Vedro v$version',
        'OS: ${kIsWeb ? 'web' : Platform.operatingSystem} ${kIsWeb ? '' : Platform.operatingSystemVersion}',
        'TV Mode: ${PlatformPerfProfile.isTv} (override=${app.prefs.tvModeOverride})',
        'Skin: ${app.prefs.skinId} (${app.prefs.themeMode})',
        'Server: ${app.isSignedIn ? (app.capabilities?.dialect ?? 'connected') : 'signed_out'} (${app.savedServers.length} saved)',
        'Video: hwdec=${app.settings['hwdec'] ?? 'auto_zero_copy'}, tone=${app.settings['tone_mapping'] ?? 'bt2446a'}, anime4k=${app.prefs.anime4kEnabled}, beauty=${app.prefs.beautyFilterPreset}',
        'Audio: mode=${app.settings['audio_mode'] ?? 'auto'}, maxVol=${app.prefs.maxVolumePercent}%',
        'AI/ASR: ai=${app.prefs.aiEnabled ? app.prefs.aiModel : 'off'}, asr=${app.prefs.asrEngine} (localReady=${LocalAsrManager.instance.isModelDownloaded})',
        'Downloads: ${app.downloads.length} tasks',
      ].join('\n');
      await Clipboard.setData(ClipboardData(text: diag));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制脱敏诊断信息到剪贴板')),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('备份与关于', '配置导出恢复、诊断信息与版本更新'),
        const _GroupHeader('配置备份与恢复'),
        _GroupedCard(
          children: [
            _ActionRow(
              title: '导出配置备份 (JSON)',
              trailing: Icon(Icons.ios_share_rounded, size: 17, color: skin.fg3),
              onTap: exportBackup,
            ),
            _ActionRow(
              title: '导入配置备份 (JSON)',
              trailing: Icon(Icons.download_for_offline_outlined, size: 18, color: skin.fg3),
              onTap: importBackup,
            ),
            _ActionRow(
              title: '恢复默认偏好设置',
              trailing: const Icon(Icons.restart_alt_rounded, size: 18, color: VedroTheme.danger),
              onTap: confirmResetPrefs,
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _GroupHeader('关于 Vedro'),
        _GroupedCard(
          children: [
            _InfoKVRow('当前版本', 'v$version', mono: true, highlight: true),
            _InfoKVRow('运行平台', kIsWeb ? 'Web' : Platform.operatingSystem),
            _SwitchRow(
              title: '启动时自动检查更新',
              subtitle: '检测到新版本时自动弹窗，支持应用内 SHA-256 校验与一键安装',
              value: app.prefs.autoCheckUpdates,
              onChanged: (v) => _updatePrefs(app.prefs.copyWith(autoCheckUpdates: v)),
            ),
            UpdateCheckBadgeTile(currentVersion: version),
            _ActionRow(
              title: '复制脱敏诊断信息',
              trailing: Icon(Icons.copy_rounded, size: 17, color: skin.fg3),
              onTap: copyDiagnostics,
            ),
            _ActionRow(
              title: 'GitHub 开源主页',
              trailing: Icon(Icons.open_in_new_rounded, size: 17, color: skin.fg3),
              onTap: () => NativePlaybackChannel.openUrl('https://github.com/JHruan1/vedro'),
            ),
            _ActionRow(
              title: '开源软件许可声明',
              trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.fg3),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Vedro',
                applicationVersion: 'v$version',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<bool> _verifyCurrentPin(VedroPreferences p, {required String title}) async {
    if (p.passcodeHash.isEmpty) return true;
    final lockout = PinLockoutController.forState(widget.appState);
    final initRem = lockout.remainingLockoutSecs;
    String? err = initRem > 0 ? '尝试次数过多，请 $initRem 秒后重试' : null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => VedroControllerScope<TextEditingController>(
        create: () => TextEditingController(),
        dispose: (c) => c.dispose(),
        builder: (ctx, ctrl) => StatefulBuilder(
          builder: (ctx, setModal) {
            void submit() {
              final res = lockout.verify(ctrl.text.trim(), p.passcodeHash);
              if (!res.ok) {
                setModal(() => err = res.error ?? '密码不正确');
                return;
              }
              Navigator.pop(ctx, true);
            }

            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    obscureText: true,
                    maxLength: 4,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => submit(),
                    decoration: const InputDecoration(labelText: '请输入当前 4 位数字密码', counterText: ''),
                  ),
                  if (err != null) ...[
                    const SizedBox(height: 8),
                    Text(err!, style: const TextStyle(color: VedroTheme.danger, fontSize: 12.5)),
                  ],
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                FilledButton(onPressed: submit, child: const Text('验证')),
              ],
            );
          },
        ),
      ),
    );
    return ok == true;
  }

  Future<void> _openSetPinDialog(VedroPreferences p) async {
    String? err;
    final chosenPin = await showDialog<String>(
      context: context,
      builder: (ctx) => VedroControllerScope<List<TextEditingController>>(
        create: () => [TextEditingController(), TextEditingController()],
        dispose: (ctrls) {
          for (final c in ctrls) {
            c.dispose();
          }
        },
        builder: (ctx, ctrls) {
          final pin1 = ctrls[0];
          final pin2 = ctrls[1];
          return StatefulBuilder(
            builder: (ctx, setModal) {
              void submit() {
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
                Navigator.pop(ctx, a);
              }

              return AlertDialog(
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
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: '输入 4 位数字密码', counterText: ''),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pin2,
                      obscureText: true,
                      maxLength: 4,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => submit(),
                      decoration: const InputDecoration(labelText: '再次确认密码', counterText: ''),
                    ),
                    if (err != null) ...[
                      const SizedBox(height: 10),
                      Text(err!, style: const TextStyle(color: VedroTheme.danger, fontSize: 12.5)),
                    ],
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                  FilledButton(onPressed: submit, child: const Text('保存密码')),
                ],
              );
            },
          );
        },
      ),
    );
    if (chosenPin != null && chosenPin.isNotEmpty && mounted) {
      PinLockoutController.forState(widget.appState).reset();
      await _updatePrefs(p.copyWith(
        passcodeEnabled: true,
        passcodeHash: createSaltedPasscodeHash(chosenPin),
      ));
    }
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
  const _GroupedCard({super.key, required this.children});
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

class _InfoKVRow extends StatelessWidget {
  const _InfoKVRow(
    this.label,
    this.value, {
    this.mono = false,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool mono;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(color: skin.fg2, fontSize: 13.5),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: highlight ? skin.accent : skin.fg,
                fontSize: 13.5,
                fontFamily: mono ? 'monospace' : null,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
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
            return PressableScale(
              key: keyPrefix != null ? ValueKey('$keyPrefix-${entry.$1}') : null,
              onTap: () => onChanged(entry.$1),
              hoverScale: 1.0,
              pressScale: 0.96,
              borderRadius: BorderRadius.circular(7),
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
    return PressableScale(
      onTap: () => onChanged(!value),
      hoverScale: 1.0,
      pressScale: 0.99,
      borderRadius: BorderRadius.circular(skin.cardRadius.clamp(10.0, 18.0)),
      child: Padding(
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
            ExcludeFocus(
              child: Transform.scale(
                scale: 0.78,
                child: CupertinoSwitch(
                  value: value,
                  activeTrackColor: skin.accent,
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
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
