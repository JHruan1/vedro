import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/preferences.dart';
import '../core/theme/vedro_theme.dart';
import '../state/app_state.dart';
import 'vedro_ui.dart';

/// Privacy Protection gate:
/// - Prompts for a 4-digit passcode on startup / resume past timeout when enabled.
/// - Blurs app content automatically when entering inactive / background state if enabled.
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
  bool _blurred = false;
  bool _checkedInitialLock = false;
  DateTime? _pausedAt;
  String _pin = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.appState.addListener(_onStateChanged);
    _onStateChanged();
  }

  @override
  void dispose() {
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
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _pausedAt ??= DateTime.now();
      if (p.blurInBackground && !_blurred && mounted) {
        setState(() => _blurred = true);
      }
    } else if (state == AppLifecycleState.resumed) {
      final elapsed = _pausedAt == null
          ? 0
          : DateTime.now().difference(_pausedAt!).inSeconds;
      _pausedAt = null;
      final shouldLock =
          p.passcodeEnabled && p.passcodeHash.isNotEmpty && elapsed >= p.lockTimeoutSecs;
      if (mounted) {
        setState(() {
          _blurred = false;
          if (shouldLock) {
            _locked = true;
            _pin = '';
            _error = null;
          }
        });
      }
    }
  }

  void _pressDigit(String digit) {
    if (_pin.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      _pin += digit;
    });
    if (_pin.length == 4) {
      if (hashPasscode(_pin) == widget.appState.prefs.passcodeHash) {
        HapticFeedback.mediumImpact();
        setState(() {
          _locked = false;
          _pin = '';
          _error = null;
        });
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          _pin = '';
          _error = '密码不正确，请重试';
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
    return Stack(
      children: [
        widget.child,
        if (_blurred && !_locked)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Container(
                color: const Color(0xBB0B0B0D),
                child: const Center(child: VedroBrandMark(size: 56)),
              ),
            ),
          ),
        if (_locked)
          Positioned.fill(
            child: KeyboardListener(
              focusNode: FocusNode()..requestFocus(),
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
                filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
                child: Material(
                  color: const Color(0xEB0B0B0D),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const VedroBrandMark(size: 48),
                          const SizedBox(height: 18),
                          const Text(
                            '输入密码解锁 Vedro',
                            style: TextStyle(
                              color: VedroTheme.fg,
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
                                  color: filled ? Colors.white : Colors.transparent,
                                  border: Border.all(
                                    color: filled ? Colors.white : const Color(0x55FFFFFF),
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
                          _PinKeypad(onDigit: _pressDigit, onBackspace: _backspace),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PinKeypad extends StatelessWidget {
  const _PinKeypad({required this.onDigit, required this.onBackspace});
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
                onTap: () => isBack ? onBackspace() : onDigit(key),
                hoverScale: 1.05,
                pressScale: 0.92,
                child: Container(
                  width: 68,
                  height: 68,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isBack ? Colors.transparent : const Color(0x14FFFFFF),
                    border: isBack
                        ? null
                        : Border.all(color: const Color(0x1EFFFFFF), width: 0.8),
                  ),
                  child: isBack
                      ? const Icon(Icons.backspace_outlined, size: 22, color: VedroTheme.fg2)
                      : Text(
                          key,
                          style: const TextStyle(
                            color: VedroTheme.fg,
                            fontSize: 24,
                            fontWeight: FontWeight.w400,
                            fontFeatures: [FontFeature.tabularFigures()],
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
