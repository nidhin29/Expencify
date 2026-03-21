import 'package:flutter_test/flutter_test.dart';
import 'package:expencify/application/services/sms/sms_parser_service.dart';

void main() {
  group('Merchant Cleanup Tests', () {
    test('Should remove "On [date]" from merchant name', () async {
      final sms = "Paid Rs. 90 to JOBY JAYAKUMAR On 26-02-26 using UPI.";
      final result = await SmsParserService.parseSms(sms);

      expect(result, isNotNull);
      expect(result!['merchant'], 'JOBY JAYAKUMAR');
    });

    test('Should remove "On [day]" from merchant name', () async {
      final sms = "Paid Rs. 15 to KARUNA MEDICALS On 26 using UPI.";
      final result = await SmsParserService.parseSms(sms);

      expect(result, isNotNull);
      expect(result!['merchant'], 'KARUNA MEDICALS');
    });

    test('Should handle "On" at the end of string', () async {
      final sms = "Spent Rs. 351 at DAILY FRESH SUPERMARKET On 26";
      final result = await SmsParserService.parseSms(sms);

      expect(result, isNotNull);
      expect(result!['merchant'], 'DAILY FRESH SUPERMARKET');
    });

    test('Should handle lowercase "on"', () async {
      final sms = "Paid Rs. 30 to JOJIMOL JOHNY on 25. Info: 123";
      final result = await SmsParserService.parseSms(sms);

      expect(result, isNotNull);
      expect(result!['merchant'], 'JOJIMOL JOHNY');
    });

    test('Should handle newline before "On"', () async {
      final sms = "Paid to DAILY FRESH SUPERMARKET\nOn 26. Bal: 100";
      final result = await SmsParserService.parseSms(sms);

      expect(result, isNotNull);
      expect(result!['merchant'], 'DAILY FRESH SUPERMARKET');
    });

    test('Should handle "On" followed by full date', () async {
      final sms = "Paid to JOBY JAYAKUMAR On 26-FEB-2026. Txn: 1";
      final result = await SmsParserService.parseSms(sms);

      expect(result, isNotNull);
      expect(result!['merchant'], 'JOBY JAYAKUMAR');
    });
  });
}
