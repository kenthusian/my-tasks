import 'package:flutter/material.dart';

import '../data/local_db.dart';
import '../state/task_store.dart';
import 'format.dart';

/// Activity tab: history of pushes, pulls, retries and conflict resolutions.
class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key, required this.store, required this.active});

  final TaskStore store;

  /// True while this tab is visible; the log reloads when it becomes visible.
  final bool active;

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  late Future<List<LogEntry>> _future = widget.store.activityLog();

  static const _icons = {
    'push': (Icons.cloud_upload, emerald),
    'pull': (Icons.cloud_download, indigo),
    'retry': (Icons.replay, amber),
    'conflict': (Icons.call_merge, rose),
  };

  @override
  void didUpdateWidget(ActivityPage old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _refresh();
  }

  void _refresh() => setState(() => _future = widget.store.activityLog());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.light ? slate50 : null,
      appBar: AppBar(
        title: const Text('Activity', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh)],
      ),
      body: FutureBuilder<List<LogEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Could not load activity: ${snap.error}'));
          }
          final entries = snap.data!;
          if (entries.isEmpty) {
            return const Center(
              child: Text('Nothing synced yet.', style: TextStyle(color: slate500)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final e = entries[i];
              final (icon, color) = _icons[e.kind] ?? (Icons.info_outline, slate500);
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: slate200.withValues(alpha: 0.7)),
                ),
                child: Row(children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: color.withValues(alpha: 0.12),
                    child: Icon(icon, size: 16, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(e.message, style: const TextStyle(fontSize: 13))),
                  const SizedBox(width: 8),
                  Text(formatClock(e.at), style: const TextStyle(fontSize: 11, color: slate400)),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
