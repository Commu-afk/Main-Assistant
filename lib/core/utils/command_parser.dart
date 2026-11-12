import 'russian_numbers.dart';

class ParsedCommand {
  final String title;
  final String type;
  final DateTime? dueAt;
  final bool typeDetected;
  final bool timeDetected;

  const ParsedCommand({
    required this.title,
    required this.type,
    required this.dueAt,
    this.typeDetected = false,
    this.timeDetected = false,
  });
}

/// Границы слова для кириллицы.
///
/// `\b` в Dart (как в JavaScript) считает словесными только латиницу и цифры,
/// поэтому для русских слов он не срабатывает: «\bзавтра\b» не находит
/// «завтра». Расставляем границы явно.
String _word(String body) => '(?<![А-Яа-яЁё])$body(?![А-Яа-яЁё])';

const Map<String, int> _periodHours = {
  'утром': 9,
  'днём': 13,
  'днем': 13,
  'вечером': 18,
  'ночью': 22,
  'полдень': 12,
  'полночь': 0,
  'обед': 13,
};

int? _monthNumber(String word) {
  final w = word.toLowerCase();
  if (w.startsWith('январ')) return 1;
  if (w.startsWith('феврал')) return 2;
  if (w.startsWith('март')) return 3;
  if (w.startsWith('апрел')) return 4;
  if (w == 'май' || w == 'мая') return 5;
  if (w.startsWith('июн')) return 6;
  if (w.startsWith('июл')) return 7;
  if (w.startsWith('август')) return 8;
  if (w.startsWith('сентябр')) return 9;
  if (w.startsWith('октябр')) return 10;
  if (w.startsWith('ноябр')) return 11;
  if (w.startsWith('декабр')) return 12;
  return null;
}

int? _weekdayNumber(String word) {
  final w = word.toLowerCase();
  if (w.startsWith('понедельник')) return DateTime.monday;
  if (w.startsWith('вторник')) return DateTime.tuesday;
  if (w.startsWith('сред')) return DateTime.wednesday;
  if (w.startsWith('четверг')) return DateTime.thursday;
  if (w.startsWith('пятниц')) return DateTime.friday;
  if (w.startsWith('суббот')) return DateTime.saturday;
  if (w.startsWith('воскресень')) return DateTime.sunday;
  return null;
}

int _applyDayPeriod(int hour, String? period) {
  switch (period) {
    case 'утра':
      return hour == 12 ? 0 : hour;
    case 'дня':
      return hour == 12 ? 12 : (hour < 12 ? hour + 12 : hour);
    case 'вечера':
      return hour == 12 ? 0 : (hour < 12 ? hour + 12 : hour);
    case 'ночи':
      return hour == 12 ? 0 : hour;
    default:
      return hour;
  }
}

/// Разбирает фразу на тип записи, название и срок.
///
/// Тип определяется по ключевым словам («встреча», «созвон», «напомни»),
/// иначе берётся [fallbackType]. Время разбирается независимо от даты:
/// «завтра в 18:00» -> завтра, 18:00, а не полночь.
ParsedCommand parseCommand(String input, String fallbackType) {
  // Модель распознаёт числа словами, поэтому «через пять минут» сначала
  // превращаем в «через 5 минут».
  final original = normalizeRussianNumbers(input.trim());
  final lower = original.toLowerCase();

  var type = fallbackType;
  var typeDetected = false;

  if (RegExp(
    _word(r'(напомн[а-я]*|не\s+(?:забудь|забыть))'),
    caseSensitive: false,
  ).hasMatch(lower)) {
    type = 'reminder';
    typeDetected = true;
  } else if (RegExp(
    _word(
      r'(встреч[а-я]*|созвон[а-я]*|переговор[а-я]*|совещани[а-я]*'
      r'|собеседовани[а-я]*|визит[а-я]*|при[её]м[а-я]*)',
    ),
    caseSensitive: false,
  ).hasMatch(lower)) {
    type = 'meeting';
    typeDetected = true;
  } else if (RegExp(
    _word(r'(задач[а-я]*|задани[а-я]*|дело|дела)'),
    caseSensitive: false,
  ).hasMatch(lower)) {
    type = 'task';
    typeDetected = true;
  }

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  DateTime? date;
  var hasRelativeDue = false;
  var weekdayMatchedToday = false;
  var timeDetected = false;
  String cleaned = original;

  // --- Относительные сроки: «через полчаса», «через 2 часа», «через день».
  final halfHour = RegExp(
    _word(r'через\s+полчаса'),
    caseSensitive: false,
  ).firstMatch(cleaned);
  final hourAndHalf = RegExp(
    _word(r'через\s+полтора\s+часа'),
    caseSensitive: false,
  ).firstMatch(cleaned);
  final coupleMinutes = RegExp(
    _word(r'через\s+(?:пару|несколько)\s+минут[а-я]*'),
    caseSensitive: false,
  ).firstMatch(cleaned);
  final numericRelative = RegExp(
    _word(
      r'через\s+(\d{1,3})\s*'
      r'(минут[а-я]*|час[а-я]*|день|дня|дней|недел[а-я]*|месяц[а-я]*)',
    ),
    caseSensitive: false,
  ).firstMatch(cleaned);
  final singleRelative = RegExp(
    _word(r'через\s+(минуту|час|день|неделю|месяц)'),
    caseSensitive: false,
  ).firstMatch(cleaned);

  if (halfHour != null) {
    date = now.add(const Duration(minutes: 30));
    hasRelativeDue = true;
    timeDetected = true;
    cleaned = cleaned.replaceRange(halfHour.start, halfHour.end, ' ');
  } else if (hourAndHalf != null) {
    date = now.add(const Duration(minutes: 90));
    hasRelativeDue = true;
    timeDetected = true;
    cleaned = cleaned.replaceRange(hourAndHalf.start, hourAndHalf.end, ' ');
  } else if (coupleMinutes != null) {
    date = now.add(const Duration(minutes: 2));
    hasRelativeDue = true;
    timeDetected = true;
    cleaned = cleaned.replaceRange(coupleMinutes.start, coupleMinutes.end, ' ');
  } else if (numericRelative != null) {
    final amount = int.tryParse(numericRelative.group(1)!);
    final unit = numericRelative.group(2)!.toLowerCase();

    if (amount != null) {
      if (unit.startsWith('минут')) {
        date = now.add(Duration(minutes: amount));
      } else if (unit.startsWith('час')) {
        date = now.add(Duration(hours: amount));
      } else if (unit.startsWith('недел')) {
        date = now.add(Duration(days: amount * 7));
      } else if (unit.startsWith('месяц')) {
        date = DateTime(
          now.year,
          now.month + amount,
          now.day,
          now.hour,
          now.minute,
        );
      } else {
        date = now.add(Duration(days: amount));
      }
      hasRelativeDue = true;
      timeDetected = true;
      cleaned = cleaned.replaceRange(
        numericRelative.start,
        numericRelative.end,
        ' ',
      );
    }
  } else if (singleRelative != null) {
    final unit = singleRelative.group(1)!.toLowerCase();
    if (unit == 'минуту') {
      date = now.add(const Duration(minutes: 1));
    } else if (unit == 'час') {
      date = now.add(const Duration(hours: 1));
    } else if (unit == 'неделю') {
      date = now.add(const Duration(days: 7));
    } else if (unit == 'месяц') {
      date = DateTime(now.year, now.month + 1, now.day, now.hour, now.minute);
    } else {
      date = now.add(const Duration(days: 1));
    }
    hasRelativeDue = true;
    timeDetected = true;
    cleaned = cleaned.replaceRange(
      singleRelative.start,
      singleRelative.end,
      ' ',
    );
  }

  // --- Даты: сегодня / завтра / послезавтра.
  if (date == null) {
    final afterTomorrow = RegExp(_word(r'послезавтра'), caseSensitive: false);
    final tomorrow = RegExp(_word(r'завтра'), caseSensitive: false);
    final todayWord = RegExp(_word(r'сегодня'), caseSensitive: false);

    if (afterTomorrow.hasMatch(cleaned)) {
      date = today.add(const Duration(days: 2));
      cleaned = cleaned.replaceAll(afterTomorrow, ' ');
    } else if (tomorrow.hasMatch(cleaned)) {
      date = today.add(const Duration(days: 1));
      cleaned = cleaned.replaceAll(tomorrow, ' ');
    } else if (todayWord.hasMatch(cleaned)) {
      date = today;
      cleaned = cleaned.replaceAll(todayWord, ' ');
    }
  }

  // --- Дата вида «26 октября» / «26-го октября 2026».
  if (date == null) {
    final monthDate = RegExp(
      r'(?<!\d)(\d{1,2})(?:\s*[- ]?(?:го|е|ое))?\s+'
      r'(январ[а-я]*|феврал[а-я]*|март[а-я]*|апрел[а-я]*|ма[йя]'
      r'|июн[а-я]*|июл[а-я]*|август[а-я]*|сентябр[а-я]*'
      r'|октябр[а-я]*|ноябр[а-я]*|декабр[а-я]*)'
      r'(?:\s+(\d{4}))?',
      caseSensitive: false,
    ).firstMatch(cleaned);

    if (monthDate != null) {
      final day = int.tryParse(monthDate.group(1)!);
      final month = _monthNumber(monthDate.group(2)!);
      final explicitYear = monthDate.group(3) == null
          ? null
          : int.tryParse(monthDate.group(3)!);

      if (day != null && month != null) {
        var year = explicitYear ?? now.year;
        final probe = DateTime(year, month, day);
        final valid = probe.month == month && probe.day == day;

        if (valid) {
          if (explicitYear == null && probe.isBefore(today)) {
            year += 1;
          }
          date = DateTime(year, month, day);
          cleaned = cleaned.replaceRange(monthDate.start, monthDate.end, ' ');
        }
      }
    }
  }

  // --- Дата вида «26.10.2026» (с годом, чтобы не путать со временем).
  if (date == null) {
    final dottedDate = RegExp(r'(?<!\d)(\d{1,2})\.(\d{1,2})\.(\d{2,4})(?!\d)')
        .firstMatch(cleaned);

    if (dottedDate != null) {
      final day = int.tryParse(dottedDate.group(1)!);
      final month = int.tryParse(dottedDate.group(2)!);
      var year = int.tryParse(dottedDate.group(3)!);

      if (day != null && month != null && year != null) {
        if (year < 100) year += 2000;
        final probe = DateTime(year, month, day);
        if (probe.month == month && probe.day == day) {
          date = DateTime(year, month, day);
          cleaned = cleaned.replaceRange(dottedDate.start, dottedDate.end, ' ');
        }
      }
    }
  }

  // --- «На следующей неделе» — тот же день через неделю.
  if (date == null) {
    final nextWeek = RegExp(
      _word(r'(?:на\s+)?следующей\s+неделе'),
      caseSensitive: false,
    ).firstMatch(cleaned);

    if (nextWeek != null) {
      date = today.add(const Duration(days: 7));
      cleaned = cleaned.replaceRange(nextWeek.start, nextWeek.end, ' ');
    }
  }

  // --- День недели: «в пятницу», «на следующий понедельник».
  if (date == null) {
    final weekday = RegExp(
      r'(?:(?<![А-Яа-яЁё])(?:в|во|на)\s+)?'
      r'(?:(?:следующ|ближайш)[а-я]*\s+)?'
      r'(?<![А-Яа-яЁё])'
      r'(понедельник(?:а|у|ом|е)?|вторник(?:а|у|ом|е)?'
      r'|сред(?:а|у|ы|ой|е)|четверг(?:а|у|ом|е)?'
      r'|пятниц(?:а|у|ы|ей|е)|суббот(?:а|у|ы|ой|е)'
      r'|воскресень(?:е|я|ю|ем))'
      r'(?![А-Яа-яЁё])',
      caseSensitive: false,
    ).firstMatch(cleaned);

    if (weekday != null) {
      final target = _weekdayNumber(weekday.group(1)!);
      if (target != null) {
        final daysAhead = (target - now.weekday + 7) % 7;
        date = today.add(Duration(days: daysAhead));
        weekdayMatchedToday = daysAhead == 0;
        cleaned = cleaned.replaceRange(weekday.start, weekday.end, ' ');
      }
    }
  }

  // --- Время. Разбирается всегда, даже если дата уже известна.
  int? hour;
  int? minute;

  final colonTime = RegExp(
    r'(?:(?<![А-Яа-яЁё])(?:в|во|к|на)\s+)?'
    r'(\d{1,2})[:.](\d{2})(?:\s*(утра|дня|вечера|ночи))?(?!\d)',
    caseSensitive: false,
  ).firstMatch(cleaned);

  if (colonTime != null) {
    final parsedHour = int.tryParse(colonTime.group(1)!);
    final parsedMinute = int.tryParse(colonTime.group(2)!);
    final period = colonTime.group(3)?.toLowerCase();

    if (parsedHour != null &&
        parsedHour <= 23 &&
        parsedMinute != null &&
        parsedMinute <= 59) {
      hour = _applyDayPeriod(parsedHour, period);
      minute = parsedMinute;
      timeDetected = true;
      cleaned = cleaned.replaceRange(colonTime.start, colonTime.end, ' ');
    }
  }

  if (hour == null) {
    // Распознавание иногда отдаёт время без двоеточия: «в 15 30».
    final spacedTime = RegExp(
      r'(?:(?<![А-Яа-яЁё])(?:в|во|к|на)\s+)'
      r'(\d{1,2})\s+(\d{2})(?:\s*(утра|дня|вечера|ночи))?'
      r'(?=\s*(?:$|[,.;!?]))',
      caseSensitive: false,
    ).firstMatch(cleaned);

    if (spacedTime != null) {
      final parsedHour = int.tryParse(spacedTime.group(1)!);
      final parsedMinute = int.tryParse(spacedTime.group(2)!);
      final period = spacedTime.group(3)?.toLowerCase();

      if (parsedHour != null &&
          parsedHour <= 23 &&
          parsedMinute != null &&
          parsedMinute <= 59) {
        hour = _applyDayPeriod(parsedHour, period);
        minute = parsedMinute;
        timeDetected = true;
        cleaned = cleaned.replaceRange(spacedTime.start, spacedTime.end, ' ');
      }
    }
  }

  if (hour == null) {
    // «в 18 часов», «к 9 утра», «на 15:00» — сильный признак времени.
    final hourWithPreposition = RegExp(
      r'(?:(?<![А-Яа-яЁё])(?:в|во|к|на)\s+)'
      r'(\d{1,2})\s*'
      r'(?:час[а-я]*\s*(?:(утра|дня|вечера|ночи))?'
      r'|(утра|дня|вечера|ночи))',
      caseSensitive: false,
    ).firstMatch(cleaned);

    if (hourWithPreposition != null) {
      final parsedHour = int.tryParse(hourWithPreposition.group(1)!);
      final period =
          (hourWithPreposition.group(2) ?? hourWithPreposition.group(3))
              ?.toLowerCase();

      if (parsedHour != null && parsedHour >= 1 && parsedHour <= 23) {
        hour = _applyDayPeriod(parsedHour, period);
        minute = 0;
        timeDetected = true;
        cleaned = cleaned.replaceRange(
          hourWithPreposition.start,
          hourWithPreposition.end,
          ' ',
        );
      }
    }
  }

  if (hour == null) {
    // «в 18» без слова «часов» — только если дальше конец фразы,
    // знак препинания или служебное слово. Иначе «в 5 яблок» станет временем.
    final bareHour = RegExp(
      r'(?:(?<![А-Яа-яЁё])(?:в|во|к|на)\s+)(\d{1,2})'
      r'(?=\s*(?:$|[,.;!?]'
      r'|(?:и|а|но|с|со|на|к|до|по|за|из|от|у)\s))',
      caseSensitive: false,
    ).firstMatch(cleaned);

    if (bareHour != null) {
      final parsedHour = int.tryParse(bareHour.group(1)!);

      if (parsedHour != null && parsedHour >= 1 && parsedHour <= 23) {
        hour = parsedHour;
        minute = 0;
        timeDetected = true;
        cleaned = cleaned.replaceRange(bareHour.start, bareHour.end, ' ');
      }
    }
  }

  if (hour == null) {
    final hourWord = RegExp(
      r'(?<![А-Яа-яЁё])(\d{1,2})\s*час[а-я]*'
      r'(?:\s*(утра|дня|вечера|ночи))?(?![А-Яа-яЁё])',
      caseSensitive: false,
    ).firstMatch(cleaned);

    if (hourWord != null) {
      final parsedHour = int.tryParse(hourWord.group(1)!);
      final period = hourWord.group(2)?.toLowerCase();

      if (parsedHour != null && parsedHour >= 1 && parsedHour <= 23) {
        hour = _applyDayPeriod(parsedHour, period);
        minute = 0;
        timeDetected = true;
        cleaned = cleaned.replaceRange(hourWord.start, hourWord.end, ' ');
      }
    }
  }

  if (hour == null) {
    final dayPeriod = RegExp(
      r'(?:(?<![А-Яа-яЁё])(?:в|во)\s+)?'
      r'(?<![А-Яа-яЁё])'
      r'(утром|днём|днем|вечером|ночью|полдень|полночь|обед[а-я]*)'
      r'(?![А-Яа-яЁё])',
      caseSensitive: false,
    ).firstMatch(cleaned);

    if (dayPeriod != null) {
      final word = dayPeriod.group(1)!.toLowerCase();
      final periodHour = word.startsWith('обед')
          ? _periodHours['обед']
          : _periodHours[word];

      if (periodHour != null) {
        hour = periodHour;
        minute = 0;
        timeDetected = true;
        cleaned = cleaned.replaceRange(dayPeriod.start, dayPeriod.end, ' ');
      }
    }
  }

  if (hour != null) {
    final base = date ?? today;
    var due = DateTime(base.year, base.month, base.day, hour, minute ?? 0);

    if (date == null) {
      // Без явной даты время, которое уже прошло, переносим на завтра.
      if (!due.isAfter(now)) due = due.add(const Duration(days: 1));
    } else if (weekdayMatchedToday && !due.isAfter(now)) {
      // «В понедельник» в понедельник вечером — это следующий понедельник.
      due = due.add(const Duration(days: 7));
    }

    date = due;
  } else if (date != null && !hasRelativeDue) {
    // Указана только дата — ставим на 9 утра, если это время ещё впереди.
    var due = DateTime(date.year, date.month, date.day, 9);
    if (!due.isAfter(now)) {
      due = due.add(Duration(days: weekdayMatchedToday ? 7 : 1));
    }
    date = due;
  }

  // --- Чистим название от служебных слов.
  cleaned = cleaned.replaceFirst(
    RegExp(
      r'^(?:\s*(?:пожалуйста|пожалуй)[,\s]+)?\s*'
      r'(?:добавь|добавить|создай|создать|запиши|записать|поставь|поставить'
      r'|назначь|назначить|напомни|напомнить|не\s+забудь|не\s+забыть'
      r'|нужно|надо|хочу|хотел|хотела)(?![А-Яа-яЁё])\s*(?:мне\s+)?',
      caseSensitive: false,
    ),
    '',
  );

  cleaned = cleaned.replaceFirst(
    RegExp(
      r'^(?:(?:про|о|об|обо|насчёт|насчет|на)\s+)?'
      r'(?:задач[а-я]*|задани[а-я]*|напоминани[а-я]*|встреч[а-я]*'
      r'|созвон[а-я]*|переговор[а-я]*|совещани[а-я]*'
      r'|собеседовани[а-я]*|визит[а-я]*|при[её]м[а-я]*)'
      r'(?![А-Яа-яЁё])\s*',
      caseSensitive: false,
    ),
    '',
  );

  cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  cleaned = cleaned
      .replaceAll(RegExp(r'^[,;:.\-–—\s]+|[,;:.\-–—\s]+$'), '')
      .trim();
  // Предлог, оставшийся висеть в конце после вырезания времени.
  cleaned = cleaned
      .replaceAll(
        RegExp(
          r'\s+(?:в|во|на|к|с|со|про|о|об|за|до|по|из|от|у)$',
          caseSensitive: false,
        ),
        '',
      )
      .trim();

  return ParsedCommand(
    title: cleaned,
    type: type,
    dueAt: date,
    typeDetected: typeDetected,
    timeDetected: timeDetected,
  );
}
