part of '../settings_screen.dart';

/// AI Translation/Local ASR, Privacy Lock, Config Backup & About/Updates sections.
extension _SettingsAiPrivacySectionsExt on _SettingsDetailPaneState {
  // 13. AI 翻译（极简零废话 UI + 模型列表一键拉取 + 直连/代理出口切换）
  Widget _buildAi(VedroAppState app, VedroPreferences p) {
    final isBili = p.aiBaseUrl.toLowerCase().contains('index-translate.bilibili.com');

    Future<void> applyPreset({
      required String baseUrl,
      required String model,
      required bool directIp,
      bool clearKey = false,
    }) async {
      final oldHost = Uri.tryParse(p.aiBaseUrl)?.host.toLowerCase() ?? '';
      final newHost = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
      final shouldClearKey = clearKey || (oldHost.isNotEmpty && newHost.isNotEmpty && oldHost != newHost);
      _aiUrlCtrl.text = baseUrl;
      _aiModelCtrl.text = model;
      if (shouldClearKey) _aiKeyCtrl.clear();
      await _updatePrefs(p.copyWith(
        aiEnabled: true,
        aiBaseUrl: baseUrl,
        aiModel: model,
        aiApiKey: shouldClearKey ? '' : _aiKeyCtrl.text.trim(),
        aiDirectClientIp: directIp,
        aiCachedModels: const [],
      ));
    }

    Future<void> applyAsrPreset({
      required String baseUrl,
      required String model,
      required bool directIp,
      bool clearKey = false,
    }) async {
      final oldHost = Uri.tryParse(p.asrBaseUrl)?.host.toLowerCase() ?? '';
      final newHost = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
      final shouldClearKey = clearKey || (oldHost.isNotEmpty && newHost.isNotEmpty && oldHost != newHost);
      _asrUrlCtrl.text = baseUrl;
      _asrModelCtrl.text = model;
      if (shouldClearKey) _asrKeyCtrl.clear();
      await _updatePrefs(p.copyWith(
        asrEnabled: true,
        asrBaseUrl: baseUrl,
        asrModel: model,
        asrApiKey: shouldClearKey ? '' : _asrKeyCtrl.text.trim(),
        asrDirectClientIp: directIp,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'AI 翻译',
          '支持影片简介翻译、播放器 YouTube 式双语字幕预读翻译，以及无字幕视频 AI 语音识别转译',
        ),
        const _GroupHeader('文本与双语字幕翻译'),
        _GroupedCard(
          children: [
            _SwitchRow(
              title: '启用翻译',
              value: p.aiEnabled,
              onChanged: (v) => _updatePrefs(p.copyWith(aiEnabled: v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    key: const ValueKey('ai-preset-bilibili'),
                    selected: isBili,
                    label: const Text('Bilibili'),
                    onSelected: (_) => applyPreset(
                      baseUrl: 'https://index-translate.bilibili.com/v1',
                      model: 'Index-Translate-35B-A3B',
                      directIp: true,
                      clearKey: true,
                    ),
                  ),
                  ChoiceChip(
                    selected: p.aiBaseUrl.contains('deepseek.com'),
                    label: const Text('DeepSeek'),
                    onSelected: (_) => applyPreset(
                      baseUrl: 'https://api.deepseek.com/v1',
                      model: 'deepseek-chat',
                      directIp: true,
                    ),
                  ),
                  ChoiceChip(
                    selected: p.aiBaseUrl.contains('openai.com'),
                    label: const Text('OpenAI'),
                    onSelected: (_) => applyPreset(
                      baseUrl: 'https://api.openai.com/v1',
                      model: 'gpt-4o-mini',
                      directIp: false,
                    ),
                  ),
                  ChoiceChip(
                    selected: p.aiBaseUrl.contains('11434'),
                    label: const Text('Ollama'),
                    onSelected: (_) => applyPreset(
                      baseUrl: 'http://127.0.0.1:11434/v1',
                      model: 'qwen2.5:7b',
                      directIp: true,
                      clearKey: true,
                    ),
                  ),
                ],
              ),
            ),
            if (isBili)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: VedroSkin.of(context).accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: VedroSkin.of(context).accent.withValues(alpha: 0.28),
                      width: 0.7,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 15, color: VedroSkin.of(context).accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bilibili 公共免费接口已自动启用礼貌限流保护：单线程请求、≥2.4 秒间隔、预读上限 55 秒且本地持久化缓存译文，不重复轰炸公共服务；如需更快并发可切换 DeepSeek / OpenAI / Ollama。',
                          style: TextStyle(
                            color: VedroSkin.of(context).fg2,
                            fontSize: 11.5,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            _InlineSegmentedRow<String>(
              title: '目标语言',
              value: p.aiTargetLang,
              items: const [
                ('简体中文', '简中'),
                ('繁體中文', '繁中'),
                ('English', 'EN'),
                ('日本語', '日文'),
              ],
              onChanged: (v) => _updatePrefs(p.copyWith(aiTargetLang: v)),
            ),
            _InlineSegmentedRow<bool>(
              title: '网络出口',
              keyPrefix: 'ai-egress',
              value: p.aiDirectClientIp,
              items: const [
                (true, '本机直连'),
                (false, '跟随系统'),
              ],
              onChanged: (v) => _updatePrefs(p.copyWith(aiDirectClientIp: v)),
            ),
            _SwitchRow(
              title: '双语对照',
              value: p.aiBilingualSubtitle,
              onChanged: (v) => _updatePrefs(p.copyWith(aiBilingualSubtitle: v)),
            ),
            _InlineSegmentedRow<String>(
              title: '双语字幕默认排版',
              keyPrefix: 'pref-ai-subtitle-mode',
              value: p.aiSubtitleMode,
              items: const [
                ('bilingual_trans_top', '译文在上'),
                ('bilingual_orig_top', '原文在上'),
                ('translated_only', '仅译文'),
              ],
              onChanged: (v) => _updatePrefs(p.copyWith(aiSubtitleMode: v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: VedroPrecisionSlider(
                key: const ValueKey('pref-ai-subtitle-font-scale'),
                label: '翻译字幕默认字号',
                valueText: '${(p.aiSubtitleFontScale * 100).round()}%',
                value: p.aiSubtitleFontScale,
                min: 0.6,
                max: 1.8,
                step: 0.05,
                defaultValue: 1.0,
                snapValues: const [0.8, 1.0, 1.25, 1.5],
                onChanged: (v) => _updatePrefs(p.copyWith(aiSubtitleFontScale: v)),
              ),
            ),
            _InlineSegmentedRow<int>(
              title: '字幕预读批量',
              keyPrefix: 'pref-ai-subtitle-batch',
              value: p.aiSubtitleBatchSize,
              items: const [
                (12, '12 句'),
                (16, '16 句'),
                (24, '24 句'),
              ],
              onChanged: (v) => _updatePrefs(p.copyWith(aiSubtitleBatchSize: v)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _aiUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'API Base URL',
                      hintText: 'https://api.openai.com/v1',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _aiKeyCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: isBili ? '免 Key' : 'sk-...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _aiModelCtrl,
                          decoration: const InputDecoration(
                            labelText: '模型',
                            hintText: 'gpt-4o-mini',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        key: const ValueKey('ai-fetch-models-btn'),
                        onPressed: _fetchingAiModels
                            ? null
                            : () async {
                                _setDetailPaneState(() {
                                  _fetchingAiModels = true;
                                  _aiTestResult = null;
                                });
                                try {
                                  final models = await app.fetchAiModels(
                                    baseUrl: _aiUrlCtrl.text.trim(),
                                    apiKey: _aiKeyCtrl.text.trim(),
                                    directIp: p.aiDirectClientIp,
                                  );
                                  if (!mounted) return;
                                  if (models.isNotEmpty) {
                                    _aiModelCtrl.text = app.prefs.aiModel;
                                  }
                                  _setDetailPaneState(() => _aiTestResult = '已获取 ${models.length} 个模型');
                                } catch (e) {
                                  if (mounted) {
                                    _setDetailPaneState(() => _aiTestResult = e
                                        .toString()
                                        .replaceFirst('VedroCoreException: ', '')
                                        .replaceFirst('Exception: ', ''));
                                  }
                                } finally {
                                  if (mounted) _setDetailPaneState(() => _fetchingAiModels = false);
                                }
                              },
                        icon: const Icon(Icons.list_alt_rounded, size: 15),
                        label: Text(_fetchingAiModels ? '获取中' : '获取模型'),
                      ),
                    ],
                  ),
                  if (p.aiCachedModels.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 132),
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: p.aiCachedModels.map((m) {
                            final selected = p.aiModel == m;
                            return ChoiceChip(
                              key: ValueKey('ai-model-chip-$m'),
                              selected: selected,
                              label: Text(m, style: const TextStyle(fontSize: 12)),
                              onSelected: (_) {
                                _aiModelCtrl.text = m;
                                _updatePrefs(p.copyWith(
                                  aiBaseUrl: _aiUrlCtrl.text.trim(),
                                  aiApiKey: _aiKeyCtrl.text.trim(),
                                  aiModel: m,
                                ));
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: () async {
                          await _updatePrefs(p.copyWith(
                            aiBaseUrl: _aiUrlCtrl.text.trim(),
                            aiApiKey: _aiKeyCtrl.text.trim(),
                            aiModel: _aiModelCtrl.text.trim(),
                          ));
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已保存')),
                            );
                          }
                        },
                        child: const Text('保存', style: TextStyle(fontSize: 13)),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: _testingAi
                            ? null
                            : () async {
                                await _updatePrefs(p.copyWith(
                                  aiEnabled: true,
                                  aiBaseUrl: _aiUrlCtrl.text.trim(),
                                  aiApiKey: _aiKeyCtrl.text.trim(),
                                  aiModel: _aiModelCtrl.text.trim(),
                                ));
                                if (!mounted) return;
                                _setDetailPaneState(() {
                                  _testingAi = true;
                                  _aiTestResult = null;
                                });
                                try {
                                  final res = await app.translateText('Hello Cinema World');
                                  if (mounted) {
                                    _setDetailPaneState(() => _aiTestResult = res);
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    _setDetailPaneState(() => _aiTestResult =
                                        e.toString().replaceFirst('VedroCoreException: ', ''));
                                  }
                                } finally {
                                  if (mounted) _setDetailPaneState(() => _testingAi = false);
                                }
                              },
                        child: Text(_testingAi ? '测试中' : '测试', style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                  if (_aiTestResult != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _aiTestResult!,
                      style: TextStyle(
                        color: (_aiTestResult!.contains('失败') || _aiTestResult!.contains('HTTP'))
                            ? VedroTheme.danger
                            : const Color(0xFF10B981),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _GroupHeader('AI 语音识别转字幕 (ASR · 无字幕视频自动听音转译)'),
        KeyedSubtree(
          key: const ValueKey('settings-asr-card'),
          child: _GroupedCard(
            children: [
              _InlineSegmentedRow<String>(
                title: '语音识别引擎',
                keyPrefix: 'asr-engine',
                value: p.asrEngine,
                items: const [
                  ('local', '本地离线模型（推荐）'),
                  ('cloud', '云端 / 自建 API'),
                ],
                onChanged: (v) => _updatePrefs(p.copyWith(asrEngine: v)),
              ),
              _InlineSegmentedRow<String>(
                title: '视频原声语言',
                keyPrefix: 'asr-lang',
                value: p.asrSourceLang,
                items: const [
                  ('auto', '自动'),
                  ('ja', '日语'),
                  ('en', '英语'),
                  ('zh', '中文'),
                  ('ko', '韩语'),
                ],
                onChanged: (v) => _updatePrefs(p.copyWith(asrSourceLang: v)),
              ),
              if (p.asrEngine == 'local')
                ListenableBuilder(
                  listenable: LocalAsrManager.instance,
                  builder: (context, _) {
                    final mgr = LocalAsrManager.instance;
                    final skin = VedroSkin.of(context);
                    final accent = Theme.of(context).colorScheme.secondary;
                    final sizeStr = mgr.downloadedBytes > 0
                        ? fmtFileSize(mgr.downloadedBytes)
                        : '约 229 MB';
                    return Padding(
                      key: const ValueKey('settings-local-asr-panel'),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: (mgr.isModelDownloaded
                                          ? const Color(0xFF10B981)
                                          : accent)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  mgr.isModelDownloaded
                                      ? Icons.check_circle_outline_rounded
                                      : Icons.downloading_rounded,
                                  size: 18,
                                  color: mgr.isModelDownloaded
                                      ? const Color(0xFF10B981)
                                      : accent,
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            LocalAsrModelSpec.displayName,
                                            style: TextStyle(
                                              color: skin.fg,
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          mgr.isModelDownloaded ? '已就绪 · $sizeStr' : sizeStr,
                                          style: TextStyle(
                                            color: mgr.isModelDownloaded
                                                ? const Color(0xFF10B981)
                                                : skin.fg3,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      LocalAsrModelSpec.languagesLabel,
                                      style: TextStyle(color: skin.fg3, fontSize: 11.5),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text('下载源：', style: TextStyle(color: skin.fg2, fontSize: 12)),
                              ChoiceChip(
                                selected: p.asrUseChinaMirror,
                                label: const Text('国内镜像加速', style: TextStyle(fontSize: 12)),
                                onSelected: (_) =>
                                    _updatePrefs(p.copyWith(asrUseChinaMirror: true)),
                              ),
                              ChoiceChip(
                                selected: !p.asrUseChinaMirror,
                                label: const Text('HuggingFace 官方', style: TextStyle(fontSize: 12)),
                                onSelected: (_) =>
                                    _updatePrefs(p.copyWith(asrUseChinaMirror: false)),
                              ),
                            ],
                          ),
                          if (mgr.isDownloading) ...[
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: mgr.downloadProgress > 0 ? mgr.downloadProgress : null,
                                minHeight: 5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    mgr.downloadStage,
                                    style: TextStyle(color: skin.fg2, fontSize: 12),
                                  ),
                                ),
                                TextButton(
                                  onPressed: mgr.cancelDownload,
                                  child: const Text('取消', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ],
                          if (mgr.downloadError != null && mgr.downloadError!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              mgr.downloadError!,
                              style: const TextStyle(color: VedroTheme.danger, fontSize: 12),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              if (!mgr.isModelDownloaded)
                                FilledButton.icon(
                                  key: const ValueKey('download-local-asr-btn'),
                                  onPressed: mgr.isDownloading
                                      ? null
                                      : () => mgr.downloadModel(
                                            useChinaMirror: p.asrUseChinaMirror,
                                          ),
                                  icon: const Icon(Icons.download_rounded, size: 16),
                                  label: Text(
                                    mgr.isDownloading ? '正在下载…' : '一键下载离线模型 (~229 MB)',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                )
                              else
                                OutlinedButton.icon(
                                  key: const ValueKey('delete-local-asr-btn'),
                                  onPressed: mgr.isDownloading
                                      ? null
                                      : () async {
                                          final messenger = ScaffoldMessenger.of(context);
                                          await mgr.deleteModel();
                                          if (mounted) {
                                            messenger.showSnackBar(
                                              const SnackBar(content: Text('已删除本地离线语音模型')),
                                            );
                                          }
                                        },
                                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                  label: const Text('删除模型释放空间', style: TextStyle(fontSize: 12.5)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '内置 sherpa-onnx + Silero VAD 直接从视频流提取音轨，无需录屏/麦克风权限弹窗；完全本地离线免费识别，中高端手机可流畅运行（长时间识别会有轻微功耗与温热，建议搭配上方 AI 翻译生成双语字幕）。',
                            style: TextStyle(color: skin.fg3, fontSize: 11.5, height: 1.45),
                          ),
                        ],
                      ),
                    );
                  },
                )
              else ...[
                _SwitchRow(
                  key: const ValueKey('pref-asr-enabled'),
                  title: '启用云端 / 自建语音识别',
                  subtitle: '零本地模型占用，通过 OpenAI 兼容接口切片识别音频并生成双语字幕',
                  value: p.asrEnabled,
                  onChanged: (v) => _updatePrefs(p.copyWith(asrEnabled: v)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        key: const ValueKey('asr-preset-groq'),
                        selected: p.asrBaseUrl.contains('groq.com'),
                        label: const Text('Groq Whisper（极速）'),
                        onSelected: (_) => applyAsrPreset(
                          baseUrl: 'https://api.groq.com/openai/v1',
                          model: 'whisper-large-v3-turbo',
                          directIp: false,
                        ),
                      ),
                      ChoiceChip(
                        key: const ValueKey('asr-preset-siliconflow'),
                        selected: p.asrBaseUrl.contains('siliconflow.cn'),
                        label: const Text('硅基流动 SenseVoice'),
                        onSelected: (_) => applyAsrPreset(
                          baseUrl: 'https://api.siliconflow.cn/v1',
                          model: 'FunAudioLLM/SenseVoiceSmall',
                          directIp: true,
                        ),
                      ),
                      ChoiceChip(
                        selected: p.asrBaseUrl.contains('openai.com'),
                        label: const Text('OpenAI Whisper'),
                        onSelected: (_) => applyAsrPreset(
                          baseUrl: 'https://api.openai.com/v1',
                          model: 'whisper-1',
                          directIp: false,
                        ),
                      ),
                      ChoiceChip(
                        selected: p.asrBaseUrl.contains('127.0.0.1') ||
                            p.asrBaseUrl.contains('localhost'),
                        label: const Text('本地 / NAS Whisper'),
                        onSelected: (_) => applyAsrPreset(
                          baseUrl: 'http://127.0.0.1:8000/v1',
                          model: 'whisper-large-v3-turbo',
                          directIp: true,
                          clearKey: true,
                        ),
                      ),
                    ],
                  ),
                ),
                _InlineSegmentedRow<bool>(
                  title: 'ASR 网络出口',
                  value: p.asrDirectClientIp,
                  items: const [
                    (true, '本机直连'),
                    (false, '跟随系统'),
                  ],
                  onChanged: (v) => _updatePrefs(p.copyWith(asrDirectClientIp: v)),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _asrUrlCtrl,
                        decoration: const InputDecoration(
                          labelText: 'ASR API Base URL（OpenAI /audio/transcriptions 兼容）',
                          hintText: 'https://api.groq.com/openai/v1',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _asrKeyCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'ASR API Key',
                          hintText: 'gsk_... / sk-...（本地自建可留空）',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _asrModelCtrl,
                        decoration: const InputDecoration(
                          labelText: '语音识别模型',
                          hintText: 'whisper-large-v3-turbo',
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          FilledButton(
                            onPressed: () async {
                              await _updatePrefs(p.copyWith(
                                asrEnabled: true,
                                asrBaseUrl: _asrUrlCtrl.text.trim(),
                                asrApiKey: _asrKeyCtrl.text.trim(),
                                asrModel: _asrModelCtrl.text.trim(),
                              ));
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('语音识别 (ASR) 配置已保存')),
                                );
                              }
                            },
                            child: const Text('保存语音识别配置', style: TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // 14. 隐私保护
  Widget _buildPrivacy(VedroPreferences p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('隐私保护'),
        _GroupedCard(
          children: [
            _SwitchRow(
              title: '启用密码解锁应用',
              subtitle: '启动或从后台切回时需要输入 4 位数字密码',
              value: p.passcodeEnabled,
              onChanged: (v) async {
                if (v) {
                  await _openSetPinDialog(p);
                } else {
                  final verified = await _verifyCurrentPin(p, title: '输入当前密码以关闭应用锁');
                  if (verified && mounted) {
                    await _updatePrefs(p.copyWith(passcodeEnabled: false, passcodeHash: ''));
                  }
                }
              },
            ),
            if (p.passcodeEnabled)
              _ActionRow(
                title: '修改 4 位解锁密码',
                trailing: Icon(Icons.chevron_right_rounded, size: 18, color: VedroSkin.of(context).fg3),
                onTap: () async {
                  final verified = await _verifyCurrentPin(p, title: '验证当前密码');
                  if (verified && mounted) {
                    await _openSetPinDialog(p);
                  }
                },
              ),
            _InlineSegmentedRow<int>(
              title: '自动锁定时间',
              value: p.lockTimeoutSecs,
              items: const [(0, '立即'), (60, '1 分'), (300, '5 分'), (900, '15 分')],
              onChanged: (v) => _updatePrefs(p.copyWith(lockTimeoutSecs: v)),
            ),
          ],
        ),
      ],
    );
  }

  // 15. 备份与关于
  Widget _buildAboutAndBackup(VedroAppState app) {
    final skin = VedroSkin.of(context);
    final version = app.core.coreVersion;

    Future<void> exportBackup() async {
      final jsonText = app.exportConfigJson();
      await Clipboard.setData(ClipboardData(text: jsonText));
      if (!mounted) return;
      await showVedroDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: skin.surface,
          title: Text('已导出配置备份', style: TextStyle(color: skin.fg, fontSize: 16)),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '已自动复制到剪贴板（已自动剔除 API Key、应用密码哈希与登录令牌等敏感字段）。',
                  style: TextStyle(color: skin.fg2, fontSize: 12.5, height: 1.45),
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: skin.surface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: skin.border, width: 0.7),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        jsonText,
                        style: TextStyle(color: skin.fg2, fontFamily: 'monospace', fontSize: 11.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: jsonText));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('再次复制'),
            ),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('完成'),
            ),
          ],
        ),
      );
    }

    Future<void> importBackup() async {
      String? err;
      final ok = await showVedroDialog<bool>(
        context: context,
        builder: (ctx) => VedroControllerScope<TextEditingController>(
          create: () => TextEditingController(),
          dispose: (c) => c.dispose(),
          builder: (ctx, ctrl) => StatefulBuilder(
            builder: (ctx, setModal) => AlertDialog(
              backgroundColor: skin.surface,
              title: Text('导入配置备份', style: TextStyle(color: skin.fg, fontSize: 16)),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '粘贴由 Vedro 导出的 JSON 配置，将恢复外观、播放、字幕、弹幕及首页布局（不影响已登录服务器与安全密码）。',
                      style: TextStyle(color: skin.fg2, fontSize: 12.5, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: ctrl,
                      minLines: 4,
                      maxLines: 8,
                      style: TextStyle(color: skin.fg, fontFamily: 'monospace', fontSize: 12),
                      decoration: const InputDecoration(hintText: '{"format":"vedro-backup-v1", ...}'),
                    ),
                    if (err != null) ...[
                      const SizedBox(height: 8),
                      Text(err!, style: const TextStyle(color: VedroTheme.danger, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (ctx.mounted && data?.text != null) {
                      ctrl.text = data!.text!;
                      setModal(() => err = null);
                    }
                  },
                  child: const Text('从剪贴板粘贴'),
                ),
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                FilledButton(
                  onPressed: () async {
                    try {
                      await app.importConfigJson(ctrl.text);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      if (ctx.mounted) setModal(() => err = VedroErrorFormatter.friendly(e));
                    }
                  },
                  child: const Text('导入'),
                ),
              ],
            ),
          ),
        ),
      );
      if (ok == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已成功导入配置备份')),
        );
      }
    }

    Future<void> confirmResetPrefs() async {
      final ok = await showVedroDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: skin.surface,
          title: Text('恢复默认偏好设置？', style: TextStyle(color: skin.fg, fontSize: 16)),
          content: Text(
            '将重置外观皮肤、播放、视频、字幕、弹幕及界面偏好为出厂默认值，不会删除已保存的服务器、账号或离线下载文件。',
            style: TextStyle(color: skin.fg2, fontSize: 13),
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: VedroTheme.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('恢复默认'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await app.resetPreferencesToDefaults();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已恢复默认偏好设置')),
          );
        }
      }
    }

    Future<void> copyDiagnostics() async {
      final diag = [
        'Vedro v$version',
        'OS: ${kIsWeb ? 'web' : Platform.operatingSystem} ${kIsWeb ? '' : Platform.operatingSystemVersion}',
        'TV Mode: ${PlatformPerfProfile.isTv} (override=${app.prefs.tvModeOverride})',
        'Skin: ${app.prefs.skinId} (${app.prefs.themeMode})',
        'Server: ${app.isSignedIn ? (app.capabilities?.dialect ?? 'connected') : 'signed_out'} (${app.savedServers.length} saved)',
        'Video: hwdec=${app.settings['hwdec'] ?? 'auto_zero_copy'}, tone=${app.settings['tone_mapping'] ?? 'bt2446a'}, anime4k=${app.prefs.anime4kEnabled}, beauty=${app.prefs.beautyFilterPreset}',
        'Audio: mode=${app.settings['audio_mode'] ?? 'auto'}, maxVol=${app.prefs.maxVolumePercent}%',
        'AI/ASR: ai=${app.prefs.aiEnabled ? app.prefs.aiModel : 'off'}, asr=${app.prefs.asrEngine} (localReady=${LocalAsrManager.instance.isModelDownloaded})',
        'Downloads: ${app.downloads.length} tasks',
      ].join('\n');
      await Clipboard.setData(ClipboardData(text: diag));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制脱敏诊断信息到剪贴板')),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('备份与关于', '配置导出恢复、诊断信息与版本更新'),
        const _GroupHeader('配置备份与恢复'),
        _GroupedCard(
          children: [
            _ActionRow(
              title: '导出配置备份 (JSON)',
              trailing: Icon(Icons.ios_share_rounded, size: 17, color: skin.fg3),
              onTap: exportBackup,
            ),
            _ActionRow(
              title: '导入配置备份 (JSON)',
              trailing: Icon(Icons.download_for_offline_outlined, size: 18, color: skin.fg3),
              onTap: importBackup,
            ),
            _ActionRow(
              title: '恢复默认偏好设置',
              trailing: const Icon(Icons.restart_alt_rounded, size: 18, color: VedroTheme.danger),
              onTap: confirmResetPrefs,
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _GroupHeader('关于 Vedro'),
        _GroupedCard(
          children: [
            _InfoKVRow('当前版本', 'v$version', mono: true, highlight: true),
            _InfoKVRow('运行平台', kIsWeb ? 'Web' : Platform.operatingSystem),
            _SwitchRow(
              title: '启动时自动检查更新',
              subtitle: '检测到新版本时自动弹窗，支持应用内 SHA-256 校验与一键安装',
              value: app.prefs.autoCheckUpdates,
              onChanged: (v) => _updatePrefs(app.prefs.copyWith(autoCheckUpdates: v)),
            ),
            UpdateCheckBadgeTile(currentVersion: version),
            _ActionRow(
              title: '复制脱敏诊断信息',
              trailing: Icon(Icons.copy_rounded, size: 17, color: skin.fg3),
              onTap: copyDiagnostics,
            ),
            _ActionRow(
              title: 'GitHub 开源主页',
              trailing: Icon(Icons.open_in_new_rounded, size: 17, color: skin.fg3),
              onTap: () => NativePlaybackChannel.openUrl('https://github.com/JHruan1/vedro'),
            ),
            _ActionRow(
              title: '开源软件许可声明',
              trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.fg3),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Vedro',
                applicationVersion: 'v$version',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<bool> _verifyCurrentPin(VedroPreferences p, {required String title}) async {
    if (p.passcodeHash.isEmpty) return true;
    final lockout = PinLockoutController.forState(widget.appState);
    final initRem = lockout.remainingLockoutSecs;
    String? err = initRem > 0 ? '尝试次数过多，请 $initRem 秒后重试' : null;
    final ok = await showVedroDialog<bool>(
      context: context,
      builder: (ctx) => VedroControllerScope<TextEditingController>(
        create: () => TextEditingController(),
        dispose: (c) => c.dispose(),
        builder: (ctx, ctrl) => StatefulBuilder(
          builder: (ctx, setModal) {
            void submit() {
              final res = lockout.verify(ctrl.text.trim(), p.passcodeHash);
              if (!res.ok) {
                setModal(() => err = res.error ?? '密码不正确');
                return;
              }
              Navigator.pop(ctx, true);
            }

            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    obscureText: true,
                    maxLength: 4,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => submit(),
                    decoration: const InputDecoration(labelText: '请输入当前 4 位数字密码', counterText: ''),
                  ),
                  if (err != null) ...[
                    const SizedBox(height: 8),
                    Text(err!, style: const TextStyle(color: VedroTheme.danger, fontSize: 12.5)),
                  ],
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                FilledButton(onPressed: submit, child: const Text('验证')),
              ],
            );
          },
        ),
      ),
    );
    return ok == true;
  }

  Future<void> _openSetPinDialog(VedroPreferences p) async {
    String? err;
    final chosenPin = await showVedroDialog<String>(
      context: context,
      builder: (ctx) => VedroControllerScope<List<TextEditingController>>(
        create: () => [TextEditingController(), TextEditingController()],
        dispose: (ctrls) {
          for (final c in ctrls) {
            c.dispose();
          }
        },
        builder: (ctx, ctrls) {
          final pin1 = ctrls[0];
          final pin2 = ctrls[1];
          return StatefulBuilder(
            builder: (ctx, setModal) {
              void submit() {
                final a = pin1.text.trim();
                final b = pin2.text.trim();
                if (!RegExp(r'^\d{4}$').hasMatch(a)) {
                  setModal(() => err = '请输入 4 位纯数字');
                  return;
                }
                if (a != b) {
                  setModal(() => err = '两次输入的密码不一致');
                  return;
                }
                Navigator.pop(ctx, a);
              }

              return AlertDialog(
                title: const Text('设置 4 位应用密码'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: pin1,
                      autofocus: true,
                      obscureText: true,
                      maxLength: 4,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: '输入 4 位数字密码', counterText: ''),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pin2,
                      obscureText: true,
                      maxLength: 4,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => submit(),
                      decoration: const InputDecoration(labelText: '再次确认密码', counterText: ''),
                    ),
                    if (err != null) ...[
                      const SizedBox(height: 10),
                      Text(err!, style: const TextStyle(color: VedroTheme.danger, fontSize: 12.5)),
                    ],
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                  FilledButton(onPressed: submit, child: const Text('保存密码')),
                ],
              );
            },
          );
        },
      ),
    );
    if (chosenPin != null && chosenPin.isNotEmpty && mounted) {
      PinLockoutController.forState(widget.appState).reset();
      await _updatePrefs(p.copyWith(
        passcodeEnabled: true,
        passcodeHash: createSaltedPasscodeHash(chosenPin),
      ));
    }
  }
}
