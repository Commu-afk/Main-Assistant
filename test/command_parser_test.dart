import 'package:flutter_test/flutter_test.dart';
import 'package:local_assistant/core/utils/command_parser.dart';
import 'package:local_assistant/core/utils/russian_numbers.dart';

void main() {
  group('normalizeRussianNumbers', () {
    test('одиночные числа', () {
      expect(normalizeRussianNumbers('пять минут'), '5 минут');
      expect(normalizeRussianNumbers('двадцать три'), '23');
      expect(normalizeRussianNumbers('сорок'), '40');
    });

    test('составные числа', () {
      expect(normalizeRussianNumbers('сто двадцать три'), '123');
      expect(normalizeRussianNumbers('девятьсот девяносто девять'), '999');
    });

    test('тысячи', () {
      expect(normalizeRussianNumbers('две тысячи пятьсот'), '2500');
      expect(normalizeRussianNumbers('тысяча'), '1000');
    });

    test('не трогает обычные слова и пунктуацию', () {
      expect(
        normalizeRussianNumbers('Позвонить маме, купить хлеб!'),
        'Позвонить маме, купить хлеб!',
      );
      expect(
        normalizeRussianNumbers('встреча в пять часов, зал два'),
        'встреча в 5 часов, зал 2',
      );
    });

    test('не склеивает числа через знаки препинания', () {
      expect(normalizeRussianNumbers('пять, шесть'), '5, 6');
    });
  });

  group('parseCommand', () {
    test('понимает время словами', () {
      final parsed = parseCommand('позвонить в пять часов вечера', 'task');
      expect(parsed.title, 'позвонить');
      expect(parsed.dueAt?.hour, 17);
    });

    test('понимает дательный падеж и минуты с частью дня', () {
      final before = DateTime.now();

      final toFive = parseCommand('позвонить к пяти часам вечера', 'task');
      expect(toFive.title, 'позвонить');
      expect(toFive.dueAt, isNotNull);
      expect(toFive.dueAt!.hour, 17);
      expect(toFive.dueAt!.minute, 0);

      final morning = parseCommand('позвонить завтра в 9:30 утра', 'task');
      final tomorrow = before.add(const Duration(days: 1));
      expect(morning.title, 'позвонить');
      expect(morning.dueAt!.day, tomorrow.day);
      expect(morning.dueAt!.hour, 9);
      expect(morning.dueAt!.minute, 30);
    });

    test('понимает «через N минут»', () {
      final before = DateTime.now();
      final parsed = parseCommand(
        'позвонить через двадцать три минуты',
        'task',
      );
      expect(parsed.title, 'позвонить');
      expect(parsed.dueAt, isNotNull);
      expect(
        parsed.dueAt!.difference(before).inMinutes,
        inInclusiveRange(22, 24),
      );
    });

    test('понимает «через N часов» и цифры в тексте', () {
      final before = DateTime.now();
      final parsed = parseCommand('позвонить через два часа', 'task');
      expect(parsed.title, 'позвонить');
      expect(parsed.dueAt!.difference(before).inHours, inInclusiveRange(1, 2));
    });

    test('время разбирается вместе с относительной датой', () {
      final parsed = parseCommand('позвонить маме завтра в 18:00', 'task');
      final tomorrow = DateTime.now().add(const Duration(days: 1));

      expect(parsed.title, 'позвонить маме');
      expect(parsed.dueAt, isNotNull);
      expect(parsed.dueAt!.day, tomorrow.day);
      expect(parsed.dueAt!.hour, 18);
      expect(parsed.dueAt!.minute, 0);
    });

    test('понимает день недели', () {
      final now = DateTime.now();
      final target = (now.weekday + 1) % 7 + 1;
      final names = [
        '',
        'понедельник',
        'вторник',
        'среду',
        'четверг',
        'пятницу',
        'субботу',
        'воскресенье',
      ];
      final daysAhead = (target - now.weekday + 7) % 7;
      final expected = DateTime(now.year, now.month, now.day + daysAhead);

      final parsed = parseCommand(
        'позвонить в ${names[target]} в 10:00',
        'task',
      );

      expect(parsed.title, 'позвонить');
      expect(parsed.dueAt!.weekday, target);
      expect(parsed.dueAt!.day, expected.day);
      expect(parsed.dueAt!.hour, 10);
    });

    test('понимает часть дня без точного часа', () {
      final parsed = parseCommand('завтра вечером купить хлеб', 'task');
      final tomorrow = DateTime.now().add(const Duration(days: 1));

      expect(parsed.title, 'купить хлеб');
      expect(parsed.dueAt!.day, tomorrow.day);
      expect(parsed.dueAt!.hour, 18);
    });

    test('понимает короткие относительные сроки', () {
      final before = DateTime.now();

      final halfHour = parseCommand('позвонить через полчаса', 'task');
      expect(
        halfHour.dueAt!.difference(before).inMinutes,
        inInclusiveRange(29, 31),
      );

      final hour = parseCommand('позвонить через час', 'task');
      expect(
        hour.dueAt!.difference(before).inMinutes,
        inInclusiveRange(59, 61),
      );
    });

    test('сам определяет встречу по ключевому слову', () {
      final parsed = parseCommand('Встреча с Ивановым завтра в 15:00', 'task');

      expect(parsed.type, 'meeting');
      expect(parsed.typeDetected, isTrue);
      expect(parsed.title, 'с Ивановым');
      expect(parsed.dueAt!.hour, 15);
    });

    test('напоминание без времени остаётся без срока', () {
      final parsed = parseCommand('напомни купить хлеб', 'task');

      expect(parsed.type, 'reminder');
      expect(parsed.typeDetected, isTrue);
      expect(parsed.title, 'купить хлеб');
      expect(parsed.dueAt, isNull);
    });

    test('убирает тип записи из названия', () {
      final parsed = parseCommand('Создай задачу купить хлеб', 'task');

      expect(parsed.type, 'task');
      expect(parsed.title, 'купить хлеб');
      expect(parsed.dueAt, isNull);
    });

    test('сохраняет цифры в названии', () {
      final parsed = parseCommand('купить пять яблок', 'task');
      expect(parsed.title, 'купить 5 яблок');
      expect(parsed.dueAt, isNull);
    });

    test('понимает «напомни» и не оставляет его в названии', () {
      final before = DateTime.now();
      final parsed = parseCommand(
        'Напомни мне через две минуты проверить уведомления',
        'task',
      );

      expect(parsed.type, 'reminder');
      expect(parsed.title, 'проверить уведомления');
      expect(parsed.dueAt, isNotNull);
      expect(
        parsed.dueAt!.difference(before).inMinutes,
        inInclusiveRange(1, 2),
      );
    });
  });
}
