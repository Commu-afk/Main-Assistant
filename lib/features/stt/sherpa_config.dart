import 'dart:io';

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Набор файлов оффлайн-модели Sherpa-ONNX.
class SherpaModelFiles {
  const SherpaModelFiles({
    required this.dir,
    required this.tokens,
    required this.encoder,
    required this.decoder,
    required this.joiner,
  });

  final String dir;
  final String tokens;
  final String encoder;
  final String decoder;
  final String joiner;

  @override
  String toString() =>
      'SherpaModelFiles(dir: $dir, encoder: ${p.basename(encoder)})';
}

/// Достаёт модель из assets во внутреннюю папку приложения.
///
/// На Windows/macOS/Linux файлы ассетов и так лежат на диске, но на Android и
/// iOS они упакованы внутрь приложения, поэтому ONNX Runtime не может открыть
/// их по пути ассета. Единый путь для всех платформ — скопировать модель в
/// `getApplicationSupportDirectory()` один раз и дальше читать оттуда.
class SherpaConfig {
  SherpaConfig._();

  /// Папка с моделью внутри `assets/`.
  static const String assetDir = 'assets/stt/sherpa/ru';

  /// Служебные файлы, которые не нужны рантайму.
  static const Set<String> _ignoredNames = {'.gitkeep'};

  /// Возвращает локальные пути к файлам модели, копируя их из assets при
  /// необходимости.
  static Future<SherpaModelFiles> load() async {
    final dir = await _syncAssetsToDisk();
    final files = _resolveFiles(dir);

    if (files == null) {
      throw StateError(
        'В папке модели не найдены нужные файлы.\n'
        'Ожидаются tokens.txt и encoder*/decoder*/joiner*.onnx.\n'
        'Папка: $dir',
      );
    }
    return files;
  }

  static Future<String> _syncAssetsToDisk() async {
    final supportDir = await getApplicationSupportDirectory();
    final targetDir = Directory(
      p.join(supportDir.path, 'models', 'sherpa', 'ru'),
    );
    await targetDir.create(recursive: true);

    final assets = await _listModelAssets();
    if (assets.isEmpty) {
      throw StateError(
        'В assets нет файлов модели ($assetDir). '
        'Скачайте модель Sherpa-ONNX и положите файлы в $assetDir',
      );
    }

    for (final asset in assets) {
      final name = p.basename(asset);
      if (_ignoredNames.contains(name)) continue;

      final target = File(p.join(targetDir.path, name));
      final data = await rootBundle.load(asset);

      if (await target.exists() &&
          await target.length() == data.lengthInBytes) {
        continue;
      }

      await target.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }

    return targetDir.path;
  }

  static Future<List<String>> _listModelAssets() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final prefix = '$assetDir/';
    final assets = manifest
        .listAssets()
        .where((a) => a.startsWith(prefix))
        .toList()
      ..sort();
    return assets;
  }

  static SherpaModelFiles? _resolveFiles(String dir) {
    final d = Directory(dir);
    if (!d.existsSync()) return null;

    final names = d
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .toList();

    final tokens = _pickExact(names, 'tokens.txt');
    final encoder = _pickByPrefix(names, 'encoder');
    final decoder = _pickByPrefix(names, 'decoder');
    final joiner = _pickByPrefix(names, 'joiner');

    if (tokens == null || encoder == null || decoder == null || joiner == null) {
      return null;
    }

    return SherpaModelFiles(
      dir: dir,
      tokens: p.join(dir, tokens),
      encoder: p.join(dir, encoder),
      decoder: p.join(dir, decoder),
      joiner: p.join(dir, joiner),
    );
  }

  static String? _pickExact(List<String> names, String name) {
    return names.contains(name) ? name : null;
  }

  /// Ищет `<prefix>*.onnx`, предпочитая int8-вариант (быстрее и меньше).
  static String? _pickByPrefix(List<String> names, String prefix) {
    final matches = names
        .where((n) => n.startsWith(prefix) && n.endsWith('.onnx'))
        .toList();
    if (matches.isEmpty) return null;

    final int8 = matches.where((n) => n.contains('.int8.')).toList();
    if (int8.isNotEmpty) {
      int8.sort();
      return int8.first;
    }
    matches.sort();
    return matches.first;
  }

  /// Тип модели для Sherpa. Пустая строка — автоопределение по метаданным.
  static String detectModelType(String dir) {
    final lower = dir.toLowerCase();
    if (lower.contains('nemo_transducer') || lower.contains('nemo-transducer')) {
      return 'nemo_transducer';
    }
    return '';
  }
}
