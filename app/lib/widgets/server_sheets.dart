import 'dart:async';

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
    builder: (ctx) => _ServerHubSheetBody(
      appState: appState,
      parentContext: context,
    ),
  );
}

String _maskProxyCredentials(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.userInfo.isEmpty) return trimmed;
  return uri.replace(userInfo: '***').toString();
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

  // Jellyfin Quick Connect (TV remote friendly passwordless sign-in!)
  String? _qcCode;
  String? _qcSecret;
  bool _qcStarting = false;
  Timer? _qcPollTimer;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.initialUrl?.trim() ?? '');
    _proxyCtrl.text = widget.appState.customProxyUrl;
    _acceptInvalidCerts = widget.appState.acceptInvalidCerts;
    widget.appState.discoverLanServers();
  }

  @override
  void dispose() {
    _qcPollTimer?.cancel();
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _proxyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.appState.isBusy) return;
    _qcPollTimer?.cancel();
    setState(() {
      _localError = null;
      _qcCode = null;
      _qcSecret = null;
    });
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

  Future<void> _startQuickConnect() async {
    if (widget.appState.isBusy || _qcStarting) return;
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _localError = '请先输入服务器地址');
      return;
    }
    _qcPollTimer?.cancel();
    setState(() {
      _localError = null;
      _qcStarting = true;
      _qcCode = null;
      _qcSecret = null;
    });
    try {
      final res = await widget.appState.initiateQuickConnect(
        url,
        proxyUrl: _proxyCtrl.text,
        acceptInvalidTls: _acceptInvalidCerts,
      );
      if (!mounted) return;
      final code = res['code']?.toString() ?? '';
      final secret = res['secret']?.toString() ?? '';
      if (code.isEmpty || secret.isEmpty) {
        throw Exception('该服务器未开启 Quick Connect');
      }
      setState(() {
        _qcCode = code;
        _qcSecret = secret;
        _qcStarting = false;
      });
      _qcPollTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
        if (!mounted || _qcSecret == null) {
          t.cancel();
          return;
        }
        try {
          final done = await widget.appState.pollQuickConnect(_qcSecret!);
          if (done) {
            t.cancel();
            if (mounted) Navigator.of(context).pop(true);
          }
        } catch (e) {
          t.cancel();
          if (mounted) {
            setState(() {
              _qcCode = null;
              _qcSecret = null;
              _localError = VedroErrorFormatter.format(e);
            });
          }
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _qcStarting = false;
          _localError = VedroErrorFormatter.format(e);
        });
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
        final maskedSysProxy = _maskProxyCredentials(widget.appState.systemProxyUrl);

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
                            Flexible(
                              child: Text(
                                '${d['name'] ?? addr}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: skin.fg2, fontSize: 12),
                              ),
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
                autofocus: true,
                enabled: !busy,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                style: TextStyle(color: skin.fg, fontSize: 14),
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'https://emby.example.com:8096',
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
              if (_qcCode != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: skin.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: skin.accent.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Jellyfin Quick Connect 授权码',
                        style: TextStyle(color: skin.fg2, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        _qcCode!,
                        style: TextStyle(
                          color: skin.fg,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 4,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '请在已登录设备的 Jellyfin「快速连接」中输入此码，授权后自动完成登录',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: skin.fg3, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              PressableScale(
                onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                hoverScale: 1.0,
                pressScale: 0.99,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
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
                                hintText: maskedSysProxy.isNotEmpty
                                    ? '系统代理: $maskedSysProxy'
                                    : 'http://127.0.0.1:7890',
                              ),
                            ),
                            const SizedBox(height: 6),
                            PressableScale(
                              onTap: busy
                                  ? null
                                  : () => setState(() => _acceptInvalidCerts = !_acceptInvalidCerts),
                              hoverScale: 1.0,
                              pressScale: 0.99,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '允许自签名证书',
                                        style: TextStyle(color: skin.fg2, fontSize: 13),
                                      ),
                                    ),
                                    ExcludeFocus(
                                      child: Transform.scale(
                                        scale: 0.8,
                                        child: CupertinoSwitch(
                                          value: _acceptInvalidCerts,
                                          onChanged: busy
                                              ? null
                                              : (v) => setState(() => _acceptInvalidCerts = v),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
                  style: FilledButton.styleFrom(
                    disabledBackgroundColor: skin.surface2,
                    disabledForegroundColor: skin.fg2,
                  ),
                  onPressed: busy ? null : _submit,
                  child: busy
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: skin.fg,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                stage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: skin.fg, fontSize: 14),
                              ),
                            ),
                          ],
                        )
                      : const Text('连接并添加'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 38,
                child: OutlinedButton.icon(
                  onPressed: (busy || _qcStarting) ? null : _startQuickConnect,
                  icon: _qcStarting
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.8, color: skin.accent),
                        )
                      : const Icon(Icons.qr_code_2_rounded, size: 16),
                  label: Text(
                    _qcCode != null ? '刷新 Jellyfin 快速连接码' : 'Jellyfin 快速连接（电视免输密码）',
                    style: const TextStyle(fontSize: 12.5),
                  ),
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
  const _ServerHubSheetBody({
    required this.appState,
    required this.parentContext,
  });
  final VedroAppState appState;
  final BuildContext parentContext;

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
              Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
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
                  PressableScale(
                    onTap: () async {
                      Navigator.pop(context);
                      if (parentContext.mounted) {
                        await showAddServerSheet(context: parentContext, appState: appState);
                      }
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
                  if (parentContext.mounted) {
                    await showAddServerSheet(context: parentContext, appState: appState);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
