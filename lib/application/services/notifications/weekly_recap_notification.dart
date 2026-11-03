import '../../../infrastructure/database/database_helper.dart';
import '../../../infrastructure/repositories/sqlite_transaction_repository.dart';
import '../reports/weekly_recap.dart';
import '../reports/insight_period.dart';
import 'budget_update_preferences.dart';
import 'budget_update_service.dart';
import 'budget_notification_log.dart';
import 'notification_service.dart';

class WeeklyRecapNotification {
  final DatabaseHelper helper;
  final NotificationService notifications;
  WeeklyRecapNotification({
    DatabaseHelper? helper,
    NotificationService? notifications,
  }) : helper = helper ?? DatabaseHelper(),
       notifications = notifications ?? NotificationService();
  Future<void> run({DateTime? at}) async {
    final now = at ?? DateTime.now();
    final prefs = await BudgetUpdatePreferences.load();
    if (!prefs.weekly ||
        now.weekday != DateTime.monday ||
        !budgetUpdateDue(
          now,
          prefs.weeklyMinute,
          beforeMinute: 1440,
          maxDelay: const Duration(days: 1),
        )) {
      return;
    }
    final recap = await WeeklyRecap.load(
      SqliteTransactionRepository(helper),
      now,
    );
    if (recap.total == 0 && recap.priorTotal == 0) return;
    final key = 'weekly:${recap.from.toIso8601String()}';
    if (!await notifications.canShowNotification('budget_updates')) return;
    final db = await helper.database;
    if (!await claimBudgetNotification(db, key, now)) return;
    try {
      final delta = recap.difference;
      final comparison = recap.priorTotal == 0
          ? 'No recorded spending in the previous week.'
          : delta == 0
          ? 'The same as the previous week.'
          : '${BudgetUpdateService.amount(delta.abs())} ${delta > 0 ? 'more' : 'less'} than the previous week.';
      final changes = recap.changes;
      final biggest = changes.isEmpty || changes.first.value == 0
          ? ''
          : ' Biggest category change: ${changes.first.key}, ${BudgetUpdateService.amount(changes.first.value.abs())} ${changes.first.value > 0 ? 'more' : 'less'}.';
      await notifications.showNotification(
        id: 1400000004,
        channelId: 'budget_updates',
        title: 'Your weekly spending recap',
        body:
            '${insightRangeLabel(recap.from, recap.to)}: ${BudgetUpdateService.amount(recap.total)} recorded across all accounts. $comparison$biggest',
        payload: 'weekly_recap',
      );
    } catch (_) {
      await releaseBudgetNotification(db, key);
      rethrow;
    }
  }
}
