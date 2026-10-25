import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/utils/command_parser.dart';
import '../../data/database/task_database.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechAvailable = false;
  bool _isListening = false;
  String _voiceStatus = 'Микрофон ещё не запущен';
  String? _speechLocaleId;

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
    _initSpeech();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _searchController.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          setState(() {
            _isListening = status == 'listening';
            if (status == 'done' || status == 'notListening') {
              _voiceStatus = 'Распознавание завершено';
            }
          });
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _isListening = false;
            _voiceStatus = 'Ошибка распознавания: ${error.errorMsg}';
          });
        },
      );

      if (!mounted) return;

      String? localeId = _speechLocaleId;
      if (available && localeId == null) {
        try {
          final locales = await _speech.locales();
          for (final locale in locales) {
            final id = locale.localeId.toLowerCase();
            if (id.startsWith('ru')) {
              localeId = locale.localeId;
              break;
            }
          }
          if (localeId == null && locales.isNotEmpty) {
            localeId = locales.first.localeId;
          }
        } catch (_) {}
      }

      setState(() {
        _speechAvailable = available;
        _speechLocaleId = localeId;
        _voiceStatus = available
            ? (localeId == null
                ? 'Микрофон готов'
                : 'Микрофон готов ($localeId)')
            : 'Распознавание речи недоступно';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _speechAvailable = false;
        _voiceStatus = 'Не удалось запустить микрофон: $e';
      });
    }
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) {
      await _initSpeech();
      if (!_speechAvailable) {
        _showMessage(_voiceStatus);
        return;
      }
    }

    if (_isListening) {
      await _speech.stop();
      return;
    }

    try {
      setState(() {
        _voiceStatus = 'Слушаю... Говорите по-русски';
      });

      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          localeId: _speechLocaleId ?? 'ru-RU',
          listenFor: const Duration(seconds: 15),
        ),
        onResult: (result) {
          if (!mounted) return;
          setState(() {
            _titleController.text = result.recognizedWords;
            _titleController.selection = TextSelection.collapsed(
              offset: _titleController.text.length,
            );
            _voiceStatus = result.finalResult
                ? 'Распознано: ${result.recognizedWords}'
                : 'Слушаю: ${result.recognizedWords}';
          });
          if (result.finalResult) {
            _speech.stop();
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _voiceStatus = 'Не удалось начать запись: $e';
      });
      _showMessage(_voiceStatus);
    }
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
        'Добавь задачу купить молоко завтра в 18:00',
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
                              hintText: 'Добавь задачу купить молоко завтра в 18:00',
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _addEntry(),
                          ),
                          Row(
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: _toggleListening,
                                icon: Icon(_isListening ? Icons.stop : Icons.mic),
                                label: Text(_isListening ? 'Остановить' : 'Говорить'),
                              ),
                              const SizedBox(width: 12),
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
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _addEntry,
                              icon: const Icon(Icons.add),
                              label: const Text('Сохранить'),
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
                                        '${_typeLabel(type)}'
                                        '${dueAt == null ? '' : '\n${_formatDate(dueAt)}'}',
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
