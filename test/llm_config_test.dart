import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_assistant/features/llm/llm_config.dart';
import 'package:path/path.dart' as p;

void main() {
  group('LlmConfig.firstGgufIn', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('llm_config_test');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('возвращает null для пустой папки', () async {
      expect(await LlmConfig.firstGgufIn(tmp.path), isNull);
    });

    test('возвращает null для несуществующей папки', () async {
      expect(await LlmConfig.firstGgufIn(p.join(tmp.path, 'нет')), isNull);
    });

    test('игнорирует недокачанные файлы и другие расширения', () async {
      await File(p.join(tmp.path, 'model.gguf.part')).writeAsString('x');
      await File(p.join(tmp.path, 'notes.txt')).writeAsString('x');

      expect(await LlmConfig.firstGgufIn(tmp.path), isNull);
    });

    test('выбирает gguf по алфавиту', () async {
      for (final name in ['b.gguf', 'a.gguf', 'c.gguf']) {
        await File(p.join(tmp.path, name)).writeAsString('x');
      }

      expect(await LlmConfig.firstGgufIn(tmp.path), p.join(tmp.path, 'a.gguf'));
    });
  });
}
