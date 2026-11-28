part of '../player_screen.dart';

/// Main player canvas, video viewport, top/bottom cinema chrome, gesture HUD & episode drawer.
extension _PlayerHudExt on _PlayerScreenState {
  Widget _buildPlayerScaffold(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 760;
    final isMac = !kIsWeb && Platform.isMacOS;
    final isWin = !kIsWeb && Platform.isWindows;
    final topPad = MediaQuery.paddingOf(context).top;
    final step = widget.appState.prefs.seekStepSecs;
    final showSpecs = widget.appState.prefs.showSpecBadges;
    final specs = showSpecs
        ? <String>[
            if (_prepared?.dolbyVisionLabel != null) _prepared!.dolbyVisionLabel!,
            if (_prepared?.spatialAudioLabel != null) _prepared!.spatialAudioLabel!,
          ]
        : const <String>[];

    final hideCursor = !_controlsVisible && !_showEpisodeDrawer && !_paused && !_loading;
    final shouldAutoHideWinCaption = !_controlsVisible && !_showEpisodeDrawer;
    if (NativePlaybackChannel.playerHudAutoHideNotifier.value != shouldAutoHideWinCaption) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          NativePlaybackChannel.playerHudAutoHideNotifier.value = shouldAutoHideWinCaption;
        }
      });
    }
    final tvPadX = _isTv ? 32.0 : 0.0;
    final tvPadY = _isTv ? 18.0 : 0.0;
    final osdInteractive =
        _controlsVisible && !_showEpisodeDrawer && !_screenLocked && !_inPipMode && !_gesturePeekingVideo;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent && !_showEpisodeDrawer && !_screenLocked) {
                final delta = event.scrollDelta.dy > 0 ? -4.0 : 4.0;
                _setVolume(_volume + delta);
                _flashGestureHud('volume');
              }
            },
            child: MouseRegion(
              cursor: hideCursor ? SystemMouseCursors.none : SystemMouseCursors.basic,
              onHover: (_) {
                final nowMs = DateTime.now().millisecondsSinceEpoch;
                if (nowMs - _lastHoverRevealMs < 250) return;
                _lastHoverRevealMs = nowMs;
                if (_screenLocked) {
                  _revealLockIconBriefly();
                } else if (!_inPipMode) {
                  _revealControls();
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: (d) => _openContextMenu(d.globalPosition),
                onTapDown: (d) => _lastTapDownPos = d.localPosition,
                onTap: () {
                  if (_inPipMode) return;
                  if (_screenLocked) {
                    _revealLockIconBriefly();
                    return;
                  }
                  if (_showEpisodeDrawer) {
                    _setPlayerState(() => _showEpisodeDrawer = false);
                    _scheduleHideControls();
                    return;
                  }
                  if (_controlsVisible) {
                    _hideControlsTimer?.cancel();
                    _setPlayerState(() => _controlsVisible = false);
                  } else {
                    _revealControls();
                  }
                },
                onDoubleTap: () => _handleDoubleTap(size.width),
                onLongPressStart: (_) {
                  if (_screenLocked || _inPipMode) return;
                  HapticFeedback.mediumImpact();
                  _preBoostSpeed = _speed;
                  _setPlayerState(() => _isSpeedBoost = true);
                  _setSpeed(widget.appState.prefs.longPressSpeed);
                },
                onLongPressEnd: (_) {
                  if (!_isSpeedBoost) return;
                  _setPlayerState(() => _isSpeedBoost = false);
                  _setSpeed(_preBoostSpeed);
                },
                onLongPressCancel: () {
                  if (!_isSpeedBoost) return;
                  _setPlayerState(() => _isSpeedBoost = false);
                  _setSpeed(_preBoostSpeed);
                },
                onScaleStart: (d) {
                  if (_showEpisodeDrawer || _screenLocked || _inPipMode) return;
                  // Edge-swipe dead-zone so Android/iOS system back & notification swipes don't conflict
                  if (_isMobile && d.pointerCount == 1) {
                    final fp = d.localFocalPoint;
                    if (fp.dx < 28 ||
                        fp.dx > size.width - 28 ||
                        fp.dy < 36 ||
                        fp.dy > size.height - 36) {
                      _scaleAxis = 'blocked';
                      return;
                    }
                  }
                  _scaleAxis = null;
                  _scaleAnchor = d.localFocalPoint;
                  _pinchBaseZoom = _videoZoom;
                  if (d.pointerCount >= 2 && widget.appState.prefs.pinchToZoom) {
                    _scaleAxis = 'pinch';
                    _hideControlsTimer?.cancel();
                  }
                },
                onScaleUpdate: (d) {
                  if (_showEpisodeDrawer || _screenLocked || _inPipMode || _scaleAxis == 'blocked') {
                    return;
                  }
                  if ((d.pointerCount >= 2 || _scaleAxis == 'pinch') &&
                      widget.appState.prefs.pinchToZoom) {
                    _scaleAxis = 'pinch';
                    final nextZoom = (_pinchBaseZoom + (d.scale - 1.0) * 0.85).clamp(-0.5, 1.5);
                    if ((nextZoom - _videoZoom).abs() > 0.015) {
                      _setVideoZoom(nextZoom);
                    }
                    return;
                  }
                  final delta = d.focalPointDelta;
                  if (_scaleAxis == null) {
                    final totalDx = (d.localFocalPoint.dx - _scaleAnchor.dx).abs();
                    final totalDy = (d.localFocalPoint.dy - _scaleAnchor.dy).abs();
                    if (totalDx < 8 && totalDy < 8) return;
                    if (totalDx >= totalDy) {
                      if (_durationSecs <= 0) return;
                      _scaleAxis = 'h';
                      _hideControlsTimer?.cancel();
                      _scrubStartSecs = _positionSecs;
                      _scrubTargetSecs = _positionSecs;
                      _scrubTargetNotifier.value = _positionSecs;
                      _setPlayerState(() {
                        _scrubbing = true;
                      });
                    } else {
                      _scaleAxis = 'v';
                      if (_controlsVisible && !_gesturePeekingVideo) {
                        _setPlayerState(() => _gesturePeekingVideo = true);
                      }
                    }
                  }
                  if (_scaleAxis == 'h' && _scrubbing && size.width > 0) {
                    final deltaSecs = (delta.dx / size.width) * 180.0;
                    _scrubTargetSecs = (_scrubTargetSecs + deltaSecs).clamp(0.0, _durationSecs);
                    // Zero full-screen PlayerScreen rebuild while dragging!
                    _scrubTargetNotifier.value = _scrubTargetSecs;
                  } else if (_scaleAxis == 'v' && size.height > 0) {
                    final vDelta = -delta.dy / (size.height * 0.55);
                    if (_scaleAnchor.dx < size.width * 0.5) {
                      _setBrightness(_brightness + vDelta);
                      _flashGestureHud('brightness');
                    } else {
                      _setVolume(_volume + vDelta * 100);
                      _flashGestureHud('volume');
                    }
                  }
                },
                onScaleEnd: (_) {
                  if (_screenLocked) {
                    _scaleAxis = null;
                    return;
                  }
                  if (_gesturePeekingVideo) {
                    _setPlayerState(() => _gesturePeekingVideo = false);
                    _scheduleHideControls();
                  }
                  if (_scrubbing) {
                    final target = _scrubTargetSecs;
                    _setPlayerState(() => _scrubbing = false);
                    _seekTo(target);
                    _scheduleHideControls();
                  }
                  _scaleAxis = null;
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RepaintBoundary(
                      child: Video(
                        controller: _videoController,
                        controls: NoVideoControls,
                        fill: Colors.black,
                        fit: _aspectMode == 'fill'
                            ? BoxFit.cover
                            : (_aspectMode == 'stretch' ? BoxFit.fill : BoxFit.contain),
                      ),
                    ),

                    // Software brightness veil only when OS native brightness is unavailable (Desktop)
                    if (!_usingNativeBrightness && _brightness < 0.99)
                      IgnorePointer(
                        child: Container(
                          color: Colors.black.withValues(alpha: (1.0 - _brightness).clamp(0.0, 0.85)),
                        ),
                      ),

                    // AI Bilingual / ASR Lookahead Subtitle Overlay (`Positioned.fill` sits directly
                    // in `Stack`, with internal `RepaintBoundary` + `ValueNotifier` isolating repaints)
                    AiBilingualSubtitleOverlay(
                      controller: _aiSubCtrl,
                      subScale: _subScale,
                      translationFontScale: _aiSubFontScale,
                      subPos: _subPos,
                      colorHex: widget.appState.prefs.subtitleColorHex,
                      outlineWidth: widget.appState.prefs.subtitleOutlineWidth,
                      bgOpacity: widget.appState.prefs.subtitleBgOpacity,
                      fontFamily: _subFontFamily,
                    ),

                    // GPU-cached Canvas Danmaku overlay driven solely by _positionNotifier
                    if (_danmakuEnabled && !_inPipMode)
                      RepaintBoundary(
                        child: ValueListenableBuilder<double>(
                          valueListenable: _positionNotifier,
                          builder: (_, posSecs, __) => DanmakuLayer(
                            comments: _danmakuComments,
                            positionSecs: posSecs,
                            opacity: _danmakuOpacity,
                            fontSize: _danmakuFontSize,
                            speedSecs: _danmakuSpeedSecs,
                            areaFraction: _danmakuArea,
                            hideTop: _danmakuHideTop,
                            hideBottom: _danmakuHideBottom,
                          ),
                        ),
                      ),

                    if ((_loading || _buffering) && !_inPipMode)
                      Center(
                        child: ValueListenableBuilder<int>(
                          valueListenable: _networkSpeedBpsNotifier,
                          builder: (_, bps, __) {
                            final showNet = !_isLocalFile &&
                                widget.appState.prefs.showNetworkSpeed;
                            final label = _loading ? '正在加载' : '缓冲中';
                            return GlassSurface(
                              borderRadius: 16,
                              enableBlur: false,
                              color: const Color(0xD8121318),
                              borderColor: const Color(0x30FFFFFF),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.0,
                                      color: VedroTheme.fg,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    showNet && bps > 0
                                        ? '$label · ${fmtTransferSpeed(bps)}'
                                        : '$label…',
                                    style: const TextStyle(
                                      color: VedroTheme.fg,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      fontFeatures: [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                    // Live network download speed pill (zero full-page rebuild via ValueNotifier)
                    if (widget.appState.prefs.showNetworkSpeed &&
                        !_isLocalFile &&
                        !_showEpisodeDrawer &&
                        !_screenLocked &&
                        !_inPipMode)
                      Positioned(
                        top: (_controlsVisible ? topPad + 60 : topPad + 14) + tvPadY,
                        right: ((isWin && !_isFullscreen && !_controlsVisible) ? 148 : 20) + tvPadX,
                        child: IgnorePointer(
                          child: ValueListenableBuilder<int>(
                            valueListenable: _networkSpeedBpsNotifier,
                            builder: (_, bps, __) {
                              if (bps <= 0 && !_buffering && !_loading && !_controlsVisible) {
                                return const SizedBox.shrink();
                              }
                              return Container(
                                key: const ValueKey('player-network-speed-pill'),
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0x8C0D0E12),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.14),
                                    width: 0.7,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.arrow_downward_rounded,
                                      size: 11.5,
                                      color: bps > 0
                                          ? const Color(0xFF34D399)
                                          : Colors.white.withValues(alpha: 0.65),
                                    ),
                                    const SizedBox(width: 3.5),
                                    Text(
                                      fmtTransferSpeed(bps),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        fontFeatures: [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                    // Actionable Error Recovery Banner (Retry / Software Decode Retry / Dismiss)
                    if (_error != null && !_inPipMode)
                      Positioned(
                        bottom: 140 + tvPadY,
                        left: 24 + tvPadX,
                        right: 24 + tvPadX,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 540),
                            child: GlassSurface(
                              borderRadius: 14,
                              enableBlur: false,
                              color: const Color(0xEE221216),
                              borderColor: const Color(0x66FF6B6F),
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.error_outline_rounded,
                                          size: 18, color: VedroTheme.danger),
                                      const SizedBox(width: 8),
                                      const Expanded(
                                        child: Text(
                                          '播放遇到问题',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _error!,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFFCA5A5),
                                      fontSize: 12.5,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _DeckPillButton(
                                        focusNode: _errorRetryFocusNode,
                                        label: '重试播放',
                                        active: true,
                                        onTap: () {
                                          _autoRetryCount = 0;
                                          _retryAnchorSecs = -1.0;
                                          unawaited(_startPlayback(
                                            _prepared?.mediaSourceId,
                                            resumeFromSecs: _positionSecs,
                                          ));
                                        },
                                      ),
                                      if (_hwDecodeEnabled)
                                        _DeckPillButton(
                                          label: '切换软解重试',
                                          onTap: () {
                                            _setPlayerState(() => _hwDecodeEnabled = false);
                                            _autoRetryCount = 0;
                                            _retryAnchorSecs = -1.0;
                                            unawaited(_startPlayback(
                                              _prepared?.mediaSourceId,
                                              resumeFromSecs: _positionSecs,
                                            ));
                                          },
                                        ),
                                      _DeckPillButton(
                                        label: '关闭提示',
                                        onTap: () => _setPlayerState(() => _error = null),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Up-Next 6-second Auto-Play Countdown Card
                    if (_upNextCountdown > 0 && _nextEpisode != null && !_inPipMode)
                      Positioned(
                        right: 28 + tvPadX,
                        bottom: (_controlsVisible ? 110 : 34) + tvPadY,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 340),
                          child: GlassSurface(
                            borderRadius: 16,
                            enableBlur: false,
                            color: const Color(0xE814161F),
                            borderColor: const Color(0x40FFFFFF),
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$_upNextCountdown 秒后自动播放下一集',
                                  style: const TextStyle(
                                    color: Color(0xFFB3B9C9),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_nextEpisode!.episodeCode ?? ''} ${_nextEpisode!.displayName}'.trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _DeckPillButton(
                                      focusNode: _upNextPlayFocusNode,
                                      label: '立即播放',
                                      active: true,
                                      onTap: () {
                                        final next = _nextEpisode;
                                        _setPlayerState(_cancelUpNextCountdown);
                                        if (next != null) unawaited(_switchEpisode(next));
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    _DeckPillButton(
                                      label: '取消',
                                      onTap: () => _setPlayerState(() {
                                        _cancelUpNextCountdown();
                                        if (_durationSecs > 0 &&
                                            _positionSecs >= _durationSecs - 2.0) {
                                          _hasEndedReplay = true;
                                        }
                                      }),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // End-of-Video Replay Overlay
                    if (_hasEndedReplay && _upNextCountdown == 0 && _error == null && !_inPipMode)
                      Center(
                        child: GlassSurface(
                          borderRadius: 18,
                          enableBlur: false,
                          color: const Color(0xE012141C),
                          borderColor: const Color(0x36FFFFFF),
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                '已播放完毕',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _DeckPillButton(
                                    focusNode: _replayFocusNode,
                                    label: '重新播放',
                                    active: true,
                                    onTap: () async {
                                      _setPlayerState(() {
                                        _completedTriggered = false;
                                        _hasEndedReplay = false;
                                      });
                                      await _seekTo(0);
                                      await _player.play();
                                    },
                                  ),
                                  if (_nextEpisode != null) ...[
                                    const SizedBox(width: 8),
                                    _DeckPillButton(
                                      label: '下一集',
                                      onTap: () => _switchEpisode(_nextEpisode!),
                                    ),
                                  ],
                                  const SizedBox(width: 8),
                                  _DeckPillButton(
                                    label: '退出',
                                    onTap: _requestExit,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Skip Intro / Outro floating button (also offers reactive +85s pill for TV episodes without IntroSkipper)
                    if (!_showEpisodeDrawer && !_screenLocked && !_inPipMode && _upNextCountdown == 0)
                      ValueListenableBuilder<MediaSegmentModel?>(
                        valueListenable: _activeSegmentNotifier,
                        builder: (_, seg, __) {
                          if (seg != null) {
                            return Positioned(
                              right: 28 + tvPadX,
                              bottom: (_controlsVisible ? 104 : 30) + tvPadY,
                              child: PressableScale(
                                focusNode: _skipIntroFocusNode,
                                onTap: () => _seekTo(seg.endSecs),
                                hoverScale: 1.04,
                                pressScale: 0.94,
                                borderRadius: BorderRadius.circular(12),
                                child: GlassSurface(
                                  borderRadius: 12,
                                  enableBlur: false,
                                  color: const Color(0xDC181920),
                                  borderColor: const Color(0x45FFFFFF),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        seg.buttonLabel,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Icon(Icons.skip_next_rounded, size: 18, color: Colors.white),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }
                          return ValueListenableBuilder<bool>(
                            valueListenable: _quickSkipEligibleNotifier,
                            builder: (_, eligible, __) {
                              final showQuickSkip = _controlsVisible &&
                                  eligible &&
                                  !_quickSkipIntroDismissed &&
                                  _segments.isEmpty &&
                                  _currentItem.type == 'Episode';
                              if (!showQuickSkip) return const SizedBox.shrink();
                              return Positioned(
                                right: 28 + tvPadX,
                                bottom: 104 + tvPadY,
                                child: PressableScale(
                                  focusNode: _skipIntroFocusNode,
                                  onTap: () {
                                    _setPlayerState(() => _quickSkipIntroDismissed = true);
                                    _quickSkipEligibleNotifier.value = false;
                                    unawaited(_seekBy(85, showHud: true));
                                  },
                                  hoverScale: 1.04,
                                  pressScale: 0.94,
                                  borderRadius: BorderRadius.circular(12),
                                  child: const GlassSurface(
                                    borderRadius: 12,
                                    enableBlur: false,
                                    color: Color(0xD6181920),
                                    borderColor: Color(0x3CFFFFFF),
                                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '跳过片头 +85s',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        SizedBox(width: 5),
                                        Icon(Icons.fast_forward_rounded, size: 16, color: Colors.white),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),

                    if (_isSpeedBoost && !_inPipMode)
                      Positioned(
                        top: topPad + 48 + tvPadY,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: GlassSurface(
                            borderRadius: 20,
                            enableBlur: false,
                            color: const Color(0xD814161D),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.fast_forward_rounded, size: 15, color: VedroTheme.fg),
                                const SizedBox(width: 6),
                                Text(
                                  '${widget.appState.prefs.longPressSpeed.toStringAsFixed(1)}×',
                                  style: const TextStyle(
                                    color: VedroTheme.fg,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    if (_scrubbing && !_inPipMode)
                      Center(
                        child: ValueListenableBuilder<double>(
                          valueListenable: _scrubTargetNotifier,
                          builder: (_, targetSecs, __) => GlassSurface(
                            borderRadius: 16,
                            enableBlur: false,
                            color: const Color(0xDC12141C),
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${_fmtTime(targetSecs)} / ${_fmtTime(_durationSecs)}',
                                  style: const TextStyle(
                                    color: VedroTheme.fg,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _fmtDelta(targetSecs - _scrubStartSecs),
                                  style: const TextStyle(
                                    color: VedroTheme.fg2,
                                    fontSize: 12.5,
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Isolated Gesture HUD (instant 120Hz updates with zero full-screen setState!)
                    if (!_scrubbing && !_inPipMode)
                      ValueListenableBuilder<({String? mode, String text, double value, int seq})>(
                        valueListenable: _gestureHudNotifier,
                        builder: (_, hud, __) {
                          if (hud.mode == null) return const SizedBox.shrink();
                          return Center(
                            child: GlassSurface(
                              borderRadius: 16,
                              enableBlur: false,
                              color: const Color(0xDC12141C),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              child: _buildGestureHudContent(hud.mode!, hud.text, hud.value),
                            ),
                          );
                        },
                      ),

                    if (_showStats && !_inPipMode)
                      Positioned(
                        top: topPad + 72 + tvPadY,
                        left: 24 + tvPadX,
                        child: ValueListenableBuilder<Map<String, dynamic>>(
                          valueListenable: _statsNotifier,
                          builder: (_, stats, __) => NerdStatsHud(stats: stats),
                        ),
                      ),

                    // Screen-lock minimal unlock button (focusable via D-Pad!)
                    if (_screenLocked && _lockIconVisible && !_inPipMode)
                      Positioned(
                        left: 24 + tvPadX,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: PressableScale(
                            focusNode: _unlockFocusNode,
                            onTap: _toggleScreenLock,
                            borderRadius: BorderRadius.circular(22),
                            child: const GlassSurface(
                              borderRadius: 22,
                              enableBlur: false,
                              color: Color(0xDC14151B),
                              borderColor: Color(0x38FFFFFF),
                              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock_open_rounded, size: 18, color: Colors.white),
                                  SizedBox(width: 6),
                                  Text('解锁屏幕',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Windowed Windows top drag zone even when player HUD is auto-hidden
                    if (!kIsWeb && Platform.isWindows && !_isFullscreen && !osdInteractive)
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 138,
                        height: 36,
                        child: WindowsWindowDragArea(),
                      ),

                    // Auto-hiding IINA / Apple TV+ chrome (also hides cleanly while peeking video during sheet slider drags!)
                    ValueListenableBuilder<bool>(
                      valueListenable: _sheetPeekNotifier,
                      builder: (_, sheetPeeking, child) {
                        final showOsd = osdInteractive && !sheetPeeking;
                        return ExcludeFocus(
                          excluding: !showOsd,
                          child: IgnorePointer(
                            ignoring: !showOsd,
                            child: AnimatedOpacity(
                              opacity: showOsd ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 180),
                              curve: VedroTheme.easeOut,
                              child: child,
                            ),
                          ),
                        );
                      },
                      child: Stack(
                            children: [
                              // Top Bar
                              Positioned(
                                top: tvPadY,
                                left: tvPadX,
                                right: tvPadX,
                                child: AnimatedSlide(
                                  offset: osdInteractive ? Offset.zero : const Offset(0, -0.22),
                                  duration: const Duration(milliseconds: 250),
                                  curve: VedroTheme.easeOut,
                                  child: MouseRegion(
                                    onEnter: (_) {
                                      _hoveringChrome = true;
                                      _hideControlsTimer?.cancel();
                                    },
                                    onExit: (_) {
                                      _hoveringChrome = false;
                                      _scheduleHideControls();
                                    },
                                    child: DecoratedBox(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [Color(0xC4000000), Colors.transparent],
                                        ),
                                      ),
                                      child: Stack(
                                        children: [
                                          Positioned.fill(
                                            child: WindowsWindowDragArea(enabled: !_isFullscreen),
                                          ),
                                          Padding(
                                            padding: EdgeInsets.fromLTRB(
                                              (isMac && !_isFullscreen)
                                                  ? (MediaQuery.sizeOf(context).width < 560 ? 20 : 82)
                                                  : 20,
                                              topPad + 12,
                                              (!kIsWeb && Platform.isWindows && !_isFullscreen)
                                                  ? (MediaQuery.sizeOf(context).width < 560 ? 20 : 148)
                                                  : 20,
                                              28,
                                            ),
                                            child: Row(
                                        children: [
                                          _CircleHudButton(
                                            icon: Icons.arrow_back_ios_new_rounded,
                                            iconSize: 15,
                                            tooltip: '返回 (Esc)',
                                            onTap: _requestExit,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    _currentItem.seriesName != null
                                                        ? '${_currentItem.seriesName} ${_currentItem.episodeCode ?? ''} · ${_currentItem.displayName}'
                                                        : _currentItem.displayName,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w600,
                                                      letterSpacing: -0.2,
                                                    ),
                                                  ),
                                                ),
                                                if (specs.isNotEmpty) ...[
                                                  const SizedBox(width: 10),
                                                  SpecGlyphRow(specs: specs, forceDarkScrim: true),
                                                ],
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          // Mobile fullscreen live clock & battery %
                                          if (_isMobile && size.width >= 460)
                                            ValueListenableBuilder<
                                                ({String clock, int batteryPct, bool charging})>(
                                              valueListenable: _statusBarNotifier,
                                              builder: (_, info, __) {
                                                if (info.clock.isEmpty) {
                                                  return const SizedBox.shrink();
                                                }
                                                return Padding(
                                                  padding: const EdgeInsets.only(right: 10),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        info.clock,
                                                        style: const TextStyle(
                                                          color: Color(0xCCFFFFFF),
                                                          fontSize: 11.5,
                                                          fontWeight: FontWeight.w500,
                                                          fontFeatures: [
                                                            FontFeature.tabularFigures()
                                                          ],
                                                        ),
                                                      ),
                                                      if (info.batteryPct >= 0) ...[
                                                        const SizedBox(width: 6),
                                                        Icon(
                                                          info.charging
                                                              ? Icons.battery_charging_full_rounded
                                                              : (info.batteryPct <= 20
                                                                  ? Icons.battery_alert_rounded
                                                                  : Icons.battery_std_rounded),
                                                          size: 13.5,
                                                          color: info.batteryPct <= 20 && !info.charging
                                                              ? const Color(0xFFF87171)
                                                              : const Color(0xCCFFFFFF),
                                                        ),
                                                        const SizedBox(width: 2),
                                                        Text(
                                                          '${info.batteryPct}%',
                                                          style: const TextStyle(
                                                            color: Color(0xCCFFFFFF),
                                                            fontSize: 11,
                                                            fontFeatures: [
                                                              FontFeature.tabularFigures()
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          // Isolated sleep timer pill
                                          ValueListenableBuilder<int>(
                                            valueListenable: _sleepRemainingNotifier,
                                            builder: (_, remSecs, __) {
                                              if (remSecs <= 0 && !_sleepAfterEpisode) {
                                                return const SizedBox.shrink();
                                              }
                                              return Padding(
                                                padding: const EdgeInsets.only(right: 6),
                                                child: _DeckPillButton(
                                                  label: _sleepAfterEpisode
                                                      ? '本集后休眠'
                                                      : '休眠 ${_fmtTime(remSecs.toDouble())}',
                                                  active: true,
                                                  onTap: _openMoreToolsSheet,
                                                ),
                                              );
                                            },
                                          ),
                                          if (size.width >= 460)
                                            Tooltip(
                                              message: _hwDecodeEnabled
                                                  ? '当前硬件解码，点击切至软解'
                                                  : '当前软件解码，点击切至硬解',
                                              child: _DeckPillButton(
                                                label: _hwDecodeEnabled ? 'HW' : 'SW',
                                                active: _hwDecodeEnabled,
                                                onTap: _toggleHwDecode,
                                              ),
                                            ),
                                          if (_isDesktop && wide) ...[
                                            const SizedBox(width: 6),
                                            _CircleHudButton(
                                              icon: _alwaysOnTop
                                                  ? Icons.push_pin_rounded
                                                  : Icons.push_pin_outlined,
                                              active: _alwaysOnTop,
                                              tooltip: _alwaysOnTop ? '取消置顶 (T)' : '窗口置顶 (T)',
                                              onTap: _toggleAlwaysOnTop,
                                            ),
                                          ],
                                          if (widget.appState.prefs.enablePip &&
                                              NativePlaybackChannel.supportsNativePip) ...[
                                            const SizedBox(width: 6),
                                            _CircleHudButton(
                                              icon: Icons.picture_in_picture_alt_rounded,
                                              tooltip: '画中画',
                                              onTap: _enterPipSafely,
                                            ),
                                          ],
                                          const SizedBox(width: 6),
                                          _CircleHudButton(
                                            icon: Icons.lock_outline_rounded,
                                            tooltip: '锁屏防误触 (L)',
                                            onTap: _toggleScreenLock,
                                          ),
                                          const SizedBox(width: 6),
                                          _CircleHudButton(
                                            icon: Icons.more_horiz_rounded,
                                            tooltip: '更多工具（比例 / 画面 / 参数 / 章节 / 定时 / 色彩）',
                                            onTap: _openMoreToolsSheet,
                                          ),
                                        ],
                                      ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // Bottom Cinema Control Island (follows active skin & Liquid Glass; compact 2-row deck!)
                              Positioned(
                                left: (wide ? 24 : 12) + tvPadX,
                                right: (wide ? 24 : 12) + tvPadX,
                                bottom: MediaQuery.paddingOf(context).bottom + (wide ? 18 : 10) + tvPadY,
                                child: AnimatedSlide(
                                  offset: osdInteractive ? Offset.zero : const Offset(0, 0.22),
                                  duration: const Duration(milliseconds: 260),
                                  curve: VedroTheme.easeOut,
                                  child: MouseRegion(
                                    onEnter: (_) {
                                      _hoveringChrome = true;
                                      _hideControlsTimer?.cancel();
                                    },
                                    onExit: (_) {
                                      _hoveringChrome = false;
                                      _scheduleHideControls();
                                    },
                                    child: Center(
                                      child: Builder(
                                        builder: (context) {
                                          final skin = VedroSkin.of(context);
                                          final osd = skin.osdStyle;
                                          final isFullGradient = osd == 'cinema_gradient';
                                          final isMinimalGlass = osd == 'minimal_glass';
                                          final useLiquid = osdInteractive && skin.isLiquidGlass;
                                          final islandBg = skin.isLiquidGlass
                                              ? VedroLiquidGlassShader.liquidFillColor(
                                                  isLight: skin.isLight,
                                                  canvas: skin.canvas,
                                                  surface: skin.surface,
                                                  surface2: skin.surface2,
                                                  density: VedroGlassDensity.chrome,
                                                )
                                              : (isFullGradient
                                                  ? Color.lerp(skin.canvas, skin.surface, 0.22)!
                                                      .withValues(alpha: skin.isLight ? 0.92 : 0.90)
                                                  : (isMinimalGlass
                                                      ? Color.lerp(skin.glass, skin.accent, 0.08)!
                                                          .withValues(alpha: skin.isLight ? 0.88 : 0.84)
                                                      : skin.glassStrong.withValues(
                                                          alpha: skin.isLight ? 0.90 : 0.88,
                                                        )));
                                          final islandBorder = isMinimalGlass
                                              ? skin.accent.withValues(alpha: 0.36)
                                              : skin.borderStrong;
                                          final playBg = skin.ctaStyle == 'contrast'
                                              ? skin.fg
                                              : skin.accent;
                                          final playFg = VedroTheme.highContrastOn(playBg);
                                          final islandRadius = isFullGradient
                                              ? 14.0
                                              : (isMinimalGlass
                                                  ? 24.0
                                                  : skin.cardRadius.clamp(14.0, 24.0));
                                          return ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth: isFullGradient
                                                  ? 1440
                                                  : (isMinimalGlass ? 880 : 980),
                                            ),
                                            child: GlassSurface(
                                              borderRadius: islandRadius,
                                              enableBlur: useLiquid,
                                              color: useLiquid ? null : islandBg,
                                              borderColor: islandBorder,
                                              padding: EdgeInsets.fromLTRB(
                                                wide ? 16 : 12,
                                                8,
                                                wide ? 16 : 12,
                                                8,
                                              ),
                                              child: LayoutBuilder(
                                                builder: (context, deckConstraints) {
                                                  final deckW = deckConstraints.maxWidth;
                                                  final showDesktopVol = _isDesktop && deckW >= 740;
                                                  final showStepIcons = deckW >= 430;
                                                  final playSize = wide ? 38.0 : 35.0;

                                                  final playBtn = PressableScale(
                                                    focusNode: _playPauseFocusNode,
                                                    onTap: _togglePause,
                                                    hoverScale: 1.07,
                                                    pressScale: 0.9,
                                                    borderRadius: BorderRadius.circular(999),
                                                    child: Container(
                                                      width: playSize,
                                                      height: playSize,
                                                      decoration: BoxDecoration(
                                                        color: playBg,
                                                        shape: BoxShape.circle,
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: Colors.black.withValues(
                                                              alpha: skin.isLight ? 0.16 : 0.38,
                                                            ),
                                                            blurRadius: 10,
                                                            offset: const Offset(0, 3),
                                                          ),
                                                        ],
                                                      ),
                                                      child: AnimatedSwitcher(
                                                        duration:
                                                            const Duration(milliseconds: 180),
                                                        switchInCurve: VedroTheme.springCurve,
                                                        transitionBuilder: (child, anim) =>
                                                            ScaleTransition(
                                                          scale: Tween<double>(
                                                            begin: 0.72,
                                                            end: 1.0,
                                                          ).animate(anim),
                                                          child: FadeTransition(
                                                            opacity: anim,
                                                            child: child,
                                                          ),
                                                        ),
                                                        child: Icon(
                                                          _paused
                                                              ? Icons.play_arrow_rounded
                                                              : Icons.pause_rounded,
                                                          key: ValueKey<bool>(_paused),
                                                          size: wide ? 23 : 21,
                                                          color: playFg,
                                                        ),
                                                      ),
                                                    ),
                                                  );

                                                  final transportCluster = Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      if (_prevEpisode != null) ...[
                                                        _DeckIconButton(
                                                          icon: Icons.skip_previous_rounded,
                                                          tooltip: '上一集 (P)',
                                                          onTap: () => _switchEpisode(_prevEpisode!),
                                                        ),
                                                        const SizedBox(width: 2),
                                                      ],
                                                      if (showStepIcons) ...[
                                                        _DeckIconButton(
                                                          icon: _seekBackIcon(step),
                                                          tooltip: '后退 ${step}s',
                                                          onTap: () =>
                                                              _seekBy(-step.toDouble(), showHud: true),
                                                        ),
                                                        const SizedBox(width: 4),
                                                      ],
                                                      playBtn,
                                                      if (showStepIcons) ...[
                                                        const SizedBox(width: 4),
                                                        _DeckIconButton(
                                                          icon: _seekFwdIcon(step),
                                                          tooltip: '前进 ${step}s',
                                                          onTap: () =>
                                                              _seekBy(step.toDouble(), showHud: true),
                                                        ),
                                                      ],
                                                      if (_nextEpisode != null) ...[
                                                        const SizedBox(width: 2),
                                                        _DeckIconButton(
                                                          icon: Icons.skip_next_rounded,
                                                          tooltip: '下一集 (N)',
                                                          onTap: () => _switchEpisode(_nextEpisode!),
                                                        ),
                                                      ],
                                                    ],
                                                  );

                                                  final screenToggleBtn = _isDesktop
                                                      ? _DeckIconButton(
                                                          icon: _isFullscreen
                                                              ? Icons.fullscreen_exit_rounded
                                                              : Icons.fullscreen_rounded,
                                                          tooltip: _isFullscreen
                                                              ? '退出全屏 (F / Esc)'
                                                              : '进入全屏 (F / 双击画面)',
                                                          onTap: _toggleFullscreen,
                                                        )
                                                      : (_isMobile
                                                          ? _DeckIconButton(
                                                              icon: Icons.screen_rotation_rounded,
                                                              tooltip: _isLandscapeOrientation
                                                                  ? '切换竖屏'
                                                                  : '切换横屏',
                                                              onTap: _toggleMobileOrientation,
                                                            )
                                                          : const SizedBox.shrink());

                                                  final quickPills = Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      _DeckPillButton(
                                                        key: const ValueKey('player-speed-pill'),
                                                        label: _fmtSpeed(_speed),
                                                        active: (_speed - 1.0).abs() > 0.01,
                                                        themed: true,
                                                        compact: true,
                                                        onTap: _openSpeedSheet,
                                                      ),
                                                      if (_episodes.length > 1) ...[
                                                        const SizedBox(width: 5),
                                                        _DeckPillButton(
                                                          label: '选集',
                                                          themed: true,
                                                          compact: true,
                                                          onTap: () {
                                                            _setPlayerState(
                                                                () => _showEpisodeDrawer = true);
                                                            WidgetsBinding.instance
                                                                .addPostFrameCallback((_) {
                                                              if (mounted && _showEpisodeDrawer) {
                                                                if (_drawerActiveEpFocusNode
                                                                    .canRequestFocus) {
                                                                  _drawerActiveEpFocusNode
                                                                      .requestFocus();
                                                                } else {
                                                                  _drawerCloseFocusNode
                                                                      .requestFocus();
                                                                }
                                                              }
                                                            });
                                                          },
                                                        ),
                                                      ],
                                                      const SizedBox(width: 5),
                                                      _DeckPillButton(
                                                        label: _danmakuEnabled &&
                                                                _danmakuComments.isNotEmpty
                                                            ? '弹幕 ${_danmakuComments.length}'
                                                            : '弹幕',
                                                        active: _danmakuEnabled,
                                                        themed: true,
                                                        compact: true,
                                                        onTap: _openDanmakuSheet,
                                                      ),
                                                      const SizedBox(width: 5),
                                                      _DeckPillButton(
                                                        label: '字幕',
                                                        themed: true,
                                                        compact: true,
                                                        onTap: _openSubtitleSheet,
                                                      ),
                                                      const SizedBox(width: 5),
                                                      _DeckPillButton(
                                                        label: '音轨',
                                                        themed: true,
                                                        compact: true,
                                                        onTap: _openAudioSheet,
                                                      ),
                                                      const SizedBox(width: 5),
                                                      _DeckPillButton(
                                                        key: const ValueKey('player-beauty-pill'),
                                                        label: !_beautyParams.isActive
                                                            ? '美颜'
                                                            : '美颜·${BeautyFilterPreset.displayLabelFor(_beautyPreset, _beautyParams)}',
                                                        active: _beautyParams.isActive,
                                                        themed: true,
                                                        compact: true,
                                                        onTap: _openBeautyFilterSheet,
                                                      ),
                                                      if ((_prepared?.allSources.length ?? 0) > 1) ...[
                                                        const SizedBox(width: 5),
                                                        _DeckPillButton(
                                                          label: '版本',
                                                          themed: true,
                                                          compact: true,
                                                          onTap: _openVersionSheet,
                                                        ),
                                                      ],
                                                    ],
                                                  );

                                                  return Column(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      // Row 1: Sleek Cinema Scrub Bar (isolated RepaintBoundary + ValueNotifier)
                                                      RepaintBoundary(
                                                        child: ListenableBuilder(
                                                          listenable: Listenable.merge([
                                                            _positionNotifier,
                                                            _bufferedNotifier,
                                                            _scrubTargetNotifier,
                                                          ]),
                                                          builder: (_, __) => _CinemaScrubBar(
                                                            positionSecs: _scrubbing
                                                                ? _scrubTargetNotifier.value
                                                                : _positionNotifier.value,
                                                            bufferedSecs: _bufferedNotifier.value,
                                                            durationSecs: _durationSecs,
                                                            segments: _segments,
                                                            chapters: _chapters,
                                                            showRemaining: _showRemaining,
                                                            seekStepSecs: step.toDouble(),
                                                            fmtTime: _fmtTime,
                                                            onToggleRemaining: () => _setPlayerState(() =>
                                                                _showRemaining = !_showRemaining),
                                                            onTogglePlayPause: _togglePause,
                                                            onScrubStart: () =>
                                                                _hideControlsTimer?.cancel(),
                                                            onScrubUpdate: (secs) {
                                                              _positionSecs = secs;
                                                              _positionNotifier.value = secs;
                                                            },
                                                            onScrubEnd: (secs) {
                                                              _seekTo(secs);
                                                              _scheduleHideControls();
                                                            },
                                                            onDpadStep: (delta) {
                                                              _accumulateKeySeek(delta);
                                                              _scheduleHideControls();
                                                            },
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 6),
                                                      // Row 2: Single compact button row (Transport + optional Volume + Quick Pills + Screen Toggle)
                                                      Row(
                                                        children: [
                                                          transportCluster,
                                                          if (showDesktopVol) ...[
                                                            const SizedBox(width: 8),
                                                            ValueListenableBuilder<double>(
                                                              valueListenable: _volumeNotifier,
                                                              builder: (_, liveVol, __) => Row(
                                                                mainAxisSize: MainAxisSize.min,
                                                                children: [
                                                                  _DeckIconButton(
                                                                    icon: liveVol <= 0.1
                                                                        ? Icons.volume_off_rounded
                                                                        : (liveVol < 50
                                                                            ? Icons.volume_down_rounded
                                                                            : Icons.volume_up_rounded),
                                                                    tooltip: '静音 (M)',
                                                                    onTap: _toggleMute,
                                                                  ),
                                                                  const SizedBox(width: 2),
                                                                  SizedBox(
                                                                    width: 68,
                                                                    child: _MiniVolumeBar(
                                                                      value: (liveVol / _maxVolume)
                                                                          .clamp(0.0, 1.0),
                                                                      onChanged: (ratio) =>
                                                                          _setVolume(ratio * _maxVolume),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                          const SizedBox(width: 8),
                                                          Expanded(
                                                            child: Align(
                                                              alignment: Alignment.centerRight,
                                                              child: SingleChildScrollView(
                                                                scrollDirection: Axis.horizontal,
                                                                child: quickPills,
                                                              ),
                                                            ),
                                                          ),
                                                          if (_isDesktop || _isMobile) ...[
                                                            const SizedBox(width: 4),
                                                            screenToggleBtn,
                                                          ],
                                                        ],
                                                      ),
                                                    ],
                                                  );
                                                },
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                  // Click-outside scrim when Episode Drawer is open
                  if (_showEpisodeDrawer && !_inPipMode)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () {
                          _setPlayerState(() => _showEpisodeDrawer = false);
                          _scheduleHideControls();
                          if (_isTv && _controlsVisible) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted && _playPauseFocusNode.canRequestFocus) {
                                _playPauseFocusNode.requestFocus();
                              }
                            });
                          }
                        },
                        child: Container(color: const Color(0x66000000)),
                      ),
                    ),

                  // Slide-out high-contrast Episode Drawer (unmounted children & ExcludeFocus when hidden!)
                  if (_showEpisodeDrawer && !_inPipMode)
                    Positioned(
                      top: topPad + (isMac ? 42 : 16) + tvPadY,
                      bottom: 16 + tvPadY,
                      right: 16 + tvPadX,
                      width: (size.width - 32).clamp(260.0, 356.0),
                      child: FocusTraversalGroup(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xF8151720),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFF2D3142), width: 1.0),
                            boxShadow: const [
                              BoxShadow(color: Color(0xB8000000), blurRadius: 32, offset: Offset(0, 12)),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Builder(
                            builder: (ctx) {
                              final accent = Theme.of(ctx).colorScheme.secondary;
                              final ordered = _epDrawerDescending
                                  ? _episodes.reversed.toList()
                                  : _episodes;
                              final chunkSize = ordered.length >= 400 ? 100 : 50;
                              final rangeCount =
                                  ordered.isEmpty ? 0 : ((ordered.length - 1) ~/ chunkSize) + 1;
                              final safeRangeIdx =
                                  rangeCount == 0 ? 0 : _epDrawerRangeIdx.clamp(0, rangeCount - 1);
                              final start = safeRangeIdx * chunkSize;
                              final end = (start + chunkSize).clamp(0, ordered.length);
                              final visibleEps =
                                  rangeCount > 1 ? ordered.sublist(start, end) : ordered;

                              return Column(
                                children: [
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      16,
                                      (isWin && !_isFullscreen) ? 38 : 10,
                                      8,
                                      8,
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          '选集 (${_episodes.length})',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const Spacer(),
                                        IconButton(
                                          tooltip: _epDrawerDescending ? '切换正序' : '切换倒序',
                                          visualDensity: VisualDensity.compact,
                                          icon: Icon(
                                            _epDrawerDescending
                                                ? Icons.arrow_upward_rounded
                                                : Icons.arrow_downward_rounded,
                                            size: 17,
                                            color: VedroTheme.fg2,
                                          ),
                                          onPressed: () => _setPlayerState(() {
                                            _epDrawerDescending = !_epDrawerDescending;
                                            _epDrawerRangeIdx = 0;
                                          }),
                                        ),
                                        IconButton(
                                          tooltip: _epDrawerGrid ? '切换列表视图' : '切换数字网格',
                                          visualDensity: VisualDensity.compact,
                                          icon: Icon(
                                            _epDrawerGrid
                                                ? Icons.view_list_rounded
                                                : Icons.grid_view_rounded,
                                            size: 17,
                                            color: VedroTheme.fg2,
                                          ),
                                          onPressed: () =>
                                              _setPlayerState(() => _epDrawerGrid = !_epDrawerGrid),
                                        ),
                                        IconButton(
                                          focusNode: _drawerCloseFocusNode,
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(Icons.close_rounded,
                                              size: 18, color: VedroTheme.fg2),
                                          onPressed: () {
                                            _setPlayerState(() => _showEpisodeDrawer = false);
                                            _scheduleHideControls();
                                            if (_isTv && _controlsVisible) {
                                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                                if (mounted && _playPauseFocusNode.canRequestFocus) {
                                                  _playPauseFocusNode.requestFocus();
                                                }
                                              });
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (rangeCount > 1)
                                    SizedBox(
                                      height: 36,
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                                        itemCount: rangeCount,
                                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                                        itemBuilder: (_, rIdx) {
                                          final rStart = rIdx * chunkSize;
                                          final rEnd = (rStart + chunkSize).clamp(0, ordered.length);
                                          final firstNum =
                                              ordered[rStart].indexNumber ?? (rStart + 1);
                                          final lastNum =
                                              ordered[rEnd - 1].indexNumber ?? rEnd;
                                          final active = rIdx == safeRangeIdx;
                                          return PressableScale(
                                            onTap: () => _setPlayerState(() => _epDrawerRangeIdx = rIdx),
                                            hoverScale: 1.03,
                                            pressScale: 0.95,
                                            borderRadius: BorderRadius.circular(8),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: active
                                                    ? accent
                                                    : const Color(0xFF1F2230),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                '$firstNum-$lastNum',
                                                style: TextStyle(
                                                  color: active
                                                      ? const Color(0xFF0B0B0D)
                                                      : const Color(0xFFD5D9E6),
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                  fontFeatures: const [FontFeature.tabularFigures()],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  const Divider(height: 1, color: Color(0xFF262936)),
                                  Expanded(
                                    child: _epDrawerGrid
                                        ? GridView.builder(
                                            padding: const EdgeInsets.all(12),
                                            gridDelegate:
                                                const SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 5,
                                              mainAxisSpacing: 8,
                                              crossAxisSpacing: 8,
                                              childAspectRatio: 1.25,
                                            ),
                                            itemCount: visibleEps.length,
                                            itemBuilder: (_, idx) {
                                              final ep = visibleEps[idx];
                                              final playing = ep.id == _currentItem.id;
                                              final numLabel = '${ep.indexNumber ?? (start + idx + 1)}';
                                              return Tooltip(
                                                message: ep.displayName,
                                                child: PressableScale(
                                                  focusNode: playing ? _drawerActiveEpFocusNode : null,
                                                  onTap: () => _switchEpisode(ep),
                                                  hoverScale: 1.04,
                                                  pressScale: 0.94,
                                                  borderRadius: BorderRadius.circular(9),
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: playing
                                                          ? accent
                                                          : const Color(0xFF1F2230),
                                                      borderRadius: BorderRadius.circular(9),
                                                      border: Border.all(
                                                        color: playing
                                                            ? accent
                                                            : const Color(0xFF2F3346),
                                                        width: 0.9,
                                                      ),
                                                    ),
                                                    alignment: Alignment.center,
                                                    child: Text(
                                                      numLabel,
                                                      style: TextStyle(
                                                        color: playing
                                                            ? const Color(0xFF0B0B0D)
                                                            : (ep.played
                                                                ? const Color(0xFF8B90A4)
                                                                : Colors.white),
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.w600,
                                                        fontFeatures: const [
                                                          FontFeature.tabularFigures(),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          )
                                        : ListView.separated(
                                            padding: const EdgeInsets.all(12),
                                            itemCount: visibleEps.length,
                                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                                            itemBuilder: (_, idx) {
                                              final ep = visibleEps[idx];
                                              final playing = ep.id == _currentItem.id;
                                              return PressableScale(
                                                focusNode: playing ? _drawerActiveEpFocusNode : null,
                                                onTap: () => _switchEpisode(ep),
                                                hoverScale: 1.01,
                                                pressScale: 0.97,
                                                borderRadius: BorderRadius.circular(11),
                                                child: Container(
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color: playing
                                                        ? const Color(0xFF1F2B44)
                                                        : const Color(0xFF1D202C),
                                                    borderRadius: BorderRadius.circular(11),
                                                    border: Border.all(
                                                      color: playing
                                                          ? accent
                                                          : const Color(0xFF2B2F40),
                                                      width: playing ? 1.2 : 0.8,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      SizedBox(
                                                        width: 84,
                                                        child: AspectRatio(
                                                          aspectRatio: 16 / 9,
                                                          child: ClipRRect(
                                                            borderRadius: BorderRadius.circular(6),
                                                            child: VedroArtwork(
                                                              item: ep,
                                                              appState: widget.appState,
                                                              landscape: true,
                                                              width: 240,
                                                              displayWidth: 84,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment.start,
                                                          children: [
                                                            Text(
                                                              '${ep.indexNumber ?? (start + idx + 1)}. ${ep.displayName}',
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: TextStyle(
                                                                color: playing
                                                                    ? Colors.white
                                                                    : VedroTheme.fg,
                                                                fontSize: 13,
                                                                fontWeight: playing
                                                                    ? FontWeight.w600
                                                                    : FontWeight.w500,
                                                              ),
                                                            ),
                                                            if (fmtDurationTicks(ep.runTimeTicks)
                                                                .isNotEmpty)
                                                              Text(
                                                                fmtDurationTicks(ep.runTimeTicks),
                                                                style: const TextStyle(
                                                                  color: VedroTheme.fg3,
                                                                  fontSize: 11.5,
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildGestureHudContent(String mode, String feedbackText, double liveValue) {
    if (mode == 'seek_feedback') {
      return Text(
        feedbackText,
        style: const TextStyle(
          color: VedroTheme.fg,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      );
    }
    final isBrightness = mode == 'brightness';
    final progress = isBrightness
        ? liveValue.clamp(0.0, 1.0)
        : (liveValue / _maxVolume).clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isBrightness
              ? Icons.brightness_6_rounded
              : (liveValue <= 0.1 ? Icons.volume_off_rounded : Icons.volume_up_rounded),
          size: 18,
          color: VedroTheme.fg,
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 112,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: const Color(0x33FFFFFF),
              color: VedroTheme.fg,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 38,
          child: Text(
            isBrightness ? '${(liveValue.clamp(0.0, 1.0) * 100).round()}%' : '${liveValue.round()}%',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: VedroTheme.fg2,
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
