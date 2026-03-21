import 'package:expencify/application/services/sms/sms_parser_service.dart';

void main() async {
  final alerts = [
    "Alert! HDFC Bank A/c XXXX6512 Avg. bal. maintained as on 20-FEB-26: Rs 2450.40 Avoid non-maintenance charges by maintaining Avg. bal. of Rs 2500 in MAR-2026",
    "ഫെഡറൽ ബാങ്കിന്റെ ലൈഫ് ടൈം ഫ്രീ Celesta ക്രെഡിറ്റ് കാർഡ് ഇനി നിങ്ങൾക്കു സ്വന്തം. Rs.431,000 വരെ ലിമിറ്റുള്ള കാർഡിനായി @ https://l.federal.bank.in/FEDBNK/DckWD85k  ക്ലിക്ക് ചെയ്യുക. ഈ ഓഫർ 18-03-2026 വരെ മാത്രം. നിബന്ധനകൾ ബാധകം- ഫെഡറൽ ബാങ്ക്",
  ];

  print("--- Testing Informational Alerts ---");
  for (final alert in alerts) {
    final Map<String, dynamic>? result = await SmsParserService.parseSms(alert);
    if (result == null) {
      print("SUCCESS: Ignored alert: ${alert.substring(0, 30)}...");
    } else {
      print("FAILURE: Parsed alert as transaction: $result");
    }
  }

  print("\n--- Testing Valid Transactions ---");
  final transactions = [
    "HDFC Bank: Rs. 500 debited from A/c XX6512 to SWIGGY on 04-MAR-26",
    "Federal Bank: ₹1000.00 credited to A/c XX1234 on 05-MAR-26. Salary.",
  ];

  for (final txn in transactions) {
    final Map<String, dynamic>? result = await SmsParserService.parseSms(txn);
    if (result != null) {
      print(
        "SUCCESS: Parsed ${result['type']} transaction: ₹${result['amount']}",
      );
    } else {
      print(
        "FAILURE: Failed to parse valid transaction: ${txn.substring(0, 30)}...",
      );
    }
  }
}
