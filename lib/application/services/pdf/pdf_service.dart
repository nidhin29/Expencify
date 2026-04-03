import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:expencify/domain/entities/transaction.dart';
import 'package:expencify/domain/entities/account.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

class PdfService {
  Future<String?> exportTransactionsToPDF(
    List<TransactionModel> transactions, {
    List<Account>? accounts,
    String? filterType,
    String? filterCategory,
    DateTime? from,
    DateTime? to,
  }) async {
    // Build account lookup
    final accountMap = <int, String>{};
    if (accounts != null) {
      for (final a in accounts) {
        if (a.id != null) accountMap[a.id!] = '${a.name} (${a.bankName})';
      }
    }

    final dateFmt = DateFormat('d MMM yyyy');

    // Load fonts supporting the Rupee symbol (₹)
    final regularFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
    );

    // Colour palette
    final headerBg = PdfColor.fromHex('#6C63FF');
    final incomeCol = PdfColor.fromHex('#4CAF50');
    final expenseCol = PdfColor.fromHex('#F44336');
    final rowAlt = PdfColor.fromHex('#F5F5F5');

    // Summary stats
    double totalIncome = 0, totalExpense = 0;
    for (final t in transactions) {
      if (t.type == 'income') {
        totalIncome += t.amount;
      } else {
        totalExpense += t.amount;
      }
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (ctx) => pw.Column(
          children: [
            pw.Container(
              decoration: pw.BoxDecoration(
                color: headerBg,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 14,
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Expencify — Transaction Report',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    DateFormat('d MMM yyyy').format(DateTime.now()),
                    style: const pw.TextStyle(color: PdfColors.white),
                  ),
                ],
              ),
            ),
            if (filterType != null || filterCategory != null || from != null)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 10, left: 4, right: 4),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Row(
                      children: [
                        if (filterType != null) ...[
                          _filterBadge(
                            'Type: ${filterType.toUpperCase()}',
                            headerBg,
                          ),
                          pw.SizedBox(width: 8),
                        ],
                        if (filterCategory != null)
                          _filterBadge('Category: $filterCategory', headerBg),
                      ],
                    ),
                    if (from != null && to != null)
                      pw.Text(
                        'Period: ${dateFmt.format(from)} - ${dateFmt.format(to)}',
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                  ],
                ),
              ),
            pw.SizedBox(height: 10),
          ],
        ),
        build: (ctx) => [
          pw.SizedBox(height: 16),

          // Summary cards row
          pw.Row(
            children: [
              _summaryCard(
                'Total Transactions',
                '${transactions.length}',
                PdfColor.fromHex('#6C63FF'),
              ),
              pw.SizedBox(width: 12),
              _summaryCard(
                'Total Income',
                '₹${NumberFormat('#,##0').format(totalIncome)}',
                incomeCol,
              ),
              pw.SizedBox(width: 12),
              _summaryCard(
                'Total Expense',
                '₹${NumberFormat('#,##0').format(totalExpense)}',
                expenseCol,
              ),
              pw.SizedBox(width: 12),
              _summaryCard(
                'Net',
                '₹${NumberFormat('#,##0').format(totalIncome - totalExpense)}',
                totalIncome >= totalExpense ? incomeCol : expenseCol,
              ),
            ],
          ),

          pw.SizedBox(height: 20),

          // Table
          pw.Table(
            border: pw.TableBorder.symmetric(
              outside: const pw.BorderSide(color: PdfColors.grey300),
            ),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.6),
              1: const pw.FlexColumnWidth(2.5),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(1.8),
              4: const pw.FlexColumnWidth(2.0),
              5: const pw.FlexColumnWidth(1.4),
            },
            children: [
              // Header row
              pw.TableRow(
                decoration: pw.BoxDecoration(color: headerBg),
                children:
                    [
                          'Date',
                          'Account',
                          'Type',
                          'Category',
                          'Merchant',
                          'Amount (₹)',
                        ]
                        .map(
                          (h) => pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            child: pw.Text(
                              h,
                              style: pw.TextStyle(
                                color: PdfColors.white,
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        )
                        .toList(),
              ),
              // Data rows
              ...transactions.asMap().entries.map((entry) {
                final i = entry.key;
                final tx = entry.value;
                final isIncome = tx.type == 'income';
                final bg = i.isEven ? PdfColors.white : rowAlt;
                final amtCol = isIncome ? incomeCol : expenseCol;
                return pw.TableRow(
                  decoration: pw.BoxDecoration(color: bg),
                  children:
                      [
                        dateFmt.format(tx.date),
                        accountMap[tx.accountId] ?? 'A/c #${tx.accountId}',
                        isIncome ? 'Income' : 'Expense',
                        tx.category,
                        tx.merchant.isNotEmpty ? tx.merchant : '-',
                        (isIncome ? '+' : '-') + tx.amount.toStringAsFixed(2),
                      ].asMap().entries.map((e) {
                        final isAmt = e.key == 5;
                        return pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: pw.Text(
                            e.value,
                            style: pw.TextStyle(
                              fontSize: 9,
                              color: isAmt ? amtCol : PdfColors.black,
                              fontWeight: isAmt
                                  ? pw.FontWeight.bold
                                  : pw.FontWeight.normal,
                            ),
                          ),
                        );
                      }).toList(),
                );
              }),
            ],
          ),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final path =
        '${dir.path}/expencify_${DateTime.now().millisecondsSinceEpoch}.pdf';
    await File(path).writeAsBytes(await doc.save());
    return path;
  }

  pw.Widget _filterBadge(String text, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: color, width: 0.5),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  pw.Widget _summaryCard(String label, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: color,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: const pw.TextStyle(color: PdfColors.white, fontSize: 8),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              value,
              style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
