import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:expencify/domain/entities/transaction.dart';
import 'package:expencify/domain/entities/account.dart';
import 'package:intl/intl.dart';

class CSVService {
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

    final dateFmt = DateFormat('d MMM yyyy HH:mm');
    final rowDateFmt = DateFormat('d MMM yyyy');
    List<List<dynamic>> rows = [];

    // Metadata
    rows.add(['Expencify - Transaction Export']);
    rows.add(['Generated On:', dateFmt.format(DateTime.now())]);

    if (from != null && to != null) {
      rows.add([
        'Period:',
        '${rowDateFmt.format(from)} to ${rowDateFmt.format(to)}',
      ]);
    }

    if (filterType != null || filterCategory != null) {
      String filterStr = '';
      if (filterType != null) {
        filterStr += 'Type: ${filterType.toUpperCase()}; ';
      }
      if (filterCategory != null) {
        filterStr += 'Category: $filterCategory';
      }
      rows.add(['Filters Applied:', filterStr]);
    }

    rows.add([]); // Empty row separator

    // Table Header
    rows.add([
      'Date',
      'Account',
      'Type',
      'Category',
      'Merchant',
      'Amount (₹)',
      'Note',
      'Method',
    ]);

    for (final tx in transactions) {
      String method = 'Manual';
      if (tx.isOcr) method = 'OCR';
      if (tx.isVoice) method = 'Voice';
      if (tx.isSms) method = 'SMS';

      rows.add([
        dateFmt.format(tx.date),
        accountMap[tx.accountId] ?? 'Account #${tx.accountId}',
        tx.type == 'income' ? 'Income' : 'Expense',
        tx.category,
        tx.merchant,
        tx.amount.toStringAsFixed(2),
        tx.note,
        method,
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final directory = await getApplicationDocumentsDirectory();
    final path =
        '${directory.path}/expencify_${DateTime.now().millisecondsSinceEpoch}.csv';
    await File(path).writeAsString(csv);
    return path;
  }
}
