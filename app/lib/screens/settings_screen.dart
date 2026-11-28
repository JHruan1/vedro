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
import '../core/theme/vedro_scroll.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/ai_face_beauty_card.dart';
import '../widgets/admin_console_pane.dart';
import '../widgets/app_lock_gate.dart' show PinLockoutController;
import '../widgets/beauty_filter.dart';
import '../core/services/local_asr_engine.dart';
import '../widgets/server_card_grid.dart';
import '../widgets/skin_studio_pane.dart';
import '../widgets/update_checker.dart';
import '../widgets/vedro_ui.dart';
import 'player_screen.dart';

part 'settings/settings_ai_privacy_sections.dart';
part 'settings/settings_appearance_sections.dart';
part 'settings/settings_playback_sections.dart';
part 'settings/settings_primitives.dart';
part 'settings/settings_server_download_sections.dart';

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
  final _detailScrollCtrl = VedroScrollController();
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
      keywords: 'buffer pip speed intro outro 小窗 缓存 跳过片头片尾',
    ),
    _NavItemMeta(
      section: _SettingsSection.video,
      title: '视频设置',
      icon: Icons.hd_rounded,
      tintTop: Color(0xFFFB923C),
      tintBottom: Color(0xFFEA580C),
      group: '播放与视听',
      keywords: 'hdr dolby vision anime4k mpv.conf beauty ai face yunet 硬解 杜比视界 美颜 磨皮 滤镜 瘦脸 大眼 奶油水光',
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
      keywords: 'openai deepseek bilibili translate asr yunet beauty 翻译 模型 语音 瘦脸 大眼 美颜',
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
  final _scrollCtrl = VedroScrollController();
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

  void _setDetailPaneState(VoidCallback fn) => setState(fn);
}
