import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/preferences.dart';
import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import 'vedro_ui.dart';

/// Shared rate-limited PIN verification state (per `VedroAppState`), persisted across restarts
/// and backed by a monotonic `Stopwatch` so clock rollback cannot bypass lockout.
class PinLockoutController {
  PinLockoutController._(this._appState);

  static final Expando<PinLockoutController> _byState = Expando<PinLockoutController>('pinLockout');
  static const String _kvKey = 'pin_lockout_v1';

  static PinLockoutController forState(VedroAppState appState) {
    final existing = _byState[appState];
    if (existing != null) return existing;
    final ctrl = PinLockoutController._(appState);
    _byState[appState] = ctrl;
    unawaited(ctrl._loadPersisted());
    return ctrl;
  }

  final VedroAppState _appState;
  final Stopwatch _monotonic = Stopwatch();
  int failedAttempts = 0;
  int _lockoutDurationSecs = 0;
  int _lockoutUntilEpochMs = 0;

  int get remainingLockoutSecs {
    var remMono = 0;
    if (_monotonic.isRunning && _lockoutDurationSecs > 0) {
      remMono = _lockoutDurationSecs - _monotonic.elapsed.inSeconds;
      if (remMono <= 0) {
        _monotonic
          ..stop()
          ..reset();
        _lockoutDurationSecs = 0;
      }
    }
    var remWall = 0;
    if (_lockoutUntilEpochMs > 0) {
      final diffMs = _lockoutUntilEpochMs - DateTime.now().millisecondsSinceEpoch;
      if (diffMs > 0) {
        remWall = (diffMs / 1000).ceil();
      } else {
        _lockoutUntilEpochMs = 0;
      }
    }
    return remMono > remWall ? remMono : remWall;
  }

  ({bool ok, String? error, int lockoutSecs}) verify(String candidatePin, String storedHash) {
    final rem = remainingLockoutSecs;
    if (rem > 0) {
      return (ok: false, error: '尝试次数过多，请 $rem 秒后重试', lockoutSecs: rem);
    }
    if (verifyPasscode(candidatePin, storedHash)) {
      reset();
      return (ok: true, error: null, lockoutSecs: 0);
    }
    failedAttempts++;
    if (failedAttempts >= 5) {
      final penaltySecs = failedAttempts >= 10 ? 120 : 30;
      _lockoutDurationSecs = penaltySecs;
      _monotonic
        ..reset()
        ..start();
      _lockoutUntilEpochMs = DateTime.now().millisecondsSinceEpoch + penaltySecs * 1000;
      _persist();
      return (ok: false, error: '尝试次数过多，请 $penaltySecs 秒后重试', lockoutSecs: penaltySecs);
    }
    _persist();
    return (
      ok: false,
      error: '密码不正确，还可尝试 ${5 - failedAttempts} 次',
      lockoutSecs: 0,
    );
  }

  void reset() {
    failedAttempts = 0;
    _lockoutDurationSecs = 0;
    _lockoutUntilEpochMs = 0;
    _monotonic
      ..stop()
      ..reset();
    _persist();
  }

  Future<void> _loadPersisted() async {
    try {
      final resp = await _appState.core.invoke('get_kv', {'key': _kvKey});
      final val = resp is Map ? resp['value'] : resp;
      Map<dynamic, dynamic>? map;
      if (val is Map) {
        map = val;
      } else if (val is String && val.isNotEmpty) {
        final decoded = jsonDecode(val);
        if (decoded is Map) map = decoded;
      }
      if (map == null) return;
      final savedFails = (map['failed'] as num?)?.toInt() ?? 0;
      final savedUntil = (map['until_ms'] as num?)?.toInt() ?? 0;
      if (savedFails > failedAttempts) failedAttempts = savedFails;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (savedUntil > nowMs && savedUntil > _lockoutUntilEpochMs) {
        final remSecs = ((savedUntil - nowMs) / 1000).ceil().clamp(1, 300);
        _lockoutUntilEpochMs = nowMs + remSecs * 1000;
        _lockoutDurationSecs = remSecs;
        _monotonic
          ..reset()
          ..start();
      }
    } catch (_) {}
  }

  void _persist() {
    final payload = jsonEncode({
      'failed': failedAttempts,
      'until_ms': _lockoutUntilEpochMs,
    });
    unawaited(
      _appState.core
          .invoke('set_kv', {'key': _kvKey, 'value': payload})
          .catchError((_) => null),
    );
  }
}

/// Privacy Protection gate:
/// - Prompts for a 4-digit passcode on startup / resume past timeout ONLY when explicitly enabled.
/// - Wraps the entire Navigator in `MaterialApp.builder` so pushed routes (`PlayerScreen`, `DetailScreen`, dialogs)
///   are fully obscured when locked.
/// - Immediately draws a solid privacy curtain on `inactive`/`paused`/`hidden` ONLY when passcode lock is enabled.
/// - Fully supports D-Pad remote controls on Android TV (focusable keypad + Back blocking + zero background leak).
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.appState,
    required this.child,
  });

  /// Observable lock status so startup dialogs (e.g. update prompt) defer while locked.
  static final ValueNotifier<bool> isLockedNotifier = ValueNotifier<bool>(false);

  final VedroAppState appState;
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _locked = false;
  bool _obscuredInBackground = false;
  bool _checkedInitialLock = false;
  final Stopwatch _backgroundStopwatch = Stopwatch();
  final FocusNode _lockKeyboardNode = FocusNode(debugLabel: 'app_lock_keyboard');
  late final PinLockoutController _lockout;
  String _pin = '';
  String? _error;
  Timer? _lockoutTick;

  @override
  void initState() {
    super.initState();
    _lockout = PinLockoutController.forState(widget.appState);
    WidgetsBinding.instance.addObserver(this);
    widget.appState.addListener(_onStateChanged);
    _onStateChanged();
  }

  @override
  void dispose() {
    _lockoutTick?.cancel();
    _lockKeyboardNode.dispose();
    widget.appState.removeListener(_onStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    if (AppLockGate.isLockedNotifier.value) {
      AppLockGate.isLockedNotifier.value = false;
    }
    super.dispose();
  }

  void _setLocked(bool value) {
    _locked = value;
    if (AppLockGate.isLockedNotifier.value != value) {
      AppLockGate.isLockedNotifier.value = value;
    }
  }

  void _onStateChanged() {
    final p = widget.appState.prefs;
    if (widget.appState.isInitialized && !_checkedInitialLock) {
      _checkedInitialLock = true;
      if (p.passcodeEnabled && p.passcodeHash.isNotEmpty) {
        if (mounted) {
          setState(() => _setLocked(true));
        } else {
          _setLocked(true);
        }
      }
    }
    if ((!p.passcodeEnabled || p.passcodeHash.isEmpty) && (_locked || _obscuredInBackground)) {
      if (mounted) {
        setState(() {
          _setLocked(false);
          _obscuredInBackground = false;
        });
      } else {
        _setLocked(false);
        _obscuredInBackground = false;
      }
    }
  }

  @override
  Future<bool> didPopRoute() async {
    // Intercept hardware Back / Android TV Back button above MaterialApp's Navigator while locked.
    if (_locked || _obscuredInBackground) return true;
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final p = widget.appState.prefs;
    if (!p.passcodeEnabled || p.passcodeHash.isEmpty) {
      _backgroundStopwatch
        ..stop()
        ..reset();
      if (_obscuredInBackground && mounted) {
        setState(() => _obscuredInBackground = false);
      }
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (state != AppLifecycleState.inactive && !_backgroundStopwatch.isRunning) {
        _backgroundStopwatch
          ..reset()
          ..start();
      }
      if (!_obscuredInBackground && mounted) {
        setState(() => _obscuredInBackground = true);
      }
    } else if (state == AppLifecycleState.resumed) {
      final elapsed = _backgroundStopwatch.isRunning ? _backgroundStopwatch.elapsed.inSeconds : 0;
      _backgroundStopwatch
        ..stop()
        ..reset();
      if (mounted) {
        setState(() {
          _obscuredInBackground = false;
          if (elapsed >= p.lockTimeoutSecs) {
            _setLocked(true);
            _pin = '';
            _error = null;
          }
        });
      }
    }
  }

  void _startLockoutTicker() {
    _lockoutTick?.cancel();
    _lockoutTick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final rem = _lockout.remainingLockoutSecs;
      if (rem <= 0) {
        t.cancel();
        setState(() => _error = null);
      } else {
        setState(() => _error = '尝试次数过多，请 $rem 秒后重试');
      }
    });
  }

  void _pressDigit(String digit) {
    final rem = _lockout.remainingLockoutSecs;
    if (rem > 0) {
      _startLockoutTicker();
      setState(() => _error = '尝试次数过多，请 $rem 秒后重试');
      return;
    }
    if (_pin.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      _pin += digit;
    });
    if (_pin.length == 4) {
      final res = _lockout.verify(_pin, widget.appState.prefs.passcodeHash);
      if (res.ok) {
        HapticFeedback.mediumImpact();
        _lockoutTick?.cancel();
        setState(() {
          _setLocked(false);
          _pin = '';
          _error = null;
        });
      } else {
        HapticFeedback.heavyImpact();
        if (res.lockoutSecs > 0) {
          _startLockoutTicker();
        }
        setState(() {
          _pin = '';
          _error = res.error;
        });
      }
    }
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Zero overhead when unlocked & active (no background blur when passcode is disabled).
    if (!_locked && !_obscuredInBackground) return widget.child;

    final skin = widget.appState.prefs.activeSkin;
    if (!_locked && _obscuredInBackground) {
      return Stack(
        children: [
          Offstage(
            offstage: true,
            child: ExcludeFocus(
              excluding: true,
              child: ExcludeSemantics(
                excluding: true,
                child: AbsorbPointer(child: widget.child),
              ),
            ),
          ),
          Positioned.fill(
            child: ColoredBox(
              color: skin.canvas,
              child: const Center(child: VedroBrandMark(size: 52)),
            ),
          ),
        ],
      );
    }

    return PopScope(
      canPop: false,
      child: Stack(
        children: [
          Offstage(
            offstage: true,
            child: ExcludeFocus(
              excluding: true,
              child: ExcludeSemantics(
                excluding: true,
                child: AbsorbPointer(child: widget.child),
              ),
            ),
          ),
          Positioned.fill(
            child: FocusScope(
              autofocus: true,
              child: KeyboardListener(
                focusNode: _lockKeyboardNode,
                onKeyEvent: (ev) {
                  if (ev is! KeyDownEvent) return;
                  final ch = ev.character;
                  if (ch != null && RegExp(r'^[0-9]$').hasMatch(ch)) {
                    _pressDigit(ch);
                  } else if (ev.logicalKey == LogicalKeyboardKey.backspace) {
                    _backspace();
                  }
                },
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Material(
                    color: skin.canvas.withValues(alpha: 0.94),
                    child: SafeArea(
                      child: LayoutBuilder(
                        builder: (context, constraints) => SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: (constraints.maxHeight - 32).clamp(0.0, double.infinity),
                            ),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 300),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const VedroBrandMark(size: 48),
                                    const SizedBox(height: 16),
                                    Text(
                                      '输入密码解锁 Vedro',
                                      style: TextStyle(
                                        color: skin.fg,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: List.generate(4, (i) {
                                        final filled = i < _pin.length;
                                        return AnimatedContainer(
                                          duration: const Duration(milliseconds: 140),
                                          margin: const EdgeInsets.symmetric(horizontal: 10),
                                          width: 13,
                                          height: 13,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: filled ? skin.fg : Colors.transparent,
                                            border: Border.all(
                                              color: filled ? skin.fg : skin.borderStrong,
                                              width: 1.4,
                                            ),
                                          ),
                                        );
                                      }),
                                    ),
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      height: 20,
                                      child: _error != null
                                          ? Text(
                                              _error!,
                                              style: const TextStyle(
                                                color: VedroTheme.danger,
                                                fontSize: 12.5,
                                              ),
                                            )
                                          : null,
                                    ),
                                    const SizedBox(height: 16),
                                    _PinKeypad(
                                      skin: skin,
                                      onDigit: _pressDigit,
                                      onBackspace: _backspace,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinKeypad extends StatelessWidget {
  const _PinKeypad({required this.skin, required this.onDigit, required this.onBackspace});
  final VedroSkin skin;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((key) {
              if (key.isEmpty) {
                return const SizedBox(width: 68, height: 68);
              }
              final isBack = key == '⌫';
              return PressableScale(
                autofocus: key == '5',
                borderRadius: BorderRadius.circular(999),
                onTap: () => isBack ? onBackspace() : onDigit(key),
                hoverScale: 1.05,
                pressScale: 0.92,
                child: Container(
                  width: 68,
                  height: 68,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isBack ? Colors.transparent : skin.subtleChipBg,
                    border: isBack
                        ? null
                        : Border.all(color: skin.borderStrong, width: 0.8),
                  ),
                  child: isBack
                      ? Icon(Icons.backspace_outlined, size: 22, color: skin.fg2)
                      : Text(
                          key,
                          style: TextStyle(
                            color: skin.fg,
                            fontSize: 24,
                            fontWeight: FontWeight.w400,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}
