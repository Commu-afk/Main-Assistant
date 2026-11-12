import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/database/task_database.dart';
import 'notification_service.dart';

/// Планировщик напоминаний.
///
/// Проверяет базу при старте и раз в 20 секунд: если у записи наступил срок
/// и уведомления ещё не было — показывает системный тост и помечает запись,
/// чтобы не повторять его.
///
/// Работает, пока приложение запущено. Уведомления при закрытом приложении —
/// следующий шаг (автозапуск или задача в Планировщике Windows).
class ReminderScheduler extends ChangeNotifier {
  ReminderScheduler._();

  static final ReminderScheduler instance = ReminderScheduler._();

  static const Duration _interval = Duration(seconds: 20);

  final _notifications = NotificationService.instance;

  Timer? _timer;
  bool _checking = false;
  int _lastFired = 0;

  /// Сколько уведомлений показала последняя проверка.
  int get lastFired => _lastFired;

  bool get isRunning => _timer != null;

  void start() {
    if (_timer != null) return;
    if (!_notifications.isSupported) return;

    // Просроченные за время, пока приложение было закрыто, показываем сразу.
    checkNow();
    _timer = Timer.periodic(_interval, (_) => checkNow());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Проверить сроки немедленно. Возвращает число показанных уведомлений.
  Future<int> checkNow() async {
    if (_checking || !_notifications.isSupported) return 0;
    _checking = true;

    var fired = 0;
    try {
      final due = await TaskDatabase.instance.getDueEntries();
      for (final entry in due) {
        final id = entry['id'] as int;
        final title = (entry['title'] as String? ?? '').trim();
        final type = entry['type'] as String? ?? 'task';
        final tag = entry['tag'] as String?;

        final shown = await _notifications.show(
          title: tag == null ? _typeLabel(type) : '$tag · ${_typeLabel(type)}',
          body: title.isEmpty ? 'Пора заняться записью' : title,
        );
        if (!shown) break;

        await TaskDatabase.instance.markNotified(id);
        fired++;

        // Несколько тостов подряд Windows может схлопнуть — разводим их.
        if (fired < due.length) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
    } catch (e) {
      debugPrint('Проверка напоминаний не удалась: $e');
    } finally {
      _checking = false;
    }

    _lastFired = fired;
    if (fired > 0) notifyListeners();
    return fired;
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'reminder':
        return 'Напоминание';
      case 'meeting':
        return 'Встреча';
      default:
        return 'Задача';
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
