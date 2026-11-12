// Проверка TTS-стека без приложения: синтезирует текст в wav-файл.
//
// Запуск: dart run tool/tts_check.dart <dir-с-моделью> "<текст>" <out.wav>
//
// В <dir> должны лежать ru_RU-irina-medium.onnx, tokens.txt и espeak-ng-data/.
// Как и для stt_check.dart, DLL нужны рядом с dart.exe.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

void main(List<String> args) {
  if (args.length < 3) {
    stderr.writeln('Использование: tts_check.dart <modelDir> <text> <out.wav>');
    exit(2);
  }

  final dir = args[0];
  final text = args[1];
  final out = args[2];

  sherpa_onnx.initBindings();

  final sw = Stopwatch()..start();
  final tts = sherpa_onnx.OfflineTts(
    sherpa_onnx.OfflineTtsConfig(
      model: sherpa_onnx.OfflineTtsModelConfig(
        vits: sherpa_onnx.OfflineTtsVitsModelConfig(
          model: p.join(dir, 'ru_RU-irina-medium.onnx'),
          tokens: p.join(dir, 'tokens.txt'),
          dataDir: p.join(dir, 'espeak-ng-data'),
        ),
        numThreads: 2,
        debug: false,
      ),
    ),
  );
  stdout.writeln('Модель загружена за ${sw.elapsedMilliseconds} мс');

  sw.reset();
  final audio = tts.generate(text: text);
  stdout.writeln(
    'Синтез за ${sw.elapsedMilliseconds} мс, '
    '${audio.samples.length} сэмплов, ${audio.sampleRate} Гц',
  );

  if (audio.samples.isEmpty) {
    stderr.writeln('Пустой результат');
    exit(3);
  }

  sherpa_onnx.writeWave(
    filename: out,
    samples: audio.samples,
    sampleRate: audio.sampleRate,
  );
  stdout.writeln('Записано: $out');

  tts.free();
}
