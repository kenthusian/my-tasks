import 'package:flutter_test/flutter_test.dart';
import 'package:offline_tasks/models/recurrence.dart';
import 'package:offline_tasks/models/task.dart';
import 'package:offline_tasks/sync/conflict.dart';

Task t({
  String title = 'Buy milk',
  bool completed = false,
  int priority = 1,
  String category = '',
  int updatedAt = 100,
  int version = 1,
  bool deleted = false,
}) =>
    Task(
      id: 'a',
      title: title,
      completed: completed,
      priority: priority,
      category: category,
      updatedAt: updatedAt,
      version: version,
      deleted: deleted,
    );

void main() {
  final base = t();

  test('edits to different fields are both kept', () {
    final local = t(title: 'Buy oat milk', updatedAt: 200);
    final remote = t(completed: true, updatedAt: 150, version: 2);
    final r = mergeThreeWay(base: base, local: local, remote: remote);
    expect(r.merged.title, 'Buy oat milk');
    expect(r.merged.completed, isTrue);
    expect(r.merged.version, 2);
    expect(r.conflicts, isEmpty);
  });

  test('same field changed on both sides: newer edit wins', () {
    final local = t(title: 'Local', updatedAt: 300);
    final remote = t(title: 'Remote', updatedAt: 200, version: 2);
    final r = mergeThreeWay(base: base, local: local, remote: remote);
    expect(r.merged.title, 'Local');
    expect(r.conflicts, ['title']);

    final older = t(title: 'Local', updatedAt: 100);
    final r2 = mergeThreeWay(base: base, local: older, remote: remote);
    expect(r2.merged.title, 'Remote');
  });

  test('same value on both sides is not a conflict', () {
    final local = t(priority: 2, updatedAt: 200);
    final remote = t(priority: 2, updatedAt: 210, version: 2);
    final r = mergeThreeWay(base: base, local: local, remote: remote);
    expect(r.conflicts, isEmpty);
    expect(r.merged.priority, 2);
  });

  test('local delete loses to a remote edit', () {
    final local = t(deleted: true, updatedAt: 200);
    final remote = t(title: 'Edited elsewhere', updatedAt: 150, version: 2);
    final r = mergeThreeWay(base: base, local: local, remote: remote);
    expect(r.merged.deleted, isFalse);
    expect(r.merged.title, 'Edited elsewhere');
    expect(r.note, isNotNull);
  });

  test('remote delete loses to a local edit', () {
    final local = t(title: 'Still needed', updatedAt: 200);
    final remote = t(deleted: true, updatedAt: 150, version: 2);
    final r = mergeThreeWay(base: base, local: local, remote: remote);
    expect(r.merged.deleted, isFalse);
    expect(r.merged.title, 'Still needed');
  });

  test('delete on both sides stays deleted', () {
    final local = t(deleted: true, updatedAt: 200);
    final remote = t(deleted: true, updatedAt: 150, version: 2);
    final r = mergeThreeWay(base: base, local: local, remote: remote);
    expect(r.merged.deleted, isTrue);
  });

  test('missing base (replayed create) merges without crashing', () {
    final local = t(title: 'Same', updatedAt: 200, version: 0);
    final remote = t(title: 'Same', updatedAt: 200, version: 1);
    final r = mergeThreeWay(base: null, local: local, remote: remote);
    expect(r.merged.title, 'Same');
    expect(r.conflicts, isEmpty);
  });

  test('reordering on both devices never raises a conflict', () {
    final local = t(updatedAt: 200).copyWith(position: 5.0);
    final remote = t(updatedAt: 150, version: 2).copyWith(position: 9.0);
    final base2 = t().copyWith(position: 1.0);
    final r = mergeThreeWay(base: base2, local: local, remote: remote);
    expect(r.conflicts, isEmpty);
    expect(r.merged.position, 5.0); // newest edit wins
  });

  group('recurrence', () {
    final jan30 = DateTime(2030, 1, 30, 9, 0).millisecondsSinceEpoch;
    final before = DateTime(2030, 1, 1).millisecondsSinceEpoch;

    test('daily and weekly move the deadline forward', () {
      expect(DateTime.fromMillisecondsSinceEpoch(nextDueAt(jan30, 1, now: before)),
          DateTime(2030, 1, 31, 9, 0));
      expect(DateTime.fromMillisecondsSinceEpoch(nextDueAt(jan30, 2, now: before)),
          DateTime(2030, 2, 6, 9, 0));
    });

    test('monthly moves to the next month', () {
      final jan15 = DateTime(2030, 1, 15, 9, 0).millisecondsSinceEpoch;
      expect(DateTime.fromMillisecondsSinceEpoch(nextDueAt(jan15, 3, now: before)),
          DateTime(2030, 2, 15, 9, 0));
    });

    test('an overdue task skips to the next future occurrence', () {
      final now = DateTime(2030, 1, 20).millisecondsSinceEpoch;
      final old = DateTime(2030, 1, 10, 9, 0).millisecondsSinceEpoch;
      expect(DateTime.fromMillisecondsSinceEpoch(nextDueAt(old, 2, now: now)),
          DateTime(2030, 1, 24, 9, 0));
    });
  });
}
