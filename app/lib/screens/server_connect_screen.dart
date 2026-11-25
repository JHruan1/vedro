import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import '../widgets/vedro_ui.dart';

class ServerConnectScreen extends StatefulWidget {
  const ServerConnectScreen({super.key, required this.appState});
  final VedroAppState appState;

  @override
  State<ServerConnectScreen> createState() => _ServerConnectScreenState();
}

class _ServerConnectScreenState extends State<ServerConnectScreen> {
  final _urlCtrl = TextEditingController(text: 'https://');
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _proxyCtrl = TextEditingController();
  bool _obscure = true;
  bool _showAdvanced = false;
  bool _acceptInvalidCerts = false;

  @override
  void initState() {
    super.initState();
    _proxyCtrl.text = widget.appState.customProxyUrl;
    _acceptInvalidCerts = widget.appState.acceptInvalidCerts;
    if (widget.appState.savedServers.isNotEmpty) {
      _urlCtrl.text = widget.appState.savedServers.first.url;
      _userCtrl.text = widget.appState.savedServers.first.username ?? '';
    }
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
    try {
      await widget.appState.login(
        _urlCtrl.text,
        _userCtrl.text,
        _passCtrl.text,
        proxyUrl: _proxyCtrl.text,
        acceptInvalidTls: _acceptInvalidCerts,
      );
    } catch (_) {
      // Error surfaced cleanly via appState.errorMessage
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.appState.isBusy;
    final stageText = widget.appState.loginStage ?? '登录中…';

    return Scaffold(
      backgroundColor: VedroTheme.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: VedroBrandMark(size: 52)),
                  const SizedBox(height: 16),
                  const Text(
                    'Vedro',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: VedroTheme.fg,
                      fontSize: 25,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (widget.appState.savedServers.isNotEmpty) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: VedroTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: VedroTheme.line, width: 0.8),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < widget.appState.savedServers.length; i++) ...[
                            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                            _SavedServerRow(
                              profile: widget.appState.savedServers[i],
                              disabled: busy,
                              onTap: () => widget.appState.restoreSavedServer(
                                widget.appState.savedServers[i],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (widget.appState.discoveredServers.isNotEmpty) ...[
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
                              border: Border.all(color: VedroTheme.line, width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.wifi_tethering_rounded, size: 13, color: VedroTheme.fg2),
                                const SizedBox(width: 6),
                                Text(
                                  '${d['name'] ?? addr}',
                                  style: const TextStyle(color: VedroTheme.fg2, fontSize: 12.5),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: VedroTheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: VedroTheme.line, width: 0.8),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x5A000000),
                          blurRadius: 32,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _urlCtrl,
                          enabled: !busy,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(fontSize: 14, color: VedroTheme.fg),
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
                          style: const TextStyle(fontSize: 14, color: VedroTheme.fg),
                          decoration: const InputDecoration(
                            labelText: '用户名',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passCtrl,
                          enabled: !busy,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          style: const TextStyle(fontSize: 14, color: VedroTheme.fg),
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
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          child: widget.appState.errorMessage != null
                              ? Container(
                                  margin: const EdgeInsets.only(top: 12),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: VedroTheme.danger.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: VedroTheme.danger.withValues(alpha: 0.28),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: SelectableText(
                                    widget.appState.errorMessage!,
                                    style: const TextStyle(
                                      color: VedroTheme.danger,
                                      fontSize: 12.5,
                                      height: 1.45,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 44,
                          child: FilledButton(
                            onPressed: busy ? null : _submit,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 160),
                              child: busy
                                  ? Row(
                                      key: ValueKey(stageText),
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
                                        Text(
                                          stageText,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    )
                                  : const Text('登录', key: ValueKey('idle')),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: GestureDetector(
                      onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '网络与代理',
                              style: TextStyle(
                                color: _showAdvanced ? VedroTheme.fg2 : VedroTheme.fg3,
                                fontSize: 12.5,
                              ),
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
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: _showAdvanced
                        ? Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: VedroTheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: VedroTheme.line, width: 0.8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  controller: _proxyCtrl,
                                  enabled: !busy,
                                  style: const TextStyle(fontSize: 13.5, color: VedroTheme.fg),
                                  decoration: InputDecoration(
                                    labelText: '代理地址（留空自动跟随系统）',
                                    hintText: widget.appState.systemProxyUrl.isNotEmpty
                                        ? '系统代理: ${widget.appState.systemProxyUrl}'
                                        : 'http://127.0.0.1:7890',
                                  ),
                                ),
                                const SizedBox(height: 8),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SavedServerRow extends StatelessWidget {
  const _SavedServerRow({
    required this.profile,
    required this.disabled,
    required this.onTap,
  });

  final SavedServerProfile profile;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: disabled ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: VedroTheme.surface2,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: VedroTheme.line, width: 0.6),
              ),
              child: const Icon(Icons.dns_outlined, size: 16, color: VedroTheme.fg2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VedroTheme.fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [if (profile.username != null) profile.username!, profile.url].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: VedroTheme.fg3, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: VedroTheme.fg3),
          ],
        ),
      ),
    );
  }
}
