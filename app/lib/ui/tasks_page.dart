import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/task_store.dart';
import '../sync/sync_engine.dart';
import 'conflict_page.dart';
import 'format.dart';
import 'task_form_page.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key, required this.store});

  final TaskStore store;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  late final TextEditingController _search;

  TaskStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: store.query);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  void _openForm([Task? task]) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TaskFormPage(store: store, task: task),
    ));
  }

  void _delete(Task t) {
    _guard(() => store.deleteTask(t));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('Deleted "${t.title}"'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () => _guard(() => store.restoreTask(t)),
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Theme.of(context).brightness == Brightness.light ? slate50 : null,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                const _Header(),
                Expanded(child: _content()),
              ],
            ),
          ),
          floatingActionButton: store.loading || store.loadError != null
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _openForm(),
                  backgroundColor: indigo,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  icon: const Icon(Icons.add),
                  label: const Text('New Task'),
                ),
        );
      },
    );
  }

  Widget _content() {
    if (store.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (store.loadError != null) {
      return _Message(
        icon: Icons.error_outline,
        title: 'Something went wrong',
        subtitle: store.loadError!,
        actionLabel: 'Try again',
        onAction: store.init,
      );
    }
    final tasks = store.visible;
    // Dragging only makes sense when the full list is shown.
    final canReorder = !store.hasActiveFilter && tasks.length > 1;
    return RefreshIndicator(
      onRefresh: () => store.engine.sync(force: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _SyncBanner(engine: store.engine),
                const SizedBox(height: 12),
                _SearchBar(controller: _search, store: store),
                const SizedBox(height: 12),
                _FilterChips(store: store),
                if (canReorder)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text('Tip: press and hold a task, then drag to reorder.',
                        style: TextStyle(fontSize: 11, color: slate400)),
                  ),
              ]),
            ),
          ),
          if (tasks.isEmpty)
            SliverToBoxAdapter(
              child: store.totalCount == 0
                  ? const _Message(
                      icon: Icons.task_alt,
                      title: 'No tasks yet',
                      subtitle: 'Tap "New Task" to add one. Everything works offline.',
                    )
                  : _Message(
                      icon: Icons.search_off,
                      title: 'No tasks match',
                      subtitle: 'Try a different search or filter.',
                      actionLabel: 'Clear filters',
                      onAction: () {
                        _search.clear();
                        store.clearFilters();
                      },
                    ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              sliver: SliverReorderableList(
                itemCount: tasks.length,
                onReorderItem: (oldIndex, newIndex) {
                  if (!canReorder) return;
                  _guard(() => store.moveTask(tasks[oldIndex], tasks, newIndex));
                },
                proxyDecorator: (child, _, __) =>
                    Material(color: Colors.transparent, elevation: 6, child: child),
                itemBuilder: (context, i) {
                  final t = tasks[i];
                  final card = Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Dismissible(
                      key: ValueKey('d-${t.id}'),
                      background: _swipeBg(Alignment.centerLeft),
                      secondaryBackground: _swipeBg(Alignment.centerRight),
                      onDismissed: (_) => _delete(t),
                      child: _TaskCard(
                        task: t,
                        pending: store.engine.pendingIds.contains(t.id),
                        conflict: store.engine.conflictIds.contains(t.id),
                        onReview: () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => ConflictPage(store: store, taskId: t.id),
                        )),
                        onToggle: () => _guard(() => store.toggleCompleted(t)),
                        onTap: () => _openForm(t),
                      ),
                    ),
                  );
                  return KeyedSubtree(
                    key: ValueKey(t.id),
                    child: canReorder
                        ? ReorderableDelayedDragStartListener(index: i, child: card)
                        : card,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _swipeBg(Alignment a) => Container(
        decoration: BoxDecoration(color: rose, borderRadius: BorderRadius.circular(16)),
        alignment: a,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      );
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: indigo,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: indigo.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('My Tasks', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.1)),
              Text('Personal & Projects', style: TextStyle(fontSize: 12, color: slate500)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.engine});

  final SyncEngine engine;

  @override
  Widget build(BuildContext context) {
    final n = engine.pending;
    final changes = n == 1 ? '1 change' : '$n changes';
    late final IconData icon;
    late final Color color;
    late final String title;
    late final String subtitle;
    switch (engine.link) {
      case LinkState.offline:
        icon = Icons.cloud_off;
        color = amber;
        title = n == 0
            ? 'Offline • everything is saved on this device'
            : 'Offline • $changes saved on this device';
        subtitle = "Your edits are saved safely and will sync automatically when you're back online.";
      case LinkState.serverUnreachable:
        icon = Icons.cloud_sync;
        color = rose;
        title = "Can't reach the server${n == 0 ? '' : ' • $changes waiting'}";
        subtitle = "Don't worry, your tasks are safe on this phone. We'll keep retrying.";
      case LinkState.online:
        icon = n == 0 ? Icons.cloud_done : Icons.cloud_upload;
        color = emerald;
        title = engine.syncing
            ? 'Online • syncing…'
            : n == 0
                ? 'Online • all changes synced'
                : 'Online • $changes to send';
        subtitle = engine.lastSyncAt == null
            ? 'Connected to your sync server.'
            : 'Last synced ${formatClock(engine.lastSyncAt!)}.';
    }
    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: slate500, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.store});

  final TextEditingController controller;
  final TaskStore store;

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TextField(
        controller: controller,
        onChanged: store.setQuery,
        decoration: InputDecoration(
          hintText: 'Search your tasks...',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          icon: const Icon(Icons.search, color: slate400),
          suffixIcon: store.query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    controller.clear();
                    store.setQuery('');
                  },
                ),
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.store});

  final TaskStore store;

  @override
  Widget build(BuildContext context) {
    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
      int? count,
      Widget? leading,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? indigo : Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: selected ? indigo : slate200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[leading, const SizedBox(width: 6)],
                Text(label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: selected ? Colors.white : slate500,
                    )),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Text('$count',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white70 : slate400,
                      )),
                ],
              ],
            ),
          ),
        ),
      );
    }

    bool sel(StatusFilter f) => store.statusFilter == f && store.categoryFilter == null;
    void pick(StatusFilter f) {
      store.setCategoryFilter(null);
      store.setStatusFilter(f);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(label: 'All', selected: sel(StatusFilter.all), count: store.countFor(StatusFilter.all), onTap: () => pick(StatusFilter.all)),
          chip(
            label: 'High Priority',
            selected: sel(StatusFilter.high),
            count: store.countFor(StatusFilter.high),
            leading: const CircleAvatar(radius: 4, backgroundColor: rose),
            onTap: () => pick(StatusFilter.high),
          ),
          chip(
            label: 'Saved on phone',
            selected: sel(StatusFilter.unsynced),
            count: store.countFor(StatusFilter.unsynced),
            leading: Icon(Icons.schedule, size: 15, color: sel(StatusFilter.unsynced) ? Colors.white : amber),
            onTap: () => pick(StatusFilter.unsynced),
          ),
          chip(
            label: 'Done',
            selected: sel(StatusFilter.done),
            leading: Icon(Icons.check_circle, size: 15, color: sel(StatusFilter.done) ? Colors.white : emerald),
            onTap: () => pick(StatusFilter.done),
          ),
          for (final c in store.categories)
            chip(
              label: '#$c',
              selected: store.categoryFilter == c,
              onTap: () {
                store.setStatusFilter(StatusFilter.all);
                store.setCategoryFilter(store.categoryFilter == c ? null : c);
              },
            ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.pending,
    required this.conflict,
    required this.onReview,
    required this.onToggle,
    required this.onTap,
  });

  final Task task;
  final bool pending;
  final bool conflict;
  final VoidCallback onReview;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = task.completed;
    final overdue = !done &&
        task.dueAt != null &&
        task.dueAt! < DateTime.now().millisecondsSinceEpoch;
    final high = task.priority == 2;

    return Opacity(
      opacity: done ? 0.7 : 1,
      child: _Card(
        onTap: onTap,
        child: Column(children: [
          if (conflict)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
              decoration: BoxDecoration(
                color: amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: amber.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.sync_problem, size: 18, color: amber),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Needs your review • edited on another device',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: amber,
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: onReview,
                  child: const Text('Review', style: TextStyle(fontSize: 12)),
                ),
              ]),
            ),
          Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: onToggle,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 2, 12, 8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? indigo : Colors.transparent,
                    border: Border.all(color: done ? indigo : const Color(0xFFCBD5E1), width: 2),
                  ),
                  child: done ? const Icon(Icons.check, size: 15, color: Colors.white) : null,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          task.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: done ? FontWeight.w500 : FontWeight.w600,
                            height: 1.3,
                            decoration: done ? TextDecoration.lineThrough : null,
                            color: done ? slate400 : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _PriorityChip(priority: task.priority, done: done, emphasize: high),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (task.dueAt != null)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.schedule, size: 15, color: overdue ? rose : slate400),
                          const SizedBox(width: 4),
                          Text(formatDue(task.dueAt!),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: overdue ? rose : slate500,
                              )),
                          if (task.repeat != 0) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.repeat, size: 14, color: indigo),
                            const SizedBox(width: 2),
                            Text(repeatLabels[task.repeat],
                                style: const TextStyle(fontSize: 11, color: indigo, fontWeight: FontWeight.w500)),
                          ],
                        ]),
                      if (task.category.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: slate100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(task.category,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: slate500)),
                        ),
                      _SyncChip(pending: pending),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        ]),
      ),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({required this.priority, required this.done, required this.emphasize});

  final int priority;
  final bool done;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    if (done) {
      return const Text('Done', style: TextStyle(fontSize: 11, color: slate400, fontWeight: FontWeight.w500));
    }
    final color = switch (priority) {
      2 => rose,
      1 => slate500,
      _ => emerald,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (emphasize) ...[
          CircleAvatar(radius: 3, backgroundColor: color),
          const SizedBox(width: 5),
        ],
        Text(priorityLabels[priority],
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

class _SyncChip extends StatelessWidget {
  const _SyncChip({required this.pending});

  final bool pending;

  @override
  Widget build(BuildContext context) {
    final color = pending ? amber : emerald;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(pending ? Icons.cloud_queue : Icons.cloud_done, size: 13, color: color),
        const SizedBox(width: 4),
        Text(pending ? 'Saved on phone' : 'Synced',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color)),
      ]),
    );
  }
}

/// White rounded card used throughout, as in the design mockups.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.onTap, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      shadowColor: Colors.black12,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: slate200.withValues(alpha: 0.7)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: slate400),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: slate500)),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
