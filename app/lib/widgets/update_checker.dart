import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/ffi/vedro_bridge.dart';
import '../core/models/models.dart';
import '../core/platform/native_playback_channel.dart';
import '../core/theme/vedro_skin.dart';
import 'app_lock_gate.dart';
import 'vedro_ui.dart';

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
      host == 'release-assets.githubusercontent.com' ||
      host == 'github-releases.githubusercontent.com';
}

class VedroReleaseAsset {
  const VedroReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
    this.sha256,
  });

  final String name;
  final String downloadUrl;
  final int sizeBytes;
  final String? sha256;

  factory VedroReleaseAsset.fromJson(Map<String, dynamic> j) => VedroReleaseAsset(
        name: (j['name'] ?? '').toString(),
        downloadUrl: (j['browser_download_url'] ?? j['url'] ?? '').toString(),
        sizeBytes: (j['size'] as num?)?.toInt() ?? 0,
        sha256: j['sha256']?.toString().trim().isNotEmpty == true
            ? j['sha256'].toString().trim().toLowerCase()
            : null,
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
    final normVersion = normalizeSemver(tag.isNotEmpty ? tag : (j['version'] ?? '').toString());
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
      tagName: tag.isNotEmpty ? tag : 'v$normVersion',
      version: normVersion,
      title: (j['name']?.toString().trim().isNotEmpty == true)
          ? j['name'].toString().trim()
          : (tag.isNotEmpty ? tag : 'v$normVersion'),
      releaseNotes: (j['body'] ?? '').toString().trim(),
      htmlUrl: safeHtmlUrl,
      publishedAt: j['published_at']?.toString(),
      assets: rawAssets,
    );
  }

  /// Match the best installer package for the current OS & CPU ABI.
  VedroReleaseAsset? bestAssetForPlatform({String? osOverride, String? abiOverride}) {
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
        final rawAbi = (abiOverride ?? NativePlaybackChannel.detectedPrimaryAbi).trim().toLowerCase();
        if (rawAbi.isNotEmpty) {
          final exact = findMatching((n) => n.contains(rawAbi) && n.endsWith('.apk'));
          if (exact != null) return exact;
        }
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

/// Cross-platform GitHub Releases in-app auto-updater powered by Rust core proxy + SHA-256 verification.
class VedroUpdateChecker extends ChangeNotifier {
  VedroUpdateChecker({ReleaseJsonFetcher? fetcher, VedroCoreClient? core})
      : _fetcher = fetcher,
        _core = core;

  static const String repoSlug = 'JHruan1/vedro';
  static final VedroUpdateChecker instance = VedroUpdateChecker();

  final ReleaseJsonFetcher? _fetcher;
  VedroCoreClient? _core;

  bool isChecking = false;
  VedroReleaseInfo? latestRelease;
  bool hasUpdate = false;
  String? lastError;
  String? currentVersion;
  String? ignoredVersion;
  bool _startupChecked = false;
  VoidCallback? _unlockListener;

  // In-app update download state
  String downloadStatus = 'idle'; // idle | downloading | verifying | ready | error | cancelled
  int downloadedBytes = 0;
  int? totalBytes;
  int speedBps = 0;
  String? downloadedFilePath;
  String? downloadedFileName;
  String? downloadedSha256;
  bool sha256Verified = false;
  String? downloadError;
  Timer? _pollTimer;

  bool get canInAppDownload {
    if (_core == null || kIsWeb) return false;
    // Desktop keeps full in-app download + SHA-256 verification + native installer;
    // Android & iOS open official GitHub release download links (avoids Android REQUEST_INSTALL_PACKAGES warnings).
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  bool get isDownloading => downloadStatus == 'downloading' || downloadStatus == 'verifying';

  double? get downloadProgress {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (downloadedBytes / total).clamp(0.0, 1.0);
  }

  void attachCore(VedroCoreClient core) {
    _core = core;
  }

  Future<Map<String, dynamic>> _defaultFetch(String curVer) async {
    final core = _core;
    Object? coreErr;
    if (core != null) {
      try {
        final raw = await core.invoke('check_app_update');
        if (raw is Map<String, dynamic>) {
          return raw;
        }
      } catch (e) {
        coreErr = e;
        // Fall through to direct HttpClient if core mock/environment doesn't implement `check_app_update`
      }
    }
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);
    final ua = 'Vedro/${normalizeSemver(curVer)}';

    Future<(int, Uri, String)> fetchText(Uri uri, {String? accept}) async {
      final req = await client.getUrl(uri);
      if (accept != null) req.headers.set('Accept', accept);
      req.headers.set('User-Agent', ua);
      final resp = await req.close().timeout(const Duration(seconds: 12));
      final chunks = <int>[];
      await for (final chunk in resp.timeout(const Duration(seconds: 12))) {
        chunks.addAll(chunk);
        if (chunks.length > 2 * 1024 * 1024) {
          throw Exception('更新元数据超出大小限制');
        }
      }
      final finalUri = resp.redirects.isNotEmpty ? resp.redirects.last.location : uri;
      return (resp.statusCode, finalUri, utf8.decode(chunks, allowMalformed: true));
    }

    try {
      final apiUri = Uri.parse('https://api.github.com/repos/$repoSlug/releases/latest');
      final (apiCode, _, apiBody) = await fetchText(
        apiUri,
        accept: 'application/vnd.github+json',
      );
      if (apiCode == 200) {
        final parsed = jsonDecode(apiBody);
        if (parsed is Map<String, dynamic>) {
          return parsed;
        }
      }

      // Rate-limit-free fallback when api.github.com returns HTTP 403/429 on shared VPN/proxy IPs
      final webUri = Uri.parse('https://github.com/$repoSlug/releases/latest');
      final (webCode, finalUri, webBody) = await fetchText(webUri, accept: 'application/json');
      if (webCode != 200) {
        if (coreErr != null) throw coreErr;
        throw Exception('HTTP $apiCode');
      }
      String tag = '';
      try {
        final parsed = jsonDecode(webBody);
        if (parsed is Map<String, dynamic>) {
          tag = (parsed['tag_name'] ?? '').toString().trim();
        }
      } catch (_) {}
      if (tag.isEmpty) {
        final m = RegExp(r'/releases/tag/([^/?#]+)').firstMatch(finalUri.toString());
        if (m != null) tag = (m.group(1) ?? '').trim();
      }
      if (tag.isEmpty || !RegExp(r'^[A-Za-z0-9._+\-]{1,64}$').hasMatch(tag)) {
        throw Exception('无法解析最新版本号 (HTTP $apiCode)');
      }

      final assets = <Map<String, dynamic>>[];
      try {
        final sumsUri = Uri.parse('https://github.com/$repoSlug/releases/download/$tag/SHA256SUMS.txt');
        final (sCode, _, sBody) = await fetchText(sumsUri);
        if (sCode == 200) {
          for (final line in const LineSplitter().convert(sBody)) {
            final t = line.trim();
            if (t.isEmpty || t.startsWith('#')) continue;
            final parts = t.split(RegExp(r'\s+'));
            if (parts.length < 2) continue;
            final hash = parts[0].toLowerCase();
            final name = parts[1].replaceFirst(RegExp(r'^\*'), '').split('/').last;
            if (hash.length == 64 && RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) && name.isNotEmpty) {
              assets.add({
                'name': name,
                'url': 'https://github.com/$repoSlug/releases/download/$tag/$name',
                'size': 0,
                'sha256': hash,
              });
            }
          }
        }
      } catch (_) {}

      return {
        'tag_name': tag,
        'version': normalizeSemver(tag),
        'html_url': 'https://github.com/$repoSlug/releases/tag/$tag',
        'body': '已通过 GitHub 官方发布通道校验最新版本，支持应用内高速下载与 SHA-256 完整性校验。',
        'assets': assets,
      };
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
      lastError = e
          .toString()
          .replaceFirst('VedroCoreException: ', '')
          .replaceFirst('Exception: ', '');
      return null;
    } finally {
      isChecking = false;
      notifyListeners();
    }
  }

  void _applyDownloadState(Map<String, dynamic> st) {
    downloadStatus = (st['status'] ?? 'idle').toString();
    downloadedBytes = (st['downloaded_bytes'] as num?)?.toInt() ?? 0;
    totalBytes = (st['total_bytes'] as num?)?.toInt();
    speedBps = (st['speed_bps'] as num?)?.toInt() ?? 0;
    downloadedFilePath = st['file_path']?.toString();
    downloadedFileName = st['file_name']?.toString();
    downloadedSha256 = st['sha256']?.toString();
    sha256Verified = st['sha256_verified'] == true;
    downloadError = st['error']?.toString();
    notifyListeners();
  }

  Future<void> startInAppDownload(VedroReleaseInfo release, VedroReleaseAsset asset) async {
    final core = _core;
    if (core == null) {
      await NativePlaybackChannel.openUrl(asset.downloadUrl);
      return;
    }
    _pollTimer?.cancel();
    downloadStatus = 'downloading';
    downloadedBytes = 0;
    totalBytes = asset.sizeBytes > 0 ? asset.sizeBytes : null;
    speedBps = 0;
    downloadedFilePath = null;
    downloadedFileName = asset.name;
    downloadedSha256 = null;
    sha256Verified = false;
    downloadError = null;
    notifyListeners();

    try {
      final res = await core.invoke('start_update_download', {
        'url': asset.downloadUrl,
        'file_name': asset.name,
        'version': release.version,
        if (asset.sha256 != null && asset.sha256!.isNotEmpty) 'expected_sha256': asset.sha256,
      });
      if (res is Map<String, dynamic>) {
        _applyDownloadState(res);
      }
      if (downloadStatus == 'ready' || downloadStatus == 'error' || downloadStatus == 'cancelled') {
        return;
      }
      _pollTimer = Timer.periodic(const Duration(milliseconds: 350), (t) async {
        try {
          final cur = await core.invoke('get_update_download_status');
          if (cur is Map<String, dynamic>) {
            _applyDownloadState(cur);
            if (!isDownloading) {
              t.cancel();
            }
          }
        } catch (e) {
          t.cancel();
          downloadStatus = 'error';
          downloadError = e.toString().replaceFirst('VedroCoreException: ', '');
          notifyListeners();
        }
      });
    } catch (e) {
      downloadStatus = 'error';
      downloadError = e.toString().replaceFirst('VedroCoreException: ', '');
      notifyListeners();
    }
  }

  Future<void> cancelInAppDownload() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    final core = _core;
    if (core != null) {
      try {
        final res = await core.invoke('cancel_update_download');
        if (res is Map<String, dynamic>) {
          _applyDownloadState(res);
          return;
        }
      } catch (_) {}
    }
    downloadStatus = 'cancelled';
    speedBps = 0;
    notifyListeners();
  }

  Future<({bool ok, String? message})> installDownloadedUpdate() async {
    final path = downloadedFilePath;
    if (path == null || path.isEmpty) {
      return (ok: false, message: '尚未下载安装包');
    }
    return NativePlaybackChannel.installUpdatePackage(path, silent: true);
  }

  /// Run at most once per app session quietly after startup.
  Future<void> checkOnceOnStartup(
    BuildContext context, {
    required String currentVersion,
  }) async {
    if (_startupChecked) return;
    if (AppLockGate.isLockedNotifier.value) {
      if (_unlockListener != null) {
        AppLockGate.isLockedNotifier.removeListener(_unlockListener!);
      }
      void onUnlock() {
        if (!AppLockGate.isLockedNotifier.value) {
          AppLockGate.isLockedNotifier.removeListener(onUnlock);
          if (identical(_unlockListener, onUnlock)) _unlockListener = null;
          if (context.mounted) {
            checkOnceOnStartup(context, currentVersion: currentVersion);
          }
        }
      }
      _unlockListener = onUnlock;
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

String _fmtSpeed(int bps) {
  if (bps <= 0) return '';
  if (bps >= 1024 * 1024) {
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
  return '${(bps / 1024).toStringAsFixed(0)} KB/s';
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
  final checker = VedroUpdateChecker.instance;

  String installButtonLabel() {
    if (!kIsWeb && Platform.isWindows) return '立即安装并重启';
    if (!kIsWeb && Platform.isAndroid) return '立即安装 APK';
    if (!kIsWeb && Platform.isMacOS) return '打开安装包 (DMG)';
    return '打开安装包';
  }

  Future<void> openOrCopyLink(String url) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final opened = await NativePlaybackChannel.openUrl(url);
    if (!opened) {
      await Clipboard.setData(ClipboardData(text: url));
      messenger?.showSnackBar(
        SnackBar(content: Text('未检测到系统浏览器，已复制 GitHub 下载链接：$url')),
      );
    }
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => VedroControllerScope<ScrollController>(
      create: () => ScrollController(),
      dispose: (c) => c.dispose(),
      builder: (ctx, notesScrollCtrl) => ListenableBuilder(
        listenable: checker,
        builder: (ctx, _) {
          final supportsInApp = checker.canInAppDownload && matchedAsset != null;
          final downloading = checker.isDownloading;
          final ready = checker.downloadStatus == 'ready' &&
              checker.downloadedFileName == matchedAsset?.name &&
              (checker.downloadedFilePath?.isNotEmpty == true);
          final dlErr = checker.downloadStatus == 'error' ? checker.downloadError : null;
          final prog = checker.downloadProgress;

          return AlertDialog(
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
              constraints: const BoxConstraints(maxWidth: 460, maxHeight: 340),
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
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                          decoration: BoxDecoration(
                            color: skin.surface2,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: skin.border, width: 0.7),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    ready
                                        ? Icons.verified_rounded
                                        : Icons.download_for_offline_outlined,
                                    size: 16,
                                    color: ready ? const Color(0xFF34D399) : accent,
                                  ),
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
                                    Text(sizeLabel,
                                        style: TextStyle(color: skin.fg3, fontSize: 11.5)),
                                  ],
                                ],
                              ),
                              if (downloading) ...[
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: prog,
                                    minHeight: 5,
                                    color: accent,
                                    backgroundColor: skin.border,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        checker.downloadStatus == 'verifying'
                                            ? '正在校验 SHA-256 签名完整性…'
                                            : '${fmtFileSize(checker.downloadedBytes)}${checker.totalBytes != null ? ' / ${fmtFileSize(checker.totalBytes!)}' : ''}',
                                        style: TextStyle(color: skin.fg3, fontSize: 11),
                                      ),
                                    ),
                                    if (checker.speedBps > 0)
                                      Text(
                                        _fmtSpeed(checker.speedBps),
                                        style: TextStyle(color: accent, fontSize: 11),
                                      ),
                                  ],
                                ),
                              ] else if (ready) ...[
                                const SizedBox(height: 6),
                                Text(
                                  checker.sha256Verified
                                      ? '下载完成 · SHA-256 完整性校验已通过'
                                      : '安装包已下载就绪，可立即安装',
                                  style: const TextStyle(
                                    color: Color(0xFF34D399),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ] else if (dlErr != null && dlErr.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  dlErr,
                                  style: const TextStyle(
                                    color: Color(0xFFFCA5A5),
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      Text(
                        release.releaseNotes.isNotEmpty
                            ? release.releaseNotes
                            : '包含多项功能更新与体验优化。',
                        style: TextStyle(color: skin.fg2, fontSize: 13, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              if (onIgnoreVersion != null && !downloading)
                TextButton(
                  onPressed: () {
                    onIgnoreVersion();
                    Navigator.pop(ctx);
                  },
                  child: Text('忽略此版本', style: TextStyle(color: skin.fg3, fontSize: 12.5)),
                ),
              if (downloading)
                TextButton(
                  onPressed: () => checker.cancelInAppDownload(),
                  child: const Text('取消下载'),
                )
              else
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('稍后再说'),
                ),
              if (matchedAsset != null && !downloading)
                OutlinedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await openOrCopyLink(release.htmlUrl);
                  },
                  child: Text(supportsInApp ? '浏览器下载' : 'GitHub 发布页'),
                ),
              if (ready)
                FilledButton.icon(
                  key: const ValueKey('vedro-update-install-btn'),
                  autofocus: true,
                  onPressed: () async {
                    final res = await checker.installDownloadedUpdate();
                    if (!res.ok && ctx.mounted) {
                      ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
                        SnackBar(content: Text(res.message ?? '调起系统安装器失败，请尝试浏览器下载')),
                      );
                    }
                  },
                  icon: const Icon(Icons.install_desktop_rounded, size: 16),
                  label: Text(installButtonLabel()),
                )
              else
                FilledButton.icon(
                  key: const ValueKey('vedro-update-download-btn'),
                  autofocus: true,
                  onPressed: downloading
                      ? null
                      : () async {
                          if (supportsInApp) {
                            await checker.startInAppDownload(release, matchedAsset);
                          } else {
                            Navigator.pop(ctx);
                            await openOrCopyLink(downloadTarget);
                          }
                        },
                  icon: Icon(
                    downloading ? Icons.downloading_rounded : Icons.download_rounded,
                    size: 16,
                  ),
                  label: Text(
                    downloading
                        ? '下载中…'
                        : (supportsInApp
                            ? '立即下载更新'
                            : (matchedAsset != null ? 'GitHub 下载安装包' : '前往 GitHub 更新')),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
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
