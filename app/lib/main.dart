import 'package:flutter/material.dart';

import 'state/task_store.dart';
import 'ui/app_shell.dart';
import 'ui/format.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OfflineTasksApp());
}

class OfflineTasksApp extends StatefulWidget {
  const OfflineTasksApp({super.key});

  @override
  State<OfflineTasksApp> createState() => _OfflineTasksAppState();
}

class _OfflineTasksAppState extends State<OfflineTasksApp> {
  // Created once, above the Navigator, so state survives screen changes.
  final store = TaskStore();

  @override
  void initState() {
    super.initState();
    store.init();
  }

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness brightness) {
    final light = brightness == Brightness.light;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: indigo, brightness: brightness),
      scaffoldBackgroundColor: light ? slate50 : null,
      cardColor: light ? Colors.white : const Color(0xFF1E1E24),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: light ? Colors.white : null,
        indicatorColor: indigo.withValues(alpha: 0.12),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Tasks',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: AppShell(store: store),
    );
  }
}
