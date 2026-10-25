import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_assistant/features/tts/tts_model.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('модель озвучки распаковывается из assets вместе с espeak-ng-data',
      () async {
    final tmp = await Directory.systemTemp.createTemp('tts_model_test');
    addTearDown(() => tmp.delete(recursive: true));

    final files = await TtsModel.ensure(targetDir: tmp.path);

    expect(File(files.model).existsSync(), isTrue, reason: 'нет onnx-модели');
    expect(File(files.tokens).existsSync(), isTrue, reason: 'нет tokens.txt');
    expect(
      Directory(files.dataDir).existsSync(),
      isTrue,
      reason: 'нет espeak-ng-data',
    );
    // Вложенные каталоги espeak — как раз то, что не влезает в assets по одному.
    expect(
      Directory(p.join(files.dataDir, 'lang')).existsSync(),
      isTrue,
      reason: 'не распаковались вложенные каталоги',
    );

    // Повторный вызов не должен ничего распаковывать заново.
    final marker = File(p.join(files.dir, '.unpacked'));
    final before = await marker.lastModified();
    final again = await TtsModel.ensure(targetDir: tmp.path);
    expect(again.model, files.model);
    expect(await marker.lastModified(), before);
  });
}
