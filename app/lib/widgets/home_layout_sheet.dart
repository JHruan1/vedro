import 'package:flutter/material.dart';

import '../core/models/models.dart';
import '../core/theme/vedro_theme.dart';
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '自定义首页布局',
                      style: TextStyle(
                        color: VedroTheme.fg,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '拖动右侧手柄调整上下顺序，开关控制模块显示',
                      style: TextStyle(color: VedroTheme.fg3, fontSize: 12),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _sections = List<HomeSectionConfig>.from(HomeSectionConfig.defaults);
                    _showHero = true;
                  });
                  widget.appState.resetHomeLayout();
                },
                child: const Text(
                  '恢复默认',
                  style: TextStyle(color: VedroTheme.fg2, fontSize: 12.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Hero banner toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: VedroTheme.surface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: VedroTheme.line, width: 0.8),
            ),
            child: Row(
              children: [
                const Icon(Icons.panorama_wide_angle_outlined, size: 18, color: VedroTheme.fg2),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '顶部横幅轮播',
                        style: TextStyle(
                          color: VedroTheme.fg,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '仅选取带横版背景图的影片展示',
                        style: TextStyle(color: VedroTheme.fg3, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _showHero,
                  onChanged: (v) {
                    setState(() => _showHero = v);
                    _commit();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              proxyDecorator: (child, _, __) => Material(
                color: Colors.transparent,
                elevation: 8,
                shadowColor: const Color(0x88000000),
                borderRadius: BorderRadius.circular(13),
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
                      color: sec.visible ? VedroTheme.surface : const Color(0x88141417),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: VedroTheme.line, width: 0.8),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          child: Text(
                            '${idx + 1}',
                            style: const TextStyle(
                              color: VedroTheme.fg3,
                              fontSize: 12,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sec.title,
                                style: TextStyle(
                                  color: sec.visible ? VedroTheme.fg : VedroTheme.fg3,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (sec.subtitle.isNotEmpty)
                                Text(
                                  sec.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: VedroTheme.fg3, fontSize: 11.5),
                                ),
                            ],
                          ),
                        ),
                        Switch(
                          value: sec.visible,
                          onChanged: (v) {
                            setState(() {
                              _sections[idx] = sec.copyWith(visible: v);
                            });
                            _commit();
                          },
                        ),
                        const SizedBox(width: 4),
                        ReorderableDragStartListener(
                          index: idx,
                          child: const MouseRegion(
                            cursor: SystemMouseCursors.grab,
                            child: Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.drag_handle_rounded,
                                size: 19,
                                color: VedroTheme.fg3,
                              ),
                            ),
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
      ),
    );
  }
}
