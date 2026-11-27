import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/preferences.dart';
import '../core/theme/vedro_skin.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import 'vedro_ui.dart';

/// Privacy Protection gate:
/// - Prompts for a 4-digit passcode on startup / resume past timeout ONLY when explicitly enabled.
/// - Fully supports D-Pad remote controls on Android TV (focusable keypad + Back blocking + zero background leak).
/// - Uses a monotonic `Stopwatch` (immune to system clock rollback) and rate-limited failure backoff.
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.appState,
    required this.child,
  });

  final VedroAppState appState;
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _locked = false;
  bool _checkedInitialLock = false;
  final Stopwatch _backgroundStopwatch = Stopwatch();
  final FocusNode _lockKeyboardNode = FocusNode(debugLabel: 'app_lock_keyboard');
  String _pin = '';
  String? _error;
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;
  Timer? _lockoutTick;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  void _onStateChanged() {
    final p = widget.appState.prefs;
    if (widget.appState.isInitialized && !_checkedInitialLock) {
      _checkedInitialLock = true;
      if (p.passcodeEnabled && p.passcodeHash.isNotEmpty) {
        if (mounted) setState(() => _locked = true);
      }
    }
    if (!p.passcodeEnabled && _locked) {
      if (mounted) setState(() => _locked = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final p = widget.appState.prefs;
    if (!p.passcodeEnabled || p.passcodeHash.isEmpty) {
      _backgroundStopwatch
        ..stop()
        ..reset();
      return;
    }
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (!_backgroundStopwatch.isRunning) {
        _backgroundStopwatch
          ..reset()
          ..start();
      }
    } else if (state == AppLifecycleState.resumed) {
      final elapsed = _backgroundStopwatch.isRunning ? _backgroundStopwatch.elapsed.inSeconds : 0;
      _backgroundStopwatch
        ..stop()
        ..reset();
      if (elapsed >= p.lockTimeoutSecs && mounted) {
        setState(() {
          _locked = true;
          _pin = '';
          _error = null;
        });
      }
    }
  }

  int get _remainingLockoutSecs {
    final until = _lockoutUntil;
    if (until == null) return 0;
    final rem = until.difference(DateTime.now()).inSeconds;
    return rem > 0 ? rem : 0;
  }

  void _pressDigit(String digit) {
    if (_remainingLockoutSecs > 0) {
      setState(() => _error = '尝试次数过多，请 $_remainingLockoutSecs 秒后重试');
      return;
    }
    if (_pin.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      _pin += digit;
    });
    if (_pin.length == 4) {
      if (hashPasscode(_pin) == widget.appState.prefs.passcodeHash) {
        HapticFeedback.mediumImpact();
        _failedAttempts = 0;
        _lockoutUntil = null;
        _lockoutTick?.cancel();
        setState(() {
          _locked = false;
          _pin = '';
          _error = null;
        });
      } else {
        HapticFeedback.heavyImpact();
        _failedAttempts++;
        if (_failedAttempts >= 5) {
          final penaltySecs = _failedAttempts >= 10 ? 120 : 30;
          _lockoutUntil = DateTime.now().add(Duration(seconds: penaltySecs));
          _lockoutTick?.cancel();
          _lockoutTick = Timer.periodic(const Duration(seconds: 1), (t) {
            if (!mounted) {
              t.cancel();
              return;
            }
            final rem = _remainingLockoutSecs;
            if (rem <= 0) {
              t.cancel();
              setState(() {
                _lockoutUntil = null;
                _error = null;
              });
            } else {
              setState(() => _error = '尝试次数过多，请 $rem 秒后重试');
            }
          });
          setState(() {
            _pin = '';
            _error = '尝试次数过多，请 $penaltySecs 秒后重试';
          });
        } else {
          setState(() {
            _pin = '';
            _error = '密码不正确，还可尝试 ${5 - _failedAttempts} 次';
          });
        }
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
    // Zero overhead when unlocked (avoid activeSkin recomputation on every rebuild!)
    if (!_locked) return widget.child;

    final skin = widget.appState.prefs.activeSkin;
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
                    color: skin.canvas.withValues(alpha: 0.92),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const VedroBrandMark(size: 48),
                            const SizedBox(height: 18),
                            Text(
                              '输入密码解锁 Vedro',
                              style: TextStyle(
                                color: skin.fg,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 22),
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
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 20,
                              child: _error != null
                                  ? Text(
                                      _error!,
                                      style: const TextStyle(color: VedroTheme.danger, fontSize: 12.5),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 18),
                            _PinKeypad(skin: skin, onDigit: _pressDigit, onBackspace: _backspace),
                          ],
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
