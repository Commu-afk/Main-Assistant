import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Простые настройки приложения в JSON рядом с данными.
///
/// Пока это только голосовые флаги, но сюда же лягут голос TTS и параметры
/// генерации, когда появится экран настроек.
class AppSettings {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  static const String _fileName = 'app_settings.json';

  bool _autoSpeak = true;
  bool _voiceLoop = true;
  bool _closeToTray = true;
  bool _llmThinkBeforeAnswer = false;
  String? _llmModelId;

  /// Озвучивать ответ модели автоматически.
  bool get autoSpeak => _autoSpeak;

  /// После распознавания сразу отправлять вопрос модели.
  bool get voiceLoop => _voiceLoop;

  /// Закрывать окно в трей, а не завершать приложение.
  bool get closeToTray => _closeToTray;

  /// Перед ответом модель может сделать внутреннее обдумывание.
  bool get llmThinkBeforeAnswer => _llmThinkBeforeAnswer;

  /// Выбранный идентификатор GGUF-модели (имя файла).
  String? get llmModelId => _llmModelId;

  Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;

      final data = jsonDecode(await file.readAsString());
      if (data is! Map) return;

      _autoSpeak = data['autoSpeak'] as bool? ?? _autoSpeak;
      _voiceLoop = data['voiceLoop'] as bool? ?? _voiceLoop;
      _closeToTray = data['closeToTray'] as bool? ?? _closeToTray;
      _llmThinkBeforeAnswer =
          data['llmThinkBeforeAnswer'] as bool? ?? _llmThinkBeforeAnswer;
      final modelId = data['llmModelId'];
      _llmModelId = modelId is String && modelId.trim().isNotEmpty
          ? modelId.trim()
          : null;
    } catch (_) {
      // Битый файл настроек не должен мешать запуску.
    }
  }

  Future<void> setAutoSpeak(bool value) async {
    _autoSpeak = value;
    await _save();
  }

  Future<void> setVoiceLoop(bool value) async {
    _voiceLoop = value;
    await _save();
  }

  Future<void> setCloseToTray(bool value) async {
    _closeToTray = value;
    await _save();
  }

  Future<void> setLlmThinkBeforeAnswer(bool value) async {
    _llmThinkBeforeAnswer = value;
    await _save();
  }

  Future<void> setLlmModelId(String? value) async {
    final clean = value?.trim();
    _llmModelId = clean == null || clean.isEmpty ? null : clean;
    await _save();
  }

  Future<void> _save() async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'autoSpeak': _autoSpeak,
        'voiceLoop': _voiceLoop,
        'closeToTray': _closeToTray,
        'llmThinkBeforeAnswer': _llmThinkBeforeAnswer,
        if (_llmModelId != null) 'llmModelId': _llmModelId,
      }),
      flush: true,
    );
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fileName));
  }
}
