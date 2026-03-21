import 'package:flutter_test/flutter_test.dart';
import 'package:expencify/application/services/sms/sms_parser_service.dart';

void main() {
  group('SmsParserService Tests', () {
    test('Parse standard HDFC debit SMS', () async {
      const sms =
          'HDFC Bank: Rs 500.00 debited from a/c **1234 on 02-03-26 to SWIGGY. Info: UPI-123456789. Avl Bal: Rs 10000.00';
      final result = await SmsParserService.parseSms(sms);

      expect(result, isNotNull);
      expect(result!['amount'], 500.0);
      expect(result['type'], 'expense');
      expect(result['lastFour'], '1234');
      expect(result['balance'], 10000.0);
    });

    test('Parse SBI credit SMS', () async {
      const sms =
          'Your a/c no. XXXXXXXX5678 is credited by Rs.10,000.00 on 01-03-26 by Salary. (Gen Bal Rs.50,000.00)';
      final result = await SmsParserService.parseSms(sms);

      expect(result, isNotNull);
      expect(result!['amount'], 10000.0);
      expect(result['type'], 'income');
      expect(result['lastFour'], '5678');
      expect(result['balance'], 50000.0);
    });

    test('Parse SMS with ₹ symbol', () async {
      const sms =
          'Spent ₹1,250.50 at Amazon using card ending 9012. Avl bal ₹5,000';
      final result = await SmsParserService.parseSms(sms);

      expect(result, isNotNull);
      expect(result!['amount'], 1250.5);
      expect(result['type'], 'expense');
      expect(result['lastFour'], '9012');
      expect(result['balance'], 5000.0);
    });

    test('Parse SMS with "paid" keyword', () async {
      const sms = 'Paid Rs.200 to Chai Point. UPI Ref: 987654321';
      final result = await SmsParserService.parseSms(sms);

      expect(result, isNotNull);
      expect(result!['amount'], 200.0);
      expect(result['type'], 'expense');
    });

    test('Ignore non-bank SMS', () async {
      const sms = 'Hello, your OTP for login is 123456. Do not share.';
      final result = await SmsParserService.parseSms(sms);
      expect(result, isNull);
    });
  });

  group('Category Guessing Tests', () {
    test('Guess Food from Swiggy', () async {
      final result = await SmsParserService.applySmartRules(
        'SWIGGY',
        'debited at swiggy',
        'expense',
      );
      expect(result['category'], 'Food');
    });

    test('Guess Bills from Airtel', () async {
      final result = await SmsParserService.applySmartRules(
        'AIRTEL',
        'payment for airtel recharge',
        'expense',
      );
      expect(result['category'], 'Bills');
    });
  });
}
