import 'package:expencify/application/services/sms/sms_parser_service.dart';

void main() async {
  print("--- Testing Precision Multilingual Parser ---");

  final testCases = [
    {
      "name": "English Standard",
      "body":
          "HDFC Bank: Rs. 500 debited from A/c XX6512 to SWIGGY on 04-MAR-26",
      "expected": "expense",
    },
    {
      "name": "Malayalam Marketing (with URL)",
      "body":
          "ഫെഡറൽ ബാങ്കിന്റെ ലൈഫ് ടൈം ഫ്രീ Celesta ക്രെഡിറ്റ് കാർഡ് ഇനി നിങ്ങൾക്കു സ്വന്തം. Rs.431,000 വരെ ലിമിറ്റുള്ള കാർഡിനായി @ https://l.federal.bank.in/FEDBNK/DckWD85k  ക്ലിക്ക് ചെയ്യുക.",
      "expected": null,
    },
    {
      "name": "Hindi Transaction",
      "body": "निकाला: Rs. 1000.00 A/c XX1234 से ATM पर 05-MAR-26 को।",
      "expected": "expense",
    },
    {
      "name": "Malayalam Transaction",
      "body": "പിൻവലിച്ചു: ₹500. A/c XX6512. 04-MAR-26.",
      "expected": "expense",
    },
    {
      "name": "Tamil Transaction",
      "body": "வரவு: ₹2000.00 A/c XX9988. சம்பளம்.",
      "expected": "income",
    },
    {
      "name": "General Marketing with URL",
      "body":
          "Get personal loan up to 5L instantly! Click here: https://bank.co/apply",
      "expected": null,
    },
  ];

  int passed = 0;
  for (final test in testCases) {
    final result = await SmsParserService.parseSms(test['body'] as String);
    final actual = result?['type'];

    if (actual == test['expected']) {
      print("[PASS] ${test['name']}");
      passed++;
    } else {
      print(
        "[FAIL] ${test['name']} - Expected: ${test['expected']}, Actual: $actual",
      );
    }
  }

  print("\nResults: $passed/${testCases.length} tests passed.");
}
