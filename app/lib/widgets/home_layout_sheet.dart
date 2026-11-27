import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/platform/platform_perf.dart';
import '../core/theme/vedro_skin.dart';
import '../state/app_state.dart';
import 'vedro_ui.dart';

/// Infuse / SenPlayer style Home Layout customizer:
/// drag handles to reorder Home sections, switches to show/hide each rail & hero banner,
/// plus one-tap restore defaults. Persists directly to Rust SQLite KV store.
Future<void> showHomeLayoutSheet({
  required BuildContext context,
  required VedroAppState appState,
}) {
  return showGlassSheet<void>(
    context: context,
    builder: (ctx) => _HomeLayoutEditor(appState: appState),
  );
}

class _HomeLayoutEditor extends StatefulWidget {
  const _HomeLayoutEditor({required this.appState});
  final VedroAppState appState;

  @override
  State<_HomeLayoutEditor> createState() => _HomeLayoutEditorState();
}

class _HomeLayoutEditorState extends State<_HomeLayoutEditor> {
  late List<HomeSectionConfig> _sections;
  late bool _showHero;

  @override
  void initState() {
    super.initState();
    _sections = List<HomeSectionConfig>.from(widget.appState.homeSections);
    _showHero = widget.appState.showHomeHero;
  }

  void _commit() {
    widget.appState.saveHomeLayout(_sections, showHero: _showHero);
  }

  @override
  Widget build(BuildContext context) {
    final skin = VedroSkin.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '首页布局',
                  style: TextStyle(
                    color: skin.fg,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Tooltip(
                message: '恢复默认',
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.restore_rounded, size: 19, color: skin.fg2),
                  onPressed: () {
                    setState(() {
                      _sections = List<HomeSectionConfig>.from(HomeSectionConfig.defaults);
                      _showHero = true;
                    });
                    widget.appState.resetHomeLayout();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: skin.surface2,
              borderRadius: BorderRadius.circular(skin.cardRadius.clamp(10.0, 16.0)),
              border: Border.all(color: skin.border, width: 0.8),
            ),
            child: Row(
              children: [
                Icon(Icons.panorama_wide_angle_outlined, size: 18, color: skin.fg2),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '顶部横幅',
                    style: TextStyle(
                      color: skin.fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Transform.scale(
                  scale: 0.82,
                  child: CupertinoSwitch(
                    value: _showHero,
                    activeTrackColor: skin.accent,
                    onChanged: (v) {
                      setState(() => _showHero = v);
                      _commit();
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              proxyDecorator: (child, _, __) => Material(
                color: Colors.transparent,
                elevation: 8,
                shadowColor: const Color(0x88000000),
                borderRadius: BorderRadius.circular(skin.cardRadius.clamp(10.0, 16.0)),
                child: child,
              ),
              itemCount: _sections.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final moved = _sections.removeAt(oldIndex);
                  _sections.insert(newIndex, moved);
                });
                _commit();
              },
              itemBuilder: (context, idx) {
                final sec = _sections[idx];
                return Padding(
                  key: ValueKey(sec.id),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                    decoration: BoxDecoration(
                      color: sec.visible ? skin.surface2 : skin.surface2.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(skin.cardRadius.clamp(10.0, 16.0)),
                      border: Border.all(color: skin.border, width: 0.8),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          child: Text(
                            '${idx + 1}',
                            style: TextStyle(
                              color: skin.fg3,
                              fontSize: 12,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            sec.title,
                            style: TextStyle(
                              color: sec.visible ? skin.fg : skin.fg3,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Transform.scale(
                          scale: 0.82,
                          child: CupertinoSwitch(
                            value: sec.visible,
                            activeTrackColor: skin.accent,
                            onChanged: (v) {
                              setState(() {
                                _sections[idx] = sec.copyWith(visible: v);
                              });
                              _commit();
                            },
                          ),
                        ),
                        if (PlatformPerfProfile.isTv) ...[
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: '上移',
                            icon: Icon(Icons.keyboard_arrow_up_rounded, size: 19, color: skin.fg2),
                            onPressed: idx == 0
                                ? null
                                : () {
                                    setState(() {
                                      final moved = _sections.removeAt(idx);
                                      _sections.insert(idx - 1, moved);
                                    });
                                    _commit();
                                  },
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: '下移',
                            icon: Icon(Icons.keyboard_arrow_down_rounded, size: 19, color: skin.fg2),
                            onPressed: idx == _sections.length - 1
                                ? null
                                : () {
                                    setState(() {
                                      final moved = _sections.removeAt(idx);
                                      _sections.insert(idx + 1, moved);
                                    });
                                    _commit();
                                  },
                          ),
                        ] else ...[
                          const SizedBox(width: 4),
                          ReorderableDragStartListener(
                            index: idx,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.grab,
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  Icons.drag_handle_rounded,
                                  size: 19,
                                  color: skin.fg3,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
