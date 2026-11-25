import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import 'vedro_ui.dart';

/// Present SenPlayer / Forward style frosted modal to add / sign into a media server.
Future<bool?> showAddServerSheet({
  required BuildContext context,
  required VedroAppState appState,
  String? initialUrl,
}) {
  return showGlassSheet<bool>(
    context: context,
    builder: (ctx) => _AddServerForm(
      appState: appState,
      initialUrl: initialUrl,
    ),
  );
}

/// Present SenPlayer / Forward style Multi-Server & Multi-Route Switcher with live ping test.
Future<void> showServerHubSheet({
  required BuildContext context,
  required VedroAppState appState,
}) {
  return showGlassSheet<void>(
    context: context,
    builder: (ctx) => _ServerHubSheetBody(appState: appState),
  );
}

class _AddServerForm extends StatefulWidget {
  const _AddServerForm({required this.appState, this.initialUrl});
  final VedroAppState appState;
  final String? initialUrl;

  @override
  State<_AddServerForm> createState() => _AddServerFormState();
}

class _AddServerFormState extends State<_AddServerForm> {
  late final TextEditingController _urlCtrl;
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _proxyCtrl = TextEditingController();
  bool _obscure = true;
  bool _showAdvanced = false;
  bool _acceptInvalidCerts = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.initialUrl ?? 'https://');
    _proxyCtrl.text = widget.appState.customProxyUrl;
    _acceptInvalidCerts = widget.appState.acceptInvalidCerts;
    widget.appState.discoverLanServers();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _proxyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.appState.isBusy) return;
    setState(() => _localError = null);
    try {
      await widget.appState.login(
        _urlCtrl.text,
        _userCtrl.text,
        _passCtrl.text,
        proxyUrl: _proxyCtrl.text,
        acceptInvalidTls: _acceptInvalidCerts,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _localError = widget.appState.errorMessage);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final busy = widget.appState.isBusy;
        final stage = widget.appState.loginStage ?? '连接中…';
        final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(22, 14, 22, 22 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '添加媒体服务器',
                style: TextStyle(
                  color: VedroTheme.fg,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '支持 embygo / Emby / Jellyfin，添加后可在服务器面板配置多条线路。',
                style: TextStyle(color: VedroTheme.fg3, fontSize: 12.5),
              ),
              if (widget.appState.discoveredServers.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.appState.discoveredServers.map((d) {
                    final addr = d['address']?.toString() ?? '';
                    return PressableScale(
                      onTap: () => setState(() => _urlCtrl.text = addr),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: VedroTheme.surface2,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: VedroTheme.line, width: 0.7),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.wifi_tethering_rounded, size: 13, color: VedroTheme.fg2),
                            const SizedBox(width: 6),
                            Text(
                              '${d['name'] ?? addr}',
                              style: const TextStyle(color: VedroTheme.fg2, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _urlCtrl,
                enabled: !busy,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                style: const TextStyle(color: VedroTheme.fg, fontSize: 14),
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'https://example.com',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _userCtrl,
                enabled: !busy,
                textInputAction: TextInputAction.next,
                style: const TextStyle(color: VedroTheme.fg, fontSize: 14),
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passCtrl,
                enabled: !busy,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                style: const TextStyle(color: VedroTheme.fg, fontSize: 14),
                decoration: InputDecoration(
                  labelText: '密码',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 18,
                      color: VedroTheme.fg3,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Text(
                        '网络与代理',
                        style: TextStyle(color: VedroTheme.fg3, fontSize: 12.5),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _showAdvanced
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: VedroTheme.fg3,
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: _showAdvanced
                    ? Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          children: [
                            TextField(
                              controller: _proxyCtrl,
                              enabled: !busy,
                              style: const TextStyle(color: VedroTheme.fg, fontSize: 13.5),
                              decoration: InputDecoration(
                                labelText: '代理地址（留空自动跟随系统）',
                                hintText: widget.appState.systemProxyUrl.isNotEmpty
                                    ? '系统代理: ${widget.appState.systemProxyUrl}'
                                    : 'http://127.0.0.1:7890',
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    '允许自签名证书',
                                    style: TextStyle(color: VedroTheme.fg2, fontSize: 13),
                                  ),
                                ),
                                Switch(
                                  value: _acceptInvalidCerts,
                                  onChanged: busy
                                      ? null
                                      : (v) => setState(() => _acceptInvalidCerts = v),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              if (_localError != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: VedroTheme.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: VedroTheme.danger.withValues(alpha: 0.28)),
                  ),
                  child: SelectableText(
                    _localError!,
                    style: const TextStyle(color: VedroTheme.danger, fontSize: 12.5),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 44,
                child: FilledButton(
                  onPressed: busy ? null : _submit,
                  child: busy
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(stage, style: const TextStyle(color: Colors.white, fontSize: 14)),
                          ],
                        )
                      : const Text('连接并添加'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ServerHubSheetBody extends StatefulWidget {
  const _ServerHubSheetBody({required this.appState});
  final VedroAppState appState;

  @override
  State<_ServerHubSheetBody> createState() => _ServerHubSheetBodyState();
}

class _ServerHubSheetBodyState extends State<_ServerHubSheetBody> {
  final Map<String, Map<String, Map<String, dynamic>>> _pings = {};
  final Set<String> _pinging = {};
  String? _expandedServerId;

  @override
  void initState() {
    super.initState();
    _expandedServerId = widget.appState.activeServerId ??
        (widget.appState.savedServers.isNotEmpty ? widget.appState.savedServers.first.id : null);
  }

  Future<void> _runPing(String serverId) async {
    setState(() => _pinging.add(serverId));
    try {
      final res = await widget.appState.testServerRoutes(serverId);
      final map = <String, Map<String, dynamic>>{};
      for (final r in res) {
        final rid = r['id']?.toString();
        if (rid != null) map[rid] = r;
      }
      if (mounted) {
        setState(() => _pings[serverId] = map);
      }
    } finally {
      if (mounted) setState(() => _pinging.remove(serverId));
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
          title: Text('为 ${server.name} 添加线路', style: const TextStyle(fontSize: 16)),
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
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Expanded(
                      child: Text('允许自签名证书', style: TextStyle(color: VedroTheme.fg2, fontSize: 13)),
                    ),
                    Switch(
                      value: allowSelfSigned,
                      onChanged: (v) => setDlg(() => allowSelfSigned = v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消', style: TextStyle(color: VedroTheme.fg2)),
            ),
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
      final updated = [...server.routes, created];
      await widget.appState.saveServerRoutes(
        server.id,
        updated,
        activeRouteId: server.activeRouteId,
      );
      if (mounted) _runPing(server.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final servers = widget.appState.savedServers;
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
          children: [
            Row(
              children: [
                const Text(
                  '服务器与线路',
                  style: TextStyle(
                    color: VedroTheme.fg,
                    fontSize: 17.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                PressableScale(
                  onTap: () async {
                    Navigator.pop(context);
                    await showAddServerSheet(context: context, appState: widget.appState);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: VedroTheme.fg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, size: 15, color: VedroTheme.canvas),
                        SizedBox(width: 4),
                        Text(
                          '添加服务器',
                          style: TextStyle(
                            color: VedroTheme.canvas,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (servers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(
                    '尚未添加任何媒体服务器',
                    style: TextStyle(color: VedroTheme.fg3, fontSize: 13.5),
                  ),
                ),
              )
            else
              ...servers.map((srv) {
                final isActive = srv.id == widget.appState.activeServerId;
                final expanded = _expandedServerId == srv.id;
                final srvPings = _pings[srv.id] ?? const {};
                final testing = _pinging.contains(srv.id);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isActive ? const Color(0x18FFFFFF) : VedroTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isActive ? VedroTheme.lineStrong : VedroTheme.line,
                      width: 0.8,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        onTap: () async {
                          if (!isActive) {
                            Navigator.pop(context);
                            await widget.appState.restoreSavedServer(srv);
                          } else {
                            setState(() => _expandedServerId = expanded ? null : srv.id);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: isActive ? VedroTheme.accentSoft : VedroTheme.surface2,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Icon(
                                  Icons.dns_outlined,
                                  size: 17,
                                  color: isActive ? VedroTheme.accent : VedroTheme.fg2,
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
                                            srv.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: VedroTheme.fg,
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        if (isActive) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF3ECF8E),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      [
                                        if (srv.username != null) srv.username!,
                                        srv.activeRoute?.name ?? '默认线路',
                                        '${srv.routes.length} 条线路',
                                      ].join(' · '),
                                      style: const TextStyle(color: VedroTheme.fg3, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: '展开线路',
                                icon: Icon(
                                  expanded
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  size: 20,
                                  color: VedroTheme.fg2,
                                ),
                                onPressed: () =>
                                    setState(() => _expandedServerId = expanded ? null : srv.id),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (expanded) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    '线路切换',
                                    style: TextStyle(
                                      color: VedroTheme.fg3,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Spacer(),
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      foregroundColor: VedroTheme.fg2,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: testing ? null : () => _runPing(srv.id),
                                    icon: testing
                                        ? const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.6,
                                              color: VedroTheme.fg2,
                                            ),
                                          )
                                        : const Icon(Icons.speed_rounded, size: 15),
                                    label: const Text('一键测速', style: TextStyle(fontSize: 12)),
                                  ),
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      foregroundColor: VedroTheme.accent,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: () => _addRouteDialog(srv),
                                    icon: const Icon(Icons.add_rounded, size: 15),
                                    label: const Text('加线路', style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ...srv.routes.map((route) {
                                final activeRoute = isActive &&
                                    (srv.activeRoute?.id == route.id || srv.url == route.url);
                                final ping = srvPings[route.id];
                                return InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () async {
                                    Navigator.pop(context);
                                    await widget.appState.switchServerRoute(srv.id, route.id);
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 11,
                                      vertical: 9,
                                    ),
                                    decoration: BoxDecoration(
                                      color: activeRoute
                                          ? VedroTheme.accentSoft
                                          : VedroTheme.surface2,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: activeRoute
                                            ? VedroTheme.accent.withValues(alpha: 0.5)
                                            : VedroTheme.line,
                                        width: 0.7,
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
                                                  fontWeight: activeRoute
                                                      ? FontWeight.w600
                                                      : FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(height: 1),
                                              Text(
                                                route.url,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: VedroTheme.fg3,
                                                  fontSize: 11.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (ping != null) _LatencyPill(ping: ping),
                                        if (srv.routes.length > 1)
                                          IconButton(
                                            visualDensity: VisualDensity.compact,
                                            icon: const Icon(
                                              Icons.close_rounded,
                                              size: 15,
                                              color: VedroTheme.fg3,
                                            ),
                                            onPressed: () async {
                                              final next = srv.routes
                                                  .where((r) => r.id != route.id)
                                                  .toList();
                                              await widget.appState.saveServerRoutes(srv.id, next);
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor: VedroTheme.danger,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: () => widget.appState.deleteServer(srv.id),
                                  child: const Text('移除此服务器', style: TextStyle(fontSize: 12)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

class _LatencyPill extends StatelessWidget {
  const _LatencyPill({required this.ping});
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
      color = const Color(0xFF3ECF8E);
      text = '$ms ms';
    } else if (ms < 350) {
      color = const Color(0xFFF0A53A);
      text = '$ms ms';
    } else {
      color = VedroTheme.danger;
      text = '$ms ms';
    }
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
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
