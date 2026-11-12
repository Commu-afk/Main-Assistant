import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_assistant/data/database/task_database.dart';

void main() {
  final now = DateTime(2026, 5, 10, 12);

  group('nextOccurrence', () {
    test('ежедневно: срок ещё не наступил — берём следующий день', () {
      final due = DateTime(2026, 5, 10, 18);
      expect(
        TaskDatabase.nextOccurrence('daily', due, null, now: now),
        DateTime(2026, 5, 11, 18),
      );
    });

    test('ежедневно: пропущенные дни не копятся', () {
      final due = DateTime(2026, 5, 1, 9);
      expect(
        TaskDatabase.nextOccurrence('daily', due, null, now: now),
        DateTime(2026, 5, 11, 9),
      );
    });

    test('еженедельно: шаг 7 дней', () {
      final due = DateTime(2026, 5, 6, 9);
      expect(
        TaskDatabase.nextOccurrence('weekly', due, null, now: now),
        DateTime(2026, 5, 13, 9),
      );
    });

    test('ежемесячно: 31 января + 1 месяц = 28 февраля', () {
      final jan31 = DateTime(2026, 1, 31, 10);
      expect(
        TaskDatabase.nextOccurrence(
          'monthly',
          jan31,
          null,
          now: DateTime(2026, 1, 31, 11),
        ),
        DateTime(2026, 2, 28, 10),
      );
    });

    test('ежегодно: 29 февраля переносится на 28-е', () {
      final leap = DateTime(2024, 2, 29, 8);
      expect(
        TaskDatabase.nextOccurrence(
          'yearly',
          leap,
          null,
          now: DateTime(2024, 3, 1),
        ),
        DateTime(2025, 2, 28, 8),
      );
    });

    test('по датам: берётся ближайшая будущая дата серии', () {
      final dates = [
        DateTime(2026, 5, 1),
        DateTime(2026, 5, 20),
        DateTime(2026, 6, 1),
      ];
      final encoded = jsonEncode(
        dates.map((d) => d.toIso8601String()).toList(),
      );

      expect(
        TaskDatabase.nextOccurrence(
          'dates',
          DateTime(2026, 5, 1),
          encoded,
          now: now,
        ),
        DateTime(2026, 5, 20),
      );
    });

    test('по датам: время суток берётся у текущего срока', () {
      final encoded = jsonEncode([
        DateTime(2026, 5, 1).toIso8601String(),
        DateTime(2026, 5, 20).toIso8601String(),
      ]);

      expect(
        TaskDatabase.nextOccurrence(
          'dates',
          DateTime(2026, 5, 1, 18, 30),
          encoded,
          now: now,
        ),
        DateTime(2026, 5, 20, 18, 30),
      );
    });

    test('по датам: серия исчерпана — следующего срока нет', () {
      final encoded = jsonEncode([
        DateTime(2026, 4, 1).toIso8601String(),
        DateTime(2026, 5, 1).toIso8601String(),
      ]);

      expect(
        TaskDatabase.nextOccurrence(
          'dates',
          DateTime(2026, 5, 1),
          encoded,
          now: now,
        ),
        isNull,
      );
    });

    test('без правила повторения возвращает null', () {
      expect(
        TaskDatabase.nextOccurrence('unknown', DateTime(2026, 5, 10), null),
        isNull,
      );
    });
  });
}
