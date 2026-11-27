part of '../home_screen.dart';

/// SenPlayer / Forward Home Server Hub shown on startup when no server is active yet.
class _ServerWelcomeHub extends StatelessWidget {
  const _ServerWelcomeHub({
    required this.appState,
    required this.wide,
    required this.onOpenAddServer,
    this.onOpenLocalMedia,
    this.onOpenNetworkUrl,
    required this.onOpenServerHub,
    required this.onOpenSettings,
  });

  final VedroAppState appState;
  final bool wide;
  final void Function([String? initialUrl]) onOpenAddServer;
  final VoidCallback? onOpenLocalMedia;
  final VoidCallback? onOpenNetworkUrl;
  final VoidCallback onOpenServerHub;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final saved = appState.savedServers;
    final discovered = appState.discoveredServers;
    final btnR = skin.pillRadius >= 100 ? 12.0 : skin.pillRadius.clamp(6.0, 16.0);

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, wide ? 84 : 28, 24, wide ? 48 : 112),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: saved.length > 1 ? 940 : 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: VedroBrandMark(size: 56)),
                const SizedBox(height: 18),
                Text(
                  'Vedro',
                  textAlign: TextAlign.center,
                  style: skin.applyHeadlineMood(
                    TextStyle(
                      color: skin.fg,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.7,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    PressableScale(
                      onTap: () => onOpenAddServer(),
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          color: skin.primaryCtaBg,
                          gradient: skin.primaryCtaGradient,
                          borderRadius: BorderRadius.circular(btnR),
                          border: skin.primaryCtaBorder,
                          boxShadow: skin.primaryCtaShadow,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded, size: 19, color: skin.primaryCtaFg),
                            const SizedBox(width: 6),
                            Text(
                              '添加服务器',
                              style: TextStyle(
                                color: skin.primaryCtaFg,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (onOpenLocalMedia != null)
                      Tooltip(
                        message: '本地播放',
                        child: PressableScale(
                          onTap: onOpenLocalMedia,
                          pressScale: 0.92,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: skin.surface2,
                              borderRadius: BorderRadius.circular(btnR),
                              border: Border.all(color: skin.border, width: 0.8),
                            ),
                            child: Icon(Icons.folder_open_rounded, size: 19, color: skin.fg2),
                          ),
                        ),
                      ),
                    if (onOpenNetworkUrl != null)
                      Tooltip(
                        message: '网络链接',
                        child: PressableScale(
                          onTap: onOpenNetworkUrl,
                          pressScale: 0.92,
                          borderRadius: BorderRadius.circular(btnR),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: skin.surface2,
                              borderRadius: BorderRadius.circular(btnR),
                              border: Border.all(color: skin.border, width: 0.8),
                            ),
                            child: Icon(Icons.link_rounded, size: 19, color: skin.fg2),
                          ),
                        ),
                      ),
                    Tooltip(
                      message: '设置',
                      child: PressableScale(
                        onTap: onOpenSettings,
                        pressScale: 0.92,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: skin.surface2,
                            borderRadius: BorderRadius.circular(btnR),
                            border: Border.all(color: skin.border, width: 0.8),
                          ),
                          child: Icon(Icons.tune_rounded, size: 19, color: skin.fg2),
                        ),
                      ),
                    ),
                  ],
                ),

                if (saved.isNotEmpty) ...[
                  const SizedBox(height: 36),
                  ServerCardGrid(
                    appState: appState,
                    onSelectServer: (srv) => appState.restoreSavedServer(srv),
                    onAddServer: () => onOpenAddServer(),
                  ),
                ],

                if (discovered.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    '局域网发现',
                    style: TextStyle(
                      color: skin.fg2,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: discovered.map((d) {
                      final addr = d['address']?.toString() ?? '';
                      return PressableScale(
                        onTap: () => onOpenAddServer(addr),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                          decoration: BoxDecoration(
                            color: skin.surface,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: skin.border, width: 0.7),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.wifi_tethering_rounded, size: 15, color: skin.fg2),
                              const SizedBox(width: 8),
                              Text(
                                '${d['name'] ?? addr}',
                                style: TextStyle(color: skin.fg, fontSize: 13),
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
      ),
    );
  }
}
