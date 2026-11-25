import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/models/preferences.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import 'vedro_ui.dart';

/// Opens a polished macOS / iOS frosted card settings sheet for a specific media server:
/// custom alias, subtitle/remark, card color theme, icon, hide-URL privacy toggle,
/// multi-route list + live ping test + add route, and remove server.
Future<void> showServerCardSettingsSheet({
  required BuildContext context,
  required VedroAppState appState,
  required SavedServerProfile server,
}) {
  return showGlassSheet<void>(
    context: context,
    builder: (ctx) => _ServerCardSettingsSheet(appState: appState, server: server),
  );
}

/// Responsive Multi-Server Card Grid (or Compact List) used across:
/// - Startup Server Hub (`HomeScreen`)
/// - Settings → 服务器与线路 (`SettingsScreen`)
/// - Quick Server Switcher Sheet (`server_sheets.dart`)
class ServerCardGrid extends StatefulWidget {
  const ServerCardGrid({
    super.key,
    required this.appState,
    required this.onSelectServer,
    required this.onAddServer,
    this.compact = false,
    this.showHeaderControls = true,
  });

  final VedroAppState appState;
  final Future<void> Function(SavedServerProfile server) onSelectServer;
  final VoidCallback onAddServer;
  final bool compact;
  final bool showHeaderControls;

  @override
  State<ServerCardGrid> createState() => _ServerCardGridState();
}

class _ServerCardGridState extends State<ServerCardGrid> {
  final Map<String, Map<String, Map<String, dynamic>>> _pings = {};
  final Set<String> _pinging = {};

  Future<void> _pingServer(String serverId) async {
    if (_pinging.contains(serverId)) return;
    setState(() => _pinging.add(serverId));
    try {
      final res = await widget.appState.testServerRoutes(serverId);
      final map = <String, Map<String, dynamic>>{};
      for (final r in res) {
        final rid = r['id']?.toString();
        if (rid != null) map[rid] = r;
      }
      if (mounted) setState(() => _pings[serverId] = map);
    } finally {
      if (mounted) setState(() => _pinging.remove(serverId));
    }
  }

  Future<void> _pingAll() async {
    for (final s in widget.appState.savedServers) {
      await _pingServer(s.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.appState;
    final servers = app.savedServers;
    final isList = app.prefs.serverCardLayout == 'list';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeaderControls && servers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Text(
                  '已保存服务器 (${servers.length})',
                  style: const TextStyle(
                    color: VedroTheme.fg2,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (servers.isNotEmpty)
                  _SmallGhostButton(
                    icon: Icons.speed_rounded,
                    label: _pinging.isNotEmpty ? '测速中…' : '全部测速',
                    onTap: _pinging.isNotEmpty ? null : _pingAll,
                  ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    color: VedroTheme.surface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: VedroTheme.line, width: 0.7),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LayoutToggleBtn(
                        icon: Icons.grid_view_rounded,
                        active: !isList,
                        tooltip: '卡片网格',
                        onTap: () => app.updatePrefs(app.prefs.copyWith(serverCardLayout: 'grid')),
                      ),
                      _LayoutToggleBtn(
                        icon: Icons.view_agenda_outlined,
                        active: isList,
                        tooltip: '紧凑列表',
                        onTap: () => app.updatePrefs(app.prefs.copyWith(serverCardLayout: 'list')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        if (isList)
          Column(
            children: [
              for (final srv in servers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ServerCompactRowCard(
                    server: srv,
                    appState: app,
                    isActive: app.isSignedIn && srv.id == app.activeServerId,
                    pings: _pings[srv.id] ?? const {},
                    pinging: _pinging.contains(srv.id),
                    onTap: () => widget.onSelectServer(srv),
                    onPing: () => _pingServer(srv.id),
                    onOpenSettings: () => showServerCardSettingsSheet(
                      context: context,
                      appState: app,
                      server: srv,
                    ),
                  ),
                ),
              _AddServerDashedTile(compact: true, onTap: widget.onAddServer),
            ],
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final cols = widget.compact
                  ? (w >= 540 ? 2 : 1)
                  : (w >= 860 ? 3 : (w >= 500 ? 2 : 1));
              const gap = 14.0;
              final cardW = (w - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final srv in servers)
                    SizedBox(
                      width: cardW,
                      child: _ServerRichCard(
                        server: srv,
                        appState: app,
                        isActive: app.isSignedIn && srv.id == app.activeServerId,
                        pings: _pings[srv.id] ?? const {},
                        pinging: _pinging.contains(srv.id),
                        onTap: () => widget.onSelectServer(srv),
                        onPing: () => _pingServer(srv.id),
                        onOpenSettings: () => showServerCardSettingsSheet(
                          context: context,
                          appState: app,
                          server: srv,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: cardW,
                    child: _AddServerDashedTile(compact: false, onTap: widget.onAddServer),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _ServerRichCard extends StatefulWidget {
  const _ServerRichCard({
    required this.server,
    required this.appState,
    required this.isActive,
    required this.pings,
    required this.pinging,
    required this.onTap,
    required this.onPing,
    required this.onOpenSettings,
  });

  final SavedServerProfile server;
  final VedroAppState appState;
  final bool isActive;
  final Map<String, Map<String, dynamic>> pings;
  final bool pinging;
  final VoidCallback onTap;
  final VoidCallback onPing;
  final VoidCallback onOpenSettings;

  @override
  State<_ServerRichCard> createState() => _ServerRichCardState();
}

class _ServerRichCardState extends State<_ServerRichCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final srv = widget.server;
    final style = widget.appState.serverCardStyleFor(srv.id);
    final theme = style.resolveTheme(srv.id);
    final displayName = style.customName.trim().isNotEmpty ? style.customName.trim() : srv.name;
    final activeRoute = srv.activeRoute;
    final activePing = activeRoute != null ? widget.pings[activeRoute.id] : null;
    final hostDisplay = style.hideAddress
        ? '地址已隐藏'
        : (Uri.tryParse(activeRoute?.url ?? srv.url)?.host ?? srv.url);

    return PressableScale(
      onTap: widget.onTap,
      onHoverChanged: (v) => setState(() => _hovered = v),
      hoverScale: 1.015,
      pressScale: 0.98,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [theme.bgTop, theme.bgBottom],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: widget.isActive
                ? theme.accent.withValues(alpha: 0.78)
                : (_hovered ? const Color(0x40FFFFFF) : const Color(0x1EFFFFFF)),
            width: widget.isActive ? 1.35 : 0.85,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.isActive
                  ? theme.accent.withValues(alpha: 0.14)
                  : const Color(0x36000000),
              blurRadius: widget.isActive ? 22 : 12,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Icon badge + Title + Settings button
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.accent.withValues(alpha: 0.35), width: 0.8),
                  ),
                  child: Icon(style.iconData, size: 20, color: theme.accent),
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
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          if (widget.isActive) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0x2834D399),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0x5534D399), width: 0.6),
                              ),
                              child: const Text(
                                '已连接',
                                style: TextStyle(
                                  color: Color(0xFF34D399),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        style.subtitle.trim().isNotEmpty
                            ? style.subtitle.trim()
                            : [
                                if (srv.username != null && srv.username!.isNotEmpty) srv.username!,
                                hostDisplay,
                              ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xA8FFFFFF), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: '服务器卡片与线路设置',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: widget.onOpenSettings,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: const Color(0x18FFFFFF),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: const Color(0x1CFFFFFF), width: 0.6),
                      ),
                      child: const Icon(Icons.tune_rounded, size: 15, color: Color(0xD8FFFFFF)),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Bottom metadata chips: Dialect + Active Route + Latency + Quick Ping
            Row(
              children: [
                _MiniCardChip(
                  label: srv.dialect.isEmpty ? 'Emby' : srv.dialect.toUpperCase(),
                  color: theme.accent,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: _MiniCardChip(
                    label:
                        '${activeRoute?.name ?? '默认线路'}${srv.routes.length > 1 ? ' (${srv.routes.length})' : ''}',
                    color: const Color(0xCCFFFFFF),
                  ),
                ),
                const Spacer(),
                if (activePing != null)
                  _LatencyBadge(ping: activePing)
                else
                  InkWell(
                    borderRadius: BorderRadius.circular(7),
                    onTap: widget.pinging ? null : widget.onPing,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: widget.pinging
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.6,
                                color: Color(0xB8FFFFFF),
                              ),
                            )
                          : const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.speed_rounded, size: 13, color: Color(0x99FFFFFF)),
                                SizedBox(width: 3),
                                Text('测速', style: TextStyle(color: Color(0x99FFFFFF), fontSize: 11)),
                              ],
                            ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerCompactRowCard extends StatelessWidget {
  const _ServerCompactRowCard({
    required this.server,
    required this.appState,
    required this.isActive,
    required this.pings,
    required this.pinging,
    required this.onTap,
    required this.onPing,
    required this.onOpenSettings,
  });

  final SavedServerProfile server;
  final VedroAppState appState;
  final bool isActive;
  final Map<String, Map<String, dynamic>> pings;
  final bool pinging;
  final VoidCallback onTap;
  final VoidCallback onPing;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final style = appState.serverCardStyleFor(server.id);
    final theme = style.resolveTheme(server.id);
    final displayName = style.customName.trim().isNotEmpty ? style.customName.trim() : server.name;
    final activeRoute = server.activeRoute;
    final activePing = activeRoute != null ? pings[activeRoute.id] : null;

    return PressableScale(
      onTap: onTap,
      hoverScale: 1.006,
      pressScale: 0.99,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [theme.bgTop, theme.bgBottom],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? theme.accent.withValues(alpha: 0.72) : const Color(0x1CFFFFFF),
            width: isActive ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(style.iconData, size: 18, color: theme.accent),
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
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 7),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Color(0xFF34D399),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (style.subtitle.trim().isNotEmpty) style.subtitle.trim(),
                      if (server.username != null && server.username!.isNotEmpty) server.username!,
                      activeRoute?.name ?? '默认线路',
                      if (server.routes.length > 1) '${server.routes.length} 条线路',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0x9EFFFFFF), fontSize: 12),
                  ),
                ],
              ),
            ),
            if (activePing != null) _LatencyBadge(ping: activePing),
            const SizedBox(width: 6),
            IconButton(
              tooltip: '测速',
              visualDensity: VisualDensity.compact,
              icon: pinging
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.7, color: VedroTheme.fg2),
                    )
                  : const Icon(Icons.speed_rounded, size: 17, color: VedroTheme.fg2),
              onPressed: pinging ? null : onPing,
            ),
            IconButton(
              tooltip: '卡片与线路设置',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.tune_rounded, size: 17, color: VedroTheme.fg2),
              onPressed: onOpenSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddServerDashedTile extends StatelessWidget {
  const _AddServerDashedTile({required this.compact, required this.onTap});
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      hoverScale: 1.01,
      pressScale: 0.98,
      child: Container(
        height: compact ? 54 : 118,
        decoration: BoxDecoration(
          color: const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(compact ? 14 : 18),
          border: Border.all(color: const Color(0x26FFFFFF), width: 1),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0x16FFFFFF),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.add_rounded, size: 18, color: VedroTheme.fg),
              ),
              const SizedBox(width: 9),
              const Text(
                '添加媒体服务器',
                style: TextStyle(
                  color: VedroTheme.fg2,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniCardChip extends StatelessWidget {
  const _MiniCardChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: const Color(0x18FFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _LatencyBadge extends StatelessWidget {
  const _LatencyBadge({required this.ping});
  final Map<String, dynamic> ping;

  @override
  Widget build(BuildContext context) {
    final ok = ping['ok'] == true;
    final ms = (ping['latency_ms'] as num?)?.toInt();
    final Color color;
    final String text;
    if (!ok || ms == null) {
      color = VedroTheme.danger;
      text = '不可达';
    } else if (ms < 120) {
      color = const Color(0xFF34D399);
      text = '$ms ms';
    } else if (ms < 350) {
      color = const Color(0xFFFBBF24);
      text = '$ms ms';
    } else {
      color = VedroTheme.danger;
      text = '$ms ms';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _SmallGhostButton extends StatelessWidget {
  const _SmallGhostButton({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: VedroTheme.surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: VedroTheme.line, width: 0.7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: VedroTheme.fg2),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(color: VedroTheme.fg2, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _LayoutToggleBtn extends StatelessWidget {
  const _LayoutToggleBtn({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 26,
          height: 24,
          decoration: BoxDecoration(
            color: active ? VedroTheme.surface3 : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 15, color: active ? Colors.white : VedroTheme.fg3),
        ),
      ),
    );
  }
}

class _ServerCardSettingsSheet extends StatefulWidget {
  const _ServerCardSettingsSheet({required this.appState, required this.server});
  final VedroAppState appState;
  final SavedServerProfile server;

  @override
  State<_ServerCardSettingsSheet> createState() => _ServerCardSettingsSheetState();
}

class _ServerCardSettingsSheetState extends State<_ServerCardSettingsSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _subCtrl;
  late String _themeId;
  late String _iconId;
  late bool _hideAddress;
  final Map<String, Map<String, dynamic>> _pings = {};
  bool _pinging = false;

  @override
  void initState() {
    super.initState();
    final st = widget.appState.serverCardStyleFor(widget.server.id);
    _nameCtrl = TextEditingController(text: st.customName);
    _subCtrl = TextEditingController(text: st.subtitle);
    _themeId = st.themeId;
    _iconId = st.iconId;
    _hideAddress = st.hideAddress;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _subCtrl.dispose();
    super.dispose();
  }

  SavedServerProfile get _liveServer {
    for (final s in widget.appState.savedServers) {
      if (s.id == widget.server.id) return s;
    }
    return widget.server;
  }

  Future<void> _saveStyle() async {
    await widget.appState.updateServerCardStyle(
      widget.server.id,
      ServerCardStyle(
        customName: _nameCtrl.text.trim(),
        subtitle: _subCtrl.text.trim(),
        themeId: _themeId,
        iconId: _iconId,
        hideAddress: _hideAddress,
      ),
    );
  }

  Future<void> _runPing() async {
    setState(() => _pinging = true);
    try {
      final res = await widget.appState.testServerRoutes(widget.server.id);
      if (mounted) {
        setState(() {
          for (final r in res) {
            final rid = r['id']?.toString();
            if (rid != null) _pings[rid] = r;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _pinging = false);
    }
  }

  Future<void> _addRouteDialog(SavedServerProfile server) async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController(text: 'https://');
    final proxyCtrl = TextEditingController();
    var allowSelfSigned = false;

    final created = await showDialog<ServerRouteModel>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('为 ${widget.appState.displayNameForServer(server)} 添加线路',
              style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '线路名称',
                    hintText: '如：香港直连 / 内网线路 / CF 备用',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: '线路地址',
                    hintText: 'https://line2.example.com',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: proxyCtrl,
                  decoration: const InputDecoration(
                    labelText: '独立代理（可选，留空跟随系统）',
                    hintText: 'http://127.0.0.1:7890',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(
                      child: Text('允许自签名证书', style: TextStyle(color: VedroTheme.fg2, fontSize: 13)),
                    ),
                    Transform.scale(
                      scale: 0.8,
                      child: CupertinoSwitch(
                        value: allowSelfSigned,
                        onChanged: (v) => setDlg(() => allowSelfSigned = v),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final u = urlCtrl.text.trim();
                if (u.isEmpty) return;
                final n = nameCtrl.text.trim().isNotEmpty
                    ? nameCtrl.text.trim()
                    : '线路 ${server.routes.length + 1}';
                Navigator.pop(
                  ctx,
                  ServerRouteModel(
                    id: 'r_${DateTime.now().millisecondsSinceEpoch}',
                    name: n,
                    url: u,
                    proxyUrl: proxyCtrl.text.trim().isEmpty ? null : proxyCtrl.text.trim(),
                    acceptInvalidCerts: allowSelfSigned,
                  ),
                );
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    urlCtrl.dispose();
    proxyCtrl.dispose();

    if (created != null) {
      await widget.appState.saveServerRoutes(
        server.id,
        [...server.routes, created],
        activeRouteId: server.activeRouteId,
      );
      if (mounted) _runPing();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final srv = _liveServer;
        final previewTheme = _themeId.isNotEmpty
            ? ServerCardTheme.byId(_themeId)
            : ServerCardTheme.forSeed(srv.id);
        final previewIcon = ServerCardStyle.icons[_iconId]?.$2 ?? Icons.dns_rounded;
        final previewName = _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : srv.name;
        final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 22 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text(
                    '服务器卡片与线路设置',
                    style: TextStyle(
                      color: VedroTheme.fg,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () async {
                      await _saveStyle();
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('保存', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Live Card Preview
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [previewTheme.bgTop, previewTheme.bgBottom],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: previewTheme.accent.withValues(alpha: 0.6),
                    width: 1.1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: previewTheme.accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(previewIcon, size: 20, color: previewTheme.accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            previewName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _subCtrl.text.trim().isNotEmpty
                                ? _subCtrl.text.trim()
                                : (_hideAddress ? '地址已隐藏' : srv.url),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xA6FFFFFF), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    _MiniCardChip(
                      label: srv.dialect.toUpperCase(),
                      color: previewTheme.accent,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Alias & Subtitle
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: '卡片显示名称',
                        hintText: srv.name,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _subCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: '备注 / 副标题（可选）',
                        hintText: '如：4K 原盘主力服',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Card Color Theme Picker
              const Text('卡片配色', style: TextStyle(color: VedroTheme.fg2, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ServerCardTheme.all.map((t) {
                  final on = previewTheme.id == t.id;
                  return GestureDetector(
                    onTap: () => setState(() => _themeId = t.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: on ? t.accent.withValues(alpha: 0.18) : VedroTheme.surface2,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: on ? t.accent : VedroTheme.line,
                          width: on ? 1.1 : 0.7,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 11,
                            height: 11,
                            decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            t.label,
                            style: TextStyle(
                              color: on ? Colors.white : VedroTheme.fg2,
                              fontSize: 12,
                              fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // Card Icon Picker
              const Text('卡片图标', style: TextStyle(color: VedroTheme.fg2, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ServerCardStyle.icons.entries.map((entry) {
                  final on = _iconId == entry.key;
                  return GestureDetector(
                    onTap: () => setState(() => _iconId = entry.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: on ? previewTheme.accent.withValues(alpha: 0.18) : VedroTheme.surface2,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: on ? previewTheme.accent : VedroTheme.line,
                          width: on ? 1.1 : 0.7,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(entry.value.$2, size: 15, color: on ? previewTheme.accent : VedroTheme.fg2),
                          const SizedBox(width: 5),
                          Text(
                            entry.value.$1,
                            style: TextStyle(
                              color: on ? Colors.white : VedroTheme.fg2,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),

              // Hide URL privacy switch
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('卡片隐藏服务器域名', style: TextStyle(color: VedroTheme.fg, fontSize: 13.5)),
                        Text('截屏或分享时隐藏真实域名地址', style: TextStyle(color: VedroTheme.fg3, fontSize: 11.5)),
                      ],
                    ),
                  ),
                  Transform.scale(
                    scale: 0.8,
                    child: CupertinoSwitch(
                      value: _hideAddress,
                      onChanged: (v) => setState(() => _hideAddress = v),
                    ),
                  ),
                ],
              ),

              const Divider(height: 24),

              // Routes section
              Row(
                children: [
                  Text(
                    '多线路管理 (${srv.routes.length})',
                    style: const TextStyle(color: VedroTheme.fg2, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  _SmallGhostButton(
                    icon: Icons.speed_rounded,
                    label: _pinging ? '测速中…' : '测速',
                    onTap: _pinging ? null : _runPing,
                  ),
                  const SizedBox(width: 8),
                  _SmallGhostButton(
                    icon: Icons.add_rounded,
                    label: '加线路',
                    onTap: () => _addRouteDialog(srv),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...srv.routes.map((route) {
                final activeRoute = srv.id == widget.appState.activeServerId &&
                    (srv.activeRoute?.id == route.id || srv.url == route.url);
                final ping = _pings[route.id];
                return InkWell(
                  borderRadius: BorderRadius.circular(11),
                  onTap: () async {
                    await _saveStyle();
                    if (context.mounted) Navigator.pop(context);
                    await widget.appState.switchServerRoute(srv.id, route.id);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 7),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: activeRoute ? previewTheme.accent.withValues(alpha: 0.14) : VedroTheme.surface2,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: activeRoute ? previewTheme.accent.withValues(alpha: 0.6) : VedroTheme.line,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                route.name,
                                style: TextStyle(
                                  color: activeRoute ? Colors.white : VedroTheme.fg,
                                  fontSize: 13.5,
                                  fontWeight: activeRoute ? FontWeight.w600 : FontWeight.w500,
                                ),
                              ),
                              if (!_hideAddress)
                                Text(
                                  route.url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: VedroTheme.fg3, fontSize: 11.5),
                                ),
                            ],
                          ),
                        ),
                        if (ping != null) _LatencyBadge(ping: ping),
                        if (srv.routes.length > 1)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close_rounded, size: 15, color: VedroTheme.fg3),
                            onPressed: () async {
                              final next = srv.routes.where((r) => r.id != route.id).toList();
                              await widget.appState.saveServerRoutes(srv.id, next);
                            },
                          ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: VedroTheme.danger),
                  onPressed: () async {
                    Navigator.pop(context);
                    await widget.appState.deleteServer(srv.id);
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('移除此服务器', style: TextStyle(fontSize: 12.5)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
