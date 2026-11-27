part of 'app_state.dart';

/// Resumable offline downloads, queue orchestration & EmbyGo quota tracking.
extension VedroAppStateDownloads on VedroAppState {
  Future<void> _persistDownloads() async {
    try {
      await core.invoke('set_kv', {
        'key': 'downloads_queue',
        'value': downloads.map((d) => d.toJson()).toList(),
      });
    } catch (_) {}
  }

  String get downloadsDirectoryPath {
    if (prefs.downloadCustomDir.trim().isNotEmpty) {
      return prefs.downloadCustomDir.trim();
    }
    return '${_supportDirPath ?? Directory.systemTemp.path}/vedro_downloads';
  }

  String get fontsDirectoryPath =>
      '${_supportDirPath ?? Directory.systemTemp.path}/vedro_fonts';

  /// Account-level download eligibility.
  /// On EmbyGo, honors `meQuota.limits.allowDownloads` (which accounts for admin, server download-quota,
  /// and `EnableContentDownloading`). On standard Emby/Jellyfin, honors `User.Policy.EnableContentDownloading`.
  bool get canDownloadAccount {
    if (!isSignedIn) return false;
    if (meQuota != null) return meQuota!.limits.allowDownloads;
    return enableContentDownloading || (capabilities?.isEmbyGo == true && isAdmin);
  }

  /// Strict item-level download permission check.
  /// Always hides download controls when the user lacks permission on Emby, Jellyfin, or EmbyGo.
  bool canDownloadItem(MediaItemModel? item) {
    if (!isSignedIn || item == null) return false;
    if (item.canDownload != null) return item.canDownload!;
    if (!item.isPlayable) return false;
    return canDownloadAccount;
  }

  Future<void> refreshMeQuota() async {
    if (!isSignedIn) {
      meQuota = null;
      isLoadingQuota = false;
      notifyListeners();
      return;
    }
    final epoch = _sessionEpoch;
    isLoadingQuota = true;
    notifyListeners();
    try {
      final res = await core.invoke('get_me_quota');
      if (epoch != _sessionEpoch || _disposed) return;
      if (res is Map<String, dynamic> && res.containsKey('limits')) {
        meQuota = MeQuotaModel.fromJson(res);
      } else {
        meQuota = null;
      }
    } catch (_) {
      // Standard Emby / Jellyfin servers do not expose `/emby-compat/me/quota`.
    } finally {
      if (epoch == _sessionEpoch) {
        isLoadingQuota = false;
        notifyListeners();
      }
    }
  }

  int get effectiveDownloadConcurrency {
    final localMax = prefs.downloadMaxConcurrent.clamp(1, 5);
    final dq = meQuota?.downloadQuota;
    if (dq != null && dq.enabled && !dq.adminExempt && dq.maxConcurrentDownloads > 0) {
      return localMax < dq.maxConcurrentDownloads ? localMax : dq.maxConcurrentDownloads;
    }
    return localMax;
  }

  Future<void> enqueueDownload(
    MediaItemModel item, {
    String? mediaSourceId,
    String? versionLabel,
    int? expectedBytes,
  }) async {
    await enqueueBatchDownloads([
      (
        item: item,
        mediaSourceId: mediaSourceId,
        versionLabel: versionLabel,
        expectedBytes: expectedBytes,
      ),
    ]);
  }

  /// Enqueue one or more episodes/versions cleanly into the resumable, concurrency-bounded download queue.
  Future<int> enqueueBatchDownloads(
    List<({MediaItemModel item, String? mediaSourceId, String? versionLabel, int? expectedBytes})>
        requests,
  ) async {
    if (requests.isEmpty) return 0;
    for (final req in requests) {
      if (!canDownloadItem(req.item)) {
        throw Exception('当前账号未开放下载权限，请联系管理员');
      }
    }

    final dq = meQuota?.downloadQuota;
    if (dq != null && dq.enabled && !dq.adminExempt) {
      final totalNeeded = requests.fold<int>(0, (sum, r) => sum + (r.expectedBytes ?? 0));
      if (totalNeeded > 0 && !dq.canFitBytes(totalNeeded)) {
        throw Exception(
          '下载流量包余额不足：当前剩余 ${fmtQuotaBytes(dq.totalRemainingBytes)}，所选文件共需 ${fmtQuotaBytes(totalNeeded)}（仅限原文件下载，在线播放不限流量）',
        );
      }
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    var added = 0;
    for (var i = 0; i < requests.length; i++) {
      final req = requests[i];
      final dupIdx = downloads.indexWhere((d) =>
          d.itemId == req.item.id &&
          (req.mediaSourceId == null ||
              d.mediaSourceId == null ||
              d.mediaSourceId == req.mediaSourceId) &&
          (d.status == 'downloading' || d.status == 'queued' || d.status == 'completed'));
      if (dupIdx >= 0) continue;

      final taskId = '${req.item.id}_${nowMs}_$i';
      downloads.insert(
        added,
        DownloadTaskModel(
          id: taskId,
          itemId: req.item.id,
          title: req.item.cardTitle,
          subtitle: req.item.cardSubtitle,
          mediaSourceId: req.mediaSourceId,
          versionLabel: req.versionLabel ?? '',
          totalBytes: req.expectedBytes ?? 0,
          status: 'queued',
          createdAt: nowMs + i,
        ),
      );
      added++;
    }
    if (added == 0) return 0;
    notifyListeners();
    await _persistDownloads();
    _pumpDownloadQueue();
    return added;
  }

  void pauseDownload(String taskId) {
    final handle = _activeDownloadHandles[taskId];
    if (handle != null) {
      handle.paused = true;
      handle.abort();
    }
    _replaceDownload(
      taskId,
      (d) => d.copyWith(status: 'paused', speedBytesPerSec: 0, clearError: true),
    );
    unawaited(_persistDownloads());
    _pumpDownloadQueue();
  }

  void resumeDownload(String taskId) {
    final idx = downloads.indexWhere((d) => d.id == taskId);
    if (idx < 0) return;
    final task = downloads[idx];
    if (task.status == 'downloading' || task.status == 'completed') return;
    downloads[idx] = task.copyWith(
      status: 'queued',
      speedBytesPerSec: 0,
      retryCount: 0,
      clearError: true,
    );
    notifyListeners();
    unawaited(_persistDownloads());
    _pumpDownloadQueue();
  }

  void pauseAllDownloads() {
    for (final d in List<DownloadTaskModel>.from(downloads)) {
      if (d.status == 'downloading' || d.status == 'queued') {
        pauseDownload(d.id);
      }
    }
  }

  void resumeAllDownloads() {
    var changed = false;
    for (var i = 0; i < downloads.length; i++) {
      final d = downloads[i];
      if (d.status == 'paused' || d.status == 'failed') {
        downloads[i] = d.copyWith(
          status: 'queued',
          speedBytesPerSec: 0,
          retryCount: 0,
          clearError: true,
        );
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      unawaited(_persistDownloads());
      _pumpDownloadQueue();
    }
  }

  void _pumpDownloadQueue() {
    final maxConcurrent = effectiveDownloadConcurrency;
    while (_activeDownloadHandles.length < maxConcurrent) {
      // Pick oldest queued task (so multi-episode downloads progress E01 -> E02 -> E03 in order)
      DownloadTaskModel? nextTask;
      for (final d in downloads.reversed) {
        if (d.status == 'queued' && !_activeDownloadHandles.containsKey(d.id)) {
          nextTask = d;
          break;
        }
      }
      if (nextTask == null) break;
      final handle = _ActiveDownloadHandle();
      _activeDownloadHandles[nextTask.id] = handle;
      unawaited(_runResumableDownload(nextTask.id, handle));
    }
  }

  Future<void> _runResumableDownload(String taskId, _ActiveDownloadHandle handle) async {
    const maxAttempts = 8;
    Timer? inFlightRefreshTimer;

    try {
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        if (handle.paused || handle.cancelled) return;
        final currentIdx = downloads.indexWhere((d) => d.id == taskId);
        if (currentIdx < 0) return;
        final task = downloads[currentIdx];

        if (prefs.downloadWifiOnly) {
          final wifi = await NativePlaybackChannel.isWifiConnected();
          if (!wifi) {
            _replaceDownload(
              taskId,
              (d) => d.copyWith(
                status: 'paused',
                speedBytesPerSec: 0,
                error: '等待 Wi-Fi 连接（可在设置中关闭仅 Wi-Fi 下载）',
              ),
            );
            await _persistDownloads();
            return;
          }
        }

        _replaceDownload(
          taskId,
          (d) => d.copyWith(
            status: 'downloading',
            retryCount: attempt,
            error: attempt > 0 ? '断流自动断点续传中（第 $attempt 次重试）…' : null,
            clearError: attempt == 0,
          ),
        );

        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 20);
        handle.client = client;

        try {
          final prep = await core.invoke('prepare_download', {
            'item_id': task.itemId,
            if (task.mediaSourceId != null && task.mediaSourceId!.isNotEmpty)
              'media_source_id': task.mediaSourceId,
          }) as Map<String, dynamic>;

          if (handle.paused || handle.cancelled) return;

          final initialUrlStr = (prep['url'] ?? '').toString();
          if (initialUrlStr.isEmpty) {
            throw const _PermanentDownloadError('无法获取原文件下载地址');
          }
          final rawHeaders = (prep['headers'] as Map?)?.map(
                (k, v) => MapEntry(k.toString(), v.toString()),
              ) ??
              const <String, String>{};
          final rawExt = (prep['container']?.toString().trim().isNotEmpty == true)
              ? prep['container'].toString().trim().replaceFirst(RegExp(r'^\.'), '')
              : 'mkv';
          final ext = rawExt.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '').toLowerCase();
          final safeExt = ext.isEmpty ? 'mkv' : ext;
          final safeItemId = task.itemId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]+'), '_');
          final rawFilename = prep['filename']?.toString().trim() ?? '';
          final fallbackSize = (prep['size'] as num?)?.toInt() ?? task.totalBytes;
          final proxyUrl = prep['proxy_url']?.toString().trim() ?? '';
          final acceptInvalid = prep['accept_invalid_certs'] == true;

          final initialUri = Uri.parse(initialUrlStr);
          if (!NativePlaybackChannel.isAllowedHttpUrl(initialUrlStr)) {
            throw const _PermanentDownloadError('下载地址协议不安全，已拒绝');
          }
          final initialHost = initialUri.host.toLowerCase();
          if (acceptInvalid && initialHost.isNotEmpty) {
            client.badCertificateCallback =
                (_, host, __) => host.toLowerCase() == initialHost;
          }
          if (proxyUrl.isNotEmpty) {
            final parsedProxy = Uri.tryParse(proxyUrl);
            if (parsedProxy != null && parsedProxy.host.isNotEmpty && parsedProxy.port > 0) {
              final proxySpec = 'PROXY ${parsedProxy.host}:${parsedProxy.port}';
              client.findProxy = (_) => proxySpec;
            }
          }

          // Determine stable final path & `.part` resume path BEFORE issuing HTTP request
          final dir = Directory(downloadsDirectoryPath);
          if (!await dir.exists()) await dir.create(recursive: true);

          String outPath = task.filePath;
          if (outPath.isEmpty || !_isPathInsideDirectory(outPath, dir.path)) {
            final baseName = rawFilename.isNotEmpty
                ? rawFilename
                : '${task.title}${task.subtitle.isNotEmpty ? ' - ${task.subtitle}' : ''}${task.versionLabel.isNotEmpty ? ' [${task.versionLabel}]' : ''}.$safeExt';
            final safeName = _sanitizeDownloadFileName(
              baseName,
              fallback: '${safeItemId.isEmpty ? 'media' : safeItemId}.$safeExt',
            );
            outPath = '${dir.path}/$safeName';
            _replaceDownload(taskId, (d) => d.copyWith(filePath: outPath));
          }

          final partFile = File('$outPath.part');
          var offset = partFile.existsSync() ? partFile.lengthSync() : 0;
          if (fallbackSize > 0 && offset == fallbackSize) {
            // Already completely on disk from previous interrupted rename
            if (File(outPath).existsSync()) File(outPath).deleteSync();
            partFile.renameSync(outPath);
            _replaceDownload(
              taskId,
              (d) => d.copyWith(
                filePath: outPath,
                totalBytes: fallbackSize,
                downloadedBytes: fallbackSize,
                speedBytesPerSec: 0,
                status: 'completed',
                clearError: true,
              ),
            );
            await _persistDownloads();
            return;
          }

          var currentUri = initialUri;
          final initialOrigin = '${currentUri.scheme}://${currentUri.authority}';
          final initialIsPrivate = _isPrivateOrLoopbackHost(initialUri.host);
          HttpClientResponse? resp;

          for (var hop = 0; hop < 6; hop++) {
            if (handle.paused || handle.cancelled) return;
            final req = await client.getUrl(currentUri);
            req.followRedirects = false;
            final sameOrigin = '${currentUri.scheme}://${currentUri.authority}' == initialOrigin;
            rawHeaders.forEach((k, v) {
              final lower = k.toLowerCase();
              final isAuthHeader = lower == 'authorization' ||
                  lower == 'x-emby-authorization' ||
                  lower == 'x-emby-token' ||
                  lower == 'x-mediabrowser-token';
              if (sameOrigin || !isAuthHeader) {
                req.headers.set(k, v);
              }
            });
            if (offset > 0) {
              req.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
              if (task.etag != null && task.etag!.isNotEmpty) {
                req.headers.set('If-Range', task.etag!);
              }
            }
            final r = await req.close().timeout(const Duration(seconds: 25));
            if (r.statusCode == 301 ||
                r.statusCode == 302 ||
                r.statusCode == 303 ||
                r.statusCode == 307 ||
                r.statusCode == 308) {
              final loc = r.headers.value(HttpHeaders.locationHeader);
              await r.drain<void>();
              if (loc == null || loc.isEmpty) {
                throw const _PermanentDownloadError('下载重定向地址无效');
              }
              final nextUri = currentUri.resolve(loc);
              final nextScheme = nextUri.scheme.toLowerCase();
              if (nextScheme != 'http' && nextScheme != 'https') {
                throw const _PermanentDownloadError('下载重定向协议不安全，已拦截');
              }
              if (!initialIsPrivate && _isPrivateOrLoopbackHost(nextUri.host)) {
                throw const _PermanentDownloadError('下载重定向至内网地址，已拦截');
              }
              currentUri = nextUri;
              continue;
            }
            resp = r;
            break;
          }

          if (resp == null) {
            throw const _PermanentDownloadError('下载重定向次数过多');
          }

          if (resp.statusCode == 416) {
            await resp.drain<void>();
            if (fallbackSize > 0 && offset >= fallbackSize) {
              if (File(outPath).existsSync()) File(outPath).deleteSync();
              partFile.renameSync(outPath);
              _replaceDownload(
                taskId,
                (d) => d.copyWith(
                  filePath: outPath,
                  totalBytes: offset,
                  downloadedBytes: offset,
                  speedBytesPerSec: 0,
                  status: 'completed',
                  clearError: true,
                ),
              );
              await _persistDownloads();
              return;
            }
            if (partFile.existsSync()) partFile.deleteSync();
            throw const _TransientDownloadError('断点偏移失效，正在重新下载');
          }

          if (resp.statusCode < 200 || resp.statusCode >= 300) {
            final quotaErr = resp.headers.value('x-embygo-quota-error')?.trim() ?? '';
            final bodyBytes = <int>[];
            await for (final chunk in resp.timeout(const Duration(seconds: 10))) {
              if (bodyBytes.length < 64 * 1024) {
                final take = (64 * 1024) - bodyBytes.length;
                bodyBytes.addAll(chunk.length <= take ? chunk : chunk.sublist(0, take));
              } else {
                break;
              }
            }
            final bodyStr = utf8.decode(bodyBytes, allowMalformed: true).trim();
            String serverMsg = '';
            if (bodyStr.startsWith('{')) {
              try {
                final parsed = jsonDecode(bodyStr);
                if (parsed is Map && parsed['Message'] != null) {
                  serverMsg = parsed['Message'].toString().trim();
                }
              } catch (_) {}
            }
            final msg = _formatDownloadHttpError(resp.statusCode, quotaErr, serverMsg);
            // 401/403/404 are non-retryable permission/quota errors; 429/5xx are transient
            if (resp.statusCode == 429 || resp.statusCode >= 500) {
              final retryAfter = int.tryParse(resp.headers.value('retry-after') ?? '');
              throw _TransientDownloadError(msg, retryAfterSecs: retryAfter);
            }
            throw _PermanentDownloadError(msg);
          }

          // Refine filename from Content-Disposition only when starting fresh at offset 0
          if (offset == 0 && task.filePath.isEmpty) {
            final cdFilename = _parseContentDispositionFilename(
              resp.headers.value('content-disposition'),
            );
            if (cdFilename.isNotEmpty) {
              final safeCd = _sanitizeDownloadFileName(cdFilename, fallback: '');
              if (safeCd.isNotEmpty) {
                final candidate = '${dir.path}/$safeCd';
                if (_isPathInsideDirectory(candidate, dir.path)) {
                  outPath = candidate;
                  _replaceDownload(taskId, (d) => d.copyWith(filePath: outPath));
                }
              }
            }
          }

          final activePartFile = File('$outPath.part');
          final respEtag = resp.headers.value(HttpHeaders.etagHeader)?.trim();
          final contentRange = resp.headers.value(HttpHeaders.contentRangeHeader);
          final isPartial = resp.statusCode == 206 && offset > 0;

          int expectedTotal = fallbackSize;
          FileMode writeMode = FileMode.write;
          var received = 0;

          if (isPartial) {
            final parsedRange = _parseContentRange(contentRange);
            if (parsedRange != null && parsedRange.start == offset) {
              writeMode = FileMode.append;
              received = offset;
              if (parsedRange.total > 0) expectedTotal = parsedRange.total;
            } else if (resp.contentLength > 0) {
              writeMode = FileMode.append;
              received = offset;
              expectedTotal = offset + resp.contentLength;
            } else {
              offset = 0;
              received = 0;
              writeMode = FileMode.write;
            }
          } else {
            offset = 0;
            received = 0;
            writeMode = FileMode.write;
            if (resp.contentLength > 0) expectedTotal = resp.contentLength;
          }

          _replaceDownload(
            taskId,
            (d) => d.copyWith(
              filePath: outPath,
              etag: respEtag ?? d.etag,
              totalBytes: expectedTotal,
              downloadedBytes: received,
              status: 'downloading',
              clearError: true,
            ),
          );

          inFlightRefreshTimer?.cancel();
          inFlightRefreshTimer = Timer(const Duration(milliseconds: 650), () {
            if (!_disposed) unawaited(refreshMeQuota());
          });

          final sink = activePartFile.openWrite(mode: writeMode);
          var lastEmit = DateTime.now();
          var lastEmitBytes = received;
          var bytesSinceFlush = 0;

          try {
            await for (final chunk in resp.timeout(const Duration(seconds: 25))) {
              if (handle.paused || handle.cancelled) break;
              sink.add(chunk);
              received += chunk.length;
              bytesSinceFlush += chunk.length;
              // Periodic flush applies backpressure so gigabit downloads never balloon RAM
              if (bytesSinceFlush >= 1024 * 1024) {
                bytesSinceFlush = 0;
                await sink.flush();
              }
              final now = DateTime.now();
              final elapsedMs = now.difference(lastEmit).inMilliseconds;
              if (elapsedMs >= 400) {
                final deltaBytes = received - lastEmitBytes;
                final speed = elapsedMs > 0 ? ((deltaBytes * 1000) ~/ elapsedMs) : 0;
                lastEmit = now;
                lastEmitBytes = received;
                _replaceDownload(
                  taskId,
                  (d) => d.copyWith(
                    filePath: outPath,
                    totalBytes: expectedTotal,
                    downloadedBytes: received,
                    speedBytesPerSec: speed,
                    status: 'downloading',
                    clearError: true,
                  ),
                  tickOnly: true,
                );
              }
            }
            await sink.flush();
            await sink.close();
          } catch (streamErr) {
            try {
              await sink.flush();
              await sink.close();
            } catch (_) {}
            if (handle.paused || handle.cancelled) return;
            _replaceDownload(
              taskId,
              (d) => d.copyWith(downloadedBytes: received, speedBytesPerSec: 0),
            );
            throw _TransientDownloadError('连接中断，准备断点续传：$streamErr');
          }

          if (handle.paused || handle.cancelled) {
            _replaceDownload(
              taskId,
              (d) => d.copyWith(
                downloadedBytes: received,
                speedBytesPerSec: 0,
                // Don't clobber `'queued'` if user paused and immediately clicked resume while worker exited!
                status: handle.paused && d.status == 'downloading' ? 'paused' : d.status,
              ),
            );
            await _persistDownloads();
            return;
          }

          // Strict integrity verification: NEVER mark a truncated half-downloaded file as completed!
          if (expectedTotal > 0 && received < expectedTotal) {
            _replaceDownload(
              taskId,
              (d) => d.copyWith(downloadedBytes: received, speedBytesPerSec: 0),
            );
            throw _TransientDownloadError(
              '连接提前断开（已传 ${fmtFileSize(received)} / ${fmtFileSize(expectedTotal)}），正在断点续传…',
            );
          }

          if (File(outPath).existsSync()) {
            try {
              File(outPath).deleteSync();
            } catch (_) {}
          }
          if (activePartFile.existsSync()) {
            activePartFile.renameSync(outPath);
          }

          _replaceDownload(
            taskId,
            (d) => d.copyWith(
              filePath: outPath,
              totalBytes: expectedTotal > 0 ? expectedTotal : received,
              downloadedBytes: received,
              speedBytesPerSec: 0,
              status: 'completed',
              clearError: true,
            ),
          );
          await _persistDownloads();
          return;
        } on _PermanentDownloadError catch (e) {
          _replaceDownload(
            taskId,
            (d) => d.copyWith(
              status: 'failed',
              speedBytesPerSec: 0,
              error: e.message,
            ),
          );
          await _persistDownloads();
          return;
        } catch (e) {
          if (handle.paused || handle.cancelled) return;
          final msg = e is _TransientDownloadError
              ? e.message
              : e.toString().replaceFirst('Exception: ', '');
          if (attempt + 1 >= maxAttempts) {
            _replaceDownload(
              taskId,
              (d) => d.copyWith(
                status: 'failed',
                speedBytesPerSec: 0,
                error: '已自动续传 $maxAttempts 次仍中断：$msg（已保留进度，可点击继续）',
              ),
            );
            await _persistDownloads();
            return;
          }
          final waitSecs = e is _TransientDownloadError && e.retryAfterSecs != null
              ? e.retryAfterSecs!.clamp(2, 30)
              : [2, 4, 6, 10, 15, 20, 25][attempt.clamp(0, 6)];
          _replaceDownload(
            taskId,
            (d) => d.copyWith(
              status: 'downloading',
              speedBytesPerSec: 0,
              retryCount: attempt + 1,
              error: '连接中断，${waitSecs}s 后断点续传（第 ${attempt + 1}/$maxAttempts 次）',
            ),
          );
          await _persistDownloads();
          await Future.any<void>([
            Future<void>.delayed(Duration(seconds: waitSecs)),
            handle.cancelSignal.future,
          ]);
        } finally {
          inFlightRefreshTimer?.cancel();
          handle.client = null;
          client.close(force: true);
        }
      }
    } finally {
      inFlightRefreshTimer?.cancel();
      if (_activeDownloadHandles[taskId] == handle) {
        _activeDownloadHandles.remove(taskId);
      }
      if (!handle.done.isCompleted) {
        handle.done.complete();
      }
      if (!_disposed) {
        unawaited(refreshMeQuota());
        _quotaRefreshTimer?.cancel();
        _quotaRefreshTimer = Timer(const Duration(seconds: 2), () {
          if (!_disposed) unawaited(refreshMeQuota());
        });
        _pumpDownloadQueue();
      }
    }
  }

  static String _sanitizeDownloadFileName(String raw, {required String fallback}) {
    final base = raw
        .replaceAll('\\', '/')
        .split('/')
        .last
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fff\-_. ()\[\]]+'), '_')
        .replaceAll('..', '_')
        .replaceAll(RegExp(r'^\.+'), '')
        .trim();
    if (base.isEmpty || base == '.' || base == '..') return fallback;
    return base.length > 180 ? base.substring(0, 180) : base;
  }

  static bool _isPathInsideDirectory(String targetPath, String baseDir) {
    try {
      final normBase = Directory(baseDir).absolute.path.replaceAll('\\', '/');
      final cleanBase = normBase.endsWith('/') ? normBase : '$normBase/';
      final normTarget = File(targetPath).absolute.path.replaceAll('\\', '/');
      if (normTarget.contains('/../') || normTarget.endsWith('/..')) return false;
      return normTarget.startsWith(cleanBase);
    } catch (_) {
      return false;
    }
  }

  static bool _isPrivateOrLoopbackHost(String host) {
    final h = host.trim().toLowerCase().replaceAll(RegExp(r'^\[|\]$'), '');
    if (h.isEmpty || h == 'localhost' || h.endsWith('.local')) return true;
    final ip = InternetAddress.tryParse(h);
    if (ip == null) return false;
    if (ip.isLoopback || ip.isLinkLocal || ip.isMulticast) return true;
    final b = ip.rawAddress;
    if (ip.type == InternetAddressType.IPv4 && b.length == 4) {
      if (b[0] == 10 || b[0] == 0 || b[0] == 127) return true;
      if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true;
      if (b[0] == 192 && b[1] == 168) return true;
      if (b[0] == 169 && b[1] == 254) return true;
      if (b[0] == 100 && b[1] >= 64 && b[1] <= 127) return true;
    }
    if (ip.type == InternetAddressType.IPv6 && b.length == 16) {
      if ((b[0] & 0xFE) == 0xFC) return true; // fc00::/7 ULA
    }
    return false;
  }

  static ({int start, int end, int total})? _parseContentRange(String? header) {
    if (header == null || header.isEmpty) return null;
    final m = RegExp(r'bytes\s+(\d+)-(\d+)/(\d+|\*)', caseSensitive: false).firstMatch(header);
    if (m == null) return null;
    final start = int.tryParse(m.group(1)!) ?? -1;
    final end = int.tryParse(m.group(2)!) ?? -1;
    final total = m.group(3) == '*' ? 0 : (int.tryParse(m.group(3)!) ?? 0);
    if (start < 0 || end < start) return null;
    return (start: start, end: end, total: total);
  }

  static String _formatDownloadHttpError(int status, String quotaErr, String serverMsg) {
    switch (quotaErr) {
      case 'insufficient_download_quota':
        return serverMsg.isNotEmpty
            ? serverMsg
            : '下载流量包余额不足（仅限原文件下载，在线播放不限流量）';
      case 'too_many_concurrent_downloads':
        return serverMsg.isNotEmpty
            ? serverMsg
            : '同时下载任务数已达上限，请等待当前下载完成后再试';
      case 'telegram_binding_required':
        return serverMsg.isNotEmpty
            ? serverMsg
            : '请先绑定 Telegram 账号后再使用共享下载流量包';
    }
    if (serverMsg.isNotEmpty) return serverMsg;
    if (status == 403) return '当前账号无下载权限，请联系管理员';
    if (status == 429) return '下载并发数已达上限，请稍后再试';
    if (status == 503) return '无法核验下载流量额度，请稍后重试';
    return '下载失败 (HTTP $status)';
  }

  static String _parseContentDispositionFilename(String? header) {
    if (header == null || header.isEmpty) return '';
    final star = RegExp(r"filename\*=UTF-8''([^;\r\n]+)", caseSensitive: false).firstMatch(header);
    if (star != null) {
      try {
        return Uri.decodeComponent(star.group(1)!.trim());
      } catch (_) {}
    }
    final quoted = RegExp(r'filename="([^"]+)"', caseSensitive: false).firstMatch(header);
    if (quoted != null) return quoted.group(1)!.trim();
    final plain = RegExp(r'filename=([^;\r\n]+)', caseSensitive: false).firstMatch(header);
    if (plain != null) return plain.group(1)!.trim();
    return '';
  }

  void _replaceDownload(
    String id,
    DownloadTaskModel Function(DownloadTaskModel) transform, {
    bool tickOnly = false,
  }) {
    final idx = downloads.indexWhere((d) => d.id == id);
    if (idx >= 0) {
      downloads[idx] = transform(downloads[idx]);
      if (!_disposed) {
        downloadsTickNotifier.value = downloadsTickNotifier.value + 1;
        if (!tickOnly) {
          notifyListeners();
        }
      }
    }
  }

  Future<void> deleteDownload(String taskId, {bool deleteFile = true}) async {
    final handle = _activeDownloadHandles.remove(taskId);
    if (handle != null) {
      handle.cancelled = true;
      handle.abort();
      try {
        await handle.done.future.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    final idx = downloads.indexWhere((d) => d.id == taskId);
    if (idx < 0) return;
    final task = downloads.removeAt(idx);
    if (deleteFile && task.filePath.isNotEmpty) {
      for (final p in [task.filePath, '${task.filePath}.part']) {
        if (!_isPathInsideDirectory(p, downloadsDirectoryPath)) continue;
        try {
          final f = File(p);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }
    notifyListeners();
    await _persistDownloads();
    _pumpDownloadQueue();
  }
}

class _ActiveDownloadHandle {
  HttpClient? client;
  bool paused = false;
  bool cancelled = false;
  final Completer<void> cancelSignal = Completer<void>();
  final Completer<void> done = Completer<void>();

  void abort() {
    if (!cancelSignal.isCompleted) {
      cancelSignal.complete();
    }
    try {
      client?.close(force: true);
    } catch (_) {}
  }
}

class _PermanentDownloadError implements Exception {
  const _PermanentDownloadError(this.message);
  final String message;
  @override
  String toString() => message;
}

class _TransientDownloadError implements Exception {
  const _TransientDownloadError(this.message, {this.retryAfterSecs});
  final String message;
  final int? retryAfterSecs;
  @override
  String toString() => message;
}
