import 'package:flutter/services.dart';
import 'budget_update_preferences.dart';

/// Native alarms own the clock; WorkManager owns the short-lived computation.
class BudgetAlarmScheduler {
  const BudgetAlarmScheduler();
  static const _channel = MethodChannel('com.nidhi.expencify/budget_alarms');
  Future<void> configure(BudgetUpdatePreferences prefs) =>
      _channel.invokeMethod<void>('configure', {
        'morning': prefs.morning,
        'morningMinute': prefs.morningMinute,
        'evening': prefs.evening,
        'eveningMinute': prefs.eveningMinute,
        'weekly': prefs.weekly,
        'weeklyMinute': prefs.weeklyMinute,
      });
}
