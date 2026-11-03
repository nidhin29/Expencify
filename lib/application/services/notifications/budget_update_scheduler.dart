import 'weekly_recap_notification.dart';
import 'budget_alarm_scheduler.dart';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import 'budget_update_preferences.dart';
import 'budget_update_service.dart';
import 'notification_service.dart';
import 'reminder_maintenance.dart';

@pragma('vm:entry-point')
void budgetUpdateDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (task == ReminderMaintenance.task) {
      await NotificationService().rescheduleAll();
      return true;
    }
    const recoveryTask = 'spendy.notifications.recovery';
    if (task != BudgetUpdateScheduler.task && task != recoveryTask) return true;
    return executeBudgetUpdate(
      daily: () => BudgetUpdateService().run(),
      weekly: () => WeeklyRecapNotification().run(),
      // The native receiver rearms before starting this isolate. No Activity-
      // owned method channel is available in a headless worker.
      rearm: () async {
        if (task == recoveryTask) await NotificationService().rescheduleAll();
      },
    );
  });
}

/// Each stage is independent: a delivery failure cannot stop future jobs.
Future<bool> executeBudgetUpdate({
  required Future<void> Function() daily,
  required Future<void> Function() weekly,
  required Future<void> Function() rearm,
}) async {
  var success = true;
  for (final stage in [daily, weekly, rearm]) {
    try {
      await stage();
    } catch (error) {
      debugPrint('Scheduled spending update failed: ${error.runtimeType}');
      success = false;
    }
  }
  return success;
}

class BudgetUpdateScheduler {
  static const task = 'spendy.budget.updates';
  static const scheduledTag = '$task.timed';
  static bool get supported => Platform.isAndroid;
  static Future<void> configure({
    Workmanager? manager,
    bool? platformSupported,
    BudgetAlarmScheduler alarms = const BudgetAlarmScheduler(),
  }) async {
    if (!(platformSupported ?? supported)) return;
    final worker = manager ?? Workmanager();
    final prefs = await BudgetUpdatePreferences.load();
    await worker.initialize(budgetUpdateDispatcher);
    // Preference changes remove jobs for old times or disabled updates.
    await worker.cancelByTag(scheduledTag);
    await alarms.configure(prefs);
    if (!prefs.morning && !prefs.evening && !prefs.weekly) {
      await worker.cancelByUniqueName(task);
      return;
    }
    // Recovery if a timed job is interrupted. Android can batch periodic work;
    // this is a fallback, rather than the clock for morning/evening delivery.
    await worker.registerPeriodicTask(
      task,
      task,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }
}
