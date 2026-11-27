part of '../admin_console_pane.dart';

class _UserDownloadQuotaDialog extends StatefulWidget {
  const _UserDownloadQuotaDialog({
    required this.appState,
    required this.userId,
    required this.userName,
    required this.initialPolicy,
    required this.onPolicyUpdated,
  });

  final VedroAppState appState;
  final String userId;
  final String userName;
  final Map<String, dynamic> initialPolicy;
  final VoidCallback onPolicyUpdated;

  @override
  State<_UserDownloadQuotaDialog> createState() => _UserDownloadQuotaDialogState();
}

class _UserDownloadQuotaDialogState extends State<_UserDownloadQuotaDialog> {
  static const int _bytesPerGiB = 1024 * 1024 * 1024;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _enableDownload = false;
  DownloadQuotaStatusModel? _quota;
  UserTrafficModel? _traffic;
  List<DownloadQuotaEventModel> _events = const [];

  final TextEditingController _packGiBCtrl = TextEditingController(text: '500');
  final TextEditingController _packNoteCtrl = TextEditingController();
  final TextEditingController _monthlyGiBCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _enableDownload = widget.initialPolicy['EnableContentDownloading'] == true;
    _load();
  }

  @override
  void dispose() {
    _packGiBCtrl.dispose();
    _packNoteCtrl.dispose();
    _monthlyGiBCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.appState.adminGetUserDetail(widget.userId);
      final events = await widget.appState.adminGetDownloadQuotaEvents(widget.userId, limit: 15);
      if (!mounted) return;
      final p = detail['Policy'] as Map<String, dynamic>?;
      if (p != null && p.containsKey('EnableContentDownloading')) {
        _enableDownload = p['EnableContentDownloading'] == true;
      }
      _quota = detail['DownloadQuota'] is Map<String, dynamic>
          ? DownloadQuotaStatusModel.fromJson(detail['DownloadQuota'] as Map<String, dynamic>)
          : null;
      _traffic = detail['Traffic'] is Map<String, dynamic>
          ? UserTrafficModel.fromJson(detail['Traffic'] as Map<String, dynamic>)
          : null;
      _events = events;
      if (_quota != null && _quota!.monthlyQuotaBytes > 0) {
        final gib = _quota!.monthlyQuotaBytes / _bytesPerGiB;
        _monthlyGiBCtrl.text =
            gib == gib.roundToDouble() ? '${gib.round()}' : gib.toStringAsFixed(1);
      }
    } catch (e) {
      if (mounted) _error = e.toString().replaceFirst('VedroCoreException: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleDownloadPermission(bool value) async {
    setState(() => _saving = true);
    try {
      await widget.appState.adminSetUserPolicy(
        widget.userId,
        {'EnableContentDownloading': value},
      );
      if (mounted) {
        setState(() => _enableDownload = value);
        widget.onPolicyUpdated();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '更新权限失败：$e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _adjustPackGiB(double gib) async {
    if (!gib.isFinite || gib.abs() > 1024 * 1024) {
      if (mounted) setState(() => _error = '请输入有效的 GiB 数值');
      return;
    }
    final bytes = (gib * _bytesPerGiB).round();
    if (bytes == 0) return;
    if (!mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.appState.adminAdjustDownloadPack(
        widget.userId,
        bytes,
        note: _packNoteCtrl.text.trim(),
      );
      if (!mounted) return;
      _packNoteCtrl.clear();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '调整流量包失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveMonthlyOverride(int? bytes) async {
    if (!mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.appState.adminSetMonthlyDownloadQuota(widget.userId, bytes);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '更新周期额度失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final dq = _quota;
    return Dialog(
      backgroundColor: skin.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(skin.cardRadius.clamp(16.0, 22.0)),
        side: BorderSide(color: skin.borderStrong, width: 0.9),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
              child: Row(
                children: [
                  Icon(CupertinoIcons.chart_pie_fill, size: 18, color: skin.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '下载额度 · ${widget.userName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: skin.fg, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: Icon(CupertinoIcons.xmark_circle_fill, size: 20, color: skin.fg3),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: skin.border),
            Flexible(
              child: _loading
                  ? Padding(
                      padding: const EdgeInsets.all(42),
                      child: CircularProgressIndicator(strokeWidth: 2, color: skin.fg2),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_error != null) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: VedroTheme.danger.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _error!,
                                style: const TextStyle(color: VedroTheme.danger, fontSize: 12.5),
                              ),
                            ),
                          ],

                          // Clean iOS Switch Row (Zero internal variable names!)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: skin.surface2,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '允许离线下载原文件',
                                    style: TextStyle(
                                      color: skin.fg,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Transform.scale(
                                  scale: 0.85,
                                  child: CupertinoSwitch(
                                    value: _enableDownload,
                                    activeTrackColor: skin.accent,
                                    onChanged: _saving ? null : _toggleDownloadPermission,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (dq != null) ...[
                            const SizedBox(height: 14),
                            // Visual 3-Column Summary Cards
                            Row(
                              children: [
                                Expanded(
                                  child: _MiniQuotaStat(
                                    label: '总可用',
                                    value: dq.adminExempt
                                        ? '不限'
                                        : fmtQuotaBytes(dq.totalRemainingBytes),
                                    accent: const Color(0xFF34D399),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _MiniQuotaStat(
                                    label: '周期剩余',
                                    value: fmtQuotaBytes(dq.monthlyRemainingBytes),
                                    accent: skin.accent,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _MiniQuotaStat(
                                    label: '永久流量包',
                                    value: fmtQuotaBytes(dq.packBytes),
                                    accent: const Color(0xFFA78BFA),
                                  ),
                                ),
                              ],
                            ),
                            if (_traffic != null || dq.activeDownloads > 0) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  _MetaBadge(
                                    '并发 ${dq.activeDownloads}/${dq.maxConcurrentDownloads > 0 ? dq.maxConcurrentDownloads : '∞'}',
                                  ),
                                  if (_traffic != null)
                                    _MetaBadge('累计已下载 ${fmtQuotaBytes(_traffic!.downloadBytes)}'),
                                ],
                              ),
                            ],

                            const SizedBox(height: 18),
                            Text(
                              '发放永久流量包',
                              style: TextStyle(
                                color: skin.fg2,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final preset in const [50.0, 100.0, 500.0, 1024.0])
                                  _CompactActionBtn(
                                    icon: CupertinoIcons.plus,
                                    label: preset >= 1024 ? '1 TB' : '${preset.round()} GB',
                                    primary: preset == 500.0,
                                    accent: skin.accent,
                                    loading: _saving,
                                    onTap: () => _adjustPackGiB(preset),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                SizedBox(
                                  width: 96,
                                  child: _IosDialogField(
                                    controller: _packGiBCtrl,
                                    hintText: 'GiB (±)',
                                    keyboardType: const TextInputType.numberWithOptions(
                                      signed: true,
                                      decimal: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _IosDialogField(
                                    controller: _packNoteCtrl,
                                    hintText: '备注（选填）',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _CompactActionBtn(
                                  icon: CupertinoIcons.checkmark_alt,
                                  label: '调整',
                                  primary: true,
                                  accent: skin.accent,
                                  loading: _saving,
                                  onTap: () {
                                    final v = double.tryParse(_packGiBCtrl.text.trim());
                                    if (v != null && v.isFinite && v != 0) _adjustPackGiB(v);
                                  },
                                ),
                              ],
                            ),

                            const SizedBox(height: 18),
                            Text(
                              '每 30 天免费额度 (GiB)',
                              style: TextStyle(
                                color: skin.fg2,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _IosDialogField(
                                    controller: _monthlyGiBCtrl,
                                    hintText: '留空跟随全局默认',
                                    keyboardType:
                                        const TextInputType.numberWithOptions(decimal: true),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _CompactActionBtn(
                                  icon: CupertinoIcons.checkmark_alt,
                                  label: '保存',
                                  primary: true,
                                  accent: skin.accent,
                                  loading: _saving,
                                  onTap: () {
                                    final v = double.tryParse(_monthlyGiBCtrl.text.trim());
                                    if (v != null && v.isFinite && v >= 0 && v <= 1024 * 1024) {
                                      _saveMonthlyOverride((v * _bytesPerGiB).round());
                                    }
                                  },
                                ),
                                const SizedBox(width: 6),
                                _CompactActionBtn(
                                  icon: CupertinoIcons.arrow_counterclockwise,
                                  label: '默认',
                                  loading: _saving,
                                  onTap: () => _saveMonthlyOverride(null),
                                ),
                              ],
                            ),
                          ],

                          if (_events.isNotEmpty) ...[
                            Divider(height: 28, color: skin.border),
                            Text(
                              '变更记录',
                              style: TextStyle(
                                color: skin.fg2,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ..._events.map((ev) {
                              final positive = ev.bytesDelta >= 0;
                              final sign = positive ? '+' : '-';
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${ev.kindLabel}${ev.note.isNotEmpty ? ' · ${ev.note}' : ''}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(color: skin.fg, fontSize: 12.5),
                                          ),
                                          if (ev.createdAt.isNotEmpty)
                                            Text(
                                              ev.createdAt.replaceFirst('T', ' ').split('.').first,
                                              style: TextStyle(color: skin.fg3, fontSize: 11),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '$sign${fmtQuotaBytes(ev.bytesDelta.abs())}',
                                      style: TextStyle(
                                        color: positive
                                            ? const Color(0xFF34D399)
                                            : VedroTheme.danger,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
