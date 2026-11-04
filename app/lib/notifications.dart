import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models/task.dart';

/// Deadline reminders. They are scheduled with the phone's alarm system, so
/// they fire at the due time even when the app is closed and the phone offline.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (_) {
      _ready = false; // notifications are a bonus; never break the app
    }
  }

  /// Replaces all reminders with one per unfinished task that has a future deadline.
  Future<void> reschedule(List<Task> tasks) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAllPendingNotifications();
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final t in tasks) {
        final due = t.dueAt;
        if (t.completed || t.deleted || due == null || due <= now) continue;
        await _plugin.zonedSchedule(
          id: t.id.hashCode & 0x7fffffff,
          title: t.title,
          body: 'This task is due now',
          scheduledDate: tz.TZDateTime.fromMillisecondsSinceEpoch(tz.UTC, due),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'deadlines',
              'Deadline reminders',
              channelDescription: 'Reminders when a task is due',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          // Inexact alarms need no special permission; may fire a few minutes late.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (_) {
      // ignore scheduling errors (e.g. permission denied)
    }
  }
}
