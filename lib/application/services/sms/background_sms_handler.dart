import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';
import '../sms/sms_parser_service.dart';
import 'package:expencify/infrastructure/database/database_helper.dart';
import 'package:expencify/infrastructure/repositories/sqlite_account_repository.dart';
import 'package:expencify/infrastructure/repositories/sqlite_transaction_repository.dart';
import 'package:expencify/infrastructure/repositories/sqlite_budget_repository.dart';
import 'package:expencify/application/services/notifications/notification_service.dart';
import 'package:expencify/domain/entities/transaction.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pending SMS Queue — drains any SMS saved by SmsReceiver while app was closed.
// Call this at app startup to catch SMS received when no Flutter engine was up.
// ─────────────────────────────────────────────────────────────────────────────
Future<void> processPendingSms() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString('pending_sms_list');
    if (raw == null || raw == '[]') return;

    final List<dynamic> list = jsonDecode(raw);
    if (list.isEmpty) return;

    // Clear immediately to avoid double-processing on concurrent starts
    await prefs.remove('pending_sms_list');

    debugPrint(
      '>>> [EXPENCIFY] Draining ${list.length} pending SMS(es) from queue...',
    );

    for (final item in list) {
      final body = item['body'] as String? ?? '';
      final ts =
          item['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
      final date = DateTime.fromMillisecondsSinceEpoch(ts);
      if (body.isNotEmpty) {
        await processSms(body, date: date);
      }
    }

    debugPrint('>>> [EXPENCIFY] Pending SMS queue drained.');
  } catch (e) {
    debugPrint('>>> [EXPENCIFY] processPendingSms error: $e');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Persistent Background Isolate for Native SMS.
// This isolate stays alive to handle instant capture without engine restarts.
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
void onNativeSmsReceived(List<String> args) async {
  // Necessary for background isolate initialization
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('>>> [EXPENCIFY_BG] Persistent Background Isolate started.');

  const channel = MethodChannel('com.example.expencify/native_sms');

  // Register handler for incoming SMS data from Kotlin
  channel.setMethodCallHandler((call) async {
    if (call.method == 'onSmsReceived') {
      try {
        final data = call.arguments as Map;
        final body = data['body'] as String;
        final ts = data['timestamp'] as int;
        final sender = data['sender'] as String;

        final date = DateTime.fromMillisecondsSinceEpoch(ts);
        debugPrint('>>> [EXPENCIFY_BG] SMS Captured via Channel: $sender');
        await processSms(body, date: date);
      } catch (e) {
        debugPrint('>>> [EXPENCIFY_BG] Channel Error: $e');
      }
    }
    return null;
  });

  // Handle any initial SMS arguments passed at startup
  if (args.length >= 2) {
    debugPrint('>>> [EXPENCIFY_BG] Processing initial SMS from startup args');
    final body = args[1];
    DateTime? smsDate;
    if (args.length >= 3) {
      final ts = int.tryParse(args[2]);
      if (ts != null) smsDate = DateTime.fromMillisecondsSinceEpoch(ts);
    }
    await processSms(body, date: smsDate ?? DateTime.now());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Entry point for the flutter_foreground_task persistent service isolate.
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
void startForegroundSmsService() {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(SmsTaskHandler());
}

// ─────────────────────────────────────────────────────────────────────────────
// Task handler — anchoring service isolate.
// ─────────────────────────────────────────────────────────────────────────────
class SmsTaskHandler extends TaskHandler {
  final _telephony = Telephony.instance;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('>>> [EXPENCIFY_SVC] Service isolate active');

    // Safety net listener
    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) async {
        debugPrint(
          '>>> [EXPENCIFY_SVC] SMS received in service: ${message.body}',
        );
        final msgDate = message.date != null
            ? DateTime.fromMillisecondsSinceEpoch(message.date!)
            : DateTime.now();
        await processSms(message.body ?? '', date: msgDate);

        // Notify Main isolate via Port for foreground instant renders
        FlutterForegroundTask.sendDataToMain({'type': 'sms_parsed'});
      },
      listenInBackground: false,
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    processPendingSms().catchError((e) {
      debugPrint('>>> [EXPENCIFY_SVC] onRepeatEvent error: $e');
    });
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('>>> [EXPENCIFY_SVC] Service isolate stopped');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Core SMS processing logic with robust duplicate prevention.
// ─────────────────────────────────────────────────────────────────────────────
Future<void> processSms(String body, {DateTime? date}) async {
  if (body.isEmpty) return;
  final effectiveDate = date ?? DateTime.now();

  try {
    final Map<String, dynamic>? data = await SmsParserService.parseSms(body);
    if (data == null) {
      debugPrint('Background SMS Handler: Not a valid bank SMS.');
      return;
    }

    final type = data['type'] as String;
    final merchant = (data['merchant'] as String?) ?? '';
    final lastFour = (data['lastFour'] as String?) ?? '';
    final amount = data['amount'] as double;

    final dbHelper = DatabaseHelper();
    final accRepo = SqliteAccountRepository(dbHelper);
    final txnRepo = SqliteTransactionRepository(dbHelper);
    final rulesResult = await SmsParserService.applySmartRules(
      merchant,
      body,
      type,
    );
    final category = rulesResult['category']!;
    final updatedMerchant = rulesResult['merchant']!;

    final accountsList = await accRepo.getAll();
    if (accountsList.isEmpty) return;

    int accountId;
    if (lastFour.isNotEmpty) {
      // Strict match: only save if SMS account matches a registered account
      final matched = accountsList
          .where((a) => a.accountNumber.endsWith(lastFour))
          .toList();
      if (matched.isEmpty) {
        debugPrint(
          '>>> [EXPENCIFY] SMS from unregistered account (****$lastFour) — ignored.',
        );
        return; // ← Drop silently; account not added in app
      }
      accountId = matched.first.id!;
    } else {
      if (accountsList.length > 1) {
        debugPrint(
          '>>> [EXPENCIFY] SMS has no account digits and multiple accounts exist — ignored.',
        );
        return;
      }

      final onlyAccount = accountsList.first;

      // 1. Safety Rule: Discard bound to default Cash account
      if (onlyAccount.bankName.toLowerCase() == 'cash' ||
          onlyAccount.accountNumber.toUpperCase() == 'CASH') {
        debugPrint(
          '>>> [EXPENCIFY] SMS has no account digits and the only account is Cash — ignored.',
        );
        return;
      }

      // 2. Safety Rule: Strict Name Containment Check
      bool matchesBankName =
          body.toLowerCase().contains(
            onlyAccount.bankName.replaceAll(' ', '').toLowerCase(),
          ) ||
          body.toLowerCase().contains(onlyAccount.bankName.toLowerCase());

      if (!matchesBankName) {
        debugPrint(
          '>>> [EXPENCIFY] SMS has no account digits and didn\'t match account Bank Name (${onlyAccount.bankName}) — ignored.',
        );
        return;
      }

      accountId = onlyAccount.id!;
    }

    // ── PERFECT DUPLICATE GUARD ─────────────────────────────────────────────
    // Uses the exact timestamp (within a 1s window) to identify the same SMS.
    final db = await dbHelper.database;
    final startRange = effectiveDate
        .subtract(const Duration(seconds: 1))
        .toIso8601String();
    final endRange = effectiveDate
        .add(const Duration(seconds: 1))
        .toIso8601String();

    final existing = await db.query(
      'transactions',
      where:
          'account_id = ? AND amount = ? AND type = ? AND date BETWEEN ? AND ?',
      whereArgs: [accountId, amount, type, startRange, endRange],
    );

    if (existing.isNotEmpty) {
      debugPrint('>>> [EXPENCIFY] Duplicate SMS (Sync/Bg/Main) — ignored.');
      return;
    }

    await txnRepo.save(
      TransactionModel(
        accountId: accountId,
        amount: amount,
        type: type,
        category: category,
        date: effectiveDate,
        note: 'Auto-detected from SMS',
        merchant: updatedMerchant,
        isSms: true,
        isOcr: false,
        isVoice: false,
      ),
    );

    await accRepo.updateBalance(accountId, type == 'income' ? amount : -amount);

    debugPrint(
      '>>> [EXPENCIFY] ✓ Saved ₹$amount ($type) | Merchant: $updatedMerchant | Date: $effectiveDate',
    );

    // ── BUDGET THRESHOLD ALERT ──────────────────────────────────────────────
    try {
      if (type == 'expense' && category.isNotEmpty) {
        final budgetRepo = SqliteBudgetRepository(dbHelper);
        final budgets = await budgetRepo.getAll();
        final matchedBudget = budgets.firstWhereOrNull(
          (b) => b.category.toLowerCase() == category.toLowerCase(),
        );

        if (matchedBudget != null) {
          final now = DateTime.now();
          DateTime startCheck = DateTime(
            now.year,
            now.month,
            1,
          ); // default monthly

          if (matchedBudget.period == 'weekly') {
            startCheck = now.subtract(Duration(days: now.weekday - 1));
          } else if (matchedBudget.period == 'yearly') {
            startCheck = DateTime(now.year, 1, 1);
          }

          final categoryTotals = await txnRepo.getCategoryTotals(
            type: 'expense',
            from: startCheck,
            accountId: accountId,
          );
          final currentSpent =
              categoryTotals.entries
                  .firstWhereOrNull(
                    (e) => e.key.toLowerCase() == category.toLowerCase(),
                  )
                  ?.value ??
              0.0;

          if (currentSpent > matchedBudget.amount) {
            final overAmount = currentSpent - matchedBudget.amount;
            await NotificationService().showInstant(
              title: '⚠️ Budget Exceeded: $category',
              body:
                  'You exceeded limit by ₹${overAmount.toStringAsFixed(0)} (Total: ₹${currentSpent.toStringAsFixed(0)} / Max: ₹${matchedBudget.amount.toStringAsFixed(0)})',
            );
            debugPrint('>>> [EXPENCIFY] Budget Alert triggered for $category');
          }
        }
      }
    } catch (e) {
      debugPrint('>>> [EXPENCIFY] Budget Alert Error: $e');
    }
  } catch (e, stack) {
    debugPrint('>>> [EXPENCIFY] ERROR: $e\n$stack');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Legacy Telephony Isolate Entry Point.
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
void onBackgroundSmsReceived(SmsMessage message) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  final msgDate = message.date != null
      ? DateTime.fromMillisecondsSinceEpoch(message.date!)
      : DateTime.now();
  await processSms(message.body ?? '', date: msgDate);
}
