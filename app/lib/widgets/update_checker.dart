import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/models.dart';
import '../core/platform/native_playback_channel.dart';
import '../core/theme/vedro_skin.dart';
import 'app_lock_gate.dart';

bool isTrustedReleaseUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed.contains(RegExp(r'[\s\x00-\x1F\x7F]'))) {
    return false;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.scheme.toLowerCase() != 'https') return false;
  if (uri.userInfo.isNotEmpty) return false;
  if (uri.hasPort && uri.port != 443) return false;
  final host = uri.host.toLowerCase();
  if (host == 'github.com') {
    return uri.path.startsWith('/${VedroUpdateChecker.repoSlug}/releases');
  }
  return host == 'objects.githubusercontent.com' ||
      host == 'release-assets.githubusercontent.com';
}

class VedroReleaseAsset {
  const VedroReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
  });

  final String name;
  final String downloadUrl;
  final int sizeBytes;

  factory VedroReleaseAsset.fromJson(Map<String, dynamic> j) => VedroReleaseAsset(
        name: (j['name'] ?? '').toString(),
        downloadUrl: (j['browser_download_url'] ?? '').toString(),
        sizeBytes: (j['size'] as num?)?.toInt() ?? 0,
      );
}

class VedroReleaseInfo {
  const VedroReleaseInfo({
    required this.tagName,
    required this.version,
    required this.title,
    required this.releaseNotes,
    required this.htmlUrl,
    this.publishedAt,
    this.assets = const [],
  });

  final String tagName;
  final String version;
  final String title;
  final String releaseNotes;
  final String htmlUrl;
  final String? publishedAt;
  final List<VedroReleaseAsset> assets;

  factory VedroReleaseInfo.fromGitHubJson(Map<String, dynamic> j) {
    final tag = (j['tag_name'] ?? '').toString().trim();
    final normVersion = normalizeSemver(tag);
    final rawAssets = ((j['assets'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(VedroReleaseAsset.fromJson)
        .where((a) => a.name.isNotEmpty && isTrustedReleaseUrl(a.downloadUrl))
        .toList();
    final rawHtmlUrl = (j['html_url'] ?? '').toString().trim();
    final safeHtmlUrl = isTrustedReleaseUrl(rawHtmlUrl)
        ? rawHtmlUrl
        : 'https://github.com/JHruan1/vedro/releases';
    return VedroReleaseInfo(
      tagName: tag,
      version: normVersion,
      title: (j['name']?.toString().trim().isNotEmpty == true)
          ? j['name'].toString().trim()
          : tag,
      releaseNotes: (j['body'] ?? '').toString().trim(),
      htmlUrl: safeHtmlUrl,
      publishedAt: j['published_at']?.toString(),
      assets: rawAssets,
    );
  }

  /// Match the best installer package for the current OS.
  VedroReleaseAsset? bestAssetForPlatform({String? osOverride}) {
    final os = (osOverride ?? (kIsWeb ? 'web' : Platform.operatingSystem)).toLowerCase();
    VedroReleaseAsset? findMatching(bool Function(String lower) test) {
      for (final a in assets) {
        if (test(a.name.toLowerCase())) return a;
      }
      return null;
    }

    switch (os) {
      case 'windows':
        return findMatching((n) => n.endsWith('-setup.exe')) ??
            findMatching((n) => n.endsWith('.exe')) ??
            findMatching((n) => n.contains('windows') && n.endsWith('.zip'));
      case 'macos':
        return findMatching((n) => n.endsWith('.dmg')) ??
            findMatching((n) => n.contains('macos'));
      case 'android':
        return findMatching((n) => n.contains('arm64-v8a') && n.endsWith('.apk')) ??
            findMatching((n) => n.contains('universal') && n.endsWith('.apk')) ??
            findMatching((n) => n.endsWith('.apk'));
      case 'ios':
        return findMatching((n) => n.endsWith('.ipa'));
      case 'linux':
        return findMatching((n) => n.endsWith('.appimage')) ??
            findMatching((n) => n.endsWith('.deb')) ??
            findMatching((n) => n.contains('linux') && n.endsWith('.tar.gz'));
      default:
        return null;
    }
  }
}

/// Normalize `"v0.3.11+26"` -> `"0.3.11"`.
String normalizeSemver(String raw) {
  var s = raw.trim();
  if (s.startsWith('v') || s.startsWith('V')) {
    s = s.substring(1);
  }
  final plus = s.indexOf('+');
  if (plus >= 0) s = s.substring(0, plus);
  return s.trim();
}

/// Compare two semantic version strings (`>0` if `a > b`, `0` if equal, `<0` if `a < b`).
/// Implements full SemVer 2.0 prerelease identifier comparison (numeric < alphanumeric, shorter < longer).
int compareSemver(String a, String b) {
  (List<int>, List<String>) parse(String v) {
    final norm = normalizeSemver(v);
    final dash = norm.indexOf('-');
    final coreStr = dash >= 0 ? norm.substring(0, dash) : norm;
    final preStr = dash >= 0 ? norm.substring(dash + 1) : '';
    final parts = coreStr.split('.');
    final core = [
      parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 0) : 0,
      parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
      parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0,
    ];
    final pre = preStr.isEmpty
        ? const <String>[]
        : preStr.split('.').where((s) => s.isNotEmpty).toList();
    return (core, pre);
  }

  final (pa, preA) = parse(a);
  final (pb, preB) = parse(b);
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
  }
  if (preA.isEmpty && preB.isEmpty) return 0;
  if (preA.isNotEmpty && preB.isEmpty) return -1;
  if (preA.isEmpty && preB.isNotEmpty) return 1;
  final minLen = preA.length < preB.length ? preA.length : preB.length;
  for (var i = 0; i < minLen; i++) {
    final ia = preA[i];
    final ib = preB[i];
    if (ia == ib) continue;
    final na = int.tryParse(ia);
    final nb = int.tryParse(ib);
    if (na != null && nb != null) return na.compareTo(nb);
    if (na != null) return -1;
    if (nb != null) return 1;
    return ia.compareTo(ib);
  }
  return preA.length.compareTo(preB.length);
}

typedef ReleaseJsonFetcher = Future<Map<String, dynamic>> Function(String currentVersion);

/// Cross-platform GitHub Releases in-app update checker.
class VedroUpdateChecker extends ChangeNotifier {
  VedroUpdateChecker({ReleaseJsonFetcher? fetcher}) : _fetcher = fetcher;

  static const String repoSlug = 'JHruan1/vedro';
  static final VedroUpdateChecker instance = VedroUpdateChecker();

  final ReleaseJsonFetcher? _fetcher;

  bool isChecking = false;
  VedroReleaseInfo? latestRelease;
  bool hasUpdate = false;
  String? lastError;
  String? currentVersion;
  String? ignoredVersion;
  bool _startupChecked = false;

  Future<Map<String, dynamic>> _defaultFetch(String curVer) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);
    try {
      final uri = Uri.parse('https://api.github.com/repos/$repoSlug/releases/latest');
      final req = await client.getUrl(uri);
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'Vedro/${normalizeSemver(curVer)}');
      final resp = await req.close().timeout(const Duration(seconds: 12));
      final chunks = <int>[];
      await for (final chunk in resp.timeout(const Duration(seconds: 12))) {
        chunks.addAll(chunk);
        if (chunks.length > 2 * 1024 * 1024) {
          throw Exception('更新元数据超出大小限制');
        }
      }
      final body = utf8.decode(chunks, allowMalformed: true);
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final parsed = jsonDecode(body);
      if (parsed is! Map<String, dynamic>) {
        throw Exception('返回格式异常');
      }
      return parsed;
    } finally {
      client.close(force: true);
    }
  }

  Future<VedroReleaseInfo?> checkForUpdate({
    required String currentVersion,
    bool force = false,
  }) async {
    if (isChecking) return latestRelease;
    final norm = normalizeSemver(currentVersion);
    if (!force && latestRelease != null && this.currentVersion == norm) {
      return latestRelease;
    }
    this.currentVersion = norm;
    isChecking = true;
    lastError = null;
    notifyListeners();
    try {
      final json = await (_fetcher ?? _defaultFetch)(this.currentVersion!);
      final info = VedroReleaseInfo.fromGitHubJson(json);
      latestRelease = info;
      hasUpdate = info.version.isNotEmpty && compareSemver(info.version, this.currentVersion!) > 0;
      return info;
    } catch (e) {
      lastError = e.toString().replaceFirst('Exception: ', '');
      return null;
    } finally {
      isChecking = false;
      notifyListeners();
    }
  }

  /// Run at most once per app session quietly after startup.
  Future<void> checkOnceOnStartup(
    BuildContext context, {
    required String currentVersion,
  }) async {
    if (_startupChecked) return;
    if (AppLockGate.isLockedNotifier.value) {
      // Wait until the user unlocks the app before prompting so dialog never collides with AppLockGate.
      void onUnlock() {
        if (!AppLockGate.isLockedNotifier.value) {
          AppLockGate.isLockedNotifier.removeListener(onUnlock);
          if (context.mounted) {
            checkOnceOnStartup(context, currentVersion: currentVersion);
          }
        }
      }
      AppLockGate.isLockedNotifier.addListener(onUnlock);
      return;
    }
    _startupChecked = true;
    await checkAndPrompt(
      context,
      currentVersion: currentVersion,
      silentIfUpToDate: true,
    );
  }

  Future<void> checkAndPrompt(
    BuildContext context, {
    required String currentVersion,
    bool silentIfUpToDate = false,
  }) async {
    final normCur = normalizeSemver(currentVersion);
    final info = await checkForUpdate(currentVersion: normCur, force: !silentIfUpToDate);
    if (!context.mounted) return;
    if (silentIfUpToDate && AppLockGate.isLockedNotifier.value) return;

    if (hasUpdate && info != null) {
      if (silentIfUpToDate && ignoredVersion == info.version) {
        return;
      }
      await showVedroUpdateDialog(
        context,
        currentVersion: normCur,
        release: info,
        onIgnoreVersion: () {
          ignoredVersion = info.version;
          notifyListeners();
        },
      );
      return;
    }

    if (silentIfUpToDate) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    if (lastError != null && lastError!.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text('检查更新失败：$lastError')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text('当前已是最新版本 (v$normCur)')),
      );
    }
  }
}

Future<void> showVedroUpdateDialog(
  BuildContext context, {
  required String currentVersion,
  required VedroReleaseInfo release,
  VoidCallback? onIgnoreVersion,
}) async {
  final skin = VedroSkin.of(context);
  final accent = Theme.of(context).colorScheme.secondary;
  final matchedAsset = release.bestAssetForPlatform();
  final downloadTarget = matchedAsset?.downloadUrl ?? release.htmlUrl;
  final sizeLabel = matchedAsset != null && matchedAsset.sizeBytes > 0
      ? fmtFileSize(matchedAsset.sizeBytes)
      : '';

  final notesScrollCtrl = ScrollController();
  try {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('vedro-update-dialog'),
        backgroundColor: skin.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: skin.border, width: 0.8),
        ),
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.system_update_alt_rounded, size: 19, color: accent),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '发现新版本 ${release.tagName}',
                    style: TextStyle(color: skin.fg, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '当前 v$currentVersion → 最新 v${release.version}',
                    style: TextStyle(color: skin.fg3, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 320),
          child: Focus(
            onKeyEvent: (_, ev) {
              if ((ev is KeyDownEvent || ev is KeyRepeatEvent) && notesScrollCtrl.hasClients) {
                if (ev.logicalKey == LogicalKeyboardKey.arrowDown) {
                  notesScrollCtrl.animateTo(
                    (notesScrollCtrl.offset + 64)
                        .clamp(0.0, notesScrollCtrl.position.maxScrollExtent),
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                  );
                  return KeyEventResult.handled;
                }
                if (ev.logicalKey == LogicalKeyboardKey.arrowUp) {
                  notesScrollCtrl.animateTo(
                    (notesScrollCtrl.offset - 64)
                        .clamp(0.0, notesScrollCtrl.position.maxScrollExtent),
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                  );
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: SingleChildScrollView(
              controller: notesScrollCtrl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (matchedAsset != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                      decoration: BoxDecoration(
                        color: skin.surface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: skin.border, width: 0.7),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.download_for_offline_outlined, size: 16, color: accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              matchedAsset.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: skin.fg,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (sizeLabel.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(sizeLabel, style: TextStyle(color: skin.fg3, fontSize: 11.5)),
                          ],
                        ],
                      ),
                    ),
                  Text(
                    release.releaseNotes.isNotEmpty ? release.releaseNotes : '包含多项功能更新与体验优化。',
                    style: TextStyle(color: skin.fg2, fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          if (onIgnoreVersion != null)
            TextButton(
              onPressed: () {
                onIgnoreVersion();
                Navigator.pop(ctx);
              },
              child: Text('忽略此版本', style: TextStyle(color: skin.fg3, fontSize: 12.5)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后再说'),
          ),
          if (matchedAsset != null)
            OutlinedButton(
              onPressed: () {
                Navigator.pop(ctx);
                NativePlaybackChannel.openUrl(release.htmlUrl);
              },
              child: const Text('全部版本'),
            ),
          FilledButton.icon(
            key: const ValueKey('vedro-update-download-btn'),
            autofocus: true,
            onPressed: () {
              Navigator.pop(ctx);
              NativePlaybackChannel.openUrl(downloadTarget);
            },
            icon: const Icon(Icons.download_rounded, size: 16),
            label: Text(matchedAsset != null ? '立即下载' : '前往更新'),
          ),
        ],
      ),
    );
  } finally {
    notesScrollCtrl.dispose();
  }
}

/// Compact clickable update chip for Settings sidebar/footer.
class UpdateCheckBadgeTile extends StatelessWidget {
  const UpdateCheckBadgeTile({
    super.key,
    required this.currentVersion,
    this.compact = false,
  });

  final String currentVersion;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    final accent = Theme.of(context).colorScheme.secondary;
    return ListenableBuilder(
      listenable: VedroUpdateChecker.instance,
      builder: (context, _) {
        final checker = VedroUpdateChecker.instance;
        final hasNew = checker.hasUpdate && checker.latestRelease != null;
        final checking = checker.isChecking;
        final label = checking
            ? '正在检查更新…'
            : (hasNew
                ? '发现新版本 ${checker.latestRelease!.tagName}'
                : '检查更新 · v${normalizeSemver(currentVersion)}');

        if (compact) {
          return InkWell(
            key: const ValueKey('settings-check-update-btn'),
            borderRadius: BorderRadius.circular(10),
            onTap: checking
                ? null
                : () => checker.checkAndPrompt(context, currentVersion: currentVersion),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: hasNew ? accent.withValues(alpha: 0.14) : skin.unifiedTileColor(),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: hasNew ? accent.withValues(alpha: 0.5) : skin.border,
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  if (checking)
                    SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 1.8, color: accent),
                    )
                  else
                    Icon(
                      hasNew ? Icons.system_update_alt_rounded : Icons.refresh_rounded,
                      size: 14,
                      color: hasNew ? accent : skin.fg3,
                    ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasNew ? accent : skin.fg2,
                        fontSize: 11.5,
                        fontWeight: hasNew ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (hasNew)
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF34D399),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          );
        }

        return InkWell(
          key: const ValueKey('settings-check-update-mobile-btn'),
          onTap: checking
              ? null
              : () => checker.checkAndPrompt(context, currentVersion: currentVersion),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.system_update_alt_rounded,
                  size: 20,
                  color: hasNew ? accent : skin.fg2,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '检查更新',
                    style: TextStyle(color: skin.fg, fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ),
                if (checking)
                  SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 1.8, color: accent),
                  )
                else ...[
                  if (hasNew)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        checker.latestRelease!.tagName,
                        style: TextStyle(
                          color: accent,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Text(
                    'v${normalizeSemver(currentVersion)}',
                    style: TextStyle(color: skin.fg3, fontSize: 13),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, size: 18, color: skin.fg3),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
