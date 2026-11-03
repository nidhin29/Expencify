import '../security/private_file_cleanup.dart';
import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:expencify/domain/entities/transaction.dart';
import 'package:expencify/domain/entities/account.dart';

class CSVService {
  final PrivateFileCleanup files;
  const CSVService({this.files = const PrivateFileCleanup()});
  Future<String?> exportTransactionsToCSV(
    List<TransactionModel> transactions, {
    List<Account>? accounts,
    String? filterType,
    String? filterCategory,
    DateTime? from,
    DateTime? to,
  }) async {
    // Build account lookup map
    final accountMap = <int, String>{};
    if (accounts != null) {
      for (final a in accounts) {
        if (a.id != null) accountMap[a.id!] = '${a.name} (${a.bankName})';
      }
    }

    // One rectangular table, ready for sorting and spreadsheet imports.
    final rows = <List<String>>[
      [
        'Date and time',
        'Account',
        'Type',
        'Category',
        'Merchant',
        'Amount',
        'Currency',
        'Note',
        'Method',
      ],
    ];

    for (final tx in transactions) {
      String method = 'Manual';
      if (tx.isOcr) method = 'OCR';
      if (tx.isVoice) method = 'Voice';
      if (tx.isSms) method = 'SMS';

      rows.add([
        tx.date.toIso8601String(),
        _spreadsheetText(accountMap[tx.accountId] ?? 'Unknown account'),
        tx.type == 'income' ? 'Income' : 'Expense',
        _spreadsheetText(tx.category),
        _spreadsheetText(tx.merchant),
        tx.amount.toStringAsFixed(2),
        'INR',
        _spreadsheetText(tx.note),
        method,
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    return (await files.create(
      'csv',
      // BOM keeps rupee symbols and non-ASCII merchant names readable in Excel.
      utf8.encode('\uFEFF$csv'),
    )).path;
  }

  String _spreadsheetText(String value) {
    // Quoting CSV fields alone does not prevent spreadsheet formula execution.
    return RegExp(r'^[\s\uFEFF]*[=+@-]').hasMatch(value) ||
            value.startsWith('\t') ||
            value.startsWith('\r') ||
            value.startsWith('\n')
        ? "'$value"
        : value;
  }
}
