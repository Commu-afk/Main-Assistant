import 'dart:async';

import 'package:flutter/material.dart';

import '../llm/llm_config.dart';
import '../llm/llm_service.dart';
import '../settings/app_settings.dart';
import '../stt/sherpa_stt_service.dart';
import '../tts/sherpa_tts_service.dart';

/// Сообщение чата. Текст изменяемый: потоковая генерация дописывает его.
class _ChatMessage {
  _ChatMessage({required this.fromUser, this.text = ''});

  final bool fromUser;
  String text;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _llm = LlmService.instance;
  final _sherpa = SherpaSttService.instance;
  final _tts = SherpaTtsService.instance;
  final _settings = AppSettings.instance;

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final List<_ChatMessage> _messages = [];

  bool _loading = true;
  bool _busy = false;
  bool _recording = false;
  bool _transcribing = false;
  bool _speaking = false;

  /// Генерацию прервал пользователь — автоозвучку в этом случае не запускаем.
  bool _generationStopped = false;
  String _status = 'Загрузка модели…';

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _sherpa.cancel();
    _tts.stop();
    super.dispose();
  }

  Future<void> _loadModel({String? path}) async {
    setState(() {
      _loading = true;
      _status = 'Загрузка модели… (первый раз это несколько секунд)';
    });

    try {
      await _llm.initialize(path: path, preferredModelId: _settings.llmModelId);
      if (!mounted) return;

      final name = _llm.modelPath?.split(RegExp(r'[\\/]')).last;
      setState(() {
        _loading = false;
        _status = 'Готова модель: $name';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = e is StateError ? e.message : '$e';
      });
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy || _loading) return;

    _input.clear();
    await _sendText(text);
  }

  Future<void> _sendText(String text) async {
    if (text.isEmpty || _busy || _loading) return;
    if (!_llm.isReady) {
      _showMessage('Модель не загружена');
      return;
    }

    // Новый вопрос важнее старой озвучки.
    if (_speaking) await _stopSpeaking();

    _generationStopped = false;
    final answer = _ChatMessage(fromUser: false);

    setState(() {
      _messages.add(_ChatMessage(fromUser: true, text: text));
      _messages.add(answer);
      _busy = true;
      _status = 'Думаю…';
    });
    _scrollToBottom();

    var failed = false;
    try {
      await for (final delta in _llm.reply(
        text,
        thinkBeforeAnswer: _settings.llmThinkBeforeAnswer,
      )) {
        if (!mounted) return;
        setState(() => answer.text += delta);
        _scrollToBottom();
      }

      if (!mounted) return;
      final seconds = _llm.lastDuration?.inMilliseconds ?? 0;
      final tokens = _llm.lastTokens;
      setState(() {
        _status = tokens == null
            ? 'Готово'
            : 'Готово: $tokens ток. за ${(seconds / 1000).toStringAsFixed(1)} с';
      });
    } catch (e) {
      failed = true;
      if (!mounted) return;
      setState(() {
        _status = 'Ошибка генерации: $e';
        if (answer.text.isEmpty) _messages.remove(answer);
      });
      _showMessage(_status);
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (!mounted || failed || _generationStopped) return;

    final reply = answer.text.trim();
    if (reply.isEmpty || !_settings.autoSpeak) return;
    await _startSpeaking(reply);
  }

  Future<void> _stop() async {
    _generationStopped = true;
    _llm.cancel();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = 'Остановлено';
    });
  }

  void _newChat() {
    _llm.newChat();
    setState(() {
      _messages.clear();
      _status = 'Новый чат';
    });
  }

  Future<void> _toggleRecording() async {
    if (_transcribing || _loading) return;

    if (_recording) {
      setState(() {
        _recording = false;
        _transcribing = true;
        _status = 'Распознаю…';
      });

      String? recognized;
      String? error;
      try {
        recognized = await _sherpa.stopAndTranscribe();
      } catch (e) {
        error = '$e';
      } finally {
        if (mounted) setState(() => _transcribing = false);
      }

      if (!mounted) return;
      if (error != null) {
        setState(() => _status = 'Ошибка распознавания: $error');
        return;
      }

      final text = recognized?.trim() ?? '';
      if (text.isEmpty) {
        setState(() => _status = 'Ничего не распознано, попробуйте ещё раз');
        return;
      }

      if (_settings.voiceLoop) {
        // Голосовой цикл: распознали — сразу спрашиваем модель.
        setState(() => _status = 'Распознано: $text');
        await _sendText(text);
      } else {
        setState(() {
          _input.text = text;
          _input.selection = TextSelection.collapsed(offset: text.length);
          _status = 'Распознано: $text';
        });
      }
      return;
    }

    // Запись важнее текущей озвучки и генерации.
    if (_speaking) await _stopSpeaking();
    if (_busy) await _stop();

    try {
      await _sherpa.startRecording();
      if (!mounted) return;
      setState(() {
        _recording = true;
        _status = 'Слушаю… Говорите по-русски';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recording = false;
        _status = 'Не удалось начать запись: $e';
      });
      _showMessage(_status);
    }
  }

  Future<void> _speak(String text) async {
    if (_speaking) {
      await _stopSpeaking();
      return;
    }
    await _startSpeaking(text);
  }

  Future<void> _startSpeaking(String text) async {
    setState(() {
      _speaking = true;
      _status = 'Синтезирую речь…';
    });

    try {
      await _tts.speak(text);
      if (!mounted) return;
      setState(() => _status = 'Озвучено');
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Ошибка озвучки: $e');
    } finally {
      if (mounted) setState(() => _speaking = false);
    }
  }

  Future<void> _stopSpeaking() async {
    await _tts.stop();
    if (!mounted) return;
    setState(() {
      _speaking = false;
      _status = 'Озвучка остановлена';
    });
  }

  Future<void> _pickModelPath() async {
    final available = await LlmConfig.availableModels();
    if (!mounted) return;

    String? selected =
        _settings.llmModelId ?? _llm.modelPath?.split(RegExp(r'[\\/]')).last;

    final result = await showDialog<_ModelSelection>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);

          return Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Модель и рассуждения',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Думать перед ответом'),
                      subtitle: const Text(
                        'Медленнее, но ответ вдумчивее: ассистент может '
                        'предложить задачу или напоминание',
                      ),
                      value: _settings.llmThinkBeforeAnswer,
                      onChanged: (value) async {
                        await _settings.setLlmThinkBeforeAnswer(value);
                        setDialogState(() {});
                      },
                    ),
                    const Divider(),
                    Text(
                      'Доступные GGUF-модели',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Qwen — быстрее, Gemma — аккуратнее в рассуждениях.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: available.isEmpty
                          ? Center(
                              child: Text(
                                'Модели не найдены.\nПоложите .gguf в папку '
                                'models рядом с приложением.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall,
                              ),
                            )
                          : RadioGroup<String>(
                              groupValue: selected,
                              onChanged: (value) {
                                if (value != null) {
                                  setDialogState(() => selected = value);
                                }
                              },
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    for (final modelPath in available)
                                      RadioListTile<String>(
                                        dense: true,
                                        value: modelPath
                                            .split(RegExp(r'[\\/]'))
                                            .last,
                                        title: Text(
                                          modelPath
                                              .split(RegExp(r'[\\/]'))
                                              .last,
                                        ),
                                        subtitle: Text(
                                          modelPath,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Отмена'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(
                            context,
                            _ModelSelection(useDefault: true),
                          ),
                          child: const Text('По умолчанию'),
                        ),
                        const SizedBox(width: 4),
                        FilledButton(
                          onPressed: () => Navigator.pop(
                            context,
                            _ModelSelection(modelId: selected),
                          ),
                          child: const Text('Применить'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (result == null) return;

    if (result.useDefault) {
      await _settings.setLlmModelId(null);
    } else if (result.modelId != null && result.modelId!.isNotEmpty) {
      await _settings.setLlmModelId(result.modelId);
    }

    if (!mounted) return;
    setState(() {});
    await _loadModel();
  }

  Future<void> _toggleVoiceSetting(String key) async {
    switch (key) {
      case 'autoSpeak':
        await _settings.setAutoSpeak(!_settings.autoSpeak);
      case 'voiceLoop':
        await _settings.setVoiceLoop(!_settings.voiceLoop);
      case 'think':
        await _settings.setLlmThinkBeforeAnswer(
          !_settings.llmThinkBeforeAnswer,
        );
    }
    if (mounted) setState(() {});
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Чат'),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Голосовые настройки',
            icon: const Icon(Icons.tune),
            onSelected: _toggleVoiceSetting,
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: 'autoSpeak',
                checked: _settings.autoSpeak,
                child: const Text('Озвучивать ответы'),
              ),
              CheckedPopupMenuItem(
                value: 'voiceLoop',
                checked: _settings.voiceLoop,
                child: const Text('Сразу отправлять распознанное'),
              ),
              CheckedPopupMenuItem(
                value: 'think',
                checked: _settings.llmThinkBeforeAnswer,
                child: const Text('Думать перед ответом'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Модель и рассуждения',
            onPressed: _loading ? null : _pickModelPath,
            icon: const Icon(Icons.memory),
          ),
          IconButton(
            tooltip: 'Новый чат',
            onPressed: _busy || _messages.isEmpty ? null : _newChat,
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 750),
          child: Column(
            children: [
              Expanded(
                child: _messages.isEmpty
                    ? _buildEmptyState()
                    : _buildMessages(),
              ),
              _buildComposer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              _loading ? 'Загружаю модель…' : 'Спросите что-нибудь',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _status,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (!_loading && !_llm.isReady) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _pickModelPath,
                icon: const Icon(Icons.memory),
                label: const Text('Выбрать модель'),
              ),
            ],
            if (!_loading && _llm.isReady) ...[
              const SizedBox(height: 20),
              Text(
                _settings.voiceLoop
                    ? 'Нажмите 🎤, скажите вопрос и нажмите стоп — '
                          'ответ придёт и озвучится сам'
                    : 'Нажмите 🎤 и скажите вопрос — текст попадёт в поле ввода',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isLast = index == _messages.length - 1;
        final isStreaming = _busy && isLast && !message.fromUser;

        return _MessageBubble(
          message: message,
          streaming: isStreaming,
          onSpeak: message.fromUser || message.text.trim().isEmpty
              ? null
              : () => _speak(message.text),
        );
      },
    );
  }

  Widget _buildComposer() {
    final theme = Theme.of(context);

    return Material(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: !_loading,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: _recording
                          ? 'Говорите, потом нажмите стоп'
                          : 'Спросите ассистента…',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  tooltip: _recording
                      ? 'Стоп и распознать'
                      : (_settings.voiceLoop
                            ? 'Сказать голосом (сразу отправится)'
                            : 'Сказать голосом'),
                  onPressed: _loading || _transcribing
                      ? null
                      : _toggleRecording,
                  icon: Icon(_recording ? Icons.stop : Icons.mic),
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  tooltip: _busy ? 'Остановить генерацию' : 'Отправить',
                  onPressed: _loading ? null : (_busy ? _stop : _send),
                  icon: Icon(_busy ? Icons.stop : Icons.send),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _status,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_speaking)
                  TextButton(
                    onPressed: _stopSpeaking,
                    child: const Text('Стоп озвучку'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Результат диалога выбора модели.
class _ModelSelection {
  _ModelSelection({this.useDefault = false, this.modelId});

  final bool useDefault;
  final String? modelId;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.streaming,
    this.onSpeak,
  });

  final _ChatMessage message;
  final bool streaming;
  final VoidCallback? onSpeak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isUser = message.fromUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? colors.primaryContainer
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.text.isEmpty && streaming)
              Text('…', style: theme.textTheme.bodyMedium)
            else
              SelectableText(message.text, style: theme.textTheme.bodyMedium),
            if (onSpeak != null) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: onSpeak,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.volume_up, size: 16, color: colors.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Озвучить',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
