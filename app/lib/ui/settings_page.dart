import 'package:flutter/material.dart';

import '../state/task_store.dart';
import 'format.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.store});

  final TaskStore store;

  Future<void> _editServerUrl(BuildContext context) async {
    final controller = TextEditingController(text: store.serverUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: 'http://10.0.2.2:3000'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Android emulator: http://10.0.2.2:3000\n'
              "Real phone: http://<your computer's Wi-Fi IP>:3000",
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (url != null) await store.setServerUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.light ? slate50 : null,
        appBar: AppBar(
          title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w700)),
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: slate200.withValues(alpha: 0.7)),
              ),
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.dns_outlined, color: indigo),
                  title: const Text('Server address'),
                  subtitle: Text(store.serverUrl),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editServerUrl(context),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.storage_outlined, color: indigo),
                  title: Text('Local storage'),
                  subtitle: Text('SQLite database on this device'),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.call_merge, color: indigo),
                  title: Text('Conflict handling'),
                  subtitle: Text(
                    'Edits to different fields are combined; if the same field '
                    'changed in both places, the newest edit wins. An edit beats a delete.',
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
