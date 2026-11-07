import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'models/task_model.dart';

/// DatabaseHelper manages local SQLite database connections and operations.
/// Follows the Singleton pattern to guarantee a single database connection.
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  /// Gets the existing database instance or initializes it if null.
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('smart_task.db');
    return _database!;
  }

  /// Initializes the SQLite database file and manages schema creation/upgrades safely.
  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);
    debugPrint('SQLite Database Path: $path');

    try {
      return await openDatabase(
        path,
        version: 3, // Incremented to version 3 for fail-safe schema migration
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE tasks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              description TEXT NOT NULL DEFAULT '',
              isCompleted INTEGER NOT NULL DEFAULT 0,
              reminderDateTime TEXT,
              isSynced INTEGER NOT NULL DEFAULT 0
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 3) {
            try {
              final pragmaResult = await db.rawQuery("PRAGMA table_info(tasks)");
              final columns =
                  pragmaResult.map((c) => (c['name'] ?? '').toString()).toList();

              if (!columns.contains('reminderDateTime')) {
                try {
                  await db.execute(
                      'ALTER TABLE tasks ADD COLUMN reminderDateTime TEXT');
                } catch (e) {
                  debugPrint('reminderDateTime column already exists: $e');
                }
              }
              if (!columns.contains('isSynced')) {
                try {
                  await db.execute(
                      'ALTER TABLE tasks ADD COLUMN isSynced INTEGER NOT NULL DEFAULT 0');
                } catch (e) {
                  debugPrint('isSynced column already exists: $e');
                }
              }
            } catch (e) {
              debugPrint('SQLite migration notice: $e');
            }
          }
        },
      );
    } catch (e) {
      debugPrint('Error opening database, resetting stale database file: $e');
      // If opening database fails due to a corrupt legacy migration lock, recreate file cleanly
      await deleteDatabase(path);
      return await openDatabase(
        path,
        version: 3,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE tasks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              description TEXT NOT NULL DEFAULT '',
              isCompleted INTEGER NOT NULL DEFAULT 0,
              reminderDateTime TEXT,
              isSynced INTEGER NOT NULL DEFAULT 0
            )
          ''');
        },
      );
    }
  }

  /// Inserts a new task into the SQLite database.
  /// Returns the auto-generated primary key ID.
  Future<int> insertTask(Task task) async {
    final db = await database;
    final id = await db.insert(
      'tasks',
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return id;
  }

  /// Fetches all tasks from SQLite, sorted by newest first (highest ID first).
  Future<List<Task>> getTasks() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'tasks',
      orderBy: 'id DESC',
    );
    return maps.map((map) => Task.fromMap(map)).toList();
  }

  /// Fetches a single task by its primary key ID.
  Future<Task?> getTaskById(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return Task.fromMap(maps.first);
    }
    return null;
  }

  /// Fetches all unsynced tasks (isSynced = 0) to sync with Firebase when online.
  Future<List<Task>> getUnsyncedTasks() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'tasks',
      where: 'isSynced = ?',
      whereArgs: [0],
    );
    return maps.map((map) => Task.fromMap(map)).toList();
  }

  /// Updates an existing task record in SQLite.
  Future<int> updateTask(Task task) async {
    if (task.id == null) return 0;
    final db = await database;
    return await db.update(
      'tasks',
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  /// Marks a specific task record as synced (isSynced = 1).
  Future<int> markAsSynced(int id) async {
    final db = await database;
    return await db.update(
      'tasks',
      {'isSynced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Deletes a task from SQLite by its primary key ID.
  Future<int> deleteTask(int id) async {
    final db = await database;
    return await db.delete(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Restores a previously deleted task (used for SnackBar UNDO functionality).
  Future<int> restoreTask(Task task) async {
    final db = await database;
    return await db.insert(
      'tasks',
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Closes the database connection.
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
