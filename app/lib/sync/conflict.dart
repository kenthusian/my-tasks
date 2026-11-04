import '../models/task.dart';

class MergeResult {
  const MergeResult(this.merged, this.conflicts, this.note);

  /// The task to keep (based on the remote version, so it can be pushed next).
  final Task merged;

  /// Fields that were changed on both sides to different values.
  final List<String> conflicts;

  /// Human-readable remark for the activity log, if anything notable happened.
  final String? note;
}

/// Three-way merge of a task that was edited on this device ([local]) and on
/// the server ([remote]) since the last time they agreed ([base]).
///
/// For each field:
///  * changed only locally  -> keep the local value
///  * changed only remotely -> keep the remote value
///  * changed on both sides to different values -> the newer `updatedAt` wins
///
/// Delete vs. edit: an edit always beats a delete, so nobody loses work.
MergeResult mergeThreeWay({
  Task? base,
  required Task local,
  required Task remote,
}) {
  final b = base?.toJson() ?? <String, Object?>{};
  final l = local.toJson();
  final r = remote.toJson();
  final out = <String, Object?>{...r};
  final conflicts = <String>[];
  var localEdit = false;
  var remoteEdit = false;

  for (final f in Task.syncedFields) {
    if (f == 'deleted') continue;
    final localChanged = l[f] != b[f];
    final remoteChanged = r[f] != b[f];
    // Reordering is not a content edit: it never asks the user anything.
    final silent = f == 'position';
    if (!silent) {
      localEdit |= localChanged;
      remoteEdit |= remoteChanged;
    }
    if (localChanged && remoteChanged && l[f] != r[f]) {
      if (!silent) conflicts.add(f);
      out[f] = local.updatedAt >= remote.updatedAt ? l[f] : r[f];
    } else if (localChanged) {
      out[f] = l[f];
    }
  }

  final wasDeleted = b['deleted'] == true;
  final localDeleted = local.deleted && !wasDeleted;
  final remoteDeleted = remote.deleted && !wasDeleted;
  String? note;
  if (localDeleted && remoteEdit && !remoteDeleted) {
    out['deleted'] = false;
    note = 'Kept "${remote.title}": it was edited elsewhere while deleted here';
  } else if (remoteDeleted && localEdit && !localDeleted) {
    out['deleted'] = false;
    note = 'Restored "${local.title}": it was edited here while deleted elsewhere';
  } else if (localDeleted || remoteDeleted) {
    out['deleted'] = true;
  }

  out['id'] = local.id;
  out['version'] = remote.version;
  out['updatedAt'] =
      local.updatedAt > remote.updatedAt ? local.updatedAt : remote.updatedAt;

  return MergeResult(
    Task.fromJson(Map<String, dynamic>.from(out)),
    conflicts,
    note,
  );
}
