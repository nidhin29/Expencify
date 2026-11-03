import 'budget_period.dart';
import 'budget_notification_log.dart';
import 'budget_update_preferences.dart';
import 'budget_update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../infrastructure/database/database_helper.dart';
import '../../../domain/repositories/transaction_repository.dart';
import '../../../domain/repositories/budget_repository.dart';
import 'notification_service.dart';

class BudgetAlertService {
  final TransactionRepository _transactionRepo;
  final BudgetRepository _budgetRepo;
  final NotificationService _notificationService;
  final DatabaseHelper helper;
  BudgetAlertService(
    this._transactionRepo,
    this._budgetRepo,
    this._notificationService, {
    DatabaseHelper? helper,
  }) : helper = helper ?? DatabaseHelper();

  Future<void> checkBudgets({DateTime? at}) async {
    if (!(await BudgetUpdatePreferences.load()).limits) return;
    final now = at ?? DateTime.now();
    final budgets = await _budgetRepo.getAll();
    if (budgets.isEmpty) return;
    final db = await helper.database;
    final prefs = await SharedPreferences.getInstance();
    final accounts = {
      for (final a in await db.query('accounts')) a['id']: a['name'],
    };
    final lines = <String>[];
    final claims = <String>[];
    try {
      for (final b in budgets) {
        if (b.id == null ||
            !b.amount.isFinite ||
            b.amount <= 0 ||
            b.startDate.isAfter(now)) {
          continue;
        }
        final (start, _) = budgetPeriod(b.period, now);
        final totals = await _transactionRepo.getCategoryTotals(
          type: 'expense',
          from: b.startDate.isAfter(start) ? b.startDate : start,
          to: now,
          accountId: b.accountId,
        );
        final spent = totals.entries
            .where((e) => e.key.toLowerCase() == b.category.toLowerCase())
            .fold<int>(0, (sum, e) => sum + (e.value * 100).round());
        final limit = (b.amount * 100).round();
        final threshold = spent >= limit
            ? '100'
            : spent * 100 >= limit * 80
            ? '80'
            : null;
        if (threshold == null) continue;
        final period = '${b.id}_${start.toIso8601String()}';
        final key = 'limit:${period}_$threshold';
        if (prefs.getBool('budget_alert_${period}_$threshold') == true) {
          continue;
        }
        if (!await claimBudgetNotification(db, key, now)) continue;
        claims.add(key);
        final scope = b.accountId == null
            ? 'All accounts'
            : accounts[b.accountId] ?? 'Account';
        final status = spent > limit
            ? '${BudgetUpdateService.amount(spent - limit)} over budget'
            : spent == limit
            ? 'Budget reached (100%)'
            : '80% reached';
        lines.add(
          '${b.category} · $scope · ${b.period}: $status. '
          '${BudgetUpdateService.amount(spent)} recorded of ${BudgetUpdateService.amount(limit)}.',
        );
        // Crossing 100% consumes the earlier warning too, even after refunds.
        if (threshold == '100') {
          final earlier = 'limit:${period}_80';
          if (await claimBudgetNotification(db, earlier, now)) {
            claims.add(earlier);
          }
        }
      }
      if (lines.isEmpty) return;
      await _notificationService.showNotification(
        id: 1400000003,
        channelId: 'budgets',
        title: lines.length == 1
            ? 'Budget update'
            : '${lines.length} budget updates',
        body: lines.join('\n'),
        payload: 'budgets',
      );
    } catch (_) {
      for (final key in claims) {
        await releaseBudgetNotification(db, key);
      }
      rethrow;
    }
  }
}
