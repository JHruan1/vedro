import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_skin.dart';
import '../state/app_state.dart';
import '../widgets/server_card_grid.dart';
import '../widgets/vedro_ui.dart';

/// First-class Media Server Switcher & Source Hub (`媒体库` tab on bottom/side/top nav):
/// Replaces duplicating the active server's library items with a dedicated multi-server
/// workspace (server cards with live latency/inventory, multi-route switching, LAN discovery,
/// add server, and local video playback).
class ServerHubScreen extends StatefulWidget {
  const ServerHubScreen({
    super.key,
    required this.appState,
    required this.onServerSelected,
    required this.onOpenAddServer,
    this.onOpenLocalMedia,
    this.onOpenNetworkUrl,
    this.onPlayLocalHistory,
    this.topInset = 0,
  });

  final VedroAppState appState;
  final VoidCallback onServerSelected;
  final void Function([String? initialUrl]) onOpenAddServer;
  final VoidCallback? onOpenLocalMedia;
  final VoidCallback? onOpenNetworkUrl;
  final void Function(VedroLocalHistoryEntry)? onPlayLocalHistory;
  final double topInset;

  @override
  State<ServerHubScreen> createState() => _ServerHubScreenState();
}

class _ServerHubScreenState extends State<ServerHubScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.appState.probeServersStatus();
      widget.appState.discoverLanServers();
    });
  }

  Future<void> _handleSelectServer(SavedServerProfile server) async {
    if (server.accessToken != null && server.userId != null) {
      HapticFeedback.lightImpact();
      final isDifferent =
          server.id != widget.appState.activeServerId || !widget.appState.isSignedIn;
      if (isDifferent) {
        // Trigger immediate 0ms switching state + navigate smoothly to Home so user
        // sees the server-switch transition instead of a 2s stall or stale Home flash.
        unawaited(widget.appState.restoreSavedServer(server).catchError((_) {}));
      }
      if (mounted) widget.onServerSelected();
    } else {
      widget.onOpenAddServer(server.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final app = widget.appState;
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final padX = app.prefs.horizontalMargin(wide);
    final isMac = !kIsWeb && Platform.isMacOS;
    final topPad = wide ? widget.topInset : MediaQuery.paddingOf(context).top;

    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final discovered = app.discoveredServers
            .where((d) => !app.savedServers.any(
                  (s) => s.url.replaceAll(RegExp(r'/$'), '') ==
                      (d['address']?.toString() ?? '').replaceAll(RegExp(r'/$'), ''),
                ))
            .toList();

        return Scaffold(
          key: const ValueKey('server-hub-screen'),
          backgroundColor: skin.canvas,
          body: VedroSkinCanvas(
            child: Padding(
              padding: EdgeInsets.only(top: topPad),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  padX + (isMac && !wide ? 64 : 0),
                  wide ? 18 : 14,
                  padX,
                  wide ? 48 : 112,
                ),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '媒体库',
                          style: skin.applyHeadlineMood(
                            TextStyle(
                              color: skin.fg,
                              fontSize: wide ? 28 : 24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.6,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (widget.onOpenNetworkUrl != null) ...[
                        Tooltip(
                          message: '网络链接',
                          child: PressableScale(
                            key: const ValueKey('server-hub-network-url-btn'),
                            onTap: widget.onOpenNetworkUrl,
                            pressScale: 0.92,
                            borderRadius: BorderRadius.circular(skin.radiusForPill(36)),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: skin.subtleChipBg,
                                shape: BoxShape.circle,
                                border: skin.cardBorder(),
                              ),
                              child: Icon(Icons.link_rounded, size: 17, color: skin.fg2),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (widget.onOpenLocalMedia != null) ...[
                        Tooltip(
                          message: '本地视频',
                          child: PressableScale(
                            key: const ValueKey('server-hub-local-video-btn'),
                            onTap: widget.onOpenLocalMedia,
                            pressScale: 0.92,
                            borderRadius: BorderRadius.circular(skin.radiusForPill(36)),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: skin.subtleChipBg,
                                shape: BoxShape.circle,
                                border: skin.cardBorder(),
                              ),
                              child: Icon(Icons.folder_open_rounded, size: 17, color: skin.fg2),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Tooltip(
                        message: '添加服务器',
                        child: PressableScale(
                          key: const ValueKey('server-hub-add-btn'),
                          onTap: () => widget.onOpenAddServer(),
                          pressScale: 0.94,
                          borderRadius: BorderRadius.circular(skin.radiusForPill(36)),
                          child: Container(
                            height: 36,
                            padding: EdgeInsets.symmetric(horizontal: wide ? 14 : 11),
                            decoration: BoxDecoration(
                              color: skin.primaryCtaBg,
                              gradient: skin.primaryCtaGradient,
                              borderRadius: BorderRadius.circular(skin.radiusForPill(36)),
                              border: skin.primaryCtaBorder,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_rounded, size: 18, color: skin.primaryCtaFg),
                                if (wide) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    '添加',
                                    style: TextStyle(
                                      color: skin.primaryCtaFg,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (app.savedServers.isEmpty)
                    VedroAdaptiveSurface(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 38),
                      borderRadius: skin.cardRadius.clamp(14.0, 22.0),
                      child: Column(
                        children: [
                          Icon(Icons.dns_rounded, size: 38, color: skin.fg3),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => widget.onOpenAddServer(),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('添加服务器'),
                          ),
                        ],
                      ),
                    )
                  else
                    ServerCardGrid(
                      appState: app,
                      onSelectServer: _handleSelectServer,
                      onAddServer: () => widget.onOpenAddServer(),
                    ),
                  if (app.localHistory.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Text(
                          '最近播放',
                          style: TextStyle(
                            color: skin.fg3,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: '清空',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.delete_sweep_outlined, size: 17, color: skin.fg3),
                          onPressed: app.clearLocalHistory,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: skin.surface,
                        borderRadius: BorderRadius.circular(skin.cardRadius.clamp(10.0, 16.0)),
                        border: skin.cardBorder(),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < app.localHistory.length; i++) ...[
                            if (i > 0) Divider(height: 1, indent: 14, endIndent: 14, color: skin.border),
                            Builder(
                              builder: (_) {
                                final entry = app.localHistory[i];
                                final pct = entry.progress;
                                return PressableScale(
                                  onTap: widget.onPlayLocalHistory == null
                                      ? null
                                      : () => widget.onPlayLocalHistory!(entry),
                                  hoverScale: 1.0,
                                  pressScale: 0.99,
                                  borderRadius: BorderRadius.circular(skin.cardRadius.clamp(8.0, 14.0)),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            color: skin.surface2,
                                            borderRadius: BorderRadius.circular(9),
                                          ),
                                          child: Icon(
                                            entry.isNetworkUrl
                                                ? Icons.link_rounded
                                                : Icons.video_file_rounded,
                                            size: 17,
                                            color: skin.accent,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                entry.title,
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
                                                entry.isNetworkUrl
                                                    ? VedroAppState.sanitizeUrlForHistory(entry.target)
                                                    : entry.target,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(color: skin.fg3, fontSize: 11.5),
                                              ),
                                              if (pct > 0) ...[
                                                const SizedBox(height: 5),
                                                ClipRRect(
                                                  borderRadius: BorderRadius.circular(2),
                                                  child: LinearProgressIndicator(
                                                    value: pct,
                                                    minHeight: 3,
                                                    backgroundColor: skin.surface2,
                                                    valueColor: AlwaysStoppedAnimation(skin.accent),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: '移除记录',
                                          icon: Icon(Icons.close_rounded, size: 16, color: skin.fg3),
                                          onPressed: () => app.removeLocalHistoryEntry(entry.key),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (discovered.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Text(
                      '局域网发现',
                      style: TextStyle(
                        color: skin.fg3,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: discovered.map((d) {
                        final addr = d['address']?.toString() ?? '';
                        final name = d['name']?.toString() ?? addr;
                        return PressableScale(
                          onTap: () => widget.onOpenAddServer(addr),
                          child: VedroAdaptiveSurface(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            borderRadius: skin.cardRadius.clamp(10.0, 16.0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.wifi_tethering_rounded, size: 16, color: skin.accent),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      name,
                                      style: TextStyle(
                                        color: skin.fg,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (addr.isNotEmpty && addr != name)
                                      Text(
                                        addr,
                                        style: TextStyle(color: skin.fg3, fontSize: 11),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
