import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Пути к распакованной модели озвучки.
class TtsModelFiles {
  const TtsModelFiles({
    required this.dir,
    required this.model,
    required this.tokens,
    required this.dataDir,
  });

  final String dir;
  final String model;
  final String tokens;

  /// Папка `espeak-ng-data` (нужна Piper для фонемизации).
  final String dataDir;
}

/// Распаковывает модель озвучки из assets в постоянную папку приложения.
///
/// В assets модель лежит одним zip-архивом: onnx-файл, tokens.txt и дерево
/// `espeak-ng-data` с вложенными каталогами, которые неудобно перечислять в
/// pubspec по одному. На Android/iOS распаковать архив обязательно: внутрь
/// apk/ipa ONNX Runtime по обычному пути не заглянет.
class TtsModel {
  TtsModel._();

  static const String assetZip = 'assets/tts/sherpa/ru.zip';
  static const String modelFileName = 'ru_RU-irina-medium.onnx';
  static const String _folder = 'tts_sherpa_ru';
  static const String _marker = '.unpacked';

  /// [targetDir] нужен только для тестов; в приложении берётся support-dir.
  static Future<TtsModelFiles> ensure({String? targetDir}) async {
    final modelDir = Directory(
      targetDir ?? p.join((await getApplicationSupportDirectory()).path, _folder),
    );

    final model = File(p.join(modelDir.path, modelFileName));
    final marker = File(p.join(modelDir.path, _marker));

    if (!(await model.exists() && await marker.exists())) {
      await modelDir.create(recursive: true);
      final data = await rootBundle.load(assetZip);
      final count = await _extract(
        bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        target: modelDir,
      );
      if (count == 0) {
        throw StateError('Архив модели озвучки пуст: $assetZip');
      }
      await marker.writeAsString('1', flush: true);
    }

    return TtsModelFiles(
      dir: modelDir.path,
      model: model.path,
      tokens: p.join(modelDir.path, 'tokens.txt'),
      dataDir: p.join(modelDir.path, 'espeak-ng-data'),
    );
  }

  /// Возвращает число распакованных файлов.
  static Future<int> _extract({
    required List<int> bytes,
    required Directory target,
  }) async {
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    var count = 0;

    for (final entry in archive) {
      if (!entry.isFile) continue;

      final path = p.normalize(p.join(target.path, entry.name));
      // Защита от «../» внутри архива.
      if (!p.isWithin(target.path, path)) continue;

      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.content as List<int>, flush: true);
      count++;
    }

    return count;
  }
}
