import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import 'server_card_grid.dart';
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
    final skin = VedroSkin.of(context);
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
              Text(
                '添加媒体服务器',
                style: TextStyle(
                  color: skin.fg,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '支持 embygo / Emby / Jellyfin，添加后可在服务器面板配置多条线路。',
                style: TextStyle(color: skin.fg3, fontSize: 12.5),
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
                          color: skin.surface2,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: skin.border, width: 0.7),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.wifi_tethering_rounded, size: 13, color: skin.fg2),
                            const SizedBox(width: 6),
                            Text(
                              '${d['name'] ?? addr}',
                              style: TextStyle(color: skin.fg2, fontSize: 12),
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
                style: TextStyle(color: skin.fg, fontSize: 14),
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
                style: TextStyle(color: skin.fg, fontSize: 14),
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passCtrl,
                enabled: !busy,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                style: TextStyle(color: skin.fg, fontSize: 14),
                decoration: InputDecoration(
                  labelText: '密码',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 18,
                      color: skin.fg3,
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
                      Text(
                        '网络与代理',
                        style: TextStyle(color: skin.fg3, fontSize: 12.5),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _showAdvanced
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: skin.fg3,
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
                              style: TextStyle(color: skin.fg, fontSize: 13.5),
                              decoration: InputDecoration(
                                labelText: 'HTTP 代理（可选，留空跟随系统）',
                                hintText: widget.appState.systemProxyUrl.isNotEmpty
                                    ? '系统代理: ${widget.appState.systemProxyUrl}'
                                    : 'http://127.0.0.1:7890',
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '允许自签名证书',
                                    style: TextStyle(color: skin.fg2, fontSize: 13),
                                  ),
                                ),
                                Transform.scale(
                                  scale: 0.8,
                                  child: CupertinoSwitch(
                                    value: _acceptInvalidCerts,
                                    onChanged: busy
                                        ? null
                                        : (v) => setState(() => _acceptInvalidCerts = v),
                                  ),
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

class _ServerHubSheetBody extends StatelessWidget {
  const _ServerHubSheetBody({required this.appState});
  final VedroAppState appState;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '媒体服务器与线路',
                    style: TextStyle(
                      color: skin.fg,
                      fontSize: 17.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  PressableScale(
                    onTap: () async {
                      Navigator.pop(context);
                      await showAddServerSheet(context: context, appState: appState);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: skin.primaryCtaBg,
                        gradient: skin.primaryCtaGradient,
                        borderRadius: BorderRadius.circular(skin.radiusForPill(32)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded, size: 15, color: skin.primaryCtaFg),
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
                ],
              ),
              const SizedBox(height: 14),
              ServerCardGrid(
                appState: appState,
                compact: true,
                onSelectServer: (srv) async {
                  Navigator.pop(context);
                  if (srv.id != appState.activeServerId || !appState.isSignedIn) {
                    await appState.restoreSavedServer(srv);
                  }
                },
                onAddServer: () async {
                  Navigator.pop(context);
                  await showAddServerSheet(context: context, appState: appState);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
