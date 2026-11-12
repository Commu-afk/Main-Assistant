import 'package:flutter/material.dart';

import '../../../core/utils/dates.dart';

/// Полоса недели над полем ввода: месяц со стрелкой вниз, стрелки недель
/// и семь дней с подсветкой сегодняшнего.
class WeekSelector extends StatelessWidget {
  const WeekSelector({
    super.key,
    required this.weekStart,
    required this.countOf,
    required this.onWeekChanged,
  });

  /// Понедельник показываемой недели.
  final DateTime weekStart;

  /// Сколько задач назначено на день (для точки под датой).
  final int Function(DateTime day) countOf;

  final ValueChanged<DateTime> onWeekChanged;

  Future<void> _openMonth(BuildContext context) async {
    final picked = await showMonthWeekPicker(
      context,
      initialWeekStart: weekStart,
    );
    if (picked != null) onWeekChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final thisWeek = startOfWeek(now);
    final onThisWeek = isSameDay(weekStart, thisWeek);
    // Месяц подписываем по середине недели: так неделя на стыке месяцев
    // подписана месяцем, в котором у неё больше дней.
    final middle = weekStart.add(const Duration(days: 3));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            InkWell(
              onTap: () => _openMonth(context),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      monthTitle(middle),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.expand_more, size: 20, color: scheme.primary),
                  ],
                ),
              ),
            ),
            const Spacer(),
            if (!onThisWeek)
              TextButton(
                onPressed: () => onWeekChanged(thisWeek),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
                child: const Text('Сегодня'),
              ),
            IconButton(
              tooltip: 'Прошлая неделя',
              visualDensity: VisualDensity.compact,
              iconSize: 20,
              onPressed: () =>
                  onWeekChanged(weekStart.subtract(const Duration(days: 7))),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Следующая неделя',
              visualDensity: VisualDensity.compact,
              iconSize: 20,
              onPressed: () =>
                  onWeekChanged(weekStart.add(const Duration(days: 7))),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: _DayCell(
                  day: weekStart.add(Duration(days: i)),
                  today: now,
                  count: countOf(weekStart.add(Duration(days: i))),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.today, required this.count});

  final DateTime day;
  final DateTime today;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isToday = isSameDay(day, today);
    final weekend = day.weekday >= 6;

    final labelColor = isToday
        ? scheme.onPrimary
        : weekend
        ? scheme.onSurfaceVariant.withValues(alpha: 0.7)
        : scheme.onSurface;

    return Tooltip(
      message:
          '${weekdayShort(day.weekday)}, ${day.day} '
          '${monthNameGenitive(day.month)}'
          '${count > 0 ? ' · задач: $count' : ''}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            weekdayShort(day.weekday),
            style: theme.textTheme.labelSmall?.copyWith(
              color: isToday
                  ? scheme.primary
                  : scheme.onSurfaceVariant.withValues(alpha: 0.8),
              fontWeight: isToday ? FontWeight.w700 : null,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isToday ? scheme.primary : null,
            ),
            child: Text(
              '${day.day}',
              style: theme.textTheme.titleSmall?.copyWith(
                color: labelColor,
                fontWeight: isToday ? FontWeight.w700 : null,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: count == 0
                  ? Colors.transparent
                  : isToday
                  ? scheme.primary
                  : scheme.primary.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// Диалог выбора недели: весь месяц, тап по любому дню выбирает его неделю.
Future<DateTime?> showMonthWeekPicker(
  BuildContext context, {
  required DateTime initialWeekStart,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _MonthWeekDialog(initialWeekStart: initialWeekStart),
  );
}

class _MonthWeekDialog extends StatefulWidget {
  const _MonthWeekDialog({required this.initialWeekStart});

  final DateTime initialWeekStart;

  @override
  State<_MonthWeekDialog> createState() => _MonthWeekDialogState();
}

class _MonthWeekDialogState extends State<_MonthWeekDialog> {
  /// Первое число показываемого месяца.
  late DateTime _month;
  late DateTime _selectedWeek;

  @override
  void initState() {
    super.initState();
    _selectedWeek = startOfWeek(widget.initialWeekStart);
    final middle = _selectedWeek.add(const Duration(days: 3));
    _month = DateTime(middle.year, middle.month);
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  Widget _cell(DateTime gridStart, int index, DateTime today) {
    final day = gridStart.add(Duration(days: index));
    return _MonthDayCell(
      day: day,
      inMonth: day.month == _month.month,
      isToday: isSameDay(day, today),
      inSelectedWeek: startOfWeek(day) == _selectedWeek,
      onTap: (picked) => Navigator.pop(context, startOfWeek(picked)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = dayOnly(DateTime.now());
    final firstDay = DateTime(_month.year, _month.month);
    final gridStart = startOfWeek(firstDay);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final offset = firstDay.difference(gridStart).inDays;
    final rows = ((offset + daysInMonth) / 7).ceil();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Прошлый месяц',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _shiftMonth(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          monthTitle(firstDay),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          'неделя ${weekRangeLabel(_selectedWeek)}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Следующий месяц',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _shiftMonth(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (var weekday = 1; weekday <= 7; weekday++)
                    Expanded(
                      child: Center(
                        child: Text(
                          weekdayShort(weekday),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              for (var row = 0; row < rows; row++)
                Row(
                  children: [
                    for (var col = 0; col < 7; col++)
                      Expanded(child: _cell(gridStart, row * 7 + col, today)),
                  ],
                ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Нажмите на день нужной недели',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Отмена'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, startOfWeek(DateTime.now())),
                    child: const Text('Текущая неделя'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthDayCell extends StatelessWidget {
  const _MonthDayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.inSelectedWeek,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool inSelectedWeek;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textColor = !inMonth
        ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
        : inSelectedWeek
        ? scheme.onPrimaryContainer
        : scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.all(1),
      child: InkWell(
        onTap: () => onTap(day),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: inSelectedWeek
                ? scheme.primaryContainer.withValues(alpha: inMonth ? 0.8 : 0.4)
                : null,
            border: isToday
                ? Border.all(color: scheme.primary, width: 1.4)
                : null,
          ),
          child: Text(
            '${day.day}',
            style: TextStyle(
              color: textColor,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
