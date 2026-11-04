import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/task_store.dart';
import 'format.dart';

/// Create (task == null) or edit a task.
class TaskFormPage extends StatefulWidget {
  const TaskFormPage({super.key, required this.store, this.task});

  final TaskStore store;
  final Task? task;

  @override
  State<TaskFormPage> createState() => _TaskFormPageState();
}

class _TaskFormPageState extends State<TaskFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late final TextEditingController _category;
  late int _priority;
  late int _repeat;
  int? _dueAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _title = TextEditingController(text: t?.title ?? '');
    _notes = TextEditingController(text: t?.notes ?? '');
    _category = TextEditingController(text: t?.category ?? '');
    _priority = t?.priority ?? 1;
    _repeat = t?.repeat ?? 0;
    _dueAt = t?.dueAt;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final initial =
        _dueAt != null ? DateTime.fromMillisecondsSinceEpoch(_dueAt!) : now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    setState(() {
      _dueAt = DateTime(date.year, date.month, date.day, time.hour, time.minute)
          .millisecondsSinceEpoch;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final t = widget.task;
      if (t == null) {
        await widget.store.addTask(
          title: _title.text,
          notes: _notes.text,
          priority: _priority,
          dueAt: _dueAt,
          category: _category.text,
          repeat: _repeat,
        );
      } else {
        await widget.store.updateTask(t.copyWith(
          title: _title.text.trim(),
          notes: _notes.text.trim(),
          priority: _priority,
          dueAt: _dueAt,
          category: _category.text.trim(),
          repeat: _dueAt == null ? 0 : _repeat,
        ));
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  Future<void> _delete() async {
    final t = widget.task!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this task?'),
        content: Text('"${t.title}" will be removed from all your devices. You can undo right after.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rose),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.store.deleteTask(t);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      return;
    }
    if (mounted) Navigator.of(context).pop();
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('Deleted "${t.title}"'),
        action: SnackBarAction(label: 'UNDO', onPressed: () => widget.store.restoreTask(t)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.task != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit task' : 'New task', style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          if (editing)
            IconButton(
              tooltip: 'Delete task',
              icon: const Icon(Icons.delete_outline, color: rose),
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              autofocus: !editing,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Please enter a title' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notes,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Text('Priority', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [
                for (var i = 0; i < 3; i++)
                  ButtonSegment(value: i, label: Text(priorityLabels[i])),
              ],
              selected: {_priority},
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(_dueAt == null ? 'No deadline' : 'Due ${formatDue(_dueAt!)}'),
              trailing: _dueAt == null
                  ? null
                  : IconButton(
                      tooltip: 'Remove deadline',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() {
                        _dueAt = null;
                        _repeat = 0;
                      }),
                    ),
              onTap: _pickDeadline,
            ),
            if (_dueAt != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.repeat, color: slate500),
                const SizedBox(width: 16),
                const Text('Repeat'),
                const Spacer(),
                DropdownButton<int>(
                  value: _repeat,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (var i = 0; i < repeatLabels.length; i++)
                      DropdownMenuItem(value: i, child: Text(repeatLabels[i])),
                  ],
                  onChanged: (v) => setState(() => _repeat = v ?? 0),
                ),
              ]),
            ],
            const SizedBox(height: 8),
            TextFormField(
              controller: _category,
              decoration: const InputDecoration(
                labelText: 'Category / tag (optional)',
                prefixIcon: Icon(Icons.label_outline),
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.store.categories.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in widget.store.categories)
                    ActionChip(label: Text(c), onPressed: () => setState(() => _category.text = c)),
                ],
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: indigo,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(editing ? 'Save changes' : 'Add task'),
            ),
            if (editing) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: rose,
                  side: const BorderSide(color: rose),
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete task'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
