import 'package:flutter/material.dart';

import '../state/task_store.dart';
import '../sync/sync_engine.dart';
import 'format.dart';

/// "Sync & Cloud" tab: connection state, queue size, manual sync, offline demo switch.
class SyncPage extends StatelessWidget {
  const SyncPage({super.key, required this.store});

  final TaskStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store.engine,
      builder: (context, _) {
        final e = store.engine;
        final (label, color, icon) = switch (e.link) {
          LinkState.online => ('Online', emerald, Icons.cloud_done),
          LinkState.offline => ('Offline', amber, Icons.cloud_off),
          LinkState.serverUnreachable => ('Server unreachable', rose, Icons.cloud_sync),
        };
        return Scaffold(
          backgroundColor: Theme.of(context).brightness == Brightness.light ? slate50 : null,
          appBar: AppBar(
            title: const Text('Sync & Cloud', style: TextStyle(fontWeight: FontWeight.w700)),
            backgroundColor: Colors.transparent,
            scrolledUnderElevation: 0,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              _Tile(
                child: Row(children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.12),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(
                        e.lastError ??
                            (e.lastSyncAt == null
                                ? 'Not synced yet'
                                : 'Last synced ${formatClock(e.lastSyncAt!)}'),
                        style: const TextStyle(color: slate500, fontSize: 12),
                      ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _Stat(value: '${e.pending}', label: 'Waiting to sync', color: e.pending == 0 ? emerald : amber)),
                const SizedBox(width: 12),
                Expanded(child: _Stat(value: '${store.totalCount}', label: 'Tasks on device', color: indigo)),
              ]),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: indigo,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: e.syncing ? null : () => e.sync(force: true),
                icon: e.syncing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.sync),
                label: Text(e.syncing ? 'Syncing…' : 'Sync now'),
              ),
              const SizedBox(height: 12),
              _Tile(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SwitchListTile(
                  value: e.simulateOffline,
                  onChanged: e.setSimulateOffline,
                  title: const Text('Simulate offline'),
                  subtitle: const Text('Pretend there is no network. Handy for demos.'),
                ),
              ),
              const SizedBox(height: 12),
              const _Tile(
                child: Text(
                  'Every change is saved on this phone first, then queued. The queue is '
                  'stored in the database, so nothing is lost if the app closes mid-sync. '
                  'Failed uploads retry automatically with growing delays.',
                  style: TextStyle(color: slate500, fontSize: 12, height: 1.5),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: slate200.withValues(alpha: 0.7)),
        ),
        child: child,
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => _Tile(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: color)),
          Text(label, style: const TextStyle(color: slate500, fontSize: 12)),
        ]),
      );
}
