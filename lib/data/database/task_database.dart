import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sql;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TaskDatabase {
  TaskDatabase._();

  static final TaskDatabase instance = TaskDatabase._();

  sql.Database? _database;

  Future<sql.Database> get database async {
    if (_database != null) return _database!;

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      sql.databaseFactory = databaseFactoryFfi;
    }

    final dbPath = p.join(await sql.getDatabasesPath(), 'assistant_tasks.db');

    _database = await sql.openDatabase(
      dbPath,
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            is_done INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            type TEXT NOT NULL DEFAULT 'task',
            due_at TEXT,
            description TEXT,
            notified_at TEXT,
            priority INTEGER NOT NULL DEFAULT 1,
            tag TEXT,
            repeat_rule TEXT,
            repeat_dates TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE tasks ADD COLUMN type TEXT NOT NULL DEFAULT 'task'",
          );
          await db.execute('ALTER TABLE tasks ADD COLUMN due_at TEXT');
          await db.execute('ALTER TABLE tasks ADD COLUMN description TEXT');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE tasks ADD COLUMN notified_at TEXT');
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE tasks ADD COLUMN priority INTEGER NOT NULL DEFAULT 1',
          );
        }
        if (oldVersion < 5) {
          await db.execute('ALTER TABLE tasks ADD COLUMN tag TEXT');
          await db.execute('ALTER TABLE tasks ADD COLUMN repeat_rule TEXT');
          await db.execute('ALTER TABLE tasks ADD COLUMN repeat_dates TEXT');
        }
      },
    );

    return _database!;
  }

  Future<List<Map<String, Object?>>> getTasks() async {
    final db = await database;
    return db.query(
      'tasks',
      orderBy:
          'is_done ASC, priority DESC, '
          "CASE WHEN due_at IS NULL THEN 1 ELSE 0 END ASC, "
          'due_at ASC, created_at ASC',
    );
  }

  Future<void> addEntry({
    required String title,
    required String type,
    DateTime? dueAt,
    int priority = 1,
    String? tag,
    String? repeatRule,
    List<DateTime>? repeatDates,
  }) async {
    final db = await database;
    await db.insert('tasks', {
      'title': title,
      'type': type,
      'is_done': 0,
      'created_at': DateTime.now().toIso8601String(),
      'due_at': dueAt?.toIso8601String(),
      'priority': priority,
      'tag': tag,
      'repeat_rule': repeatRule,
      'repeat_dates': _encodeDates(repeatDates),
    });
  }

  /// Отмечает запись выполненной. Для повторяющейся задачи создаёт следующую
  /// (копию с новым сроком) и возвращает её дату.
  Future<DateTime?> setTaskDone(int id, bool done) async {
    final db = await database;
    final rows = await db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    final rule = row['repeat_rule'] as String?;

    await db.update(
      'tasks',
      {'is_done': done ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );

    if (!done || rule == null) return null;

    final due = DateTime.tryParse(row['due_at'] as String? ?? '');
    final next = nextOccurrence(rule, due, row['repeat_dates'] as String?);
    if (next == null) return null;

    await db.insert('tasks', {
      'title': row['title'],
      'type': row['type'],
      'is_done': 0,
      'created_at': DateTime.now().toIso8601String(),
      'due_at': next.toIso8601String(),
      'description': row['description'],
      'priority': row['priority'],
      'tag': row['tag'],
      'repeat_rule': rule,
      'repeat_dates': row['repeat_dates'],
    });

    return next;
  }

  Future<void> setTaskTag(int id, String? tag) async {
    final db = await database;
    await db.update('tasks', {'tag': tag}, where: 'id = ?', whereArgs: [id]);
  }

  /// Задаёт повторение. [dates] используется только для правила `dates`;
  /// [dueAt] переносит срок на первую дату серии.
  Future<void> setTaskRepeat(
    int id,
    String? rule, {
    List<DateTime>? dates,
    DateTime? dueAt,
  }) async {
    final db = await database;
    await db.update(
      'tasks',
      {
        'repeat_rule': rule,
        'repeat_dates': rule == 'dates' ? _encodeDates(dates) : null,
        if (dueAt != null) 'due_at': dueAt.toIso8601String(),
        if (dueAt != null) 'notified_at': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Приоритет: 0 — «1», 1 — «2» (обычный), 2 — «3», 3 — «!» (срочно).
  Future<void> setTaskPriority(int id, int priority) async {
    final db = await database;
    final clamped = priority.clamp(0, 3);
    await db.update(
      'tasks',
      {'priority': clamped},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteTask(int id) async {
    final db = await database;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  /// Записи, у которых срок уже наступил, а уведомления ещё не было.
  Future<List<Map<String, Object?>>> getDueEntries({DateTime? now}) async {
    final db = await database;
    return db.query(
      'tasks',
      where:
          'is_done = 0 AND due_at IS NOT NULL AND notified_at IS NULL '
          'AND due_at <= ?',
      whereArgs: [(now ?? DateTime.now()).toIso8601String()],
      orderBy: 'due_at ASC',
    );
  }

  Future<void> markNotified(int id, {DateTime? at}) async {
    final db = await database;
    await db.update(
      'tasks',
      {'notified_at': (at ?? DateTime.now()).toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Следующий срок для повторяющейся задачи.
  ///
  /// Для `dates` берётся ближайшая дата серии, которая ещё не наступила
  /// и позже текущего срока. Для остальных правил — шаг от текущего срока,
  /// пока дата не окажется в будущем (пропущенные периоды не копятся).
  static DateTime? nextOccurrence(
    String rule,
    DateTime? due,
    String? repeatDates, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();

    if (rule == 'dates') {
      for (final date in _decodeDates(repeatDates)) {
        if (date.isAfter(current) && (due == null || date.isAfter(due))) {
          // Время суток берём у текущего срока: даты серии хранятся без него.
          return due == null
              ? date
              : DateTime(date.year, date.month, date.day, due.hour, due.minute);
        }
      }
      return null;
    }

    if (rule != 'daily' &&
        rule != 'weekly' &&
        rule != 'monthly' &&
        rule != 'yearly') {
      return null;
    }

    DateTime step(DateTime value) {
      switch (rule) {
        case 'daily':
          return value.add(const Duration(days: 1));
        case 'weekly':
          return value.add(const Duration(days: 7));
        case 'monthly':
          return _addMonths(value, 1);
        case 'yearly':
          return _addMonths(value, 12);
      }
      return value;
    }

    var next = step(due ?? current);
    var guard = 0;
    while (!next.isAfter(current) && guard < 1000) {
      next = step(next);
      guard++;
    }
    return next.isAfter(current) ? next : null;
  }

  /// Прибавляет месяцы, не выходя за границу месяца (31 января + 1 мес =
  /// 28/29 февраля).
  static DateTime _addMonths(DateTime from, int months) {
    final total = from.month - 1 + months;
    final year = from.year + total ~/ 12;
    final month = total % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = from.day > lastDay ? lastDay : from.day;

    return DateTime(
      year,
      month,
      day,
      from.hour,
      from.minute,
      from.second,
      from.millisecond,
      from.microsecond,
    );
  }

  static String? _encodeDates(List<DateTime>? dates) {
    if (dates == null || dates.isEmpty) return null;
    final sorted = dates.map((d) => d.toIso8601String()).toList()..sort();
    return jsonEncode(sorted);
  }

  static List<DateTime> _decodeDates(String? value) {
    if (value == null || value.isEmpty) return const [];
    try {
      final data = jsonDecode(value);
      if (data is! List) return const [];

      final dates = <DateTime>[];
      for (final item in data) {
        if (item is! String) continue;
        final parsed = DateTime.tryParse(item);
        if (parsed != null) dates.add(parsed);
      }
      dates.sort();
      return dates;
    } catch (_) {
      return const [];
    }
  }
}
