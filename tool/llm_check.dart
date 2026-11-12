// Проверка LLM без приложения: загружает GGUF и печатает ответ.
//
// Запуск: dart run tool/llm_check.dart <model.gguf> ["вопрос"]
import 'dart:io';

import 'package:llamadart/llamadart.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Использование: llm_check.dart <model.gguf> ["вопрос"]');
    exit(2);
  }

  final modelPath = args[0];
  final prompt = args.length > 1 ? args[1] : 'Привет! Кто ты и что умеешь?';
  final gpu = args.length > 2 && args[2] == 'gpu';

  await LlamaLogging.configure(level: LlamaLogLevel.error);

  final engine = LlamaEngine(LlamaBackend());
  final loadWatch = Stopwatch()..start();

  await engine.setModel(
    LlamaModel(ModelSource.path(modelPath)),
    params: gpu
        ? const ModelParams(
            contextSize: 2048,
            gpuLayers: 99,
            device: ComputeDevice.gpu,
          )
        : const ModelParams(contextSize: 4096, gpuLayers: 0),
  );
  stdout.writeln(
    'Модель загружена за ${(loadWatch.elapsedMilliseconds / 1000).toStringAsFixed(1)} с',
  );

  final session = ChatSession(
    engine,
    systemPrompt:
        'Ты — локальный голосовой ассистент. Отвечай по-русски кратко, '
        'обычно одно-три предложения, без Markdown.',
  );

  final genWatch = Stopwatch()..start();
  var tokens = 0;
  var chars = 0;

  stdout.writeln('--- ответ ---');
  await for (final chunk in session.create(
    [LlamaTextContent(prompt)],
    params: const GenerationParams(maxTokens: 200, temp: 0.7),
    enableThinking: false,
  )) {
    stdout.write(chunk.text);
    chars += chunk.text.length;
    final usage = chunk.usage;
    if (usage != null) tokens = usage.completionTokens;
  }
  stdout.writeln('\n--- конец ---');

  final seconds = genWatch.elapsedMilliseconds / 1000;
  stdout.writeln(
    'Время: ${seconds.toStringAsFixed(1)} с, '
    'токенов: ${tokens > 0 ? tokens : '?'}, '
    'символов: $chars',
  );
  if (tokens > 0 && seconds > 0) {
    stdout.writeln('Скорость: ${(tokens / seconds).toStringAsFixed(2)} ток/с');
  }

  await engine.dispose();
}
