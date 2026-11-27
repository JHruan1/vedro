part of '../settings_screen.dart';

/// Playback, Video/HDR, Audio, Subtitles & Danmaku settings sections.
extension _SettingsPlaybackSectionsExt on _SettingsDetailPaneState {
  // 8. 播放设置
  Widget _buildPlayback(VedroPreferences p) {
    final isMobileOs = PlatformPerfProfile.isMobile;
    final supportsPip = NativePlaybackChannel.supportsNativePip;
    final playerChoices = <String, String>{
      'builtin': !kIsWeb && Platform.isIOS ? '内置播放核心（推荐）' : '内置 Rust + MPV（推荐）',
      if (!kIsWeb && Platform.isAndroid) ...{
        'mxplayer': 'MX Player',
        'vlc': 'VLC',
        'mpv': 'MPV-Android',
        'system': '系统外部播放器',
      } else if (!kIsWeb && Platform.isIOS) ...{
        'infuse': 'Infuse',
        'vlc': 'VLC',
        'outplayer': 'Outplayer',
        'nplayer': 'nPlayer',
      } else if (!kIsWeb && Platform.isMacOS) ...{
        'iina': 'IINA',
        'infuse': 'Infuse',
        'mpv': 'MPV',
        'vlc': 'VLC',
      } else if (!kIsWeb && Platform.isWindows) ...{
        'potplayer': 'PotPlayer',
        'vlc': 'VLC',
        'mpv': 'MPV',
      } else ...{
        'mpv': '外部 MPV',
        'vlc': 'VLC',
      },
    };
    if (!playerChoices.containsKey(p.externalPlayer)) {
      playerChoices[p.externalPlayer] = p.externalPlayer;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('播放设置'),
        const _GroupHeader('默认音轨与字幕'),
        KeyedSubtree(
          key: const ValueKey('settings-global-audio-sub-card'),
          child: _GroupedCard(
            children: [
              _InlineSegmentedRow<String>(
                title: '首选音轨语言',
                value: p.preferredAudioLang,
                items: const [
                  ('auto', '原声自动'),
                  ('zh', '中文/国语'),
                  ('yue', '粤语'),
                  ('ja', '日语'),
                  ('en', '英语'),
                ],
                onChanged: (v) => _updatePrefs(p.copyWith(preferredAudioLang: v)),
              ),
              _InlineSegmentedRow<String>(
                title: '首选字幕语言',
                value: p.preferredSubLang,
                items: const [
                  ('zh', '简中'),
                  ('zh-Hant', '繁中'),
                  ('en', '英语/双语'),
                  ('ja', '日语'),
                  ('off', '关闭'),
                ],
                onChanged: (v) => _updatePrefs(p.copyWith(preferredSubLang: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _GroupHeader('播放器与交互控制'),
        _GroupedCard(
          children: [
            _AppleMenuPickerRow<String>(
              title: '默认播放器引擎',
              value: p.externalPlayer,
              items: playerChoices,
              onChanged: (v) => _updatePrefs(p.copyWith(externalPlayer: v)),
            ),
            _AppleMenuPickerRow<int>(
              title: '播放器内存缓存大小',
              value: p.bufferSizeMb,
              items: const {
                32: '32 MB（省内存）',
                64: '64 MB',
                128: '128 MB（推荐）',
                256: '256 MB（4K Remux）',
                512: '512 MB（超大缓存）',
              },
              onChanged: (v) => _updatePrefs(p.copyWith(bufferSizeMb: v)),
            ),
            _InlineSegmentedRow<int>(
              title: '快进 / 快退步长',
              value: p.seekStepSecs,
              items: const [(5, '5s'), (10, '10s'), (15, '15s'), (30, '30s')],
              onChanged: (v) => _updatePrefs(p.copyWith(seekStepSecs: v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: VedroPrecisionSlider(
                label: '默认播放倍速',
                valueText:
                    '${((p.defaultSpeed * 10 - (p.defaultSpeed * 10).round()).abs() < 0.001 ? p.defaultSpeed.toStringAsFixed(1) : p.defaultSpeed.toStringAsFixed(2))}×',
                value: p.defaultSpeed,
                min: 0.5,
                max: 3.0,
                step: 0.05,
                defaultValue: 1.0,
                ticks: const [
                  (0.5, '0.5×'),
                  (1.0, '1.0×'),
                  (1.25, '1.25×'),
                  (1.5, '1.5×'),
                  (2.0, '2.0×'),
                  (3.0, '3.0×'),
                ],
                onChanged: (v) => _updatePrefs(p.copyWith(defaultSpeed: v)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: VedroPrecisionSlider(
                label: '长按屏幕倍速',
                valueText:
                    '${((p.longPressSpeed * 10 - (p.longPressSpeed * 10).round()).abs() < 0.001 ? p.longPressSpeed.toStringAsFixed(1) : p.longPressSpeed.toStringAsFixed(2))}×',
                value: p.longPressSpeed,
                min: 1.25,
                max: 4.0,
                step: 0.25,
                defaultValue: 2.0,
                ticks: const [
                  (1.5, '1.5×'),
                  (2.0, '2.0×'),
                  (2.5, '2.5×'),
                  (3.0, '3.0×'),
                  (4.0, '4.0×'),
                ],
                onChanged: (v) => _updatePrefs(p.copyWith(longPressSpeed: v)),
              ),
            ),
            if (isMobileOs)
              _SwitchRow(
                title: '双指捏合缩放画面',
                subtitle: '播放时支持双指自由缩放，松手保持比例',
                value: p.pinchToZoom,
                onChanged: (v) => _updatePrefs(p.copyWith(pinchToZoom: v)),
              ),
            _SwitchRow(
              key: const ValueKey('pref-show-network-speed'),
              title: '显示播放网速',
              subtitle: '播放与缓冲时实时显示当前下载网速',
              value: p.showNetworkSpeed,
              onChanged: (v) => _updatePrefs(p.copyWith(showNetworkSpeed: v)),
            ),
            _SwitchRow(
              key: const ValueKey('pref-remember-brightness'),
              title: '记忆播放器亮度',
              subtitle: '下次进入播放时自动恢复上次调节的画面亮度',
              value: p.rememberBrightness,
              onChanged: (v) => _updatePrefs(p.copyWith(rememberBrightness: v)),
            ),
            _SwitchRow(
              key: const ValueKey('pref-remember-volume'),
              title: '记忆播放器音量',
              subtitle: '下次进入播放时自动恢复上次调节的音量与静音状态',
              value: p.rememberVolume,
              onChanged: (v) => _updatePrefs(p.copyWith(rememberVolume: v)),
            ),
            _SwitchRow(
              key: const ValueKey('pref-remember-speed'),
              title: '记忆播放倍速',
              subtitle: '下次进入播放时自动恢复上次选择的倍速',
              value: p.rememberSpeed,
              onChanged: (v) => _updatePrefs(p.copyWith(rememberSpeed: v)),
            ),
            _SwitchRow(
              key: const ValueKey('pref-remember-aspect'),
              title: '记忆画面比例',
              subtitle: '下次进入播放时自动恢复上次选择的画面比例',
              value: p.rememberAspect,
              onChanged: (v) => _updatePrefs(p.copyWith(rememberAspect: v)),
            ),
            if (supportsPip)
              _SwitchRow(
                title: '启用画中画 (PiP)',
                subtitle: '在播放器顶栏显示画中画入口',
                value: p.enablePip,
                onChanged: (v) => _updatePrefs(p.copyWith(enablePip: v)),
              ),
            _SwitchRow(
              title: '后台继续播放音频',
              value: p.backgroundAudio,
              onChanged: (v) => _updatePrefs(p.copyWith(backgroundAudio: v)),
            ),
            _SwitchRow(
              title: '自动连播下一集',
              value: p.autoPlayNext,
              onChanged: (v) => _updatePrefs(p.copyWith(autoPlayNext: v)),
            ),
            _SwitchRow(
              title: '记住播放进度续播',
              value: p.rememberPosition,
              onChanged: (v) => _updatePrefs(p.copyWith(rememberPosition: v)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _GroupHeader('片头与片尾跳过'),
        _GroupedCard(
          children: [
            _SwitchRow(
              title: '自动跳过片头',
              subtitle: '服务端提供标记或设置自定义片头时长时自动跳转',
              value: p.autoSkipIntro,
              onChanged: (v) => _updatePrefs(p.copyWith(autoSkipIntro: v)),
            ),
            _SliderRow(
              title: '自定义跳过片头时长',
              valueText: p.customSkipIntroSecs == 0 ? '关闭' : '${p.customSkipIntroSecs} 秒',
              value: p.customSkipIntroSecs.toDouble(),
              min: 0,
              max: 180,
              divisions: 18,
              onChanged: (v) => _updatePrefs(p.copyWith(customSkipIntroSecs: v.round())),
            ),
            _SwitchRow(
              title: '自动跳过片尾',
              value: p.autoSkipOutro,
              onChanged: (v) => _updatePrefs(p.copyWith(autoSkipOutro: v)),
            ),
            _SliderRow(
              title: '自定义跳过片尾时长',
              valueText: p.customSkipOutroSecs == 0 ? '关闭' : '${p.customSkipOutroSecs} 秒',
              value: p.customSkipOutroSecs.toDouble(),
              min: 0,
              max: 180,
              divisions: 18,
              onChanged: (v) => _updatePrefs(p.copyWith(customSkipOutroSecs: v.round())),
            ),
          ],
        ),
      ],
    );
  }

  // 9. 视频设置
  Widget _buildVideo(Map<String, dynamic> s, VedroPreferences p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('视频设置'),
        _GroupedCard(
          children: [
            _AppleMenuPickerRow<String>(
              title: '硬件解码模式',
              value: (s['hwdec'] ?? 'auto_zero_copy').toString(),
              items: const {
                'auto_zero_copy': '零拷贝硬解（推荐）',
                'auto_copy': 'Copy-Back 硬解',
                'software': '纯软件解码',
              },
              onChanged: (v) => _updateRustSetting('hwdec', v),
            ),
            _SwitchRow(
              title: '优先原生杜比视界',
              subtitle: '支持原生 HDR/DoVi 的屏幕直出，否则自动 Tone-Mapping',
              value: s['prefer_native_dolby_vision'] != false,
              onChanged: (v) => _updateRustSetting('prefer_native_dolby_vision', v),
            ),
            _AppleMenuPickerRow<String>(
              title: 'HDR 色调映射算法',
              value: (s['tone_mapping'] ?? 'bt2446a').toString(),
              items: const {
                'bt2446a': 'BT.2446a（自然高光）',
                'spline': 'Spline（动态曲线）',
                'st2094_40': 'ST.2094-40',
                'reinhard': 'Reinhard',
                'hable': 'Hable（电影感曲线）',
                'clip': 'Clip（直通）',
              },
              onChanged: (v) => _updateRustSetting('tone_mapping', v),
            ),
            _SwitchRow(
              title: '动态峰值亮度计算',
              subtitle: '实时分析每帧 HDR 峰值以防过曝',
              value: p.hdrComputePeak,
              onChanged: (v) => _updatePrefs(p.copyWith(hdrComputePeak: v)),
            ),
            _SwitchRow(
              title: '去色带 (Deband)',
              subtitle: '平滑暗场渐变断层（适合动漫与低码率片源）',
              value: s['deband'] == true,
              onChanged: (v) => _updateRustSetting('deband', v),
            ),
            _AppleMenuPickerRow<String>(
              title: '默认画面比例',
              value: p.defaultAspect,
              items: const {
                'fit': '原始比例（适应）',
                'fill': '铺满屏幕（裁切黑边）',
                'stretch': '拉伸铺满',
                '16:9': '16:9',
                '21:9': '21:9',
                '2.35:1': '2.35:1',
                '4:3': '4:3',
              },
              onChanged: (v) => _updatePrefs(p.copyWith(defaultAspect: v)),
            ),
            _AppleMenuPickerRow<String>(
              title: '帧率同步策略',
              value: p.videoSync,
              items: const {
                'audio': '音画同步（标准）',
                'display-resample': '显示器刷新率重采样（防微卡顿）',
              },
              onChanged: (v) => _updatePrefs(p.copyWith(videoSync: v)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _GroupHeader('人像美颜相机（可叠加 GPU）'),
        KeyedSubtree(
          key: const ValueKey('settings-beauty-filter-card'),
          child: _GroupedCard(
            children: [
              Builder(
                builder: (context) {
                  final bp = BeautyFilterEngine.resolveParams(
                    presetId: p.beautyFilterPreset,
                    strength: p.beautyFilterStrength,
                    smooth: p.beautySmooth,
                    whiten: p.beautyWhiten,
                    rosy: p.beautyRosy,
                    clarity: p.beautyClarity,
                  );
                  void saveChannel(BeautyFilterParams next) {
                    _updatePrefs(p.copyWith(
                      beautyFilterPreset: next.isActive ? 'custom' : 'off',
                      beautySmooth: next.smooth,
                      beautyWhiten: next.whiten,
                      beautyRosy: next.rosy,
                      beautyClarity: next.clarity,
                    ));
                  }

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bp.isActive
                              ? '当前效果：${BeautyFilterPreset.displayLabelFor(p.beautyFilterPreset, bp)} · ${bp.summaryLabel()}'
                              : '当前效果：原画关闭 · 可点选综合预设或直接拉动下方维度自由叠加',
                          style: TextStyle(color: VedroSkin.of(context).fg2, fontSize: 12.5),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: BeautyFilterPreset.all.map((preset) {
                            final selected = preset.id == 'off'
                                ? !bp.isActive
                                : (p.beautyFilterPreset == preset.id && bp.isActive);
                            return ChoiceChip(
                              selected: selected,
                              label: Text(preset.label, style: const TextStyle(fontSize: 12.5)),
                              onSelected: (_) => _updatePrefs(p.copyWith(
                                beautyFilterPreset: preset.id,
                                beautySmooth: preset.smooth,
                                beautyWhiten: preset.whiten,
                                beautyRosy: preset.rosy,
                                beautyClarity: preset.clarity,
                              )),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 10),
                        VedroPrecisionSlider(
                          label: '磨皮（肤质保边）',
                          value: bp.smooth,
                          min: 0.0,
                          max: 1.0,
                          step: 0.05,
                          defaultValue: 0.58,
                          snapValues: const [0.0, 0.35, 0.60, 0.85],
                          valueText: '${(bp.smooth * 100).round()}%',
                          onChanged: (v) => saveChannel(bp.copyWith(smooth: v)),
                        ),
                        const SizedBox(height: 8),
                        VedroPrecisionSlider(
                          label: '美白（仅提亮肤色）',
                          value: bp.whiten,
                          min: 0.0,
                          max: 1.0,
                          step: 0.05,
                          defaultValue: 0.42,
                          snapValues: const [0.0, 0.35, 0.60, 0.85],
                          valueText: '${(bp.whiten * 100).round()}%',
                          onChanged: (v) => saveChannel(bp.copyWith(whiten: v)),
                        ),
                        const SizedBox(height: 8),
                        VedroPrecisionSlider(
                          label: '粉嫩（气色与润唇）',
                          value: bp.rosy,
                          min: 0.0,
                          max: 1.0,
                          step: 0.05,
                          defaultValue: 0.30,
                          snapValues: const [0.0, 0.30, 0.55, 0.80],
                          valueText: '${(bp.rosy * 100).round()}%',
                          onChanged: (v) => saveChannel(bp.copyWith(rosy: v)),
                        ),
                        const SizedBox(height: 8),
                        VedroPrecisionSlider(
                          label: '亮眼清晰（五官立体）',
                          value: bp.clarity,
                          min: 0.0,
                          max: 1.0,
                          step: 0.05,
                          defaultValue: 0.40,
                          snapValues: const [0.0, 0.35, 0.60, 0.85],
                          valueText: '${(bp.clarity * 100).round()}%',
                          onChanged: (v) => saveChannel(bp.copyWith(clarity: v)),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0x1CF59E0B),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0x45F59E0B), width: 0.7),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.local_fire_department_outlined,
                                size: 15,
                                color: Color(0xFFD97706),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  '${BeautyFilterEngine.thermalNotice}（播放时也可直接点击底栏「美颜」按钮实时叠加调节）',
                                  style: TextStyle(
                                    color: VedroSkin.of(context).fg2,
                                    fontSize: 11.5,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _GroupHeader('Anime4K 超分与高级 MPV 参数'),
        _GroupedCard(
          children: [
            _SwitchRow(
              title: '启用 Anime4K 动漫超分锐化',
              subtitle: '自动启用 LanczosSharp 升频、暗场去色带与线条增强',
              value: p.anime4kEnabled,
              onChanged: (v) => _updatePrefs(p.copyWith(anime4kEnabled: v)),
            ),
            _AppleMenuPickerRow<String>(
              title: 'Anime4K 锐化等级',
              value: p.anime4kMode,
              items: const {
                'A': 'Mode A（高锐度修复）',
                'B': 'Mode B（均衡推荐）',
                'C': 'Mode C（柔和自然）',
                'A+A': 'Mode A+A（强效超分）',
                'B+B': 'Mode B+B（高质感均衡）',
              },
              onChanged: (v) => _updatePrefs(p.copyWith(anime4kMode: v)),
            ),
            _SwitchRow(
              title: '仅对动漫 / 动画片源生效',
              subtitle: '电影与实拍剧集保持原片质感，不额外锐化',
              value: p.anime4kOnlyAnime,
              onChanged: (v) => _updatePrefs(p.copyWith(anime4kOnlyAnime: v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Builder(
                builder: (ctx) {
                  final skin = VedroSkin.of(ctx);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '自定义 mpv.conf 参数（每行一条 key=value，# 开头为注释）',
                        style: TextStyle(color: skin.fg2, fontSize: 12.5),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _mpvConfCtrl,
                        minLines: 3,
                        maxLines: 6,
                        style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: skin.fg),
                        decoration: const InputDecoration(
                          hintText: '# 示例：\ninterpolation=yes\ntscale=oversample\ndither-depth=auto',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton(
                          onPressed: () async {
                            await _updatePrefs(p.copyWith(customMpvConf: _mpvConfCtrl.text.trim()));
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已保存自定义 mpv.conf，下次播放生效')),
                              );
                            }
                          },
                          child: const Text('保存 mpv.conf', style: TextStyle(fontSize: 13)),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 10. 音频设置
  Widget _buildAudio(Map<String, dynamic> s, VedroPreferences p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('音频设置'),
        _GroupedCard(
          children: [
            _AppleMenuPickerRow<String>(
              title: '音频输出模式',
              value: (s['audio_mode'] ?? 'auto').toString(),
              items: const {
                'auto': '自动（推荐）',
                'passthrough_bitstream': 'HDMI 源码直通 (Atmos / DTS:X)',
                'spatial_audio': '系统空间音频',
                'headphone_binaural': '耳机双耳空间化',
                'pcm_stereo': '32-bit 立体声 PCM',
              },
              onChanged: (v) => _updateRustSetting('audio_mode', v),
            ),
            _InlineSegmentedRow<String>(
              title: '首选音轨语言',
              value: p.preferredAudioLang,
              items: const [
                ('auto', '原声自动'),
                ('zh', '中文/国语'),
                ('yue', '粤语'),
                ('ja', '日语'),
                ('en', '英语'),
              ],
              onChanged: (v) => _updatePrefs(p.copyWith(preferredAudioLang: v)),
            ),
            _InlineSegmentedRow<int>(
              title: '最大音量增益',
              value: p.maxVolumePercent <= 112
                  ? 100
                  : (p.maxVolumePercent <= 137 ? 125 : 150),
              items: const [(100, '100%'), (125, '125%'), (150, '150%')],
              onChanged: (v) => _updatePrefs(p.copyWith(maxVolumePercent: v)),
            ),
            _SwitchRow(
              title: '夜间模式 (DRC 动态范围压缩)',
              subtitle: '降低爆炸声动态峰值，深夜观影更温和',
              value: s['night_mode'] == true,
              onChanged: (v) => _updateRustSetting('night_mode', v),
            ),
            _SwitchRow(
              title: '人声对白增强',
              value: s['dialogue_boost'] == true,
              onChanged: (v) => _updateRustSetting('dialogue_boost', v),
            ),
          ],
        ),
      ],
    );
  }

  // 11. 字幕设置
  Widget _buildSubtitles(VedroPreferences p) {
    final skin = VedroSkin.of(context);
    const colors = [
      ('#FFFFFF', '纯白', Color(0xFFFFFFFF)),
      ('#FFE082', '暖黄', Color(0xFFFFE082)),
      ('#A7F3D0', '淡青', Color(0xFFA7F3D0)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('字幕设置'),
        _GroupedCard(
          children: [
            _InlineSegmentedRow<String>(
              title: '首选字幕语言',
              value: p.preferredSubLang,
              items: const [
                ('zh', '简中'),
                ('zh-Hant', '繁中'),
                ('en', '英语/双语'),
                ('ja', '日语'),
                ('off', '关闭'),
              ],
              onChanged: (v) => _updatePrefs(p.copyWith(preferredSubLang: v)),
            ),
            _SwitchRow(
              title: '自动加载服务器外挂字幕',
              value: p.autoLoadExternalSubs,
              onChanged: (v) => _updatePrefs(p.copyWith(autoLoadExternalSubs: v)),
            ),
            _SwitchRow(
              title: '强制覆盖 ASS 字幕样式',
              subtitle: '使用下方统一字体与字号覆盖特效字幕原有样式',
              value: p.forceAssOverride,
              onChanged: (v) => _updatePrefs(p.copyWith(forceAssOverride: v)),
            ),
            _SliderRow(
              title: '默认字号缩放',
              valueText: '${(p.subtitleFontScale * 100).round()}%',
              value: p.subtitleFontScale,
              min: 0.6,
              max: 1.8,
              divisions: 12,
              onChanged: (v) => _updatePrefs(p.copyWith(subtitleFontScale: v)),
            ),
            _SliderRow(
              title: '默认垂直位置',
              valueText: '${p.subtitlePos}%',
              value: p.subtitlePos.toDouble(),
              min: 65,
              max: 100,
              divisions: 7,
              onChanged: (v) => _updatePrefs(p.copyWith(subtitlePos: v.round())),
            ),
            _SliderRow(
              title: '字幕描边宽度',
              valueText: p.subtitleOutlineWidth.toStringAsFixed(1),
              value: p.subtitleOutlineWidth,
              min: 0.0,
              max: 5.0,
              divisions: 10,
              onChanged: (v) => _updatePrefs(p.copyWith(subtitleOutlineWidth: v)),
            ),
            _SliderRow(
              title: '背景遮罩不透明度',
              valueText: '${(p.subtitleBgOpacity * 100).round()}%',
              value: p.subtitleBgOpacity,
              min: 0.0,
              max: 0.8,
              divisions: 8,
              onChanged: (v) => _updatePrefs(p.copyWith(subtitleBgOpacity: v)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final chips = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: colors.map((entry) {
                      final (hex, label, c) = entry;
                      final on = p.subtitleColorHex == hex;
                      return PressableScale(
                        onTap: () => _updatePrefs(p.copyWith(subtitleColorHex: hex)),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5.5),
                          decoration: BoxDecoration(
                            color: on ? skin.accent.withValues(alpha: 0.14) : skin.surface2,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: on ? skin.accent : skin.border,
                              width: on ? 1.1 : 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 11,
                                height: 11,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.black26, width: 0.6),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(label, style: TextStyle(color: skin.fg, fontSize: 12)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                  if (constraints.maxWidth < 380) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('字幕颜色', style: TextStyle(color: skin.fg, fontSize: 14)),
                        const SizedBox(height: 8),
                        chips,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: Text('字幕颜色', style: TextStyle(color: skin.fg, fontSize: 14)),
                      ),
                      chips,
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 12. 弹幕设置
  Widget _buildDanmaku(VedroPreferences p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('弹幕设置'),
        _GroupedCard(
          children: [
            _SwitchRow(
              title: '默认开启弹幕层',
              value: p.danmakuEnabled,
              onChanged: (v) => _updatePrefs(p.copyWith(danmakuEnabled: v)),
            ),
            _SliderRow(
              title: '弹幕不透明度',
              valueText: '${(p.danmakuOpacity * 100).round()}%',
              value: p.danmakuOpacity,
              min: 0.2,
              max: 1.0,
              divisions: 8,
              onChanged: (v) => _updatePrefs(p.copyWith(danmakuOpacity: v)),
            ),
            _SliderRow(
              title: '弹幕字号',
              valueText: '${p.danmakuFontSize.round()} pt',
              value: p.danmakuFontSize,
              min: 14,
              max: 28,
              divisions: 7,
              onChanged: (v) => _updatePrefs(p.copyWith(danmakuFontSize: v)),
            ),
            _SliderRow(
              title: '弹幕滚动时长（越小越快）',
              valueText: '${p.danmakuSpeedSecs.round()} 秒/屏',
              value: p.danmakuSpeedSecs,
              min: 5,
              max: 15,
              divisions: 10,
              onChanged: (v) => _updatePrefs(p.copyWith(danmakuSpeedSecs: v)),
            ),
            _InlineSegmentedRow<double>(
              title: '弹幕显示区域',
              value: p.danmakuArea,
              items: const [(0.25, '1/4 屏'), (0.5, '半屏'), (0.75, '3/4 屏'), (1.0, '全屏')],
              onChanged: (v) => _updatePrefs(p.copyWith(danmakuArea: v)),
            ),
            _SwitchRow(
              title: '屏蔽顶部固定弹幕',
              value: p.danmakuHideTop,
              onChanged: (v) => _updatePrefs(p.copyWith(danmakuHideTop: v)),
            ),
            _SwitchRow(
              title: '屏蔽底部固定弹幕',
              value: p.danmakuHideBottom,
              onChanged: (v) => _updatePrefs(p.copyWith(danmakuHideBottom: v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('自定义弹幕源',
                      style: TextStyle(color: VedroSkin.of(context).fg2, fontSize: 12.5)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _danmakuApiCtrl,
                          decoration: const InputDecoration(
                            hintText: '留空使用内置多源匹配',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: () => _updatePrefs(
                          p.copyWith(danmakuApiUrl: _danmakuApiCtrl.text.trim()),
                        ),
                        child: const Text('保存', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
