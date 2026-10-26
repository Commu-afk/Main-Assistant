import 'package:flutter/material.dart';

import '../../core/utils/command_parser.dart';
import '../../data/database/task_database.dart';
import '../reminders/notification_service.dart';
import '../reminders/reminder_scheduler.dart';
import '../stt/sherpa_stt_service.dart';
import '../tts/sherpa_tts_service.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final _sherpa = SherpaSttService.instance;
  final _tts = SherpaTtsService.instance;

  bool _isListening = false;
  bool _isTranscribing = false;
  bool _isSpeaking = false;
  String _voiceStatus = 'Загрузка модели Sherpa-ONNX...';

  String _searchQuery = '';
  bool _searchWasRun = false;
  String _selectedType = 'task';
  DateTime? _dueAt;
  List<Map<String, Object?>> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEntries();
    _initSherpa();
    ReminderScheduler.instance.addListener(_onRemindersChanged);
  }

  @override
  void dispose() {
    ReminderScheduler.instance.removeListener(_onRemindersChanged);
    _titleController.dispose();
    _searchController.dispose();
    _sherpa.cancel();
    super.dispose();
  }

  /// Планировщик показал напоминание — обновляем список, чтобы был виден
  /// статус «уведомлено».
  void _onRemindersChanged() {
    if (mounted) _loadEntries();
  }

  Future<void> _initSherpa() async {
    try {
      setState(() {
        _voiceStatus = 'Загрузка русской модели Sherpa-ONNX...';
      });
      await _sherpa.initialize();
      if (!mounted) return;
      setState(() {
        _voiceStatus = 'Готово. Нажмите «Говорить», скажите фразу и нажмите «Стоп»';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _voiceStatus = 'Модель не загружена: $e';
      });
    }
  }

  Future<void> _toggleListening() async {
    if (_isTranscribing) return;

    // Стоп -> распознаём
    if (_isListening) {
      setState(() {
        _isListening = false;
        _isTranscribing = true;
        _voiceStatus = 'Распознаю...';
      });

      try {
        final text = await _sherpa.stopAndTranscribe();
        if (!mounted) return;

        if (text.isEmpty) {
          setState(() {
            _voiceStatus = 'Ничего не распознано, попробуйте ещё раз';
          });
          return;
        }

        setState(() {
          _titleController.text = text;
          _titleController.selection = TextSelection.collapsed(
            offset: text.length,
          );
          _voiceStatus = 'Распознано: $text';
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _voiceStatus = 'Ошибка распознавания: $e';
        });
      } finally {
        if (mounted) setState(() => _isTranscribing = false);
      }
      return;
    }

    // Старт записи
    try {
      await _sherpa.startRecording();
      if (!mounted) return;
      setState(() {
        _isListening = true;
        _voiceStatus = 'Слушаю... Говорите по-русски';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _voiceStatus = 'Не удалось начать запись: $e';
      });
      _showMessage(_voiceStatus);
    }
  }

  Future<void> _speak() async {
    final text = _titleController.text.trim();
    if (text.isEmpty) {
      _showMessage('Нечего озвучивать: введите текст');
      return;
    }

    setState(() {
      _isSpeaking = true;
      _voiceStatus = 'Синтезирую речь...';
    });

    try {
      await _tts.speak(text);
      if (!mounted) return;
      setState(() => _voiceStatus = 'Озвучено: $text');
    } catch (e) {
      if (!mounted) return;
      setState(() => _voiceStatus = 'Ошибка озвучки: $e');
      _showMessage(_voiceStatus);
    } finally {
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  Future<void> _stopSpeaking() async {
    await _tts.stop();
    if (!mounted) return;
    setState(() {
      _isSpeaking = false;
      _voiceStatus = 'Озвучка остановлена';
    });
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

  Future<void> _addEntry() async {
    final command = _titleController.text.trim();
    if (command.isEmpty) {
      _showMessage('Введите команду или название записи');
      return;
    }

    final parsed = parseCommand(command, _selectedType);
    if (parsed.title.isEmpty) {
      _showMessage(
        'Не удалось определить название. Например: '
        'Напомни завтра в 9:00 купить хлеб',
      );
      return;
    }

    final savedDate = parsed.dueAt ?? _dueAt;

    try {
      await TaskDatabase.instance.addEntry(
        title: parsed.title,
        type: parsed.type,
        dueAt: savedDate,
      );

      _titleController.clear();
      setState(() {
        _dueAt = null;
        _selectedType = 'task';
      });

      await _loadEntries();

      final dateText = savedDate == null
          ? ''
          : ' (${_formatDate(savedDate.toIso8601String())})';

      _showMessage('Сохранено: ${parsed.title}$dateText');
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
    final wantsTomorrow = query.contains('завтра') && !query.contains('послезавтра');
    final wantsDayAfterTomorrow = query.contains('послезавтра');
    final wantsWeek = query.contains('неделе') ||
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
        .map((word) => word.replaceAll(RegExp(r'^[^a-zа-яё0-9]+|[^a-zа-яё0-9]+$', caseSensitive: false), ''))
        .where((word) => word.length >= 2)
        .toList();

    return _entries.where((entry) {
      final type = entry['type'] as String? ?? 'task';
      if (wantedType != null && type != wantedType) return false;

      final dueText = entry['due_at'] as String?;
      final parsedDate = dueText == null ? null : DateTime.tryParse(dueText);

      if (wantsToday || wantsTomorrow || wantsDayAfterTomorrow || wantsWeek) {
        if (parsedDate == null) return false;
        final dueDay = DateTime(parsedDate.year, parsedDate.month, parsedDate.day);

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
        RegExp(r'(ями|ами|ого|ему|ому|ыми|ими|ах|ях|ой|ей|ый|ий|ая|яя|ое|ее|ую|юю|ом|ем|ам|ям|ы|и|а|я|у|ю|е)$'),
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
      initialDate: _dueAt ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueAt ?? now),
    );

    if (time == null || !mounted) return;

    setState(() {
      _dueAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final completed = _entries.where((e) => e['is_done'] == 1).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мой ассистент'),
        centerTitle: true,
        actions: [
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
              PopupMenuItem(
                value: 'test',
                child: Text('Тест уведомления'),
              ),
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
                          Text(
                            'Мои записи: ${_entries.length} · Выполнено: $completed',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _titleController,
                            decoration: const InputDecoration(
                              labelText: 'Введите команду',
                              hintText: 'Напомни через 5 минут позвонить маме',
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _addEntry(),
                          ),
                          Row(
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: _isTranscribing ? null : _toggleListening,
                                icon: Icon(
                                  _isListening ? Icons.stop : Icons.mic,
                                ),
                                label: Text(_isListening ? 'Стоп' : 'Говорить'),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Перезагрузить модель Sherpa',
                                onPressed: _isTranscribing
                                    ? null
                                    : () async {
                                        await _sherpa.cancel();
                                        setState(() {
                                          _isListening = false;
                                          _voiceStatus = 'Перезагрузка...';
                                        });
                                        await _initSherpa();
                                      },
                                icon: const Icon(Icons.refresh),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _voiceStatus,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedType,
                            decoration: const InputDecoration(
                              labelText: 'Тип записи (если он не указан в команде)',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'task',
                                child: Text('Задача'),
                              ),
                              DropdownMenuItem(
                                value: 'reminder',
                                child: Text('Напоминание'),
                              ),
                              DropdownMenuItem(
                                value: 'meeting',
                                child: Text('Встреча'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _selectedType = value);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _chooseDateTime,
                                  icon: const Icon(Icons.calendar_month),
                                  label: Text(
                                    _dueAt == null
                                        ? 'Указать дату и время вручную'
                                        : _formatDate(_dueAt!.toIso8601String()),
                                  ),
                                ),
                              ),
                              if (_dueAt != null)
                                IconButton(
                                  tooltip: 'Убрать дату',
                                  onPressed: () => setState(() => _dueAt = null),
                                  icon: const Icon(Icons.close),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _addEntry,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Сохранить'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                tooltip: _isSpeaking
                                    ? 'Остановить озвучку'
                                    : 'Озвучить текст по-русски',
                                onPressed: _isSpeaking ? _stopSpeaking : _speak,
                                icon: Icon(
                                  _isSpeaking
                                      ? Icons.stop_circle_outlined
                                      : Icons.volume_up,
                                ),
                              ),
                            ],
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
                                child: Text('Результатов: ${_visibleEntries.length}'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 400,
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(),
                          )
                        : _visibleEntries.isEmpty
                            ? Center(
                                child: Text(
                                  _searchWasRun
                                      ? 'Ничего не найдено. Попробуйте изменить запрос.'
                                      : 'Записей пока нет. Добавь первую!',
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : ListView.builder(
                                itemCount: _visibleEntries.length,
                                itemBuilder: (context, index) {
                                  final entry = _visibleEntries[index];
                                  final id = entry['id'] as int;
                                  final title = entry['title'] as String;
                                  final done = entry['is_done'] == 1;
                                  final type = entry['type'] as String? ?? 'task';
                                  final dueAt = entry['due_at'] as String?;
                                  final notifiedAt = entry['notified_at'] as String?;
                                  final due = dueAt == null
                                      ? null
                                      : DateTime.tryParse(dueAt);
                                  final overdue = due != null &&
                                      !done &&
                                      !due.isAfter(DateTime.now());

                                  final subtitle = StringBuffer(_typeLabel(type));
                                  if (dueAt != null) {
                                    subtitle.write('\n${_formatDate(dueAt)}');
                                  }
                                  if (overdue) {
                                    subtitle.write(
                                      notifiedAt == null
                                          ? ' · срок наступил'
                                          : ' · уведомлено',
                                    );
                                  }

                                  return Card(
                                    child: ListTile(
                                      leading: Checkbox(
                                        value: done,
                                        onChanged: (value) async {
                                          await TaskDatabase.instance
                                              .setTaskDone(id, value ?? false);
                                          await _loadEntries();
                                        },
                                      ),
                                      title: Text(
                                        title,
                                        style: TextStyle(
                                          decoration: done
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                      subtitle: Text(
                                        subtitle.toString(),
                                        style: overdue
                                            ? TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error,
                                              )
                                            : null,
                                      ),
                                      isThreeLine: dueAt != null,
                                      trailing: IconButton(
                                        tooltip: 'Удалить',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () async {
                                          await TaskDatabase.instance
                                              .deleteTask(id);
                                          await _loadEntries();
                                        },
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
