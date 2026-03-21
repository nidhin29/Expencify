class SMSService {
  // Simple parser for bank SMS alerts
  // Examples:
  // "Your a/c no. XXX1234 is debited for Rs. 500.00 on 2024-05-20. Total Bal: Rs. 10000.00"
  // "Your a/c no. XXX1234 is credited with Rs. 1000.00 on 2024-05-20. Total Bal: Rs. 11000.00"

  Map<String, dynamic>? parseSMS(String message) {
    message = message.toLowerCase();

    RegExp amountRegExp = RegExp(r'(?:rs\.|inr|amt)\s*([\d,]+\.?\d*)');
    var amountMatch = amountRegExp.firstMatch(message);

    double? amount;
    if (amountMatch != null) {
      amount = double.tryParse(amountMatch.group(1)!.replaceAll(',', ''));
    }

    String? type;
    if (message.contains('debited') ||
        message.contains('spent') ||
        message.contains('paid')) {
      type = 'expense';
    } else if (message.contains('credited') ||
        message.contains('received') ||
        message.contains('added')) {
      type = 'income';
    }

    // Handle edge case: "debited" but "cash in hand" (Withdrawal)
    // If it's a withdrawal, it's a transfer between accounts, but if user wants it tracked as income to cash:
    bool isWithdrawal =
        message.contains('at atm') || message.contains('withdrawn');

    if (amount != null && type != null) {
      return {
        'amount': amount,
        'type': type,
        'is_withdrawal': isWithdrawal,
        'raw_message': message,
      };
    }
    return null;
  }
}
