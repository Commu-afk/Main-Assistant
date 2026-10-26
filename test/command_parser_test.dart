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

    test('понимает «через N минут»', () {
      final before = DateTime.now();
      final parsed = parseCommand('позвонить через двадцать три минуты', 'task');
      expect(parsed.title, 'позвонить');
      expect(parsed.dueAt, isNotNull);
      expect(
        parsed.dueAt!.difference(before).inMinutes,
        inInclusiveRange(22, 24),
      );
    });

    test('понимает «через N часов» и цифры в тексте', () {
      final before = DateTime.now();
      final parsed = parseCommand('задача через два часа', 'task');
      expect(parsed.title, 'задача');
      expect(parsed.dueAt!.difference(before).inHours, inInclusiveRange(1, 2));
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
