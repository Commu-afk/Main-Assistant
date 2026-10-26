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

    final dbPath = p.join(
      await sql.getDatabasesPath(),
      'assistant_tasks.db',
    );

    _database = await sql.openDatabase(
      dbPath,
      version: 3,
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
            notified_at TEXT
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
      },
    );

    return _database!;
  }

  Future<List<Map<String, Object?>>> getTasks() async {
    final db = await database;
    return db.query('tasks', orderBy: 'created_at DESC');
  }

  Future<void> addEntry({
    required String title,
    required String type,
    DateTime? dueAt,
  }) async {
    final db = await database;
    await db.insert('tasks', {
      'title': title,
      'type': type,
      'is_done': 0,
      'created_at': DateTime.now().toIso8601String(),
      'due_at': dueAt?.toIso8601String(),
    });
  }

  Future<void> setTaskDone(int id, bool done) async {
    final db = await database;
    await db.update(
      'tasks',
      {'is_done': done ? 1 : 0},
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
      where: 'is_done = 0 AND due_at IS NOT NULL AND notified_at IS NULL '
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
}
