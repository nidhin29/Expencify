import 'package:flutter/foundation.dart';
import 'package:expencify/infrastructure/database/database_helper.dart';
import 'package:expencify/application/services/sms/sms_parser_service.dart';

void main() async {
  final db = DatabaseHelper();

  debugPrint('--- Registering Entities ---');
  // Register "Sister" for keyword "NIKITA"
  await db.insert('registered_entities', {
    'name': 'Sister',
    'keyword': 'NIKITA',
    'category': 'Transfer',
    'type': 'income',
  });
  debugPrint('Registered: NIKITA -> Sister (Transfer)');

  // Register "Google" for keyword "GOOGLE"
  await db.insert('registered_entities', {
    'name': 'Google',
    'keyword': 'GOOGLE',
    'category': 'Salary',
    'type': 'income',
  });
  debugPrint('Registered: GOOGLE -> Google (Salary)');

  debugPrint('\n--- Testing Categorization ---');

  final testSms = [
    'A/c XX1234 credited with INR 5,000.00 on 02-03-26 by UPI from NIKITA. Ref: 123456.',
    'Salary of Rs.50,000.00 credited to your account by GOOGLE INC on 01-03-26.',
    'A/c XX9999 credited with Rs.200.00 on 02-03-26 by UPI from FRIEND. Ref: 999.',
  ];

  for (final sms in testSms) {
    debugPrint('\nSMS: "$sms"');
    final Map<String, dynamic>? parsed = await SmsParserService.parseSms(sms);
    if (parsed != null) {
      final type = parsed['type'] as String;
      final merchant = parsed['merchant'] ?? '';
      final rulesResult = await SmsParserService.applySmartRules(
        merchant,
        sms,
        type,
      );
      final category = rulesResult['category']!;
      final updatedMerchant = rulesResult['merchant']!;

      debugPrint('  Detected Type: $type');
      debugPrint('  Detected Merchant: $merchant');
      debugPrint('  Guessed Category: $category');
      if (updatedMerchant != merchant) {
        debugPrint('  Updated Merchant: $updatedMerchant');
      }
    } else {
      debugPrint('  Failed to parse.');
    }
  }
}
