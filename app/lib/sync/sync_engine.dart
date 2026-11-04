import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/local_db.dart';
import 'conflict.dart';
import 'remote_api.dart';

enum LinkState { online, offline, serverUnreachable }

/// Pushes queued local changes to the server, then pulls remote changes.
///
/// Safe by construction:
///  * the queue lives in SQLite and an entry is only removed AFTER the server
///    confirmed it, so a crash mid-sync just means the entry is sent again;
///  * resending is harmless because each change carries an `opId` the server
///    remembers and task ids are generated on the device (no duplicates);
///  * failures are retried with exponential backoff (2s, 4s, 8s ... max 5min);
///  * only one sync runs at a time; requests that arrive meanwhile are merged
///    into one follow-up run.
class SyncEngine extends ChangeNotifier {
  SyncEngine(this._db, this.api);

  final LocalDb _db;
  final RemoteApi api;

  /// Called after sync changed local data, so the UI can reload the list.
  VoidCallback? onDataChanged;

  LinkState link = LinkState.offline;
  bool syncing = false;
  int pending = 0;
  DateTime? lastSyncAt;
  String? lastError;

  bool networkAvailable = true;
  bool simulateOffline = false;

  bool _running = false;
  bool _rerun = false;
  bool _rerunForce = false;
  Timer? _timer;
  Timer? _debounce;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => sync());
  }

  void setNetwork(bool available) {
    networkAvailable = available;
    notifyListeners();
    if (available) sync(force: true);
  }

  void setSimulateOffline(bool value) {
    simulateOffline = value;
    notifyListeners();
    sync(force: true);
  }

  /// Call after every local edit: syncs shortly after, batching rapid edits.
  void scheduleSync() {
    refreshPending();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), sync);
  }

  /// Ids of tasks with changes that have not reached the server yet.
  Set<String> pendingIds = {};

  /// Tasks changed in the same field on two devices; waiting for the user.
  Set<String> conflictIds = {};

  Future<void> refreshPending() async {
    pendingIds = await _db.pendingTaskIds();
    conflictIds = await _db.conflictTaskIds();
    pending = pendingIds.length;
    notifyListeners();
  }

  /// [force] ignores retry backoff (manual "Sync now", connectivity regained).
  Future<void> sync({bool force = false}) async {
    if (_running) {
      _rerun = true;
      _rerunForce = _rerunForce || force;
      return;
    }
    _running = true;
    try {
      do {
        final f = _rerunForce;
        _rerun = false;
        _rerunForce = false;
        await _syncOnce(f);
      } while (_rerun);
    } finally {
      _running = false;
    }
  }

  Future<void> _syncOnce(bool force) async {
    await refreshPending();
    if (simulateOffline || !networkAvailable) {
      link = LinkState.offline;
      notifyListeners();
      return;
    }
    syncing = true;
    notifyListeners();
    var changed = false;
    try {
      changed = await _push(force);
      changed = await _pull() || changed;
      link = LinkState.online;
      lastError = null;
      lastSyncAt = DateTime.now();
    } on RemoteException catch (e) {
      link = LinkState.serverUnreachable;
      lastError = e.message;
    } catch (e) {
      link = LinkState.serverUnreachable;
      lastError = 'Unexpected sync error: $e';
    } finally {
      syncing = false;
      await refreshPending();
      if (changed) onDataChanged?.call();
    }
  }

  Future<bool> _push(bool force) async {
    var changed = false;
    for (final queued in await _db.dueOutbox(force: force)) {
      var conflictRounds = 0;
      while (true) {
        // Re-read: the user may have edited the task since the queue snapshot.
        final entry = await _db.outboxFor(queued.taskId);
        final task = await _db.getTask(queued.taskId);
        if (entry == null) break;
        if (task == null) {
          await _db.dropOutbox(queued.taskId);
          break;
        }
        try {
          final res = await api.push(task, opId: entry.opId);
          if (res.conflict) {
            if (++conflictRounds > 3) {
              throw RemoteException('Could not resolve conflict for "${task.title}"');
            }
            final base = await _db.baseOf(task.id);
            final result = mergeThreeWay(base: base, local: task, remote: res.task);
            if (result.conflicts.isNotEmpty) {
              // Same field edited on both devices: let the user decide.
              await _db.parkConflict(task.id, res.task, result.conflicts);
              await _db.log('conflict',
                  '"${task.title}" needs your review (${result.conflicts.join(', ')})');
              changed = true;
              break;
            }
            await _db.resolveConflict(task.id, result.merged, res.task);
            final fields = result.conflicts.isEmpty
                ? 'changes combined'
                : 'both changed: ${result.conflicts.join(', ')} (newest edit won)';
            await _db.log('conflict', '"${task.title}": $fields');
            if (result.note != null) await _db.log('conflict', result.note!);
            changed = true;
            continue; // push the merged result straight away
          }
          await _db.markSynced(task.id, task.updatedAt, res.task);
          await _db.log('push',
              task.deleted ? 'Deleted "${task.title}"' : 'Synced "${task.title}"');
          changed = true;
        } on RemoteException catch (e) {
          final attempts = entry.attempts + 1;
          final delay = Duration(seconds: min(300, 2 << min(attempts, 8)));
          await _db.recordFailure(
            task.id,
            e.message,
            attempts,
            DateTime.now().add(delay).millisecondsSinceEpoch,
          );
          await _db.log('retry',
              '"${task.title}" failed (${e.message}); retry #$attempts in ${delay.inSeconds}s');
          if (!e.permanent) rethrow; // server down: stop, try again later
        }
        break;
      }
    }
    return changed;
  }

  Future<bool> _pull() async {
    final since = int.tryParse(await _db.getMeta('last_seq') ?? '') ?? 0;
    final res = await api.pull(since);
    var changed = false;
    for (final t in res.tasks) {
      if (await _db.applyRemote(t)) {
        changed = true;
        await _db.log('pull', t.deleted ? 'Removed "${t.title}"' : 'Received "${t.title}"');
      }
    }
    await _db.setMeta('last_seq', '${res.seq}');
    return changed;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
