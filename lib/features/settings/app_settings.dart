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

  /// Озвучивать ответ модели автоматически.
  bool get autoSpeak => _autoSpeak;

  /// После распознавания сразу отправлять вопрос модели.
  bool get voiceLoop => _voiceLoop;

  /// Закрывать окно в трей, а не завершать приложение.
  bool get closeToTray => _closeToTray;

  Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;

      final data = jsonDecode(await file.readAsString());
      if (data is! Map) return;

      _autoSpeak = data['autoSpeak'] as bool? ?? _autoSpeak;
      _voiceLoop = data['voiceLoop'] as bool? ?? _voiceLoop;
      _closeToTray = data['closeToTray'] as bool? ?? _closeToTray;
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

  Future<void> _save() async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'autoSpeak': _autoSpeak,
        'voiceLoop': _voiceLoop,
        'closeToTray': _closeToTray,
      }),
      flush: true,
    );
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fileName));
  }
}
