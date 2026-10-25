import 'dart:async';

import 'package:flutter/material.dart';

import '../llm/llm_config.dart';
import '../llm/llm_service.dart';
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

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final List<_ChatMessage> _messages = [];

  bool _loading = true;
  bool _busy = false;
  bool _recording = false;
  bool _transcribing = false;
  bool _speaking = false;
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
      await _llm.initialize(path: path);
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
    if (!_llm.isReady) {
      _showMessage('Модель не загружена');
      return;
    }

    _input.clear();
    final answer = _ChatMessage(fromUser: false);

    setState(() {
      _messages.add(_ChatMessage(fromUser: true, text: text));
      _messages.add(answer);
      _busy = true;
      _status = 'Думаю…';
    });
    _scrollToBottom();

    try {
      await for (final delta in _llm.reply(text)) {
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
      if (!mounted) return;
      setState(() {
        _status = 'Ошибка генерации: $e';
        if (answer.text.isEmpty) _messages.remove(answer);
      });
      _showMessage(_status);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
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
    if (_transcribing) return;

    if (_recording) {
      setState(() {
        _recording = false;
        _transcribing = true;
        _status = 'Распознаю…';
      });

      try {
        final text = await _sherpa.stopAndTranscribe();
        if (!mounted) return;

        setState(() {
          if (text.isEmpty) {
            _status = 'Ничего не распознано, попробуйте ещё раз';
          } else {
            _input.text = text;
            _input.selection = TextSelection.collapsed(offset: text.length);
            _status = 'Распознано: $text';
          }
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _status = 'Ошибка распознавания: $e');
      } finally {
        if (mounted) setState(() => _transcribing = false);
      }
      return;
    }

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
      await _tts.stop();
      if (!mounted) return;
      setState(() {
        _speaking = false;
        _status = 'Озвучка остановлена';
      });
      return;
    }

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

  Future<void> _pickModelPath() async {
    final controller = TextEditingController(text: _llm.modelPath ?? '');

    final path = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Путь к GGUF-модели'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Полный путь к .gguf',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Модель не входит в сборку: файл нужно скачать отдельно. '
              'По умолчанию ищется ${LlmConfig.defaultModelName}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Загрузить'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (path == null) return;

    await LlmConfig.savePath(path.isEmpty ? null : path);
    await _loadModel(path: path.isEmpty ? null : path);
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Чат'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Путь к модели',
            onPressed: _loading ? null : _pickModelPath,
            icon: const Icon(Icons.folder_open),
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
                child: _messages.isEmpty ? _buildEmptyState() : _buildMessages(),
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
                icon: const Icon(Icons.folder_open),
                label: const Text('Указать путь к модели'),
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
                  tooltip: _recording ? 'Стоп и распознать' : 'Сказать голосом',
                  onPressed: _loading || _transcribing ? null : _toggleRecording,
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
                    onPressed: () => _tts.stop().then(
                      (_) => mounted ? setState(() => _speaking = false) : null,
                    ),
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
              SelectableText(
                message.text,
                style: theme.textTheme.bodyMedium,
              ),
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
