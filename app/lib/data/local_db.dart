import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/task.dart';

/// A queued change that still has to reach the server.
class OutboxEntry {
  const OutboxEntry({
    required this.taskId,
    required this.opId,
    required this.attempts,
    required this.nextAttemptAt,
    this.lastError,
  });

  final String taskId;

  /// Identifies this exact change so a retry after a lost reply is a no-op.
  final String opId;
  final int attempts;
  final int nextAttemptAt;
  final String? lastError;

  factory OutboxEntry.fromRow(Map<String, Object?> r) => OutboxEntry(
        taskId: r['task_id'] as String,
        opId: r['op_id'] as String,
        attempts: r['attempts'] as int,
        nextAttemptAt: r['next_attempt_at'] as int,
        lastError: r['last_error'] as String?,
      );
}

class LogEntry {
  const LogEntry(this.kind, this.message, this.at);
  final String kind;
  final String message;
  final DateTime at;
}

/// All persistent state lives here (SQLite), so nothing is lost when the app
/// is closed, killed, or restarted in the middle of a sync.
///
/// Tables:
///  * tasks    – every task, with `dirty` (unsynced edits) and `base` (JSON of
///               the last version the server confirmed, used for merging)
///  * outbox   – at most one pending change per task
///  * sync_log – activity history shown in the app
///  * meta     – small key/value settings (server url, last pulled seq)
class LocalDb {
  static const _uuid = Uuid();
  late final Database _db;

  Future<void> open() async {
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'tasks.db'),
      version: 2,
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) {
          // Added repeating tasks and manual ordering; keep the existing order.
          await db.execute('ALTER TABLE tasks ADD COLUMN repeat INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE tasks ADD COLUMN position REAL');
          await db.execute('UPDATE tasks SET position = -updated_at');
        }
      },
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE tasks (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            notes TEXT NOT NULL,
            completed INTEGER NOT NULL,
            priority INTEGER NOT NULL,
            due_at INTEGER,
            category TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            version INTEGER NOT NULL,
            deleted INTEGER NOT NULL,
            repeat INTEGER NOT NULL DEFAULT 0,
            position REAL,
            dirty INTEGER NOT NULL DEFAULT 0,
            base TEXT
          )''');
        await db.execute('''
          CREATE TABLE outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id TEXT NOT NULL UNIQUE,
            op_id TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            next_attempt_at INTEGER NOT NULL DEFAULT 0,
            last_error TEXT
          )''');
        await db.execute('''
          CREATE TABLE conflicts (
            task_id TEXT PRIMARY KEY,
            remote TEXT NOT NULL,
            fields TEXT NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE sync_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            message TEXT NOT NULL,
            at INTEGER NOT NULL
          )''');
        await db.execute(
            'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      },
    );
  }

  // ---- tasks -------------------------------------------------------------

  Future<List<Task>> visibleTasks() async {
    final rows = await _db.query('tasks', where: 'deleted = 0');
    return rows.map(Task.fromRow).toList();
  }

  Future<Task?> getTask(String id) async {
    final rows = await _db.query('tasks', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Task.fromRow(rows.first);
  }

  Future<Task?> baseOf(String id) async {
    final rows = await _db
        .query('tasks', columns: ['base'], where: 'id = ?', whereArgs: [id]);
    final base = rows.isEmpty ? null : rows.first['base'] as String?;
    return base == null
        ? null
        : Task.fromJson(jsonDecode(base) as Map<String, dynamic>);
  }

  /// Saves a user edit and queues it for sync in ONE transaction, so a task
  /// can never be changed without the change also being queued.
  Future<void> saveLocal(Task t) async {
    await _db.transaction((txn) async {
      final existing = await txn
          .query('tasks', columns: ['base'], where: 'id = ?', whereArgs: [t.id]);
      await txn.insert(
        'tasks',
        {
          ...t.toRow(),
          'dirty': 1,
          'base': existing.isEmpty ? null : existing.first['base'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'outbox',
        {'task_id': t.id, 'op_id': _uuid.v4(), 'attempts': 0, 'next_attempt_at': 0},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  // ---- outbox ------------------------------------------------------------

  Future<List<OutboxEntry>> dueOutbox({required bool force}) async {
    final rows = await _db.query(
      'outbox',
      where: 'task_id NOT IN (SELECT task_id FROM conflicts)'
          '${force ? '' : ' AND next_attempt_at <= ?'}',
      whereArgs: force ? null : [DateTime.now().millisecondsSinceEpoch],
      orderBy: 'id',
    );
    return rows.map(OutboxEntry.fromRow).toList();
  }

  Future<OutboxEntry?> outboxFor(String taskId) async {
    final rows =
        await _db.query('outbox', where: 'task_id = ?', whereArgs: [taskId]);
    return rows.isEmpty ? null : OutboxEntry.fromRow(rows.first);
  }

  Future<Set<String>> pendingTaskIds() async {
    final rows = await _db.query('outbox', columns: ['task_id']);
    return rows.map((r) => r['task_id'] as String).toSet();
  }

  Future<void> dropOutbox(String taskId) =>
      _db.delete('outbox', where: 'task_id = ?', whereArgs: [taskId]);

  Future<void> recordFailure(
      String taskId, String error, int attempts, int nextAttemptAt) {
    return _db.update(
      'outbox',
      {'attempts': attempts, 'next_attempt_at': nextAttemptAt, 'last_error': error},
      where: 'task_id = ?',
      whereArgs: [taskId],
    );
  }

  // ---- sync results ------------------------------------------------------

  /// The server accepted our change. Remove it from the outbox, unless the
  /// user edited the task again while the request was in flight.
  Future<void> markSynced(String taskId, int pushedUpdatedAt, Task server) async {
    await _db.transaction((txn) async {
      final rows = await txn.query('tasks', where: 'id = ?', whereArgs: [taskId]);
      if (rows.isEmpty) return;
      final local = Task.fromRow(rows.first);
      final baseJson = jsonEncode(server.toJson());
      if (local.updatedAt == pushedUpdatedAt) {
        await txn.update(
          'tasks',
          {'version': server.version, 'base': baseJson, 'dirty': 0},
          where: 'id = ?',
          whereArgs: [taskId],
        );
        await txn.delete('outbox', where: 'task_id = ?', whereArgs: [taskId]);
      } else {
        // Newer local edit exists: keep it queued, but on top of the new version.
        await txn.update(
          'tasks',
          {'version': server.version, 'base': baseJson},
          where: 'id = ?',
          whereArgs: [taskId],
        );
      }
    });
  }

  /// The server said 409. Store the merged task (based on the remote version)
  /// and keep it queued so it is pushed again.
  Future<void> resolveConflict(String taskId, Task merged, Task remote) async {
    await _db.transaction((txn) async {
      await txn.update(
        'tasks',
        {
          ...merged.toRow(),
          'dirty': 1,
          'base': jsonEncode(remote.toJson()),
        },
        where: 'id = ?',
        whereArgs: [taskId],
      );
      await txn.update(
        'outbox',
        {
          'op_id': _uuid.v4(),
          'attempts': 0,
          'next_attempt_at': 0,
          'last_error': null,
        },
        where: 'task_id = ?',
        whereArgs: [taskId],
      );
      await txn.delete('conflicts', where: 'task_id = ?', whereArgs: [taskId]);
    });
  }

  // ---- conflicts waiting for the user -------------------------------------

  /// Parks a same-field conflict: the task stays as the user left it and is
  /// not uploaded until they choose (see ConflictPage).
  Future<void> parkConflict(String taskId, Task remote, List<String> fields) =>
      _db.insert(
        'conflicts',
        {'task_id': taskId, 'remote': jsonEncode(remote.toJson()), 'fields': fields.join(',')},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<Set<String>> conflictTaskIds() async {
    final rows = await _db.query('conflicts', columns: ['task_id']);
    return rows.map((r) => r['task_id'] as String).toSet();
  }

  Future<Task?> conflictRemote(String taskId) async {
    final rows = await _db.query('conflicts', where: 'task_id = ?', whereArgs: [taskId]);
    return rows.isEmpty
        ? null
        : Task.fromJson(jsonDecode(rows.first['remote'] as String) as Map<String, dynamic>);
  }

  /// Applies a task pulled from the server. Skipped (returns false) while this
  /// device has unsynced changes for it; those are reconciled on push.
  Future<bool> applyRemote(Task remote) async {
    return _db.transaction((txn) async {
      final pending = await txn
          .query('outbox', where: 'task_id = ?', whereArgs: [remote.id]);
      if (pending.isNotEmpty) return false;
      final existing =
          await txn.query('tasks', columns: ['version'], where: 'id = ?', whereArgs: [remote.id]);
      if (existing.isNotEmpty && (existing.first['version'] as int) >= remote.version) {
        return false; // already up to date (e.g. our own push echoed back)
      }
      await txn.insert(
        'tasks',
        {
          ...remote.toRow(),
          'dirty': 0,
          'base': jsonEncode(remote.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    });
  }

  // ---- meta + log --------------------------------------------------------

  Future<String?> getMeta(String key) async {
    final rows = await _db.query('meta', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setMeta(String key, String value) => _db.insert(
        'meta',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> log(String kind, String message) async {
    await _db.insert('sync_log', {
      'kind': kind,
      'message': message,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
    await _db.rawDelete(
        'DELETE FROM sync_log WHERE id <= (SELECT MAX(id) FROM sync_log) - 200');
  }

  Future<List<LogEntry>> recentLog() async {
    final rows = await _db.query('sync_log', orderBy: 'id DESC', limit: 200);
    return rows
        .map((r) => LogEntry(
              r['kind'] as String,
              r['message'] as String,
              DateTime.fromMillisecondsSinceEpoch(r['at'] as int),
            ))
        .toList();
  }
}
