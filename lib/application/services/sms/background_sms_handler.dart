import 'sms_account_matcher.dart';
import 'sms_review_store.dart';
import 'sms_tracking_preference.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'sms_identity.dart';
import '../notifications/budget_alert_service.dart';
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
typedef PendingSmsProcessor =
    Future<bool> Function(String body, DateTime date, String? sender);

Future<bool> processPendingSms({PendingSmsProcessor? processor}) async {
  const channel = MethodChannel('com.example.expencify/native_sms');
  try {
    final list =
        await channel.invokeListMethod<dynamic>('readPendingSms') ?? [];
    var complete = true;
    for (final raw in list) {
      final item = Map<String, dynamic>.from(raw as Map);
      final body = item['body'] as String;
      final date = DateTime.fromMillisecondsSinceEpoch(
        item['timestamp'] as int,
      );
      final sender = item['sender'] as String?;
      final success = processor == null
          ? await processSms(body, date: date, sender: sender)
          : await processor(body, date, sender);
      if (!success) complete = false;
      if (success) {
        await channel.invokeMethod<void>('ackPendingSms', {'id': item['id']});
      }
    }
    return complete;
  } on MissingPluginException {
    return false;
  }
}

/// Started by a bounded job, never directly inside the SMS receiver.
@pragma('vm:entry-point')
void smsWorkDispatcher() async {
  WidgetsFlutterBinding.ensureInitialized();
  var success = false;
  try {
    success = await processPendingSms();
  } catch (_) {}
  await const MethodChannel(
    'com.example.expencify/native_sms',
  ).invokeMethod<void>('smsWorkFinished', success);
}

// ─────────────────────────────────────────────────────────────────────────────
// Core SMS processing logic with robust duplicate prevention.
// ─────────────────────────────────────────────────────────────────────────────
Future<bool> processSms(
  String body, {
  DateTime? date,
  String? sender,
  bool suppressNotification = false,
}) async {
  if (!await SmsTrackingPreference.isEnabled()) return true;
  if (body.isEmpty) return true;
  final effectiveDate = date ?? DateTime.now();
  final identity = smsIdentity(body, effectiveDate, sender: sender);

  try {
    final Map<String, dynamic>? data = await SmsParserService.parseSms(body);
    if (data == null) {
      if (SmsParserService.needsReview(body) &&
          await SmsTrackingPreference.isEnabled()) {
        await SmsReviewStore().add(
          identity,
          body,
          sender,
          effectiveDate,
          'Check the amount and whether money came in or went out.',
        );
      }
      return true;
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

    final matched = matchSmsAccount(accountsList, lastFour, body, sender);
    if (matched == null) {
      if (!await SmsTrackingPreference.isEnabled()) return true;
      await SmsReviewStore().add(
        identity,
        body,
        sender,
        effectiveDate,
        'Choose the account for this transaction.',
      );
      return true;
    }
    final accountId = matched.id!;

    if (!await SmsTrackingPreference.isEnabled()) return true;
    await txnRepo.saveSms(
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
      identity,
    );

    if (!suppressNotification) {
      try {
        await BudgetAlertService(
          txnRepo,
          SqliteBudgetRepository(dbHelper),
          NotificationService(),
        ).checkBudgets();
      } catch (_) {
        /* Do not retry a committed transaction for a notification failure. */
      }
    }
    return true;
  } catch (e) {
    debugPrint('SMS processing failed: ${e.runtimeType}');
    return false;
  }
}
