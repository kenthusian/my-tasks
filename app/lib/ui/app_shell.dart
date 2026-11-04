import 'package:flutter/material.dart';

import '../state/task_store.dart';
import 'activity_page.dart';
import 'settings_page.dart';
import 'sync_page.dart';
import 'tasks_page.dart';

/// Bottom-navigation shell. Tabs stay alive (IndexedStack), so scroll
/// position, search text and filters survive switching tabs.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.store});

  final TaskStore store;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return ListenableBuilder(
      listenable: store.engine,
      builder: (context, _) {
        final pending = store.engine.pending;
        return Scaffold(
          body: IndexedStack(
            index: _index,
            children: [
              TasksPage(store: store),
              SyncPage(store: store),
              ActivityPage(store: store, active: _index == 2),
              SettingsPage(store: store),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.check_circle_outline),
                selectedIcon: Icon(Icons.check_circle),
                label: 'Tasks',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: pending > 0,
                  label: Text('$pending'),
                  backgroundColor: Colors.amber.shade700,
                  child: const Icon(Icons.cloud_sync_outlined),
                ),
                selectedIcon: const Icon(Icons.cloud_sync),
                label: 'Sync & Cloud',
              ),
              const NavigationDestination(
                icon: Icon(Icons.history),
                label: 'Activity',
              ),
              const NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }
}
