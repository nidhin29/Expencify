import 'dart:io';
import 'package:workmanager/workmanager.dart';
import 'budget_update_scheduler.dart';

/// Renews the rolling alarm horizon; never acts as the reminder's delivery clock.
class ReminderMaintenance {
  static const task = 'spendy.reminders.refresh';
  static Future<void> configure(bool enabled) async {
    if (!Platform.isAndroid) return;
    final worker = Workmanager();
    if (!enabled) {
      await worker.cancelByUniqueName(task);
      return;
    }
    await worker.initialize(budgetUpdateDispatcher);
    await worker.registerPeriodicTask(
      task,
      task,
      frequency: const Duration(hours: 12),
      initialDelay: const Duration(hours: 12),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }
}
