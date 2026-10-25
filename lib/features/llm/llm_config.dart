import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Настройки локальной LLM: где лежит GGUF-модель и как генерировать ответ.
///
/// Модель весит ~1 ГБ, поэтому в assets её не пакуем: ищем файл рядом с
/// приложением и в рабочей папке проекта. Путь можно задать вручную —
/// он сохраняется в support-dir и имеет приоритет.
class LlmConfig {
  LlmConfig._();

  /// Модель по умолчанию: Qwen2.5-1.5B-Instruct, квантование Q4_K_M (~1 ГБ).
  static const String defaultModelName = 'qwen2.5-1.5b-instruct-q4_k_m.gguf';

  /// Переменная окружения для явного пути к модели.
  static const String envVar = 'LOCAL_ASSISTANT_MODEL';

  /// Системная инструкция ассистента.
  static const String systemPrompt =
      'Ты — локальный голосовой ассистент. Отвечай по-русски, кратко и по '
      'делу: обычно одно-три предложения. Без списков и Markdown, потому что '
      'ответ может читаться вслух. Если не знаешь ответа, скажи об этом прямо.';

  static const int contextSize = 4096;
  static const int maxTokens = 320;

  static const String _settingsFile = 'llm_settings.json';

  static Future<File> _settingsFileHandle() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _settingsFile));
  }

  /// Путь, выбранный пользователем вручную, или null.
  static Future<String?> savedPath() async {
    try {
      final file = await _settingsFileHandle();
      if (!await file.exists()) return null;

      final data = jsonDecode(await file.readAsString());
      if (data is! Map) return null;

      final value = data['modelPath'];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    } catch (_) {
      return null;
    }
  }

  /// Сохраняет (или сбрасывает при null) ручной путь к модели.
  static Future<void> savePath(String? path) async {
    final file = await _settingsFileHandle();
    await file.parent.create(recursive: true);

    final clean = path?.trim();
    if (clean == null || clean.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }

    await file.writeAsString(jsonEncode({'modelPath': clean}), flush: true);
  }

  /// Папки, в которых имеет смысл искать любую gguf-модель.
  static Future<List<String>> searchDirs() async {
    final dirs = <String>[
      p.join(p.dirname(Platform.resolvedExecutable), 'models'),
      p.join(Directory.current.path, 'assets', 'models'),
    ];

    try {
      dirs.add(p.join((await getApplicationSupportDirectory()).path, 'models'));
    } catch (_) {
      // На платформах без path_provider просто пропускаем.
    }

    return dirs;
  }

  /// Явные кандидаты в порядке приоритета.
  static Future<List<String>> candidatePaths() async {
    final candidates = <String>[];

    final override = Platform.environment[envVar];
    if (override != null && override.trim().isNotEmpty) {
      candidates.add(override.trim());
    }

    final saved = await savedPath();
    if (saved != null) candidates.add(saved);

    final dirs = await searchDirs();
    for (final dir in dirs) {
      candidates.add(p.join(dir, defaultModelName));
    }

    return candidates;
  }

  /// Ищет модель: сначала точные пути, потом любой .gguf в известных папках.
  static Future<String?> resolve() async {
    for (final path in await candidatePaths()) {
      if (await File(path).exists()) return path;
    }

    for (final dir in await searchDirs()) {
      final found = await firstGgufIn(dir);
      if (found != null) return found;
    }

    return null;
  }

  /// Первый по алфавиту .gguf в папке, кроме недокачанных (.part/.tmp).
  static Future<String?> firstGgufIn(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return null;

    final files = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path).toLowerCase();
      if (!name.endsWith('.gguf')) continue;
      if (name.endsWith('.part') || name.endsWith('.tmp')) continue;
      files.add(entity);
    }

    if (files.isEmpty) return null;
    files.sort((a, b) => a.path.compareTo(b.path));
    return files.first.path;
  }

  /// Куда положить модель, если её нет (первая папка поиска).
  static Future<String> suggestedPath() async {
    final dirs = await searchDirs();
    return p.join(dirs.first, defaultModelName);
  }
}
