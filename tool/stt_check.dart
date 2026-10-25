// Проверка STT-стека без микрофона: распознаёт wav-файл оффлайн-моделью.
//
// Запуск: dart run tool/stt_check.dart <path-to-wav>
//
// Для запуска вне приложения Dart ищет sherpa-onnx-c-api.dll и onnxruntime.dll
// рядом с dart.exe, поэтому на время проверки скопируйте обе библиотеки из
// pub-кэша (sherpa_onnx_windows/windows/) в <flutter>/bin/cache/dart-sdk/bin.
// В самом приложении библиотеки уже лежат рядом с .exe.
import 'dart:io';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

void main(List<String> args) {
  final wav = args.isNotEmpty ? args.first : 'assets/stt/sherpa/ru/test.wav';
  if (!File(wav).existsSync()) {
    stderr.writeln('Нет файла: $wav');
    exit(2);
  }

  final dir = 'assets/stt/sherpa/ru';

  sherpa_onnx.initBindings();

  final config = sherpa_onnx.OfflineRecognizerConfig(
    model: sherpa_onnx.OfflineModelConfig(
      transducer: sherpa_onnx.OfflineTransducerModelConfig(
        encoder: '$dir/encoder.int8.onnx',
        decoder: '$dir/decoder.onnx',
        joiner: '$dir/joiner.int8.onnx',
      ),
      tokens: '$dir/tokens.txt',
      numThreads: 2,
      debug: false,
    ),
  );

  final sw = Stopwatch()..start();
  final recognizer = sherpa_onnx.OfflineRecognizer(config);
  stdout.writeln('Модель загружена за ${sw.elapsedMilliseconds} мс');

  final wave = sherpa_onnx.readWave(wav);
  stdout.writeln('Wav: ${wave.samples.length} сэмплов, ${wave.sampleRate} Гц');

  sw.reset();
  final stream = recognizer.createStream();
  stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
  recognizer.decode(stream);
  final text = recognizer.getResult(stream).text;
  stream.free();

  stdout.writeln('Распознано (${sw.elapsedMilliseconds} мс): $text');

  recognizer.free();
}
