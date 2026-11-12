/// Утилиты для календарных представлений: неделя, названия месяцев и дней.
library;

const List<String> _months = [
  'январь',
  'февраль',
  'март',
  'апрель',
  'май',
  'июнь',
  'июль',
  'август',
  'сентябрь',
  'октябрь',
  'ноябрь',
  'декабрь',
];

const List<String> _monthsGenitive = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

/// Пн..Вс, индекс — `DateTime.weekday - 1`.
const List<String> _weekdaysShort = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

/// Дата без времени.
DateTime dayOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// Понедельник недели, в которую попадает [date].
DateTime startOfWeek(DateTime date) {
  final day = dayOnly(date);
  return day.subtract(Duration(days: day.weekday - 1));
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// «май» (с маленькой буквы, для середины фразы).
String monthName(int month) => _months[(month - 1) % 12];

/// «мая» — для «12 мая».
String monthNameGenitive(int month) => _monthsGenitive[(month - 1) % 12];

/// «Пн», «Вт», …
String weekdayShort(int weekday) => _weekdaysShort[(weekday - 1) % 7];

/// «Май 2026» — заголовок над полосой недели.
String monthTitle(DateTime date) {
  final name = monthName(date.month);
  return '${name[0].toUpperCase()}${name.substring(1)} ${date.year}';
}

/// «12–18 мая», «27 апреля – 3 мая», «29 декабря 2026 – 4 января 2027».
String weekRangeLabel(DateTime weekStart) {
  final start = dayOnly(weekStart);
  final end = start.add(const Duration(days: 6));

  if (start.month == end.month && start.year == end.year) {
    return '${start.day}–${end.day} ${monthNameGenitive(end.month)}';
  }
  if (start.year == end.year) {
    return '${start.day} ${monthNameGenitive(start.month)} – '
        '${end.day} ${monthNameGenitive(end.month)}';
  }
  return '${start.day} ${monthNameGenitive(start.month)} ${start.year} – '
      '${end.day} ${monthNameGenitive(end.month)} ${end.year}';
}

/// Заголовок дня в списке: «Сегодня, 12 мая», «Завтра, 13 мая»,
/// «Вчера, 11 мая» или «Ср, 14 мая».
String dayHeader(DateTime day, {DateTime? now}) {
  final target = dayOnly(day);
  final today = dayOnly(now ?? DateTime.now());
  final diff = target.difference(today).inDays;
  final date = '${target.day} ${monthNameGenitive(target.month)}';

  if (diff == 0) return 'Сегодня, $date';
  if (diff == 1) return 'Завтра, $date';
  if (diff == -1) return 'Вчера, $date';
  return '${weekdayShort(target.weekday)}, $date';
}
