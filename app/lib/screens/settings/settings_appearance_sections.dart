part of '../settings_screen.dart';

/// Skin Studio entry, Home Modules, List Badges & UI Preferences sections.
extension _SettingsAppearanceSectionsExt on _SettingsDetailPaneState {
  // 4. 应用风格 & 皮肤工坊
  Widget _buildStyle(VedroPreferences p) {
    return SkinStudioPane(
      appState: widget.appState,
      hideHeading: widget.hideHeading,
    );
  }

  // 5. 模块配置
  Widget _buildModules(VedroAppState app) {
    final sections = List<HomeSectionConfig>.from(app.homeSections);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('模块配置'),
        _GroupedCard(
          children: [
            _SwitchRow(
              title: '顶部巨幕轮播',
              value: app.showHomeHero,
              onChanged: (v) => app.saveHomeLayout(sections, showHero: v),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: _GroupHeader('板块排序')),
            TextButton(
              onPressed: app.resetHomeLayout,
              child: Text('恢复默认', style: TextStyle(color: VedroSkin.of(context).fg2, fontSize: 12.5)),
            ),
          ],
        ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: sections.length,
          onReorder: (oldIdx, newIdx) {
            if (newIdx > oldIdx) newIdx -= 1;
            final item = sections.removeAt(oldIdx);
            sections.insert(newIdx, item);
            app.saveHomeLayout(sections);
          },
          itemBuilder: (context, idx) {
            final skin = VedroSkin.of(context);
            final sec = sections[idx];
            return Padding(
              key: ValueKey('mod_${sec.id}'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                decoration: BoxDecoration(
                  color: skin.surface,
                  borderRadius: BorderRadius.circular(skin.cardRadius.clamp(8.0, 16.0)),
                  border: skin.cardBorder(),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${idx + 1}',
                        style: TextStyle(
                          color: skin.fg3,
                          fontSize: 12.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
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
                              color: sec.visible ? skin.fg : skin.fg3,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(sec.subtitle, style: TextStyle(color: skin.fg3, fontSize: 11.5)),
                        ],
                      ),
                    ),
                    Transform.scale(
                      scale: 0.78,
                      child: CupertinoSwitch(
                        value: sec.visible,
                        activeTrackColor: skin.accent,
                        onChanged: (v) {
                          sections[idx] = sec.copyWith(visible: v);
                          app.saveHomeLayout(sections);
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
                                final moved = sections.removeAt(idx);
                                sections.insert(idx - 1, moved);
                                app.saveHomeLayout(sections);
                              },
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: '下移',
                        icon: Icon(Icons.keyboard_arrow_down_rounded, size: 19, color: skin.fg2),
                        onPressed: idx == sections.length - 1
                            ? null
                            : () {
                                final moved = sections.removeAt(idx);
                                sections.insert(idx + 1, moved);
                                app.saveHomeLayout(sections);
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
                            child: Icon(Icons.drag_handle_rounded, size: 19, color: skin.fg3),
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
      ],
    );
  }

  // 6. 列表配置
  Widget _buildLists(VedroPreferences p) {
    final pct = (p.posterScale * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('列表配置'),
        _GroupedCard(
          children: [
            _InlineSegmentedRow<String>(
              title: '海报墙密度',
              keyPrefix: 'list-density',
              value: p.listDensity,
              items: const [('compact', '紧凑'), ('comfortable', '标准'), ('spacious', '宽松')],
              onChanged: (v) => _updatePrefs(p.copyWith(listDensity: v)),
            ),
            _InlineSegmentedRow<String>(
              title: '分类与边距间距',
              keyPrefix: 'list-section-spacing',
              value: p.sectionSpacing,
              items: const [('compact', '紧凑'), ('standard', '标准'), ('spacious', '宽松')],
              onChanged: (v) => _updatePrefs(p.copyWith(sectionSpacing: v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: VedroPrecisionSlider(
                key: const ValueKey('poster-scale-slider'),
                label: '卡片与图标尺寸',
                valueText: '$pct%',
                value: p.posterScale,
                min: 0.75,
                max: 1.25,
                step: 0.05,
                defaultValue: 1.0,
                ticks: const [
                  (0.80, '80%'),
                  (0.90, '90%'),
                  (1.00, '100%'),
                  (1.10, '110%'),
                  (1.20, '120%'),
                ],
                onChanged: (v) => _updatePrefs(p.copyWith(posterScale: v)),
              ),
            ),
            _AppleMenuPickerRow<String>(
              title: '媒体库默认排序',
              value: p.defaultSort,
              items: const {
                'DateCreated': '按入库时间',
                'SortName': '按片名 A–Z',
                'CommunityRating': '按社区评分',
                'PremiereDate': '按发行年份',
              },
              onChanged: (v) => _updatePrefs(p.copyWith(defaultSort: v)),
            ),
            _SwitchRow(
              title: '显示已看角标',
              value: p.showWatchedBadge,
              onChanged: (v) => _updatePrefs(p.copyWith(showWatchedBadge: v)),
            ),
            _SwitchRow(
              title: '显示未看集数角标',
              value: p.showUnplayedCount,
              onChanged: (v) => _updatePrefs(p.copyWith(showUnplayedCount: v)),
            ),
            _SwitchRow(
              title: '显示评分信息',
              value: p.showRatings,
              onChanged: (v) => _updatePrefs(p.copyWith(showRatings: v)),
            ),
            _SwitchRow(
              title: '显示发行年份',
              value: p.showYear,
              onChanged: (v) => _updatePrefs(p.copyWith(showYear: v)),
            ),
            _SwitchRow(
              key: const ValueKey('pref-show-multiversion-badge'),
              title: '显示多版本角标 (2×)',
              value: p.showMultiVersionBadge,
              onChanged: (v) => _updatePrefs(p.copyWith(showMultiVersionBadge: v)),
            ),
          ],
        ),
      ],
    );
  }

  // 7. 界面偏好
  Widget _buildUiPrefs(VedroPreferences p) {
    final showAndroidBackConfirm = kIsWeb || Platform.isAndroid || Platform.isLinux;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('界面偏好'),
        _GroupedCard(
          children: [
            _SwitchRow(
              title: 'TV 遥控器大屏模式',
              subtitle: '强制启用大屏遥控器焦点高亮、方向键操作与安全边距（Android TV 默认自动开启）',
              value: p.tvModeOverride,
              onChanged: (v) => _updatePrefs(p.copyWith(tvModeOverride: v)),
            ),
            if (showAndroidBackConfirm)
              _SwitchRow(
                key: const ValueKey('pref-confirm-exit-app'),
                title: '按返回键二次确认退出',
                value: p.confirmExitApp,
                onChanged: (v) => _updatePrefs(p.copyWith(confirmExitApp: v)),
              ),
            _SwitchRow(
              title: '显示画质与音频规格标识',
              value: p.showSpecBadges,
              onChanged: (v) => _updatePrefs(p.copyWith(showSpecBadges: v)),
            ),
            _SwitchRow(
              title: '进度条右侧显示剩余时长',
              value: p.showRemainingTime,
              onChanged: (v) => _updatePrefs(p.copyWith(showRemainingTime: v)),
            ),
            _SwitchRow(
              title: '退出播放前二次确认',
              value: p.confirmExitPlayer,
              onChanged: (v) => _updatePrefs(p.copyWith(confirmExitPlayer: v)),
            ),
            _SwitchRow(
              title: '无痕观影模式',
              value: p.incognitoMode,
              onChanged: (v) => _updatePrefs(p.copyWith(incognitoMode: v)),
            ),
          ],
        ),
      ],
    );
  }
}
