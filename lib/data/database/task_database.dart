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
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            is_done INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            type TEXT NOT NULL DEFAULT 'task',
            due_at TEXT,
            description TEXT
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
}
