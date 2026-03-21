import 'package:flutter/foundation.dart';
import 'package:expencify/application/services/sms/sms_parser_service.dart';

void main() async {
  final testCases = [
    'HDFC Bank: Rs 500.00 debited from a/c **1234 on 02-03-26 to SWIGGY. Info: UPI-123456789. Avl Bal: Rs 10000.00',
    'Your a/c no. XXXXXXXX5678 is credited by Rs.10,000.00 on 01-03-26 by Salary. (Gen Bal Rs.50,000.00)',
    'Spent ₹1,250.50 at Amazon using card ending 9012. Avl bal ₹5,000',
    'Paid Rs.200 to Chai Point. UPI Ref: 987654321',
    'Axis Bank: txn of INR 45.00 on acct XX9999 at STARBUCKS using UPI. Bal: Rs 1500',
    'ICICI Bank: Amount of Rs.1500.00 debited for your Credit Card ending 1234. Ref No: 000.',
    'Hello, your OTP for login is 123456. Do not share.',
    'Alert: Your account balance is low. Please maintain min bal.',
  ];

  debugPrint('--- SMS Parser Verification ---');
  for (var i = 0; i < testCases.length; i++) {
    final sms = testCases[i];
    debugPrint('\nTest Case ${i + 1}: "$sms"');
    final Map<String, dynamic>? result = await SmsParserService.parseSms(sms);
    if (result != null) {
      debugPrint('  SUCCESS');
      debugPrint('  Amount: ${result['amount']}');
      debugPrint('  Type: ${result['type']}');
      debugPrint('  Merchant: ${result['merchant']}');
      debugPrint('  Account: ${result['account']}');
      debugPrint('  Last4: ${result['lastFour']}');
      debugPrint('  Balance: ${result['balance']}');

      final rulesResult = await SmsParserService.applySmartRules(
        result['merchant'] ?? '',
        sms,
        result['type'] as String,
      );
      final category = rulesResult['category']!;
      final updatedMerchant = rulesResult['merchant']!;

      debugPrint('  Guessed Category: $category');
      if (updatedMerchant != (result['merchant'] ?? '')) {
        debugPrint('  Updated Merchant: $updatedMerchant');
      }
    } else {
      debugPrint('  FAILED / IGNORED');
    }
  }
}
