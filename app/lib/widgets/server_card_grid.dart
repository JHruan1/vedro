import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/models/preferences.dart';
import '../core/theme/vedro_skin.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.appState.savedServers.isNotEmpty) {
        unawaited(widget.appState.probeServersStatus());
      }
    });
  }

  Future<void> _pingServer(String serverId) async {
    if (_pinging.contains(serverId)) return;
    setState(() => _pinging.add(serverId));
    try {
      final results = await Future.wait<dynamic>([
        widget.appState.testServerRoutes(serverId),
        widget.appState.probeServersStatus(serverId: serverId, force: true),
      ]);
      final res = results.first as List<Map<String, dynamic>>;
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
    unawaited(widget.appState.probeServersStatus(force: true));
    for (final s in widget.appState.savedServers) {
      await _pingServer(s.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
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
                Icon(Icons.dns_outlined, size: 15, color: skin.fg3),
                const SizedBox(width: 6),
                Text(
                  '${servers.length}',
                  style: TextStyle(
                    color: skin.fg2,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: (_pinging.isNotEmpty || app.isProbingServers) ? '检测中' : '刷新状态',
                  child: PressableScale(
                    onTap: (_pinging.isNotEmpty || app.isProbingServers) ? null : _pingAll,
                    pressScale: 0.92,
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      width: 32,
                      height: 30,
                      decoration: BoxDecoration(
                        color: skin.surface,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: skin.border, width: 0.7),
                      ),
                      alignment: Alignment.center,
                      child: (_pinging.isNotEmpty || app.isProbingServers)
                          ? SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(strokeWidth: 1.7, color: skin.fg2),
                            )
                          : Icon(Icons.refresh_rounded, size: 15.5, color: skin.fg2),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    color: skin.surface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: skin.border, width: 0.7),
                  ),
                  child: VedroSlidingPillRow(
                    selectedIndex: isList ? 1 : 0,
                    pillDecoration: BoxDecoration(
                      color: skin.activePillBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    children: [
                      _LayoutToggleBtn(
                        icon: Icons.grid_view_rounded,
                        active: !isList,
                        tooltip: '网格',
                        onTap: () => app.updatePrefs(app.prefs.copyWith(serverCardLayout: 'grid')),
                      ),
                      _LayoutToggleBtn(
                        icon: Icons.view_agenda_outlined,
                        active: isList,
                        tooltip: '列表',
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
    final skin = VedroSkin.of(context);
    final srv = widget.server;
    final style = widget.appState.serverCardStyleFor(srv.id);
    final theme = style.resolveTheme(srv.id);
    final cardAccent = theme.cardAccent(skin);
    final displayName = style.customName.trim().isNotEmpty ? style.customName.trim() : srv.name;
    final activeRoute = srv.activeRoute;
    final activePing = activeRoute != null ? widget.pings[activeRoute.id] : null;
    final liveStatus = widget.appState.serverStatuses[srv.id];
    final isProbing = widget.pinging || (widget.appState.isProbingServers && liveStatus == null);
    final hostDisplay = style.hideAddress
        ? ''
        : (Uri.tryParse(activeRoute?.url ?? srv.url)?.host ?? srv.url);
    final subtitleText = style.subtitle.trim().isNotEmpty
        ? style.subtitle.trim()
        : hostDisplay;

    return PressableScale(
      onTap: widget.onTap,
      onLongPress: widget.onOpenSettings,
      onSecondaryTap: widget.onOpenSettings,
      onHoverChanged: (v) => setState(() => _hovered = v),
      primaryFocusRingOnly: true,
      hoverScale: 1.015,
      pressScale: 0.98,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [theme.cardBgTop(skin), theme.cardBgBottom(skin)],
          ),
          borderRadius: BorderRadius.circular(skin.cardRadius.clamp(12.0, 22.0)),
          border: Border.all(
            color: widget.isActive
                ? cardAccent.withValues(alpha: 0.78)
                : (_hovered ? skin.borderStrong : skin.border),
            width: widget.isActive ? 1.35 : 0.85,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.isActive
                  ? cardAccent.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: skin.isLight ? 0.06 : 0.22),
              blurRadius: widget.isActive ? 22 : 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Icon badge + Name + Active Checkmark + Settings icon
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: cardAccent.withValues(alpha: skin.isLight ? 0.13 : 0.18),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: cardAccent.withValues(alpha: 0.32), width: 0.8),
                      ),
                      child: Icon(style.iconData, size: 19, color: cardAccent),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: _OnlineStatusDot(
                        status: liveStatus,
                        pingOverride: activePing,
                        probing: isProbing,
                        isActiveConnected: widget.isActive,
                        ringColor: theme.cardBgTop(skin),
                      ),
                    ),
                  ],
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
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: skin.fg,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          if (widget.isActive) ...[
                            const SizedBox(width: 6),
                            Tooltip(
                              message: '已连接',
                              child: Icon(
                                Icons.check_circle_rounded,
                                size: 16,
                                color: skin.isLight
                                    ? const Color(0xFF059669)
                                    : const Color(0xFF30D158),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (subtitleText.isNotEmpty || style.hideAddress) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (style.hideAddress && style.subtitle.trim().isEmpty)
                              Icon(Icons.lock_outline_rounded, size: 11.5, color: skin.fg3)
                            else
                              Expanded(
                                child: Text(
                                  subtitleText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: skin.fg3, fontSize: 11.5),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: '测速',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: isProbing ? null : widget.onPing,
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: Center(
                        child: isProbing
                            ? SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.6,
                                  color: skin.fg2,
                                ),
                              )
                            : Icon(Icons.speed_rounded, size: 15.5, color: skin.fg3),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Tooltip(
                  message: '设置',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: widget.onOpenSettings,
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: Center(
                        child: Icon(Icons.tune_rounded, size: 15.5, color: skin.fg3),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Visual-first status strip: signal latency + compact icon+number inventory (movies/series/episodes) + route icon
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _OnlineStatusChip(
                        status: liveStatus,
                        pingOverride: activePing,
                        probing: isProbing,
                        isActiveConnected: widget.isActive,
                      ),
                      if (liveStatus != null && liveStatus.online && liveStatus.movieCount != null)
                        _InventoryChip(
                          icon: Icons.movie_outlined,
                          tooltip: '电影',
                          label: fmtCompactCount(liveStatus.movieCount!),
                        ),
                      if (liveStatus != null && liveStatus.online && liveStatus.seriesCount != null)
                        _InventoryChip(
                          icon: Icons.tv_rounded,
                          tooltip: '剧集',
                          label: fmtCompactCount(liveStatus.seriesCount!),
                        ),
                      if (liveStatus != null &&
                          liveStatus.online &&
                          liveStatus.episodeCount != null &&
                          liveStatus.episodeCount! > 0)
                        _InventoryChip(
                          icon: Icons.video_library_outlined,
                          tooltip: '集数',
                          label: fmtCompactCount(liveStatus.episodeCount!),
                        ),
                    ],
                  ),
                ),
                if (srv.routes.length > 1) ...[
                  const SizedBox(width: 6),
                  _InventoryChip(
                    icon: Icons.alt_route_rounded,
                    tooltip: activeRoute?.name ?? '线路',
                    label: '${srv.routes.length}',
                  ),
                ],
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
    final skin = VedroSkin.of(context);
    final style = appState.serverCardStyleFor(server.id);
    final theme = style.resolveTheme(server.id);
    final cardAccent = theme.cardAccent(skin);
    final displayName = style.customName.trim().isNotEmpty ? style.customName.trim() : server.name;
    final activeRoute = server.activeRoute;
    final activePing = activeRoute != null ? pings[activeRoute.id] : null;
    final liveStatus = appState.serverStatuses[server.id];
    final isProbing = pinging || (appState.isProbingServers && liveStatus == null);

    return PressableScale(
      onTap: onTap,
      onLongPress: onOpenSettings,
      onSecondaryTap: onOpenSettings,
      primaryFocusRingOnly: true,
      hoverScale: 1.006,
      pressScale: 0.99,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [theme.cardBgTop(skin), theme.cardBgBottom(skin)],
          ),
          borderRadius: BorderRadius.circular(skin.cardRadius.clamp(12.0, 22.0)),
          border: Border.all(
            color: isActive ? cardAccent.withValues(alpha: 0.72) : skin.border,
            width: isActive ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: cardAccent.withValues(alpha: skin.isLight ? 0.14 : 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(style.iconData, size: 18, color: cardAccent),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: _OnlineStatusDot(
                    status: liveStatus,
                    pingOverride: activePing,
                    probing: isProbing,
                    isActiveConnected: isActive,
                    ringColor: theme.cardBgTop(skin),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: skin.fg,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _OnlineStatusChip(
                        status: liveStatus,
                        pingOverride: activePing,
                        probing: isProbing,
                        isActiveConnected: isActive,
                      ),
                    ],
                  ),
                  if (liveStatus != null &&
                      liveStatus.online &&
                      (liveStatus.movieCount != null ||
                          liveStatus.seriesCount != null ||
                          (liveStatus.episodeCount != null && liveStatus.episodeCount! > 0))) ...[
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (liveStatus.movieCount != null)
                          _InventoryChip(
                            icon: Icons.movie_outlined,
                            tooltip: '电影',
                            label: fmtCompactCount(liveStatus.movieCount!),
                          ),
                        if (liveStatus.seriesCount != null)
                          _InventoryChip(
                            icon: Icons.tv_rounded,
                            tooltip: '剧集',
                            label: fmtCompactCount(liveStatus.seriesCount!),
                          ),
                        if (liveStatus.episodeCount != null && liveStatus.episodeCount! > 0)
                          _InventoryChip(
                            icon: Icons.video_library_outlined,
                            tooltip: '集数',
                            label: fmtCompactCount(liveStatus.episodeCount!),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: '已连接',
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 16.5,
                  color: skin.isLight ? const Color(0xFF059669) : const Color(0xFF30D158),
                ),
              ),
            ],
            const SizedBox(width: 4),
            IconButton(
              tooltip: '测速',
              visualDensity: VisualDensity.compact,
              icon: isProbing
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.7, color: skin.fg2),
                    )
                  : Icon(Icons.speed_rounded, size: 17, color: skin.fg3),
              onPressed: isProbing ? null : onPing,
            ),
            IconButton(
              tooltip: '设置',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.tune_rounded, size: 17, color: skin.fg3),
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
    final skin = VedroSkin.of(context);
    return PressableScale(
      onTap: onTap,
      hoverScale: 1.01,
      pressScale: 0.98,
      child: Container(
        height: compact ? 52 : 96,
        decoration: BoxDecoration(
          color: skin.unifiedTileColor(),
          borderRadius: BorderRadius.circular(skin.cardRadius.clamp(12.0, 22.0)),
          border: Border.all(color: skin.borderStrong, width: 1),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: skin.subtleChipBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(Icons.add_rounded, size: 18, color: skin.fg),
              ),
              const SizedBox(width: 8),
              Text(
                '添加服务器',
                style: TextStyle(
                  color: skin.fg2,
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

class _OnlineStatusDot extends StatelessWidget {
  const _OnlineStatusDot({
    required this.status,
    required this.pingOverride,
    required this.probing,
    required this.isActiveConnected,
    required this.ringColor,
  });

  final ServerLiveStatus? status;
  final Map<String, dynamic>? pingOverride;
  final bool probing;
  final bool isActiveConnected;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    final bool? online;
    final int? latencyMs;
    if (pingOverride != null) {
      online = pingOverride!['ok'] == true;
      latencyMs = (pingOverride!['latency_ms'] as num?)?.toInt();
    } else if (status != null) {
      online = status!.online;
      latencyMs = status!.latencyMs;
    } else if (isActiveConnected) {
      online = true;
      latencyMs = null;
    } else {
      online = null;
      latencyMs = null;
    }

    final Color dotColor;
    if (probing && online == null) {
      dotColor = const Color(0xFF9EA3B5);
    } else if (online == true) {
      dotColor = latencyMs != null && latencyMs >= 350
          ? const Color(0xFFFFD60A)
          : const Color(0xFF30D158);
    } else if (online == false) {
      dotColor = VedroTheme.danger;
    } else {
      dotColor = const Color(0xFF7D8294);
    }

    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        color: dotColor,
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 2),
      ),
    );
  }
}

class _OnlineStatusChip extends StatelessWidget {
  const _OnlineStatusChip({
    required this.status,
    required this.pingOverride,
    required this.probing,
    required this.isActiveConnected,
  });

  final ServerLiveStatus? status;
  final Map<String, dynamic>? pingOverride;
  final bool probing;
  final bool isActiveConnected;

  @override
  Widget build(BuildContext context) {
    final bool? online;
    final int? latencyMs;
    if (pingOverride != null) {
      online = pingOverride!['ok'] == true;
      latencyMs = (pingOverride!['latency_ms'] as num?)?.toInt();
    } else if (status != null) {
      online = status!.online;
      latencyMs = status!.latencyMs;
    } else if (isActiveConnected) {
      online = true;
      latencyMs = null;
    } else {
      online = null;
      latencyMs = null;
    }

    final Color color;
    final IconData icon;
    final String? msText;
    final String semantic;
    if (probing && online == null) {
      color = const Color(0xFF9EA3B5);
      icon = Icons.sync_rounded;
      msText = null;
      semantic = '检测中';
    } else if (online == true) {
      color = latencyMs != null && latencyMs >= 350
          ? const Color(0xFFFFD60A)
          : const Color(0xFF30D158);
      icon = Icons.signal_cellular_alt_rounded;
      msText = latencyMs != null ? '${latencyMs}ms' : null;
      semantic = latencyMs != null ? '在线 ${latencyMs}ms' : '在线';
    } else if (online == false) {
      color = VedroTheme.danger;
      icon = Icons.cloud_off_rounded;
      msText = null;
      semantic = '离线';
    } else {
      color = const Color(0xFF7D8294);
      icon = Icons.signal_cellular_alt_1_bar_rounded;
      msText = null;
      semantic = '未检测';
    }

    return Tooltip(
      message: semantic,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: msText != null ? 7 : 6, vertical: 2.5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            if (msText != null) ...[
              const SizedBox(width: 3),
              Text(
                msText,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InventoryChip extends StatelessWidget {
  const _InventoryChip({required this.icon, required this.label, this.tooltip});
  final IconData icon;
  final String label;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2.5),
      decoration: BoxDecoration(
        color: skin.subtleChipBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11.5, color: skin.fg3),
          const SizedBox(width: 3.5),
          Text(
            label,
            style: TextStyle(
              color: skin.fg2,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    return tooltip != null ? Tooltip(message: '$tooltip $label', child: chip) : chip;
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
    final String? text;
    if (!ok || ms == null) {
      color = VedroTheme.danger;
      text = null;
    } else if (ms < 120) {
      color = const Color(0xFF30D158);
      text = '${ms}ms';
    } else if (ms < 350) {
      color = const Color(0xFFFFD60A);
      text = '${ms}ms';
    } else {
      color = VedroTheme.danger;
      text = '${ms}ms';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            text == null ? Icons.cloud_off_rounded : Icons.signal_cellular_alt_rounded,
            size: 12,
            color: color,
          ),
          if (text != null) ...[
            const SizedBox(width: 3),
            Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
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
    final skin = VedroSkin.of(context);
    return Tooltip(
      message: tooltip,
      child: PressableScale(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 26,
          height: 24,
          child: Icon(icon, size: 15, color: active ? skin.activePillFg : skin.fg3),
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('线路测速失败：${VedroErrorFormatter.friendly(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _pinging = false);
    }
  }

  Future<void> _addRouteDialog(SavedServerProfile server) async {
    var allowSelfSigned = false;
    final created = await showVedroDialog<ServerRouteModel>(
      context: context,
      builder: (ctx) => VedroControllerScope<List<TextEditingController>>(
        create: () => [
          TextEditingController(),
          TextEditingController(),
          TextEditingController(),
        ],
        dispose: (ctrls) {
          for (final c in ctrls) {
            c.dispose();
          }
        },
        builder: (ctx, ctrls) {
          final nameCtrl = ctrls[0];
          final urlCtrl = ctrls[1];
          final proxyCtrl = ctrls[2];
          void submitDialog(BuildContext dlgCtx) {
            final u = urlCtrl.text.trim();
            if (u.isEmpty) return;
            final n = nameCtrl.text.trim().isNotEmpty
                ? nameCtrl.text.trim()
                : '线路 ${server.routes.length + 1}';
            Navigator.pop(
              dlgCtx,
              ServerRouteModel(
                id: 'r_${DateTime.now().millisecondsSinceEpoch}',
                name: n,
                url: u,
                proxyUrl: proxyCtrl.text.trim().isEmpty ? null : proxyCtrl.text.trim(),
                acceptInvalidCerts: allowSelfSigned,
              ),
            );
          }

          return StatefulBuilder(
            builder: (ctx, setDlg) => AlertDialog(
              title: Text('为 ${widget.appState.displayNameForServer(server)} 添加线路',
                  style: const TextStyle(fontSize: 16)),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '线路名称',
                          hintText: '如：香港直连 / 内网线路 / CF 备用',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: urlCtrl,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => submitDialog(ctx),
                        decoration: const InputDecoration(
                          labelText: '线路地址',
                          hintText: 'https://line2.example.com',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: proxyCtrl,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => submitDialog(ctx),
                        decoration: const InputDecoration(
                          labelText: '独立代理（可选，留空跟随系统）',
                          hintText: 'http://127.0.0.1:7890',
                        ),
                      ),
                      const SizedBox(height: 8),
                      PressableScale(
                        onTap: () => setDlg(() => allowSelfSigned = !allowSelfSigned),
                        hoverScale: 1.0,
                        pressScale: 0.99,
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '允许自签名证书',
                                style: TextStyle(color: VedroSkin.of(ctx).fg2, fontSize: 13),
                              ),
                            ),
                            ExcludeFocus(
                              child: Transform.scale(
                                scale: 0.8,
                                child: CupertinoSwitch(
                                  value: allowSelfSigned,
                                  onChanged: (v) => setDlg(() => allowSelfSigned = v),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                FilledButton(
                  onPressed: () => submitDialog(ctx),
                  child: const Text('添加'),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (created != null) {
      try {
        await widget.appState.saveServerRoutes(
          server.id,
          [...server.routes, created],
          activeRouteId: server.activeRouteId,
        );
        if (mounted) _runPing();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('保存线路失败：${VedroErrorFormatter.friendly(e)}')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final srv = _liveServer;
        final previewTheme = _themeId.isNotEmpty
            ? ServerCardTheme.byId(_themeId)
            : ServerCardTheme.forSeed(srv.id);
        final cardAccent = previewTheme.cardAccent(skin);
        final previewIcon = ServerCardStyle.icons[_iconId]?.$2 ?? Icons.dns_rounded;
        final previewName = _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : srv.name;
        final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 22 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '服务器卡片与线路设置',
                    style: TextStyle(
                      color: skin.fg,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
                    colors: [previewTheme.cardBgTop(skin), previewTheme.cardBgBottom(skin)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: cardAccent.withValues(alpha: 0.6),
                    width: 1.1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: cardAccent.withValues(alpha: skin.isLight ? 0.14 : 0.18),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(previewIcon, size: 20, color: cardAccent),
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
                            style: TextStyle(
                              color: skin.fg,
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
                            style: TextStyle(color: skin.fg2, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: skin.subtleChipBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        srv.dialect.toUpperCase(),
                        style: TextStyle(
                          color: cardAccent,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
                        labelText: '名称',
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
                        labelText: '备注',
                        hintText: '可选',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Card Color Theme Picker (visual swatches)
              Text('配色', style: TextStyle(color: skin.fg2, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: ServerCardTheme.all.map((t) {
                  final on = previewTheme.id == t.id;
                  final swatch = t.cardAccent(skin);
                  return Tooltip(
                    message: t.label,
                    child: PressableScale(
                      onTap: () => setState(() => _themeId = t.id),
                      pressScale: 0.9,
                      borderRadius: BorderRadius.circular(999),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: swatch,
                          shape: BoxShape.circle,
                          border: on
                              ? Border.all(color: skin.fg, width: 2.2)
                              : Border.all(color: Colors.white.withValues(alpha: 0.2), width: 0.8),
                        ),
                        child: on
                            ? Icon(Icons.check_rounded, size: 15, color: highContrastOn(swatch))
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // Card Icon Picker (visual icon tiles)
              Text('图标', style: TextStyle(color: skin.fg2, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ServerCardStyle.icons.entries.map((entry) {
                  final on = _iconId == entry.key;
                  return Tooltip(
                    message: entry.value.$1,
                    child: PressableScale(
                      onTap: () => setState(() => _iconId = entry.key),
                      pressScale: 0.9,
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: on ? cardAccent.withValues(alpha: 0.18) : skin.surface2,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: on ? cardAccent : skin.border,
                            width: on ? 1.2 : 0.7,
                          ),
                        ),
                        child: Icon(entry.value.$2, size: 17, color: on ? cardAccent : skin.fg2),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),

              // Hide URL privacy switch
              PressableScale(
                onTap: () => setState(() => _hideAddress = !_hideAddress),
                hoverScale: 1.0,
                pressScale: 0.99,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('隐藏域名', style: TextStyle(color: skin.fg, fontSize: 13.5)),
                      ),
                      ExcludeFocus(
                        child: Transform.scale(
                          scale: 0.8,
                          child: CupertinoSwitch(
                            value: _hideAddress,
                            activeTrackColor: skin.accent,
                            onChanged: (v) => setState(() => _hideAddress = v),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Divider(height: 22),

              // Routes section
              Row(
                children: [
                  Icon(Icons.alt_route_rounded, size: 15, color: skin.fg3),
                  const SizedBox(width: 6),
                  Text(
                    '线路 (${srv.routes.length})',
                    style: TextStyle(
                      color: skin.fg2,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  Tooltip(
                    message: _pinging ? '测速中' : '测速',
                    child: PressableScale(
                      onTap: _pinging ? null : _runPing,
                      pressScale: 0.92,
                      borderRadius: BorderRadius.circular(9),
                      child: Container(
                        width: 32,
                        height: 30,
                        decoration: BoxDecoration(
                          color: skin.surface2,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: skin.border, width: 0.7),
                        ),
                        alignment: Alignment.center,
                        child: _pinging
                            ? SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(strokeWidth: 1.6, color: skin.fg2),
                              )
                            : Icon(Icons.speed_rounded, size: 15.5, color: skin.fg2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: '添加线路',
                    child: PressableScale(
                      onTap: () => _addRouteDialog(srv),
                      pressScale: 0.92,
                      borderRadius: BorderRadius.circular(9),
                      child: Container(
                        width: 32,
                        height: 30,
                        decoration: BoxDecoration(
                          color: skin.surface2,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: skin.border, width: 0.7),
                        ),
                        alignment: Alignment.center,
                        child: Icon(Icons.add_rounded, size: 17, color: skin.fg2),
                      ),
                    ),
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
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    try {
                      await _saveStyle();
                      if (context.mounted) Navigator.pop(context);
                      await widget.appState.switchServerRoute(srv.id, route.id);
                    } catch (e) {
                      messenger?.showSnackBar(
                        SnackBar(content: Text('切换线路失败：${VedroErrorFormatter.friendly(e)}')),
                      );
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 7),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: activeRoute ? cardAccent.withValues(alpha: 0.14) : skin.surface2,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: activeRoute ? cardAccent.withValues(alpha: 0.6) : skin.border,
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
                                  color: skin.fg,
                                  fontSize: 13.5,
                                  fontWeight: activeRoute ? FontWeight.w600 : FontWeight.w500,
                                ),
                              ),
                              if (!_hideAddress)
                                Text(
                                  route.url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: skin.fg3, fontSize: 11.5),
                                ),
                            ],
                          ),
                        ),
                        if (ping != null) _LatencyBadge(ping: ping),
                        if (srv.routes.length > 1)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.close_rounded, size: 15, color: skin.fg3),
                            onPressed: () async {
                              try {
                                final next = srv.routes.where((r) => r.id != route.id).toList();
                                await widget.appState.saveServerRoutes(srv.id, next);
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                    SnackBar(
                                      content: Text('删除线路失败：${VedroErrorFormatter.friendly(e)}'),
                                    ),
                                  );
                                }
                              }
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
                    final confirm = await showVedroDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: skin.surface,
                        title: Text('移除服务器「$previewName」？',
                            style: TextStyle(color: skin.fg, fontSize: 16)),
                        content: Text('将移除本地保存的登录凭证与线路配置，不会影响远程服务器数据。',
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
                    if (confirm != true || !context.mounted) return;
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    Navigator.pop(context);
                    try {
                      await widget.appState.deleteServer(srv.id);
                    } catch (e) {
                      messenger?.showSnackBar(
                        SnackBar(content: Text('移除服务器失败：${VedroErrorFormatter.friendly(e)}')),
                      );
                    }
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
