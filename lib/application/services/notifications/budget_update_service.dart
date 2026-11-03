import 'package:intl/intl.dart';
import 'budget_notification_log.dart';
import '../../../infrastructure/database/database_helper.dart';
import '../../../infrastructure/repositories/sqlite_budget_repository.dart';
import '../../../infrastructure/repositories/sqlite_transaction_repository.dart';
import 'budget_update_preferences.dart';
import 'budget_period.dart';
import 'notification_service.dart';

class BudgetUpdateService {
  final DatabaseHelper helper;
  final NotificationService notifications;
  BudgetUpdateService({
    DatabaseHelper? helper,
    NotificationService? notifications,
  }) : helper = helper ?? DatabaseHelper(),
       notifications = notifications ?? NotificationService();
  static final money = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );
  static String amount(int cents) => money.format(cents / 100);

  Future<void> run({DateTime? at}) async {
    final now = at ?? DateTime.now();
    final prefs = await BudgetUpdatePreferences.load();
    final morning =
        prefs.morning &&
        budgetUpdateDue(
          now,
          prefs.morningMinute,
          beforeMinute: prefs.eveningMinute,
          maxDelay: const Duration(days: 1),
        );
    final evening =
        prefs.evening &&
        budgetUpdateDue(
          now,
          prefs.eveningMinute,
          beforeMinute: 1440,
          maxDelay: const Duration(days: 1),
        );
    if (!morning && !evening) return;
    if (!await notifications.canShowNotification('budget_updates')) return;
    final db = await helper.database;
    final day = DateTime(now.year, now.month, now.day);
    final kind = morning ? 'morning' : 'evening';
    final minute = morning ? prefs.morningMinute : prefs.eveningMinute;
    final key = '$kind:${day.toIso8601String()}:$minute';
    await db.execute(
      'CREATE TABLE IF NOT EXISTS budget_update_log (delivery_key TEXT PRIMARY KEY, created_at TEXT NOT NULL)',
    );
    if ((await db.query(
      'budget_update_log',
      where: 'delivery_key = ?',
      whereArgs: [key],
    )).isNotEmpty) {
      return;
    }
    // Preserve today's pre-upgrade claim only when it was delivered after
    // this configured time. Moving the time later intentionally permits a new
    // update; repeated runs for the same slot remain deduplicated.
    final legacy = await db.query(
      'budget_update_log',
      where: 'delivery_key = ?',
      whereArgs: ['$kind:${day.toIso8601String()}'],
    );
    final scheduled = DateTime(
      now.year,
      now.month,
      now.day,
      minute ~/ 60,
      minute % 60,
    );
    if (legacy.any(
      (r) =>
          !(DateTime.tryParse('${r['created_at']}') ?? day).isBefore(scheduled),
    )) {
      return;
    }
    final repo = SqliteTransactionRepository(helper);
    final budgets = await SqliteBudgetRepository(helper).getAll();
    final accounts = {
      for (final a in await db.query('accounts')) a['id']: a['name'],
    };
    final lines = <String>[];
    for (final b in budgets) {
      if (!b.amount.isFinite || b.amount <= 0 || b.startDate.isAfter(now)) {
        continue;
      }
      final (periodStart, end) = budgetPeriod(b.period, now);
      final start = b.startDate.isAfter(periodStart)
          ? b.startDate
          : periodStart;
      final todayStart = start.isAfter(day) ? start : day;
      final before = start.isBefore(day)
          ? await repo.getCategoryTotals(
              type: 'expense',
              from: start,
              to: day.subtract(const Duration(microseconds: 1)),
              accountId: b.accountId,
            )
          : <String, double>{};
      final current = await repo.getCategoryTotals(
        type: 'expense',
        from: todayStart,
        to: now,
        accountId: b.accountId,
      );
      int total(Map<String, double> values) => values.entries
          .where((e) => e.key.toLowerCase() == b.category.toLowerCase())
          .fold(0, (sum, e) => sum + (e.value * 100).round());
      final f = DailyBudgetFigures.calculate(
        limit: (b.amount * 100).round(),
        spentBeforeToday: total(before),
        spentToday: total(current),
        today: day,
        end: end,
      );
      final scope = b.accountId == null
          ? 'All accounts'
          : accounts[b.accountId] ?? 'Account';
      final label = '${b.category} · $scope · ${b.period}';
      if (morning) {
        lines.add(
          f.periodOverspend > 0
              ? '$label: ${amount(f.periodOverspend)} over budget.'
              : '$label: ${amount(f.availableToday)} available today.',
        );
      } else {
        final diff = f.dailyDifference;
        lines.add(
          '$label: ${amount(f.today)} recorded today; '
          '${amount(diff.abs())} ${diff >= 0 ? 'under' : 'above'} today’s allowance.'
          '${f.periodOverspend > 0 ? ' ${amount(f.periodOverspend)} over the period budget.' : ''}',
        );
      }
    }
    if (lines.isEmpty) return;
    // Atomic claim across foreground/background isolates. Claims contain no amounts.
    if (!await claimBudgetNotification(db, key, now)) return;
    try {
      await notifications.showNotification(
        id: morning ? 1400000001 : 1400000002,
        channelId: 'budget_updates',
        title: morning
            ? (now.hour < 12
                  ? 'Good morning · Your budget today'
                  : 'Your budget today')
            : 'Your budget today · Evening recap',
        body: lines.join('\n'),
        payload: 'budgets',
      );
    } catch (_) {
      await db.delete(
        'budget_update_log',
        where: 'delivery_key = ?',
        whereArgs: [key],
      );
      rethrow;
    }
    await db.delete(
      'budget_update_log',
      where: "created_at < ? AND delivery_key NOT LIKE 'limit:%'",
      whereArgs: [now.subtract(const Duration(days: 35)).toIso8601String()],
    );
  }
}
