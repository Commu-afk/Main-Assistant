import 'dart:async';

import 'package:llamadart/llamadart.dart';

import 'llm_config.dart';

/// Локальная LLM через llama.cpp (пакет llamadart).
///
/// Держит один движок и одну сессию чата: история диалога живёт внутри
/// [ChatSession], поэтому «Новый чат» — это [newChat].
class LlmService {
  LlmService._();

  static final LlmService instance = LlmService._();

  LlamaEngine? _engine;
  ChatSession? _session;

  String? _modelPath;
  String? _lastError;

  /// Время последней генерации и число выданных токенов (для статуса в UI).
  Duration? lastDuration;
  int? lastTokens;

  bool get isReady => _session != null;
  String? get modelPath => _modelPath;
  String? get lastError => _lastError;

  /// Загружает модель. Повторный вызов с тем же путём ничего не делает.
  Future<void> initialize({String? path, String? preferredModelId}) async {
    final target =
        path ?? await LlmConfig.resolve(preferredModelId: preferredModelId);
    if (target == null) {
      _lastError = 'GGUF-модель не найдена';
      throw StateError(
        'Модель не найдена. Положите GGUF-файл (Qwen/Gemma) '
        'в папку models рядом с приложением или укажите путь вручную.',
      );
    }

    if (_session != null && _modelPath == target) return;

    await _unload();

    try {
      final engine = LlamaEngine(LlamaBackend());

      // Считаем на CPU: у GTX 750 Ti всего 2 ГБ и старый Vulkan.
      await engine.setModel(
        LlamaModel(ModelSource.path(target)),
        params: const ModelParams(
          contextSize: LlmConfig.contextSize,
          gpuLayers: 0,
        ),
      );

      _engine = engine;
      _session = ChatSession(engine, systemPrompt: LlmConfig.systemPrompt);
      _modelPath = target;
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      await _unload();
      rethrow;
    }
  }

  String _buildThoughtfulPrompt(String text, {bool think = false}) {
    if (!think) return text;
    return 'Ты — внимательный локальный ассистент. Подумай над вопросом про '
        'себя, но не выводи рассуждения.\n'
        'Ответь по-русски кратко (1–3 предложения), без списков и Markdown.\n'
        'Если из вопроса следует дело, которое стоит запомнить, добавь в конце '
        'одну строку «Задача: <короткая формулировка>» — только если это '
        'действительно уместно.\n'
        'Вопрос: $text';
  }

  /// Потоковый ответ модели: отдаёт куски текста по мере генерации.
  Stream<String> reply(
    String text, {
    int? maxTokens,
    bool thinkBeforeAnswer = false,
  }) async* {
    final session = _session;
    if (session == null) {
      throw StateError('Модель не загружена');
    }

    final stopwatch = Stopwatch()..start();
    lastDuration = null;
    lastTokens = null;

    final params = GenerationParams(
      maxTokens: maxTokens ?? LlmConfig.maxTokens,
      temp: thinkBeforeAnswer ? 0.4 : 0.7,
      topK: thinkBeforeAnswer ? 30 : 40,
      topP: thinkBeforeAnswer ? 0.85 : 0.9,
    );

    final prompt = _buildThoughtfulPrompt(text, think: thinkBeforeAnswer);

    await for (final chunk in session.create(
      [LlamaTextContent(prompt)],
      params: params,
      enableThinking: false,
    )) {
      if (chunk.text.isNotEmpty) yield chunk.text;

      final usage = chunk.usage;
      if (usage != null) {
        lastTokens = usage.completionTokens;
        lastDuration = usage.duration ?? stopwatch.elapsed;
      }
    }

    lastDuration ??= stopwatch.elapsed;
  }

  /// Прерывает текущую генерацию.
  void cancel() {
    _engine?.cancelGeneration();
  }

  /// Очищает историю диалога, оставляя системную инструкцию.
  void newChat() {
    _session?.reset();
  }

  Future<void> _unload() async {
    _session = null;
    final engine = _engine;
    _engine = null;
    _modelPath = null;

    if (engine != null) {
      await engine.dispose();
    }
  }

  /// Выгружает модель из памяти.
  Future<void> dispose() => _unload();
}
