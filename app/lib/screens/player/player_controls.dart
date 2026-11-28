part of '../player_screen.dart';

/// Playback transport actions, gestures, keyboard shortcuts, HUD timers & time formatters.
extension _PlayerControlsExt on _PlayerScreenState {
  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    if (_paused ||
        _loading ||
        _showEpisodeDrawer ||
        _hoveringChrome ||
        _sheetOpen ||
        _upNextCountdown > 0 ||
        _hasEndedReplay) {
      return;
    }
    final delayMs = _isTv ? 6000 : 3400;
    _hideControlsTimer = Timer(Duration(milliseconds: delayMs), () {
      if (mounted &&
          !_paused &&
          !_scrubbing &&
          !_showEpisodeDrawer &&
          !_hoveringChrome &&
          !_sheetOpen &&
          _upNextCountdown == 0 &&
          !_hasEndedReplay) {
        _setPlayerState(() => _controlsVisible = false);
        if (_isTv && !_focusNode.hasPrimaryFocus) {
          _focusNode.requestFocus();
        }
      }
    });
  }

  Future<T?> _openPlayerSheet<T>({required WidgetBuilder builder}) {
    _hideControlsTimer?.cancel();
    _sheetOpen = true;
    return showGlassSheet<T>(
      context: context,
      forceDark: true,
      builder: builder,
    ).whenComplete(() {
      _sheetOpen = false;
      if (!mounted || _disposed) return;
      _scheduleHideControls();
      if (_isTv && _controlsVisible && !_showEpisodeDrawer && !_screenLocked) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _controlsVisible && _playPauseFocusNode.canRequestFocus) {
            _playPauseFocusNode.requestFocus();
          }
        });
      }
    });
  }

  void _revealControls({bool focusPlayButton = false}) {
    _positionNotifier.value = _positionSecs;
    _bufferedNotifier.value = _bufferedSecs;
    if (!_controlsVisible) {
      _setPlayerState(() => _controlsVisible = true);
    }
    if (focusPlayButton) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controlsVisible && !_showEpisodeDrawer && !_screenLocked) {
          _playPauseFocusNode.requestFocus();
        }
      });
    }
    _scheduleHideControls();
  }

  void _flashGestureHud(String mode, {String text = '', double? value}) {
    if (_disposed) return;
    _gestureHudTimer?.cancel();
    final liveVal = value ??
        (mode == 'brightness'
            ? _brightness
            : (mode == 'volume' ? _volume : _gestureHudNotifier.value.value));
    _gestureHudNotifier.value = (
      mode: mode,
      text: text.isNotEmpty ? text : _gestureHudNotifier.value.text,
      value: liveVal,
      seq: ++_gestureHudSeq,
    );
    _gestureHudTimer = Timer(const Duration(milliseconds: 950), () {
      if (!_disposed && mounted) {
        _gestureHudNotifier.value = (mode: null, text: '', value: 0.0, seq: ++_gestureHudSeq);
      }
    });
  }

  Future<void> _requestExit() async {
    if (widget.appState.prefs.confirmExitPlayer && !_paused && _error == null) {
      final ok = await showVedroDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('退出播放？'),
          content: const Text('当前播放进度会自动保存。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('继续观看')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _togglePause() async {
    await _player.playOrPause();
    if (!mounted || _disposed) return;
    _revealControls();
  }

  void _toggleMute() {
    if (_muted || _volume <= 0.1) {
      final restored = _preMuteVolume > 5 ? _preMuteVolume : 80.0;
      _setPlayerState(() {
        _muted = false;
        _volume = restored;
      });
      unawaited(_applyVolumeToEngine(restored));
    } else {
      _preMuteVolume = _volume;
      _setPlayerState(() {
        _muted = true;
        _volume = 0;
      });
      unawaited(_applyVolumeToEngine(0));
    }
    _schedulePersistPlayerPrefs();
    _flashGestureHud('volume');
  }

  void _setVolume(double v) {
    final clamped = v.clamp(0.0, _maxVolume);
    _setPlayerState(() {
      _volume = clamped;
      _muted = clamped <= 0.1;
    });
    unawaited(_applyVolumeToEngine(clamped));
    _schedulePersistPlayerPrefs();
  }

  void _setBrightness(double v) {
    final clamped = v.clamp(0.03, 1.0);
    _brightnessUserAdjusted = true;
    if (_usingNativeBrightness) {
      _brightness = clamped;
      unawaited(NativePlaybackChannel.setScreenBrightness(clamped));
    } else {
      _setPlayerState(() => _brightness = clamped);
    }
    _schedulePersistPlayerPrefs();
  }

  void _accumulateKeySeek(double delta) {
    _accumulatedKeySeekDelta += delta;
    final sign = _accumulatedKeySeekDelta >= 0 ? '+' : '';
    final previewTarget = (_positionSecs + _accumulatedKeySeekDelta)
        .clamp(0.0, _durationSecs > 0 ? _durationSecs : 86400.0);
    _flashGestureHud(
      'seek_feedback',
      text: '$sign${_accumulatedKeySeekDelta.round()}s (${_fmtTime(previewTarget)})',
    );
    _keySeekFlushTimer?.cancel();
    _keySeekFlushTimer = Timer(const Duration(milliseconds: 220), () {
      if (!mounted || _disposed) return;
      final d = _accumulatedKeySeekDelta;
      _accumulatedKeySeekDelta = 0.0;
      if (d.abs() > 0.01) {
        unawaited(_seekBy(d));
      }
    });
  }

  Future<void> _seekTo(double secs) async {
    final target = secs.clamp(0.0, _durationSecs > 0 ? _durationSecs : 86400.0);
    await _player.seek(Duration(milliseconds: (target * 1000).round()));
    if (!mounted || _disposed) return;
    _positionSecs = target;
    _positionNotifier.value = target;
    _syncNowPlaying(force: true);
  }

  Future<void> _seekBy(double delta, {bool showHud = false}) async {
    await _seekTo(_positionSecs + delta);
    if (!mounted || _disposed) return;
    if (showHud) {
      HapticFeedback.selectionClick();
      final sign = delta >= 0 ? '+' : '';
      _flashGestureHud('seek_feedback', text: '$sign${delta.round()}s');
    }
  }

  Future<void> _setSpeed(double s) async {
    final clamped = s.clamp(0.25, 4.0);
    await _player.setRate(clamped);
    if (mounted && !_disposed) {
      _setPlayerState(() => _speed = clamped);
      _syncNowPlaying(force: true);
    }
    if (!_isSpeedBoost) _schedulePersistPlayerPrefs();
  }

  Future<void> _applyAspectMode(String mode) async {
    if (!mounted || _disposed) return;
    _setPlayerState(() => _aspectMode = mode);
    _schedulePersistPlayerPrefs();
    switch (mode) {
      case 'fill':
        await _applyMpvProperty('keepaspect', 'yes');
        await _applyMpvProperty('video-aspect-override', '-1');
        await _applyMpvProperty('panscan', '1.0');
        break;
      case 'stretch':
        await _applyMpvProperty('panscan', '0.0');
        await _applyMpvProperty('video-aspect-override', '-1');
        await _applyMpvProperty('keepaspect', 'no');
        break;
      case '16:9':
        await _applyMpvProperty('keepaspect', 'yes');
        await _applyMpvProperty('panscan', '0.0');
        await _applyMpvProperty('video-aspect-override', '16:9');
        break;
      case '21:9':
        await _applyMpvProperty('keepaspect', 'yes');
        await _applyMpvProperty('panscan', '0.0');
        await _applyMpvProperty('video-aspect-override', '21:9');
        break;
      case '2.35:1':
        await _applyMpvProperty('keepaspect', 'yes');
        await _applyMpvProperty('panscan', '0.0');
        await _applyMpvProperty('video-aspect-override', '2.35');
        break;
      case '4:3':
        await _applyMpvProperty('keepaspect', 'yes');
        await _applyMpvProperty('panscan', '0.0');
        await _applyMpvProperty('video-aspect-override', '4:3');
        break;
      default:
        await _applyMpvProperty('keepaspect', 'yes');
        await _applyMpvProperty('panscan', '0.0');
        await _applyMpvProperty('video-aspect-override', '-1');
        break;
    }
  }

  void _handleDoubleTap(double width) {
    if (_screenLocked) return;
    final step = widget.appState.prefs.seekStepSecs.toDouble();
    final ratio = width > 0 ? _lastTapDownPos.dx / width : 0.5;
    if (_isDesktop) {
      // Classic IINA / Infuse / PotPlayer desktop behavior: double-click toggles native Fullscreen!
      _toggleFullscreen();
      return;
    }
    if (ratio < 0.35) {
      _seekBy(-step, showHud: true);
    } else if (ratio > 0.65) {
      _seekBy(step, showHud: true);
    } else {
      _togglePause();
    }
  }

  void _handleBackNavigation() {
    if (_screenLocked) {
      _revealLockIconBriefly();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _screenLocked) _unlockFocusNode.requestFocus();
      });
      _flashGestureHud('seek_feedback', text: '屏幕已锁定，请先解锁');
      return;
    }
    if (_showEpisodeDrawer) {
      _setPlayerState(() => _showEpisodeDrawer = false);
      _scheduleHideControls();
      if (_isTv && _controlsVisible) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _controlsVisible && _playPauseFocusNode.canRequestFocus) {
            _playPauseFocusNode.requestFocus();
          }
        });
      }
      return;
    }
    if (_upNextCountdown > 0) {
      final atEnd = _durationSecs > 0 && _positionSecs >= _durationSecs - 2.0;
      _setPlayerState(() {
        _cancelUpNextCountdown();
        if (atEnd) _hasEndedReplay = true;
      });
      return;
    }
    if (_isTv && _controlsVisible && _error == null && !_hasEndedReplay) {
      _hideControlsTimer?.cancel();
      _setPlayerState(() => _controlsVisible = false);
      _focusNode.requestFocus();
      return;
    }
    if (_isDesktop && _isFullscreen) {
      _toggleFullscreen();
      return;
    }
    unawaited(_requestExit());
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent ev) {
    if (ev is! KeyDownEvent && ev is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = ev.logicalKey;
    final isRepeat = ev is KeyRepeatEvent;
    final step = widget.appState.prefs.seekStepSecs.toDouble();

    // Never intercept typing inside a TextField (e.g. Danmaku search box)
    final focusedWidget = FocusManager.instance.primaryFocus?.context?.widget;
    if (focusedWidget is EditableText &&
        key != LogicalKeyboardKey.escape &&
        key != LogicalKeyboardKey.goBack) {
      return KeyEventResult.ignored;
    }

    // 1. Hardware media keys work in every state (except when screen-locked)
    if (!_screenLocked) {
      if (key == LogicalKeyboardKey.mediaPlayPause) {
        if (!isRepeat) unawaited(_togglePause());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaPlay) {
        if (!isRepeat) {
          unawaited(_player.play());
          _revealControls();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaPause) {
        if (!isRepeat) {
          unawaited(_player.pause());
          _revealControls();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaStop) {
        if (!isRepeat) unawaited(_requestExit());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaFastForward) {
        _accumulateKeySeek(step);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaRewind) {
        _accumulateKeySeek(-step);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaTrackNext && _nextEpisode != null) {
        if (!isRepeat) unawaited(_switchEpisode(_nextEpisode!));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaTrackPrevious) {
        final idx = _currentEpisodeIndex;
        if (!isRepeat && idx > 0) {
          unawaited(_switchEpisode(_episodes[idx - 1]));
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.audioVolumeMute) {
        if (!isRepeat) _toggleMute();
        return KeyEventResult.handled;
      }
    }

    // 2. Back / Escape always routed through state-aware back handler
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (!isRepeat) _handleBackNavigation();
      return KeyEventResult.handled;
    }

    // 3. Screen-locked mode: reveal unlock pill & direct focus to it
    if (_screenLocked) {
      if (!isRepeat) {
        _revealLockIconBriefly();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _screenLocked) _unlockFocusNode.requestFocus();
        });
      }
      return key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter
          ? KeyEventResult.ignored
          : KeyEventResult.handled;
    }

    // 4. Episode Drawer or interactive overlay (Up-Next / Replay / Error) open:
    // Let Flutter focus traversal drive D-Pad/Enter across overlay buttons naturally!
    if (_showEpisodeDrawer) {
      return KeyEventResult.ignored;
    }
    final isSelect = key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA ||
        (_isTv && (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter));
    final isArrow = key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;

    if ((_upNextCountdown > 0 || _hasEndedReplay || _error != null) && (isArrow || isSelect)) {
      if (_focusNode.hasPrimaryFocus) {
        if (_error != null && _errorRetryFocusNode.canRequestFocus) {
          _errorRetryFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (_upNextCountdown > 0 && _upNextPlayFocusNode.canRequestFocus) {
          _upNextPlayFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (_hasEndedReplay && _replayFocusNode.canRequestFocus) {
          _replayFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    }

    // 5. TV / D-Pad Remote Mode when OSD controls are visible:
    // Let Up/Down/Left/Right/OK navigate OSD buttons & Scrub Bar, while keeping OSD alive!
    if (_controlsVisible && _isTv && (isArrow || isSelect)) {
      _scheduleHideControls();
      if (_focusNode.hasPrimaryFocus) {
        // Focus hasn't entered OSD buttons yet -> move focus straight to Play/Pause
        _playPauseFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // 6. OSD hidden (or Desktop shortcuts): direct cinema transport controls
    if (isSelect) {
      if (!isRepeat) {
        if (_controlsVisible && !_focusNode.hasPrimaryFocus) {
          return KeyEventResult.ignored;
        }
        unawaited(_togglePause());
        _revealControls(focusPlayButton: _isTv);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      if (!isRepeat) unawaited(_togglePause());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _accumulateKeySeek(step);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _accumulateKeySeek(-step);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (_isTv) {
        if (!isRepeat) _revealControls(focusPlayButton: true);
      } else {
        _setVolume(_volume + 5);
        _flashGestureHud('volume');
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_isTv) {
        if (!isRepeat) _revealControls(focusPlayButton: true);
      } else {
        _setVolume(_volume - 5);
        _flashGestureHud('volume');
      }
      return KeyEventResult.handled;
    }

    if (isRepeat) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.keyF ||
        key == LogicalKeyboardKey.f11 ||
        (!_isTv && key == LogicalKeyboardKey.enter && _focusNode.hasPrimaryFocus)) {
      unawaited(_toggleFullscreen());
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyT) {
      unawaited(_toggleAlwaysOnTop());
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyL) {
      _toggleScreenLock();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyC && _chapters.isNotEmpty) {
      _openChaptersSheet();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyH) {
      _openShortcutsDialog();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.period) {
      unawaited(_stepFrame(true));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.comma) {
      unawaited(_stepFrame(false));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyI) {
      _setPlayerState(() => _showStats = !_showStats);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyS) {
      unawaited(_takeScreenshot());
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyD) {
      final next = !_danmakuEnabled;
      _setPlayerState(() => _danmakuEnabled = next);
      if (next && _danmakuComments.isEmpty) unawaited(_loadDanmaku());
      _flashGestureHud('seek_feedback', text: next ? '弹幕已开启' : '弹幕已关闭');
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyR) {
      unawaited(_rotateVideo());
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyN && _nextEpisode != null) {
      unawaited(_switchEpisode(_nextEpisode!));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyP && _prevEpisode != null) {
      unawaited(_switchEpisode(_prevEpisode!));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.pageDown && _chapters.isNotEmpty) {
      unawaited(_jumpChapter(true));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.pageUp && _chapters.isNotEmpty) {
      unawaited(_jumpChapter(false));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.bracketRight) {
      unawaited(_setSpeed(_speed + 0.25));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.bracketLeft) {
      unawaited(_setSpeed(_speed - 0.25));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  IconData _seekBackIcon(int step) => switch (step) {
        5 => Icons.replay_5_rounded,
        30 => Icons.replay_30_rounded,
        _ => Icons.replay_10_rounded,
      };

  IconData _seekFwdIcon(int step) => switch (step) {
        5 => Icons.forward_5_rounded,
        30 => Icons.forward_30_rounded,
        _ => Icons.forward_10_rounded,
      };

  String _fmtTime(double secs) {
    final total = secs.isFinite && secs > 0 ? secs.floor() : 0;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    return h > 0
        ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _fmtDelta(double delta) {
    final sign = delta >= 0 ? '+' : '-';
    return '$sign${_fmtTime(delta.abs())}';
  }
}
