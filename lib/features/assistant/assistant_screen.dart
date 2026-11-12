import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/constants/tags.dart';
import '../../core/desktop/desktop_lifecycle.dart';
import '../../core/utils/command_parser.dart';
import '../../core/utils/dates.dart';
import '../../data/database/task_database.dart';
import '../reminders/notification_service.dart';
import '../reminders/reminder_scheduler.dart';
import '../settings/desktop_settings_dialog.dart';
import '../stt/sherpa_stt_service.dart';
import '../tts/sherpa_tts_service.dart';
import 'widgets/week_selector.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  /// Аудиосервисы создаются при первом использовании: их конструкторы
  /// инициализируют устройства и микрофон, а для первого кадра это не нужно.
  SherpaSttService? _stt;
  SherpaTtsService? _ttsService;

  SherpaSttService get _sherpa => _stt ??= SherpaSttService.instance;
  SherpaTtsService get _tts => _ttsService ??= SherpaTtsService.instance;

  bool _isStarting = false;
  bool _isListening = false;
  bool _isTranscribing = false;
  bool _isSpeaking = false;

  String _searchQuery = '';
  bool _searchWasRun = false;
  DateTime? _pickedDueAt;
  String? _pickedTag;
  String? _pickedRepeatRule;
  List<DateTime> _pickedRepeatDates = const [];

  /// Понедельник недели, задачи которой показываем в списке.
  DateTime _weekStart = startOfWeek(DateTime.now());

  List<Map<String, Object?>> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEntries();
    _input.addListener(_onComposerChanged);
    ReminderScheduler.instance.addListener(_onRemindersChanged);
  }

  @override
  void dispose() {
    ReminderScheduler.instance.removeListener(_onRemindersChanged);
    _input.dispose();
    _searchController.dispose();
    _stt?.cancel();
    super.dispose();
  }

  /// Пересобираем состояние поля (кнопка очистки) при редактировании текста.
  void _onComposerChanged() {
    if (mounted) setState(() {});
  }

  /// Планировщик показал напоминание — обновляем список, чтобы был виден
  /// статус «уведомлено».
  void _onRemindersChanged() {
    if (mounted) _loadEntries();
  }

  Future<void> _toggleListening() async {
    if (_isTranscribing || _isStarting) return;

    // Стоп -> распознаём
    if (_isListening) {
      setState(() {
        _isListening = false;
        _isTranscribing = true;
      });

      try {
        final text = await _sherpa.stopAndTranscribe();
        if (!mounted) return;

        if (text.isEmpty) {
          _showMessage('Ничего не распознано, попробуйте ещё раз');
          return;
        }

        setState(() {
          _input.text = text;
          _input.selection = TextSelection.collapsed(offset: text.length);
        });
      } catch (e) {
        if (!mounted) return;
        _showMessage('Ошибка распознавания: $e');
      } finally {
        if (mounted) setState(() => _isTranscribing = false);
      }
      return;
    }

    // Старт записи
    try {
      if (_isSpeaking) await _stopSpeaking();
      // Первый запуск грузит модель распознавания — показываем спиннер.
      setState(() => _isStarting = true);
      await _sherpa.startRecording();
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _isListening = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _isListening = false;
      });
      _showMessage('Не удалось начать запись: $e');
    }
  }

  Future<void> _speak() async {
    final text = _input.text.trim();
    if (text.isEmpty) {
      _showMessage('Нечего озвучивать: введите или продиктуйте текст');
      return;
    }

    setState(() => _isSpeaking = true);

    try {
      await _tts.speak(text);
    } catch (e) {
      if (!mounted) return;
      _showMessage('Ошибка озвучки: $e');
    } finally {
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  Future<void> _stopSpeaking() async {
    await _tts.stop();
    if (!mounted) return;
    setState(() => _isSpeaking = false);
  }

  Future<void> _checkReminders() async {
    final fired = await ReminderScheduler.instance.checkNow();
    if (!mounted) return;
    await _loadEntries();
    if (!mounted) return;
    _showMessage(
      fired == 0 ? 'Срочных напоминаний нет' : 'Показано уведомлений: $fired',
    );
  }

  Future<void> _testNotification() async {
    final service = NotificationService.instance;
    final shown = await service.show(
      title: 'Мой ассистент',
      body: 'Уведомления работают: сюда придёт напоминание.',
    );
    if (!mounted) return;
    _showMessage(
      shown
          ? 'Уведомление отправлено'
          : 'Уведомления недоступны: '
                '${service.lastError ?? 'платформа не поддерживается'}',
    );
  }

  Future<void> _loadEntries() async {
    try {
      final entries = await TaskDatabase.instance.getTasks();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Ошибка загрузки базы данных: $e');
    }
  }

  Future<void> _create() async {
    final command = _input.text.trim();
    if (command.isEmpty) {
      _showMessage('Введите текст записи или продиктуйте его микрофоном');
      return;
    }

    final parsed = parseCommand(command, 'task');
    final title = parsed.title.isEmpty && parsed.type != 'task'
        ? _typeLabel(parsed.type)
        : parsed.title;
    if (title.isEmpty) {
      _showMessage(
        'Не удалось выделить название. Добавьте суть, например: '
        '«Напомни завтра в 9:00 купить хлеб»',
      );
      return;
    }

    // Выбранное вручную время имеет приоритет, иначе — то, что нашёл разбор.
    // Для серии конкретных дат сроком становится первая из них.
    var savedDate = _pickedDueAt ?? parsed.dueAt;
    if (savedDate == null &&
        _pickedRepeatRule == 'dates' &&
        _pickedRepeatDates.isNotEmpty) {
      savedDate = _atTime(_pickedRepeatDates.first, null);
    }

    // Повторяющейся задаче нужен срок, иначе нечего повторять: ставим
    // ближайшие 9:00.
    if (savedDate == null && _pickedRepeatRule != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 9);
      savedDate = today.isAfter(now)
          ? today
          : today.add(const Duration(days: 1));
    }

    if (parsed.type != 'task' && savedDate == null) {
      _showMessage(
        parsed.type == 'meeting'
            ? 'Похоже на встречу, но время не указано. Добавьте, например: '
                  '«Завтра в 15:00 встреча с Ивановым»'
            : 'Похоже на напоминание, но время не указано. Добавьте, например: '
                  '«Напомни через час позвонить маме»',
      );
      return;
    }

    final repeatRule = _pickedRepeatRule;

    try {
      await TaskDatabase.instance.addEntry(
        title: title,
        type: parsed.type,
        dueAt: savedDate,
        tag: _pickedTag,
        repeatRule: repeatRule,
        repeatDates: repeatRule == 'dates' ? _pickedRepeatDates : null,
      );

      _input.clear();
      setState(() {
        _pickedDueAt = null;
        _pickedTag = null;
        _pickedRepeatRule = null;
        _pickedRepeatDates = const [];
      });

      await _loadEntries();

      final dateText = savedDate == null
          ? ''
          : ' · ${_formatDate(savedDate.toIso8601String())}';
      final repeatText = repeatRule == null
          ? ''
          : ' · ${_repeatLabel(repeatRule)}';

      _showMessage(
        'Создано: ${_typeLabel(parsed.type)} «$title»$dateText$repeatText',
      );
    } catch (e) {
      _showMessage('Не удалось сохранить запись: $e');
    }
  }

  void _runSearch() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
      _searchWasRun = _searchQuery.isNotEmpty;
    });
    if (_searchQuery.isEmpty) {
      _showMessage('Введите запрос для поиска');
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _searchWasRun = false;
    });
  }

  List<Map<String, Object?>> get _visibleEntries {
    if (!_searchWasRun || _searchQuery.isEmpty) return _entries;

    final query = _searchQuery;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final dayAfterTomorrow = today.add(const Duration(days: 2));
    final weekEnd = today.add(const Duration(days: 7));

    final wantsToday = query.contains('сегодня');
    final wantsTomorrow =
        query.contains('завтра') && !query.contains('послезавтра');
    final wantsDayAfterTomorrow = query.contains('послезавтра');
    final wantsWeek =
        query.contains('неделе') ||
        query.contains('неделю') ||
        query.contains('ближайшую неделю');

    String? wantedType;
    if (query.contains('встреч')) {
      wantedType = 'meeting';
    } else if (query.contains('напомин')) {
      wantedType = 'reminder';
    } else if (query.contains('задач')) {
      wantedType = 'task';
    }

    var remaining = query
        .replaceAll(
          RegExp(
            r'\b(что|какие|какой|какая|у|меня|есть|найди|найти|покажи|показать|список|мои|мой|моя|мое|все|всё|записи|запись|задача|задачу|задачи|встреча|встречу|встречи|напоминание|напоминания|напоминаний|на|этой|эту|ближайшую|неделе|неделю|неделя|за|сегодня|завтра|послезавтра|с|про|об|обо|и|мне|пожалуйста)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\b\d{1,2}[:.]\d{2}\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final terms = remaining
        .split(' ')
        .map(
          (word) => word.replaceAll(
            RegExp(r'^[^a-zа-яё0-9]+|[^a-zа-яё0-9]+$', caseSensitive: false),
            '',
          ),
        )
        .where((word) => word.length >= 2)
        .toList();

    return _entries.where((entry) {
      final type = entry['type'] as String? ?? 'task';
      if (wantedType != null && type != wantedType) return false;

      final dueText = entry['due_at'] as String?;
      final parsedDate = dueText == null ? null : DateTime.tryParse(dueText);

      if (wantsToday || wantsTomorrow || wantsDayAfterTomorrow || wantsWeek) {
        if (parsedDate == null) return false;
        final dueDay = DateTime(
          parsedDate.year,
          parsedDate.month,
          parsedDate.day,
        );

        if (wantsToday && dueDay != today) return false;
        if (wantsTomorrow && dueDay != tomorrow) return false;
        if (wantsDayAfterTomorrow && dueDay != dayAfterTomorrow) return false;
        if (wantsWeek &&
            (dueDay.isBefore(today) || !dueDay.isBefore(weekEnd))) {
          return false;
        }
      }

      final title = (entry['title'] as String).toLowerCase();
      for (final term in terms) {
        if (!_matchesSearchTerm(title, term)) return false;
      }
      return true;
    }).toList();
  }

  bool _matchesSearchTerm(String title, String term) {
    if (title.contains(term)) return true;
    if (term.length >= 5) {
      final stem = term.replaceFirst(
        RegExp(
          r'(ями|ами|ого|ему|ому|ыми|ими|ах|ях|ой|ей|ый|ий|ая|яя|ое|ее|ую|юю|ом|ем|ам|ям|ы|и|а|я|у|ю|е)$',
        ),
        '',
      );
      if (stem.length >= 3 && title.contains(stem)) return true;
    }
    return false;
  }

  Future<void> _chooseDateTime() async {
    final now = DateTime.now();

    final date = await showDatePicker(
      context: context,
      initialDate: _pickedDueAt ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_pickedDueAt ?? now),
    );

    if (time == null || !mounted) return;

    final due = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    setState(() => _pickedDueAt = due);
  }

  /// Повторение из окна ввода: тот же диалог, что и в меню ⋮.
  Future<void> _chooseRepeat() async {
    final choice = await _askRepeat(
      currentRule: _pickedRepeatRule,
      currentDates: _pickedRepeatDates,
    );
    if (choice == null || !mounted) return;

    setState(() {
      _pickedRepeatRule = choice.rule;
      _pickedRepeatDates = choice.dates ?? const [];
      if (choice.rule == 'dates' && _pickedRepeatDates.isNotEmpty) {
        _pickedDueAt = _atTime(_pickedRepeatDates.first, _pickedDueAt);
      }
    });
  }

  /// Диалог выбора повторения. `null` — пользователь закрыл без изменений.
  Future<_RepeatChoice?> _askRepeat({
    String? currentRule,
    List<DateTime>? currentDates,
  }) {
    return showDialog<_RepeatChoice>(
      context: context,
      builder: (context) {
        SimpleDialogOption option(
          String label,
          bool selected,
          VoidCallback onPressed,
        ) {
          return SimpleDialogOption(
            onPressed: onPressed,
            child: _dialogOption(context, label, selected),
          );
        }

        return SimpleDialog(
          title: const Text('Повтор'),
          children: [
            option(
              'Не повторять',
              currentRule == null,
              () => Navigator.pop(context, const _RepeatChoice(null)),
            ),
            option(
              'Ежедневно',
              currentRule == 'daily',
              () => Navigator.pop(context, const _RepeatChoice('daily')),
            ),
            option(
              'Еженедельно',
              currentRule == 'weekly',
              () => Navigator.pop(context, const _RepeatChoice('weekly')),
            ),
            option(
              'Ежемесячно',
              currentRule == 'monthly',
              () => Navigator.pop(context, const _RepeatChoice('monthly')),
            ),
            option(
              'Ежегодно',
              currentRule == 'yearly',
              () => Navigator.pop(context, const _RepeatChoice('yearly')),
            ),
            option('Конкретные даты…', currentRule == 'dates', () async {
              final dates = await _pickRepeatDates(existing: currentDates);
              if (dates == null || !context.mounted) return;
              Navigator.pop(context, _RepeatChoice('dates', dates));
            }),
          ],
        );
      },
    );
  }

  /// Календарь с множественным выбором дат для серии.
  Future<List<DateTime>?> _pickRepeatDates({List<DateTime>? existing}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = <DateTime>{
      for (final date in existing ?? const <DateTime>[])
        DateTime(date.year, date.month, date.day),
    };

    // Календарь не даёт выбирать прошедшие дни, но у старой серии они могут
    // быть в списке — тогда показываем текущий месяц.
    final initial =
        existing != null &&
            existing.isNotEmpty &&
            !existing.first.isBefore(today)
        ? existing.first
        : today;

    return showDialog<List<DateTime>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final theme = Theme.of(context);
            final sorted = selected.toList()..sort();

            return Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 380,
                  maxHeight: 560,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Конкретные даты',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 300,
                        child: CalendarDatePicker(
                          initialDate: initial,
                          firstDate: today,
                          lastDate: DateTime(2100),
                          onDateChanged: (date) {
                            final day = DateTime(
                              date.year,
                              date.month,
                              date.day,
                            );
                            // Тап только добавляет дату: убрать её можно
                            // чипом ниже.
                            setDialogState(() => selected.add(day));
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (sorted.isEmpty)
                        Text(
                          'Нажмите на дату, чтобы добавить её в серию.',
                          style: theme.textTheme.bodySmall,
                        )
                      else
                        SizedBox(
                          height: 72,
                          child: SingleChildScrollView(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                for (final date in sorted)
                                  InputChip(
                                    label: Text(_formatDay(date)),
                                    onDeleted: () => setDialogState(
                                      () => selected.remove(date),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Отмена'),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: sorted.isEmpty
                                ? null
                                : () => Navigator.pop(context, sorted),
                            child: const Text('Готово'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _editTag(int id, String? current) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Тег'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ''),
            child: _dialogOption(context, 'Без тега', current == null),
          ),
          for (final tag in TaskTags.all)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, tag),
              child: _dialogOption(context, tag, current == tag),
            ),
        ],
      ),
    );

    if (selected == null || !mounted) return;

    await TaskDatabase.instance.setTaskTag(
      id,
      selected.isEmpty ? null : selected,
    );
    if (!mounted) return;
    await _loadEntries();
  }

  Future<void> _editRepeat(int id, Map<String, Object?> entry) async {
    final currentRule = entry['repeat_rule'] as String?;
    final currentDates = _entryRepeatDates(entry['repeat_dates']);
    final due = DateTime.tryParse(entry['due_at'] as String? ?? '');

    final choice = await _askRepeat(
      currentRule: currentRule,
      currentDates: currentDates,
    );
    if (choice == null || !mounted) return;

    final dates = choice.dates ?? const <DateTime>[];
    final dueAt = choice.rule == 'dates' && dates.isNotEmpty
        ? _atTime(dates.first, due)
        : null;

    await TaskDatabase.instance.setTaskRepeat(
      id,
      choice.rule,
      dates: dates,
      dueAt: dueAt,
    );
    if (!mounted) return;
    await _loadEntries();
  }

  List<DateTime> _entryRepeatDates(Object? value) {
    if (value is! String || value.isEmpty) return const [];
    try {
      final data = jsonDecode(value);
      if (data is! List) return const [];

      final dates = <DateTime>[];
      for (final item in data) {
        if (item is! String) continue;
        final date = DateTime.tryParse(item);
        if (date != null) dates.add(date);
      }
      dates.sort();
      return dates;
    } catch (_) {
      return const [];
    }
  }

  Widget _dialogOption(BuildContext context, String label, bool selected) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(
          selected ? Icons.check_circle : Icons.circle_outlined,
          size: 18,
          color: selected ? scheme.primary : Theme.of(context).hintColor,
        ),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }

  /// Время суток из текущего срока (или 9:00 по умолчанию).
  DateTime _atTime(DateTime date, DateTime? source) {
    return DateTime(
      date.year,
      date.month,
      date.day,
      source?.hour ?? 9,
      source?.minute ?? 0,
    );
  }

  String _repeatLabel(String? rule) {
    switch (rule) {
      case 'daily':
        return 'Ежедневно';
      case 'weekly':
        return 'Еженедельно';
      case 'monthly':
        return 'Ежемесячно';
      case 'yearly':
        return 'Ежегодно';
      case 'dates':
        return 'По датам';
    }
    return '';
  }

  String _formatDay(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  Color _priorityColor(BuildContext context, int priority, bool done) {
    if (done) return Colors.grey;
    final scheme = Theme.of(context).colorScheme;
    switch (priority) {
      case 3:
        return scheme.error;
      case 2:
        return Colors.orange.shade700;
      case 0:
        return scheme.outline;
      case 1:
      default:
        return scheme.primary;
    }
  }

  /// Метка в кружке: 1 / 2 / 3 / !.
  String _priorityMark(int priority) {
    switch (priority) {
      case 3:
        return '!';
      case 2:
        return '3';
      case 0:
        return '1';
      case 1:
      default:
        return '2';
    }
  }

  String _priorityLabel(int priority) {
    switch (priority) {
      case 3:
        return 'Срочно!';
      case 2:
        return 'Высокий';
      case 0:
        return 'Низкий';
      case 1:
      default:
        return 'Обычный';
    }
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

  String _formatDate(String? value) {
    if (value == null) return '';
    final date = DateTime.tryParse(value);
    if (date == null) return '';

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$day.$month.${date.year}, $hour:$minute';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final completed = _entries.where((e) => e['is_done'] == 1).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мой ассистент'),
        centerTitle: true,
        actions: [
          if (DesktopLifecycle.instance.isSupported)
            IconButton(
              tooltip: 'Работа в Windows',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const DesktopSettingsDialog(),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'Напоминания',
            icon: const Icon(Icons.notifications_outlined),
            onSelected: (value) {
              if (value == 'check') _checkReminders();
              if (value == 'test') _testNotification();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'check',
                child: Text('Проверить напоминания'),
              ),
              PopupMenuItem(value: 'test', child: Text('Тест уведомления')),
            ],
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 750),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          WeekSelector(
                            weekStart: _weekStart,
                            countOf: _dayCount,
                            onWeekChanged: (week) {
                              setState(() => _weekStart = startOfWeek(week));
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _input,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              hintText:
                                  'Например: Завтра в 18:00 встреча с Ивановым',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.edit_note),
                              suffixIcon: _input.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Очистить',
                                      onPressed: () => setState(() {
                                        _input.clear();
                                        _pickedDueAt = null;
                                        _pickedTag = null;
                                        _pickedRepeatRule = null;
                                        _pickedRepeatDates = const [];
                                      }),
                                      icon: const Icon(Icons.clear),
                                    ),
                            ),
                            onSubmitted: (_) => _create(),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              for (final tag in TaskTags.all)
                                ChoiceChip(
                                  label: Text(tag),
                                  selected: _pickedTag == tag,
                                  visualDensity: VisualDensity.compact,
                                  onSelected: (_) => setState(
                                    () => _pickedTag = _pickedTag == tag
                                        ? null
                                        : tag,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (_pickedDueAt != null)
                                InputChip(
                                  avatar: const Icon(Icons.event, size: 16),
                                  label: Text(
                                    _formatDate(
                                      _pickedDueAt!.toIso8601String(),
                                    ),
                                  ),
                                  onDeleted: () =>
                                      setState(() => _pickedDueAt = null),
                                ),
                              if (_pickedRepeatRule == null)
                                ActionChip(
                                  avatar: const Icon(Icons.repeat, size: 16),
                                  label: const Text('Повтор'),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _chooseRepeat,
                                )
                              else
                                InputChip(
                                  avatar: const Icon(Icons.repeat, size: 16),
                                  label: Text(_repeatLabel(_pickedRepeatRule!)),
                                  onDeleted: () => setState(() {
                                    _pickedRepeatRule = null;
                                    _pickedRepeatDates = const [];
                                  }),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 48,
                            child: Row(
                              children: [
                                IconButton.filledTonal(
                                  tooltip: _pickedDueAt == null
                                      ? 'Дата и время (необязательно)'
                                      : 'Изменить дату и время',
                                  onPressed: _chooseDateTime,
                                  icon: const Icon(Icons.calendar_month),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: _create,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Создать'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filledTonal(
                                  tooltip: _isStarting
                                      ? 'Загружаю микрофон…'
                                      : (_isTranscribing
                                            ? 'Распознаю…'
                                            : (_isListening
                                                  ? 'Стоп и распознать'
                                                  : 'Голосовой ввод')),
                                  onPressed: (_isTranscribing || _isStarting)
                                      ? null
                                      : _toggleListening,
                                  icon: _isStarting
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Icon(
                                          _isListening ? Icons.stop : Icons.mic,
                                        ),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filledTonal(
                                  tooltip: _isSpeaking
                                      ? 'Остановить озвучку'
                                      : 'Прослушать текст',
                                  onPressed: _isSpeaking
                                      ? _stopSpeaking
                                      : _speak,
                                  icon: Icon(
                                    _isSpeaking
                                        ? Icons.stop_circle_outlined
                                        : Icons.volume_up,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              labelText: 'Поиск по задачам и встречам',
                              hintText: 'Например: Что у меня завтра?',
                              prefixIcon: const Icon(Icons.search),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                tooltip: 'Очистить поиск',
                                onPressed: _clearSearch,
                                icon: const Icon(Icons.clear),
                              ),
                            ),
                            onSubmitted: (_) => _runSearch(),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: _runSearch,
                                  icon: const Icon(Icons.search),
                                  label: const Text('Найти'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _clearSearch,
                                  icon: const Icon(Icons.list),
                                  label: const Text('Все записи'),
                                ),
                              ),
                            ],
                          ),
                          if (_searchWasRun)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Результатов: ${_visibleEntries.length}',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _searchWasRun ? 'Результаты поиска' : 'Задачи по дням',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        'Записи: ${_entries.length} · Выполнено: $completed',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SizedBox(height: 440, child: _buildTaskList()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Сколько незакрытых задач на день — для точки в полосе недели.
  int _dayCount(DateTime day) {
    var count = 0;
    for (final entry in _entries) {
      if (entry['is_done'] == 1) continue;
      final due = DateTime.tryParse(entry['due_at'] as String? ?? '');
      if (due != null && isSameDay(due, day)) count++;
    }
    return count;
  }

  /// Список задач, разбитый по дням показываемой недели.
  Widget _buildTaskList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final now = DateTime.now();
    final searching = _searchWasRun;

    // Во время поиска показываем все найденные записи, иначе — только
    // выбранную неделю; записи без срока видны в обоих случаях.
    final groups = <DateTime, List<Map<String, Object?>>>{};
    final undated = <Map<String, Object?>>[];

    for (final entry in _visibleEntries) {
      final due = DateTime.tryParse(entry['due_at'] as String? ?? '');
      if (due == null) {
        undated.add(entry);
        continue;
      }

      final day = dayOnly(due);
      if (!searching && !_inWeek(day)) continue;
      groups.putIfAbsent(day, () => []).add(entry);
    }

    final days = groups.keys.toList()..sort();
    for (final day in days) {
      groups[day]!.sort(_compareEntries);
    }
    undated.sort(_compareEntries);

    final rows = <Widget>[];
    for (final day in days) {
      rows.add(_dayHeaderRow(day, isToday: isSameDay(day, now)));
      for (final entry in groups[day]!) {
        rows.add(_taskTile(entry));
      }
    }

    if (undated.isNotEmpty) {
      rows.add(_dayHeaderRow(null));
      for (final entry in undated) {
        rows.add(_taskTile(entry));
      }
    }

    if (rows.isEmpty) {
      return Center(
        child: Text(
          searching
              ? 'Ничего не найдено. Попробуйте изменить запрос.'
              : 'На этой неделе задач нет.\n'
                    'Полистайте недели или добавьте новую запись.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView(children: rows);
  }

  bool _inWeek(DateTime day) {
    final end = _weekStart.add(const Duration(days: 7));
    return !day.isBefore(_weekStart) && day.isBefore(end);
  }

  /// Активные задачи выше выполненных, дальше — по приоритету и времени.
  int _compareEntries(Map<String, Object?> a, Map<String, Object?> b) {
    final doneA = a['is_done'] == 1;
    final doneB = b['is_done'] == 1;
    if (doneA != doneB) return doneA ? 1 : -1;

    final priorityA = a['priority'] as int? ?? 1;
    final priorityB = b['priority'] as int? ?? 1;
    if (priorityA != priorityB) return priorityB.compareTo(priorityA);

    final dueA = a['due_at'] as String? ?? '';
    final dueB = b['due_at'] as String? ?? '';
    return dueA.compareTo(dueB);
  }

  Widget _dayHeaderRow(DateTime? day, {bool isToday = false}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6, left: 4, right: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: isToday ? scheme.primary : scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            day == null ? 'Без даты' : dayHeader(day),
            style: theme.textTheme.labelLarge?.copyWith(
              color: isToday ? scheme.primary : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskTile(Map<String, Object?> entry) {
    final id = entry['id'] as int;
    final title = entry['title'] as String;
    final done = entry['is_done'] == 1;
    final type = entry['type'] as String? ?? 'task';
    final dueAt = entry['due_at'] as String?;
    final notifiedAt = entry['notified_at'] as String?;
    final priority = entry['priority'] as int? ?? 1;
    final tag = entry['tag'] as String?;
    final repeatRule = entry['repeat_rule'] as String?;
    final due = dueAt == null ? null : DateTime.tryParse(dueAt);
    final overdue =
        due != null && !done && !due.isAfter(DateTime.now());

    final subtitle = StringBuffer();
    if (tag != null) subtitle.write('$tag · ');
    subtitle.write('${_typeLabel(type)} · ${_priorityLabel(priority)}');
    if (dueAt != null) {
      subtitle.write('\n${_formatDate(dueAt)}');
      if (repeatRule != null) {
        subtitle.write(' · ${_repeatLabel(repeatRule)}');
      }
    } else if (repeatRule != null) {
      subtitle.write('\nПовтор: ${_repeatLabel(repeatRule)}');
    }
    if (overdue) {
      subtitle.write(
        notifiedAt == null ? ' · срок наступил' : ' · уведомлено',
      );
    }

    final priorityColor = _priorityColor(context, priority, done);

    return Card(
      child: ListTile(
        minLeadingWidth: 0,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PriorityBadge(
              mark: _priorityMark(priority),
              color: priorityColor,
            ),
            Checkbox(
              value: done,
              onChanged: (value) async {
                final next = await TaskDatabase.instance.setTaskDone(
                  id,
                  value ?? false,
                );
                if (!mounted) return;
                await _loadEntries();
                if (next != null) {
                  _showMessage(
                    'Следующее повторение: ${_formatDate(next.toIso8601String())}',
                  );
                }
              },
            ),
          ],
        ),
        title: Text(
          title,
          style: TextStyle(
            decoration: done ? TextDecoration.lineThrough : null,
            color: done ? Theme.of(context).disabledColor : null,
          ),
        ),
        subtitle: Text(
          subtitle.toString(),
          style: TextStyle(
            color: overdue && !done
                ? Theme.of(context).colorScheme.error
                : done
                ? Theme.of(context).disabledColor
                : null,
          ),
        ),
        isThreeLine: dueAt != null || overdue || repeatRule != null,
        trailing: PopupMenuButton<Object>(
          tooltip: 'Ещё',
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            if (value is int) {
              await TaskDatabase.instance.setTaskPriority(id, value);
              if (!mounted) return;
              await _loadEntries();
              return;
            }

            switch (value) {
              case 'tag':
                await _editTag(id, tag);
              case 'repeat':
                await _editRepeat(id, entry);
              case 'delete':
                await TaskDatabase.instance.deleteTask(id);
                if (!mounted) return;
                await _loadEntries();
            }
          },
          itemBuilder: (context) => [
            for (final level in const [0, 1, 2, 3])
              CheckedPopupMenuItem<int>(
                value: level,
                checked: priority == level,
                child: Text(
                  '${_priorityMark(level)} · ${_priorityLabel(level)}',
                ),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem<Object>(
              value: 'tag',
              child: Text('Тег…'),
            ),
            const PopupMenuItem<Object>(
              value: 'repeat',
              child: Text('Повтор…'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem<Object>(
              value: 'delete',
              child: Text('Удалить'),
            ),
          ],
        ),
      ),
    );
  }
}
/// Кружок с меткой приоритета слева от задачи: 1 / 2 / 3 / !.
class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.mark, required this.color});

  final String mark;
  final Color color;

  static const double _size = 26;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color, width: 1.6),
      ),
      child: Text(
        mark,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: _size * 0.5,
          height: 1,
        ),
      ),
    );
  }
}

/// Выбор повторения в диалоге: правило и, для `dates`, список дат.
class _RepeatChoice {
  const _RepeatChoice(this.rule, [this.dates]);

  final String? rule;
  final List<DateTime>? dates;
}
