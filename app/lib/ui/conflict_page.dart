import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/task_store.dart';
import 'format.dart';

/// Shown when the same field of a task was changed on this phone and on
/// another device. The user picks which version to keep.
class ConflictPage extends StatefulWidget {
  const ConflictPage({super.key, required this.store, required this.taskId});

  final TaskStore store;
  final String taskId;

  @override
  State<ConflictPage> createState() => _ConflictPageState();
}

class _ConflictPageState extends State<ConflictPage> {
  Task? _mine;
  Task? _theirs;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mine = await widget.store.localTask(widget.taskId);
    final theirs = await widget.store.conflictRemote(widget.taskId);
    if (!mounted) return;
    setState(() {
      _mine = mine;
      _theirs = theirs;
      _loaded = true;
    });
  }

  Future<void> _choose(String choice) async {
    setState(() => _busy = true);
    try {
      await widget.store.resolveConflict(widget.taskId, choice);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not resolve: $e')));
    }
  }

  static String _show(String field, Task t) => switch (field) {
        'title' => t.title,
        'notes' => t.notes.isEmpty ? '(empty)' : t.notes,
        'completed' => t.completed ? 'Done' : 'Not done',
        'priority' => priorityLabels[t.priority],
        'repeat' => repeatLabels[t.repeat],
        'dueAt' => t.dueAt == null ? 'No deadline' : formatDue(t.dueAt!),
        _ => t.category.isEmpty ? '(none)' : t.category,
      };

  static const _labels = {
    'title': 'Title',
    'notes': 'Notes',
    'completed': 'Status',
    'priority': 'Priority',
    'dueAt': 'Deadline',
    'category': 'Category',
    'repeat': 'Repeat',
  };

  @override
  Widget build(BuildContext context) {
    final mine = _mine, theirs = _theirs;
    final body = !_loaded
        ? const Center(child: CircularProgressIndicator())
        : (mine == null || theirs == null)
            ? const Center(child: Text('This conflict is already resolved.'))
            : _content(mine, theirs);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resolve changes', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: body,
    );
  }

  Widget _content(Task mine, Task theirs) {
    final fields = [
      for (final f in Task.syncedFields)
        if (f != 'deleted' && f != 'position' && _show(f, mine) != _show(f, theirs)) f,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: amber.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: amber.withValues(alpha: 0.3)),
          ),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.sync_problem, color: amber),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'This task was changed on this phone while offline, and also on another '
                'device. Choose which version to keep.',
                style: TextStyle(height: 1.4),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Text(mine.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        for (final f in fields) ...[
          _FieldCompare(label: _labels[f]!, mine: _show(f, mine), theirs: _show(f, theirs)),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        _Option(
          title: 'Keep both',
          badge: 'Recommended',
          text: 'Combines the changes. If the same field differs, the newest edit wins.',
          icon: Icons.auto_awesome,
          primary: true,
          onTap: _busy ? null : () => _choose('both'),
        ),
        _Option(
          title: 'Keep mine',
          text: 'Use the version from this phone.',
          icon: Icons.smartphone,
          onTap: _busy ? null : () => _choose('mine'),
        ),
        _Option(
          title: 'Keep the other device',
          text: 'Use the other version. Your offline changes to these fields are discarded.',
          icon: Icons.cloud,
          onTap: _busy ? null : () => _choose('theirs'),
        ),
      ],
    );
  }
}

class _FieldCompare extends StatelessWidget {
  const _FieldCompare({required this.label, required this.mine, required this.theirs});

  final String label;
  final String mine;
  final String theirs;

  @override
  Widget build(BuildContext context) {
    Widget side(String who, IconData icon, String value, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 4),
                Text(who, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: slate200.withValues(alpha: 0.7)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: slate500, letterSpacing: 0.6)),
        const SizedBox(height: 8),
        Row(children: [
          side('Your phone', Icons.smartphone, mine, indigo),
          const SizedBox(width: 8),
          side('Other device', Icons.cloud, theirs, emerald),
        ]),
      ]),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.title,
    required this.text,
    required this.icon,
    required this.onTap,
    this.badge,
    this.primary = false,
  });

  final String title;
  final String text;
  final IconData icon;
  final String? badge;
  final bool primary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: primary ? indigo.withValues(alpha: 0.08) : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: primary ? indigo : slate200, width: primary ? 2 : 1),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: primary ? indigo : slate100,
                child: Icon(icon, size: 16, color: primary ? Colors.white : slate500),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                        decoration: BoxDecoration(color: indigo, borderRadius: BorderRadius.circular(999)),
                        child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(text, style: const TextStyle(color: slate500, fontSize: 12, height: 1.4)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
