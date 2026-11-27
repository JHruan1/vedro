import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/platform/native_playback_channel.dart';

/// Instant-response native Windows titlebar drag, double-click maximize/restore,
/// and right-click system menu surface.
///
/// Place as the background sibling (`Positioned.fill(child: WindowsWindowDragArea())`)
/// behind interactive header buttons in a `Stack`: buttons on top intercept clicks
/// normally, while pressing and dragging ANY empty header region starts native Win32
/// Aero Snap movement immediately with zero pan-slop delay or ScrollView conflict.
class WindowsWindowDragArea extends StatefulWidget {
  const WindowsWindowDragArea({
    super.key,
    this.enabled = true,
    this.forceEnableForTest = false,
    this.onStartDrag,
    this.onToggleZoom,
    this.onSystemMenu,
    this.child,
  });

  final bool enabled;
  final bool forceEnableForTest;
  final VoidCallback? onStartDrag;
  final VoidCallback? onToggleZoom;
  final VoidCallback? onSystemMenu;
  final Widget? child;

  @override
  State<WindowsWindowDragArea> createState() => _WindowsWindowDragAreaState();
}

class _WindowsWindowDragAreaState extends State<WindowsWindowDragArea> {
  DateTime? _lastPrimaryDownAt;
  Offset? _lastPrimaryDownPos;
  Offset? _secondaryDownPos;

  bool get _active =>
      widget.enabled && (widget.forceEnableForTest || (!kIsWeb && Platform.isWindows));

  void _onPointerDown(PointerDownEvent event) {
    final isPrimary =
        (event.buttons & kPrimaryMouseButton) != 0 || event.kind == PointerDeviceKind.touch;
    if (isPrimary) {
      _secondaryDownPos = null;
      final now = DateTime.now();
      final isDoubleClick = _lastPrimaryDownAt != null &&
          _lastPrimaryDownPos != null &&
          now.difference(_lastPrimaryDownAt!) <= const Duration(milliseconds: 360) &&
          (event.position - _lastPrimaryDownPos!).distance <= 6.0;
      if (isDoubleClick) {
        _lastPrimaryDownAt = null;
        _lastPrimaryDownPos = null;
        (widget.onToggleZoom ?? NativePlaybackChannel.toggleZoom)();
      } else {
        _lastPrimaryDownAt = now;
        _lastPrimaryDownPos = event.position;
        (widget.onStartDrag ?? NativePlaybackChannel.startWindowDrag)();
      }
      return;
    }
    if ((event.buttons & kSecondaryMouseButton) != 0) {
      _secondaryDownPos = event.position;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final secStart = _secondaryDownPos;
    _secondaryDownPos = null;
    if (secStart != null && (event.position - secStart).distance <= 8.0) {
      (widget.onSystemMenu ?? NativePlaybackChannel.showWindowSystemMenu)();
    }
  }

  void _onPointerCancel(PointerCancelEvent _) {
    _secondaryDownPos = null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_active) {
      return widget.child ?? const SizedBox.shrink();
    }
    return ValueListenableBuilder<bool>(
      valueListenable: NativePlaybackChannel.fullscreenNotifier,
      builder: (context, isFullscreen, _) {
        if (isFullscreen) {
          return widget.child ?? const SizedBox.shrink();
        }
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: widget.child ?? const SizedBox.expand(),
        );
      },
    );
  }
}

/// Native Windows 10/11 full-bleed immersive window frame overlay:
/// - Pairs with `WM_NCCALCSIZE` + `DwmExtendFrameIntoClientArea` in `win32_window.cpp`
///   so Hero backdrops, frosted headers, and video bleed seamlessly to `y = 0` (zero solid titlebar strip).
/// - Provides native Win32 8-direction edge/corner resizing, top-edge Aero Snap dragging,
///   right-click native system menu, and pixel-crisp Windows 11 Minimize / Maximize / Close caption controls.
class WindowsImmersiveFrame extends StatefulWidget {
  const WindowsImmersiveFrame({
    super.key,
    required this.isLight,
    required this.child,
    this.forceEnableForTest = false,
  });

  final bool isLight;
  final Widget child;
  final bool forceEnableForTest;

  @override
  State<WindowsImmersiveFrame> createState() => _WindowsImmersiveFrameState();
}

class _WindowsImmersiveFrameState extends State<WindowsImmersiveFrame>
    with WidgetsBindingObserver {
  bool _captionHovered = false;

  bool get _active => widget.forceEnableForTest || (!kIsWeb && Platform.isWindows);

  @override
  void initState() {
    super.initState();
    if (_active && !widget.forceEnableForTest) {
      WidgetsBinding.instance.addObserver(this);
      NativePlaybackChannel.ensureWindowListener();
      NativePlaybackChannel.syncMaximizedState();
    }
  }

  @override
  void dispose() {
    if (_active && !widget.forceEnableForTest) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (_active && !widget.forceEnableForTest) {
      NativePlaybackChannel.syncMaximizedState();
    }
  }

  Widget _buildResizeEdge({
    double? left,
    double? right,
    double? top,
    double? bottom,
    double? width,
    double? height,
    required MouseCursor cursor,
    required String edge,
  }) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      width: width,
      height: height,
      child: MouseRegion(
        cursor: cursor,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (ev) {
            if ((ev.buttons & kPrimaryMouseButton) != 0 || ev.kind == PointerDeviceKind.touch) {
              NativePlaybackChannel.startWindowResize(edge);
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_active) {
      return widget.child;
    }

    return ValueListenableBuilder<bool>(
      valueListenable: NativePlaybackChannel.fullscreenNotifier,
      builder: (context, isFullscreen, _) {
        if (isFullscreen) {
          return widget.child;
        }
        return ValueListenableBuilder<bool>(
          valueListenable: NativePlaybackChannel.maximizedNotifier,
          builder: (context, isMaximized, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: NativePlaybackChannel.playerHudAutoHideNotifier,
              builder: (context, autoHideForPlayer, _) {
                final showCaptions = !autoHideForPlayer || _captionHovered;
                // In auto-hiding video player mode, canvas is always dark cinema black.
                final effectiveLight = autoHideForPlayer ? false : widget.isLight;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    widget.child,

                    // Top fallback drag & Aero Snap strip cleanly above y=11+ buttons
                    // (seamlessly joins each page's full-height WindowsWindowDragArea below it)
                    Positioned(
                      top: isMaximized ? 0 : 4,
                      left: isMaximized ? 0 : 10,
                      right: 138,
                      height: isMaximized ? 11 : 7,
                      child: WindowsWindowDragArea(
                        key: const ValueKey('win-top-fallback-drag-strip'),
                        forceEnableForTest: widget.forceEnableForTest,
                      ),
                    ),

                    // Seamless Windows 11 Caption Controls (Minimize / Maximize-Restore / Close)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: MouseRegion(
                        onEnter: (_) => setState(() => _captionHovered = true),
                        onExit: (_) => setState(() => _captionHovered = false),
                        child: AnimatedOpacity(
                          opacity: showCaptions ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 180),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _WinCaptionButton(
                                key: const ValueKey('win-caption-minimize'),
                                tooltip: '最小化',
                                isLight: effectiveLight,
                                kind: _WinGlyphKind.minimize,
                                onTap: NativePlaybackChannel.minimizeWindow,
                              ),
                              _WinCaptionButton(
                                key: const ValueKey('win-caption-maximize'),
                                tooltip: isMaximized ? '向下还原' : '最大化',
                                isLight: effectiveLight,
                                kind: isMaximized
                                    ? _WinGlyphKind.restore
                                    : _WinGlyphKind.maximize,
                                onTap: NativePlaybackChannel.toggleZoom,
                              ),
                              _WinCaptionButton(
                                key: const ValueKey('win-caption-close'),
                                tooltip: '关闭',
                                isLight: effectiveLight,
                                isClose: true,
                                kind: _WinGlyphKind.close,
                                onTap: NativePlaybackChannel.closeWindow,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Native 8-direction resize borders when in windowed (non-maximized) state
                    if (!isMaximized) ...[
                      _buildResizeEdge(
                        left: 0,
                        top: 10,
                        bottom: 10,
                        width: 5,
                        cursor: SystemMouseCursors.resizeLeftRight,
                        edge: 'left',
                      ),
                      _buildResizeEdge(
                        right: 0,
                        top: 32,
                        bottom: 10,
                        width: 5,
                        cursor: SystemMouseCursors.resizeLeftRight,
                        edge: 'right',
                      ),
                      _buildResizeEdge(
                        left: 10,
                        right: 138,
                        top: 0,
                        height: 4,
                        cursor: SystemMouseCursors.resizeUpDown,
                        edge: 'top',
                      ),
                      _buildResizeEdge(
                        left: 10,
                        right: 10,
                        bottom: 0,
                        height: 5,
                        cursor: SystemMouseCursors.resizeUpDown,
                        edge: 'bottom',
                      ),
                      _buildResizeEdge(
                        left: 0,
                        top: 0,
                        width: 10,
                        height: 10,
                        cursor: SystemMouseCursors.resizeUpLeftDownRight,
                        edge: 'topLeft',
                      ),
                      _buildResizeEdge(
                        right: 0,
                        top: 0,
                        width: 6,
                        height: 6,
                        cursor: SystemMouseCursors.resizeUpRightDownLeft,
                        edge: 'topRight',
                      ),
                      _buildResizeEdge(
                        right: 0,
                        bottom: 0,
                        width: 10,
                        height: 10,
                        cursor: SystemMouseCursors.resizeUpLeftDownRight,
                        edge: 'bottomRight',
                      ),
                      _buildResizeEdge(
                        left: 0,
                        bottom: 0,
                        width: 10,
                        height: 10,
                        cursor: SystemMouseCursors.resizeUpRightDownLeft,
                        edge: 'bottomLeft',
                      ),
                    ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

enum _WinGlyphKind { minimize, maximize, restore, close }

class _WinCaptionButton extends StatefulWidget {
  const _WinCaptionButton({
    super.key,
    required this.tooltip,
    required this.isLight,
    required this.kind,
    required this.onTap,
    this.isClose = false,
  });

  final String tooltip;
  final bool isLight;
  final _WinGlyphKind kind;
  final VoidCallback onTap;
  final bool isClose;

  @override
  State<_WinCaptionButton> createState() => _WinCaptionButtonState();
}

class _WinCaptionButtonState extends State<_WinCaptionButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    Color bg = Colors.transparent;
    if (_hovered || _pressed) {
      if (widget.isClose) {
        bg = _pressed ? const Color(0xFFB2271A) : const Color(0xFFC42B1C);
      } else {
        bg = widget.isLight
            ? Colors.black.withValues(alpha: _pressed ? 0.11 : 0.065)
            : Colors.white.withValues(alpha: _pressed ? 0.14 : 0.09);
      }
    }

    final Color glyphColor;
    if (widget.isClose && (_hovered || _pressed)) {
      glyphColor = Colors.white;
    } else if (widget.isLight) {
      glyphColor = _hovered ? const Color(0xFF09090B) : const Color(0xCC18181B);
    } else {
      glyphColor = _hovered ? Colors.white : const Color(0xD9F4F4F6);
    }

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 550),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            width: 46,
            height: 32,
            color: bg,
            alignment: Alignment.center,
            child: CustomPaint(
              size: const Size(10, 10),
              painter: _WinCaptionGlyphPainter(
                kind: widget.kind,
                color: glyphColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WinCaptionGlyphPainter extends CustomPainter {
  const _WinCaptionGlyphPainter({required this.kind, required this.color});

  final _WinGlyphKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.05
      ..strokeCap = StrokeCap.square
      ..isAntiAlias = true;

    switch (kind) {
      case _WinGlyphKind.minimize:
        canvas.drawLine(
          Offset(0, size.height * 0.5),
          Offset(size.width, size.height * 0.5),
          paint,
        );
      case _WinGlyphKind.maximize:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
            const Radius.circular(1.0),
          ),
          paint,
        );
      case _WinGlyphKind.restore:
        // Back window
        final path = Path()
          ..moveTo(2.5, 2.5)
          ..lineTo(2.5, 0.5)
          ..lineTo(size.width - 0.5, 0.5)
          ..lineTo(size.width - 0.5, size.height - 2.5)
          ..lineTo(size.width - 2.5, size.height - 2.5);
        canvas.drawPath(path, paint);
        // Front window
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0.5, 2.5, size.width - 3, size.height - 3),
            const Radius.circular(0.8),
          ),
          paint,
        );
      case _WinGlyphKind.close:
        final closePaint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.15
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true;
        canvas.drawLine(const Offset(0.5, 0.5), Offset(size.width - 0.5, size.height - 0.5), closePaint);
        canvas.drawLine(Offset(size.width - 0.5, 0.5), Offset(0.5, size.height - 0.5), closePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WinCaptionGlyphPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}
