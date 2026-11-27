import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
      if (server.id != widget.appState.activeServerId || !widget.appState.isSignedIn) {
        await widget.appState.restoreSavedServer(server);
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
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final headerTitle = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
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
                          if (app.savedServers.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                app.isSignedIn
                                    ? '当前连接：${app.activeServerDisplayName}'
                                    : '选择要进入的媒体服务器',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: skin.fg3, fontSize: 12.5),
                              ),
                            ),
                        ],
                      );
                      final actionButtons = <Widget>[
                        if (widget.onOpenNetworkUrl != null)
                          PressableScale(
                            key: const ValueKey('server-hub-network-url-btn'),
                            onTap: widget.onOpenNetworkUrl,
                            borderRadius: BorderRadius.circular(skin.radiusForPill(36)),
                            child: Container(
                              height: 36,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: skin.subtleChipBg,
                                borderRadius: BorderRadius.circular(skin.radiusForPill(36)),
                                border: skin.cardBorder(),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.link_rounded, size: 15.5, color: skin.fg2),
                                  const SizedBox(width: 6),
                                  Text(
                                    '网络链接',
                                    style: TextStyle(
                                      color: skin.fg,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (widget.onOpenLocalMedia != null)
                          PressableScale(
                            key: const ValueKey('server-hub-local-video-btn'),
                            onTap: widget.onOpenLocalMedia,
                            borderRadius: BorderRadius.circular(skin.radiusForPill(36)),
                            child: Container(
                              height: 36,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: skin.subtleChipBg,
                                borderRadius: BorderRadius.circular(skin.radiusForPill(36)),
                                border: skin.cardBorder(),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.folder_open_rounded, size: 15.5, color: skin.fg2),
                                  const SizedBox(width: 6),
                                  Text(
                                    '本地视频',
                                    style: TextStyle(
                                      color: skin.fg,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        PressableScale(
                          key: const ValueKey('server-hub-add-btn'),
                          onTap: () => widget.onOpenAddServer(),
                          borderRadius: BorderRadius.circular(skin.radiusForPill(36)),
                          child: Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: skin.primaryCtaBg,
                              gradient: skin.primaryCtaGradient,
                              borderRadius: BorderRadius.circular(skin.radiusForPill(36)),
                              border: skin.primaryCtaBorder,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_rounded, size: 17, color: skin.primaryCtaFg),
                                const SizedBox(width: 4),
                                Text(
                                  '添加服务器',
                                  style: TextStyle(
                                    color: skin.primaryCtaFg,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ];

                      if (constraints.maxWidth < 560) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            headerTitle,
                            const SizedBox(height: 12),
                            Wrap(spacing: 8, runSpacing: 8, children: actionButtons),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: headerTitle),
                          const SizedBox(width: 12),
                          Wrap(spacing: 8, runSpacing: 8, children: actionButtons),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  if (app.savedServers.isEmpty)
                    VedroAdaptiveSurface(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 38),
                      borderRadius: skin.cardRadius.clamp(14.0, 22.0),
                      child: Column(
                        children: [
                          Icon(Icons.dns_rounded, size: 38, color: skin.fg3),
                          const SizedBox(height: 12),
                          Text(
                            '尚未添加媒体服务器',
                            style: TextStyle(
                              color: skin.fg,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '支持 EmbyGo / Emby / Jellyfin 多服共存与多线路切换',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: skin.fg3, fontSize: 13),
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: () => widget.onOpenAddServer(),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('添加媒体服务器'),
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
                          '最近本地与链接播放',
                          style: TextStyle(
                            color: skin.fg3,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: app.clearLocalHistory,
                          child: Text('清空', style: TextStyle(color: skin.fg3, fontSize: 12)),
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
