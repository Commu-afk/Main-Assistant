import 'russian_numbers.dart';

class ParsedCommand {
  final String title;
  final String type;
  final DateTime? dueAt;

  const ParsedCommand({
    required this.title,
    required this.type,
    required this.dueAt,
  });
}

/// Границы слова для кириллицы.
///
/// `\b` в Dart (как в JavaScript) считает словесными только латиницу и цифры,
/// поэтому для русских слов он не срабатывает: «\bзавтра\b» не находит
/// «завтра». Расставляем границы явно.
String _word(String body) => '(?<![А-Яа-яЁё])$body(?![А-Яа-яЁё])';

ParsedCommand parseCommand(String input, String fallbackType) {
  // Модель распознаёт числа словами, поэтому «через пять минут» сначала
  // превращаем в «через 5 минут».
  final original = normalizeRussianNumbers(input.trim());
  final lower = original.toLowerCase();

  String type = fallbackType;
  if (lower.contains('встреч')) {
    type = 'meeting';
  } else if (lower.contains('напомн')) {
    type = 'reminder';
  } else if (lower.contains('задач')) {
    type = 'task';
  }

  final now = DateTime.now();
  DateTime? date;
  String cleaned = original;

  final relativeDate = RegExp(
    _word(r'послезавтра'),
    caseSensitive: false,
  );
  final tomorrow = RegExp(_word(r'завтра'), caseSensitive: false);
  final today = RegExp(_word(r'сегодня'), caseSensitive: false);

  if (relativeDate.hasMatch(cleaned)) {
    date = DateTime(now.year, now.month, now.day + 2);
    cleaned = cleaned.replaceAll(relativeDate, '');
  } else if (tomorrow.hasMatch(cleaned)) {
    date = DateTime(now.year, now.month, now.day + 1);
    cleaned = cleaned.replaceAll(tomorrow, '');
  } else if (today.hasMatch(cleaned)) {
    date = DateTime(now.year, now.month, now.day);
    cleaned = cleaned.replaceAll(today, '');
  }

  int? hour;
  int? minute;

  // Относительное время: «через 5 минут», «через 2 часа», «через 3 дня».
  final relative = RegExp(
    _word(r'через\s+(\d{1,3})\s*(минут(?:у|ы)?|час(?:а|ов)?|день|дня|дней)'),
    caseSensitive: false,
  ).firstMatch(cleaned);

  if (relative != null) {
    final amount = int.tryParse(relative.group(1)!);
    final unit = relative.group(2)!.toLowerCase();

    if (amount != null) {
      if (unit.startsWith('минут')) {
        date = now.add(Duration(minutes: amount));
      } else if (unit.startsWith('час')) {
        date = now.add(Duration(hours: amount));
      } else {
        date = DateTime(now.year, now.month, now.day + amount);
      }
      cleaned = cleaned.replaceRange(relative.start, relative.end, ' ');
    }
  }

  if (date == null) {
    final colonTime = RegExp(r'(\d{1,2})[:.](\d{2})(?!\d)').firstMatch(cleaned);

    if (colonTime != null) {
      final parsedHour = int.tryParse(colonTime.group(1)!);
      final parsedMinute = int.tryParse(colonTime.group(2)!);

      if (parsedHour != null &&
          parsedHour <= 23 &&
          parsedMinute != null &&
          parsedMinute <= 59) {
        hour = parsedHour;
        minute = parsedMinute;
        cleaned = cleaned.replaceRange(colonTime.start, colonTime.end, ' ');
      }
    } else {
      final hourTime = RegExp(
        _word(
          r'в\s+(\d{1,2})(?:\s*(?:час(?:а|ов)?))?(?:\s*(утра|дня|вечера|ночи))?',
        ),
        caseSensitive: false,
      ).firstMatch(cleaned);

      if (hourTime != null) {
        final parsedHour = int.tryParse(hourTime.group(1)!);
        final period = hourTime.group(2)?.toLowerCase();

        if (parsedHour != null && parsedHour >= 1 && parsedHour <= 23) {
          var result = parsedHour;
          if (result <= 12) {
            if (period == 'вечера' || period == 'дня') result += 12;
            if (period == 'ночи' || period == 'утра') {
              if (result == 12) result = 0;
            }
          }
          hour = result;
          minute = 0;
          cleaned = cleaned.replaceRange(hourTime.start, hourTime.end, ' ');
        }
      }
    }
  }

  if (hour != null) {
    date ??= DateTime(now.year, now.month, now.day);
    date = DateTime(date.year, date.month, date.day, hour, minute ?? 0);
  }

  cleaned = cleaned.replaceFirst(
    RegExp(
      r'^\s*(добавь|создай|запиши|поставь|назначь|напомни)\s+(мне\s+)?',
      caseSensitive: false,
    ),
    '',
  );

  cleaned = cleaned.replaceFirst(
    RegExp(
      r'^\s*(мне\s+)?(задачу|напоминание|встречу)\s*',
      caseSensitive: false,
    ),
    '',
  );

  cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  cleaned = cleaned.replaceAll(RegExp(r'^[,;:\- ]+|[,;:\- ]+$'), '').trim();

  return ParsedCommand(
    title: cleaned,
    type: type,
    dueAt: date,
  );
}
