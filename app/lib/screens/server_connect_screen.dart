import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/prism_theme.dart';
import '../state/app_state.dart';
import '../widgets/badge_strip.dart';

class ServerConnectScreen extends StatefulWidget {
  const ServerConnectScreen({super.key, required this.appState});
  final PrismAppState appState;

  @override
  State<ServerConnectScreen> createState() => _ServerConnectScreenState();
}

class _ServerConnectScreenState extends State<ServerConnectScreen> {
  final _urlCtrl = TextEditingController(text: 'http://127.0.0.1:8097');
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    widget.appState.discoverLanServers();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    try {
      await widget.appState.login(_urlCtrl.text, _userCtrl.text, _passCtrl.text);
    } catch (_) {
      // Error surfaced via appState.errorMessage
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.play_circle_filled_rounded, size: 64, color: PrismTheme.accent),
                const SizedBox(height: 12),
                const Text(
                  'Prism Player',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Rust 原生内核 • 杜比视界 & 杜比全景声 • 完美适配 embygo / Emby / Jellyfin',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: PrismTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 14),
                const Center(
                  child: BadgeStrip(
                    badges: ['embygo DirectPlay', 'Dolby Vision', 'Dolby Atmos', 'Rust Core'],
                  ),
                ),
                const SizedBox(height: 28),
                if (widget.appState.savedServers.isNotEmpty) ...[
                  const Text(
                    '已保存的服务器',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  ...widget.appState.savedServers.map((srv) => _SavedServerTile(
                        profile: srv,
                        onTap: () => widget.appState.restoreSavedServer(srv),
                      )),
                  const SizedBox(height: 18),
                ],
                if (widget.appState.discoveredServers.isNotEmpty) ...[
                  const Text(
                    '局域网自动发现 (UDP 7359)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.appState.discoveredServers.map((d) {
                      final addr = d['address']?.toString() ?? '';
                      return ActionChip(
                        avatar: const Icon(Icons.lan_rounded, size: 16),
                        label: Text('${d['name'] ?? addr}'),
                        onPressed: () => setState(() => _urlCtrl.text = addr),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _urlCtrl,
                          decoration: const InputDecoration(
                            labelText: '服务器地址',
                            hintText: 'https://embygo.example.com',
                            prefixIcon: Icon(Icons.dns_rounded),
                          ),
                          keyboardType: TextInputType.url,
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _userCtrl,
                          decoration: const InputDecoration(
                            labelText: '用户名',
                            prefixIcon: Icon(Icons.person_rounded),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _passCtrl,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: '密码',
                            prefixIcon: const Icon(Icons.lock_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                        if (widget.appState.errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            widget.appState.errorMessage!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: widget.appState.isBusy ? null : _submit,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: widget.appState.isBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.login_rounded),
                          label: const Text('连接并登录', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                      ],
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
}

class _SavedServerTile extends StatelessWidget {
  const _SavedServerTile({required this.profile, required this.onTap});
  final SavedServerProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.cloud_done_rounded, color: PrismTheme.embygoGreen),
        title: Text(profile.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${profile.username ?? ''} • ${profile.url} (${profile.dialect})'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
