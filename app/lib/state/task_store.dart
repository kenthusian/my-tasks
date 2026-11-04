import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/local_db.dart';
import '../models/recurrence.dart';
import '../models/task.dart';
import '../notifications.dart';
import '../sync/conflict.dart';
import '../sync/remote_api.dart';
import '../sync/sync_engine.dart';

enum StatusFilter { all, high, unsynced, done }

/// Single source of truth for the UI. Lives above the navigator, so filters,
/// search text and the task list survive navigation between screens.
///
/// Every edit updates the in-memory list first (instant UI), then writes to
/// SQLite, then asks the sync engine to push in the background.
class TaskStore extends ChangeNotifier {
  TaskStore() {
    db = LocalDb();
    api = RemoteApi(defaultServerUrl);
    engine = SyncEngine(db, api);
    notifications = NotificationService();
  }

  /// 10.0.2.2 is how the Android emulator reaches the host computer.
  static const defaultServerUrl = 'http://10.0.2.2:3000';
  static const _uuid = Uuid();

  late final LocalDb db;
  late final RemoteApi api;
  late final SyncEngine engine;
  late final NotificationService notifications;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  List<Task> _all = [];
  bool loading = true;
  String? loadError;

  String query = '';
  StatusFilter statusFilter = StatusFilter.all;
  String? categoryFilter;

  String get serverUrl => api.baseUrl;

  Future<void> init() async {
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      await db.open();
      await notifications.init();
      api.baseUrl = await db.getMeta('server_url') ?? defaultServerUrl;
      engine.onDataChanged = reload;
      engine.addListener(notifyListeners);
      await reload();
    } catch (e) {
      loadError = 'Could not open local storage: $e';
      loading = false;
      notifyListeners();
      return;
    }
    loading = false;
    notifyListeners();

    final connectivity = Connectivity();
    engine.networkAvailable = _hasNetwork(await connectivity.checkConnectivity());
    _connectivitySub = connectivity.onConnectivityChanged
        .listen((r) => engine.setNetwork(_hasNetwork(r)));
    engine.start();
    await engine.refreshPending();
    engine.sync(force: true); // finishes any sync that was interrupted last run
  }

  bool _hasNetwork(List<ConnectivityResult> r) =>
      r.any((c) => c != ConnectivityResult.none);

  Future<void> reload() async {
    _all = await db.visibleTasks();
    notifyListeners();
    notifications.reschedule(_all);
  }

  // ---- derived views -----------------------------------------------------

  List<String> get categories {
    final set = _all.map((t) => t.category).where((c) => c.isNotEmpty).toSet();
    return set.toList()..sort();
  }

  int get totalCount => _all.length;

  bool _matchesStatus(Task t, StatusFilter f) => switch (f) {
        StatusFilter.all => true,
        StatusFilter.high => t.priority == 2 && !t.completed,
        StatusFilter.unsynced => engine.pendingIds.contains(t.id),
        StatusFilter.done => t.completed,
      };

  int countFor(StatusFilter f) => _all.where((t) => _matchesStatus(t, f)).length;

  List<Task> get visible {
    final q = query.trim().toLowerCase();
    final list = _all.where((t) {
      if (!_matchesStatus(t, statusFilter)) return false;
      if (categoryFilter != null && t.category != categoryFilter) return false;
      if (q.isEmpty) return true;
      return t.title.toLowerCase().contains(q) ||
          t.notes.toLowerCase().contains(q) ||
          t.category.toLowerCase().contains(q);
    }).toList();
    // Unfinished tasks first, then the user's manual order (drag-and-drop).
    list.sort((a, b) {
      if (a.completed != b.completed) return a.completed ? 1 : -1;
      return a.sortKey.compareTo(b.sortKey);
    });
    return list;
  }

  bool get hasActiveFilter =>
      query.trim().isNotEmpty ||
      statusFilter != StatusFilter.all ||
      categoryFilter != null;

  void setQuery(String v) {
    query = v;
    notifyListeners();
  }

  void setStatusFilter(StatusFilter f) {
    statusFilter = f;
    notifyListeners();
  }

  void setCategoryFilter(String? c) {
    categoryFilter = c;
    notifyListeners();
  }

  void clearFilters() {
    query = '';
    statusFilter = StatusFilter.all;
    categoryFilter = null;
    notifyListeners();
  }

  // ---- edits -------------------------------------------------------------

  Future<void> addTask({
    required String title,
    String notes = '',
    int priority = 1,
    int? dueAt,
    String category = '',
    int repeat = 0,
  }) {
    final stamp = _stamp(0);
    return _commit(Task(
      id: _uuid.v4(),
      title: title.trim(),
      notes: notes.trim(),
      priority: priority,
      dueAt: dueAt,
      category: category.trim(),
      repeat: dueAt == null ? 0 : repeat,
      position: -stamp.toDouble(), // new tasks go to the top
      updatedAt: stamp,
    ));
  }

  Future<void> updateTask(Task t) => _commit(t.copyWith(updatedAt: _stamp(t.updatedAt)));

  Future<void> toggleCompleted(Task t) async {
    final completing = !t.completed;
    final repeats = completing && t.repeat != 0 && t.dueAt != null;
    // The finished occurrence stops repeating; the new one carries the rule.
    await _commit(t.copyWith(
      completed: completing,
      repeat: repeats ? 0 : t.repeat,
      updatedAt: _stamp(t.updatedAt),
    ));
    if (repeats) {
      final stamp = _stamp(0);
      await _commit(Task(
        id: _uuid.v4(),
        title: t.title,
        notes: t.notes,
        priority: t.priority,
        category: t.category,
        repeat: t.repeat,
        dueAt: nextDueAt(t.dueAt!, t.repeat),
        position: t.sortKey, // same place in the list
        updatedAt: stamp,
      ));
    }
  }

  /// Moves [t] to [newIndex] within [ordered] (the list as currently shown).
  Future<void> moveTask(Task t, List<Task> ordered, int newIndex) {
    final rest = [...ordered]..removeWhere((x) => x.id == t.id);
    final i = newIndex.clamp(0, rest.length);
    final prev = i > 0 ? rest[i - 1].sortKey : null;
    final next = i < rest.length ? rest[i].sortKey : null;
    final key = prev == null
        ? (next ?? 0) - 1000
        : next == null
            ? prev + 1000
            : (prev + next) / 2;
    return _commit(t.copyWith(position: key, updatedAt: _stamp(t.updatedAt)));
  }

  Future<void> deleteTask(Task t) =>
      _commit(t.copyWith(deleted: true, updatedAt: _stamp(t.updatedAt)));

  Future<void> restoreTask(Task t) =>
      _commit(t.copyWith(deleted: false, updatedAt: _stamp(t.updatedAt)));

  /// Strictly increasing timestamps, so two quick edits never tie.
  int _stamp(int previous) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return now > previous ? now : previous + 1;
  }

  Future<void> _commit(Task t) async {
    final i = _all.indexWhere((x) => x.id == t.id);
    if (t.deleted) {
      if (i >= 0) _all.removeAt(i);
    } else if (i >= 0) {
      _all[i] = t;
    } else {
      _all.add(t);
    }
    notifyListeners(); // UI is already up to date before the disk write
    try {
      await db.saveLocal(t);
    } catch (e) {
      await reload(); // show what is really stored
      rethrow;
    }
    engine.scheduleSync();
  }

  // ---- conflict review ---------------------------------------------------

  Future<Task?> localTask(String id) => db.getTask(id);

  Future<Task?> conflictRemote(String id) => db.conflictRemote(id);

  /// [choice]: 'both' (merge, newest edit wins per field), 'mine' or 'theirs'.
  Future<void> resolveConflict(String id, String choice) async {
    final local = await db.getTask(id);
    final remote = await db.conflictRemote(id);
    if (local == null || remote == null) return;
    final base = await db.baseOf(id);
    final Task merged = switch (choice) {
      'mine' => local.copyWith(version: remote.version, updatedAt: _stamp(remote.updatedAt)),
      'theirs' => remote.copyWith(updatedAt: _stamp(remote.updatedAt)),
      _ => mergeThreeWay(base: base, local: local, remote: remote)
          .merged
          .copyWith(updatedAt: _stamp(remote.updatedAt)),
    };
    await db.resolveConflict(id, merged, remote);
    await db.log('conflict', 'You resolved "${local.title}" (${switch (choice) {
      'mine' => 'kept yours',
      'theirs' => 'kept other device',
      _ => 'kept both',
    }})');
    await reload();
    await engine.refreshPending();
    engine.sync(force: true);
  }

  // ---- settings ----------------------------------------------------------

  Future<void> setServerUrl(String url) async {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.isEmpty) return;
    api.baseUrl = u;
    await db.setMeta('server_url', u);
    notifyListeners();
    engine.sync(force: true);
  }

  Future<List<LogEntry>> activityLog() => db.recentLog();

  @override
  void dispose() {
    _connectivitySub?.cancel();
    engine.dispose();
    super.dispose();
  }
}
