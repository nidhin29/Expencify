import 'package:flutter_test/flutter_test.dart';
import 'package:expencify/application/services/sms/sms_parser_service.dart';

void main() {
  group('Global Multilingual Parser Tests', () {
    final testCases = [
      {
        "name": "Hindi Transaction",
        "body": "निकाला: Rs. 1000.00 A/c XX1234 से ATM पर 05-MAR-26 को।",
        "expected": "expense",
      },
      {
        "name": "Marathi Transaction",
        "body": "तुमच्या खात्यातून Rs 500 डेबिट झाले आहेत. व्यवहार आयडी 123.",
        "expected": "expense",
      },
      {
        "name": "Bengali Transaction",
        "body": "আপনার অ্যাকাউন্টে Rs 2000 ক্রেডিট হয়েছে।",
        "expected": "income",
      },
      {
        "name": "Kannada Transaction",
        "body": "ನಿಮ್ಮ ಖಾತೆಗೆ ₹100 ಜಮೆಯಾಗಿದೆ.",
        "expected": "income",
      },
      {
        "name": "Arabic Transaction",
        "body": "تم خصم مبلغ 50 درهم من حسابك.",
        "expected": "expense",
      },
      {
        "name": "Spanish Transaction",
        "body": "Se ha debitado 100 EUR de su cuenta.",
        "expected": "expense",
      },
      {
        "name": "French Transaction",
        "body": "Votre compte a été crédité de 1500 EUR.",
        "expected": "income",
      },
    ];

    for (final testCase in testCases) {
      test(testCase['name'] as String, () async {
        final result = await SmsParserService.parseSms(
          testCase['body'] as String,
        );
        expect(result?['type'], testCase['expected']);
      });
    }
    group('Marketing Shield', () {
      test('Malayalam Marketing Shield', () async {
        const sms =
            "ഫെഡറൽ ബാങ്കിന്റെ ലൈഫ് ടൈം ഫ്രീ Celesta ക്രെഡിറ്റ് കാർഡ് ഇനി നിങ്ങൾക്കു സ്വന്തം. Rs.431,000 വരെ ലിമിറ്റുള്ള കാർഡിനായി @ https://l.federal.bank.in/FEDBNK/DckWD85k  ക്ലിക്ക് ചെയ്യുക.";
        final result = await SmsParserService.parseSms(sms);
        expect(result, isNull);
      });
    });
  });
}
