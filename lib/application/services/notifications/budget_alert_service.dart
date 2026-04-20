import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../domain/repositories/transaction_repository.dart';
import '../../../domain/repositories/budget_repository.dart';
import 'notification_service.dart';

class BudgetAlertService {
  final TransactionRepository _transactionRepo;
  final BudgetRepository _budgetRepo;
  final NotificationService _notificationService;

  BudgetAlertService(
    this._transactionRepo,
    this._budgetRepo,
    this._notificationService,
  );

  /// Checks spending against budgets and triggers notifications if thresholds are crossed.
  /// Called after every transaction change.
  Future<void> checkBudgets() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    // 1. Get all monthly budgets
    final budgets = await _budgetRepo.getAll(period: 'monthly');
    if (budgets.isEmpty) return;

    // 2. Get spending totals for current month
    final totals = await _transactionRepo.getCategoryTotals(
      type: 'expense',
      from: startOfMonth,
      to: endOfMonth,
    );

    final prefs = await SharedPreferences.getInstance();

    for (final budget in budgets) {
      final category = budget.category;
      final limit = budget.amount;
      final spent = totals[category] ?? 0.0;

      if (limit <= 0) continue;

      final ratio = spent / limit;

      // Thresholds: 1.0 (100%), 0.8 (80%), 0.5 (50%)
      if (ratio >= 1.0) {
        await _notifyIfNew(prefs, category, '100', '🚨 Budget Exhausted: $category', 
            'You have spent ₹${spent.toStringAsFixed(0)} which is 100% of your ₹${limit.toStringAsFixed(0)} budget.');
      } else if (ratio >= 0.8) {
        await _notifyIfNew(prefs, category, '80', '⚠️ Budget Warning: $category', 
            'You have reached 80% of your ₹${limit.toStringAsFixed(0)} budget for $category.');
      } else if (ratio >= 0.5) {
        await _notifyIfNew(prefs, category, '50', 'ℹ️ Budget Notice: $category', 
            'You have used 50% of your monthly ₹${limit.toStringAsFixed(0)} budget.');
      }
    }
  }

  Future<void> _notifyIfNew(
    SharedPreferences prefs,
    String category,
    String threshold,
    String title,
    String body,
  ) async {
    final now = DateTime.now();
    final key = 'budget_alert_${category.replaceAll(' ', '_')}_${now.year}_${now.month}_$threshold';

    // Don't notify twice for the same threshold in the same month
    if (prefs.getBool(key) == true) return;

    // Show notification
    await _showBudgetNotification(title, body);

    // Mark as notified
    await prefs.setBool(key, true);
  }

  Future<void> _showBudgetNotification(String title, String body) async {
    await _notificationService.showNotification(
      id: DateTime.now().millisecond,
      channelId: 'budgets',
      title: title,
      body: body,
      payload: 'budgets',
      color: const Color(0xFFEF4444),
    );
  }
}
