import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Системные уведомления.
///
/// Сейчас поддерживается только Windows (тосты через WinRT). На Android
/// уведомления появятся отдельным этапом: там нужен канал, иконка и
/// разрешение POST_NOTIFICATIONS, а проверить это пока не на чем.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String _appName = 'Мой ассистент';
  static const String _appUserModelId = 'LocalAssistant.Desktop.1';

  /// GUID регистрации обработчика нажатия на уведомление. Постоянный:
  /// при смене Windows может перестать будить приложение по клику.
  static const String _callbackGuid = 'd2f5a0c1-6c4e-4b9a-9d3b-8a7f5c2e1b40';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  String? _lastError;

  bool get isSupported => Platform.isWindows;
  bool get isReady => _ready;
  String? get lastError => _lastError;

  Future<void> initialize() async {
    if (_ready || !isSupported) return;

    try {
      const settings = InitializationSettings(
        windows: WindowsInitializationSettings(
          appName: _appName,
          appUserModelId: _appUserModelId,
          guid: _callbackGuid,
        ),
      );

      await _plugin.initialize(settings: settings);
      _ready = true;
      _lastError = null;
    } catch (e) {
      _lastError = '$e';
      debugPrint('Уведомления недоступны: $e');
    }
  }

  /// Показывает тост. Возвращает false, если платформа не поддерживается
  /// или система отказала.
  Future<bool> show({required String title, required String body}) async {
    await initialize();
    if (!_ready) return false;

    try {
      await _plugin.show(
        id: DateTime.now().millisecondsSinceEpoch.remainder(0x7FFFFFFF),
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          windows: WindowsNotificationDetails(
            duration: WindowsNotificationDuration.long,
          ),
        ),
      );
      _lastError = null;
      return true;
    } catch (e) {
      _lastError = '$e';
      debugPrint('Не удалось показать уведомление: $e');
      return false;
    }
  }
}
