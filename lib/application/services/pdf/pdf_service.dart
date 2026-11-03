import '../security/private_file_cleanup.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:expencify/domain/entities/transaction.dart';
import 'package:expencify/domain/entities/account.dart';
import 'package:intl/intl.dart';

class PdfService {
  final PrivateFileCleanup files;
  const PdfService({this.files = const PrivateFileCleanup()});
  static final _purple = PdfColor.fromHex('#7C3AED');
  static final _ink = PdfColor.fromHex('#201A30');
  static final _muted = PdfColor.fromHex('#625D6D');
  static final _line = PdfColor.fromHex('#E7E3ED');
  static final _green = PdfColor.fromHex('#176B46');
  static final _red = PdfColor.fromHex('#A82349');
  Future<String?> exportTransactionsToPDF(
    List<TransactionModel> transactions, {
    List<Account>? accounts,
    String? filterType,
    String? filterCategory,
    DateTime? from,
    DateTime? to,
  }) async {
    final accountMap = {
      for (final a in accounts ?? <Account>[])
        if (a.id != null) a.id!: a,
    };
    final date = DateFormat('d MMM yyyy');
    final money = NumberFormat('#,##,##0.00', 'en_IN');
    final period = from != null && to != null
        ? '${date.format(from)} - ${date.format(to)}'
        : from != null
        ? 'From ${date.format(from)}'
        : to != null
        ? 'Through ${date.format(to)}'
        : 'All dates';
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Inter-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Inter-SemiBold.ttf'),
    );
    final doc = pw.Document(
      title: 'Spendy transaction report',
      author: 'Spendy',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    var incomePaise = 0, expensePaise = 0;
    for (final tx in transactions) {
      if (tx.type == 'income') {
        incomePaise += (tx.amount * 100).round();
      } else {
        expensePaise += (tx.amount * 100).round();
      }
    }
    final net = incomePaise - expensePaise;
    final generated = date.format(DateTime.now());
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 1000,
        margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 14),
          margin: const pw.EdgeInsets.only(bottom: 16),
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _line)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Spendy',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  color: _purple,
                ),
              ),
              pw.Text(
                'TRANSACTION REPORT',
                style: pw.TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.3,
                  color: _muted,
                ),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 10),
          decoration: pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _line)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Generated $generated | INR',
                style: pw.TextStyle(fontSize: 8, color: _muted),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(fontSize: 8, color: _muted),
              ),
            ],
          ),
        ),
        build: (context) => [
          pw.Text(
            'Your transactions',
            style: pw.TextStyle(
              fontSize: 24,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
          pw.SizedBox(height: 7),
          pw.Text(period, style: pw.TextStyle(fontSize: 11, color: _muted)),
          if (filterType != null || filterCategory != null) ...[
            pw.SizedBox(height: 7),
            pw.Text(
              [
                if (filterType != null)
                  filterType == 'income' ? 'Income' : 'Expenses',
                if (filterCategory != null) filterCategory,
              ].join(' | '),
              style: pw.TextStyle(fontSize: 10, color: _muted),
            ),
          ],
          pw.SizedBox(height: 20),
          pw.Row(
            children: [
              _summary('Income', '₹${money.format(incomePaise / 100)}', _green),
              pw.SizedBox(width: 10),
              _summary(
                'Expenses',
                '₹${money.format(expensePaise / 100)}',
                _red,
              ),
              pw.SizedBox(width: 10),
              _summary(
                'Net cash flow',
                '${net < 0 ? '-' : ''}₹${money.format(net.abs() / 100)}',
                net < 0 ? _red : _green,
              ),
            ],
          ),
          pw.SizedBox(height: 22),
          pw.Text(
            '${transactions.length} ${transactions.length == 1 ? 'transaction' : 'transactions'}',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
          pw.SizedBox(height: 10),
          if (transactions.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 24),
              child: pw.Text(
                'No transactions in this report.',
                style: pw.TextStyle(fontSize: 11, color: _muted),
              ),
            )
          else
            pw.Table(
              columnWidths: {
                0: const pw.FixedColumnWidth(75),
                1: const pw.FlexColumnWidth(2.2),
                2: const pw.FlexColumnWidth(1.6),
                3: const pw.FixedColumnWidth(100),
              },
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              children: [
                pw.TableRow(
                  repeat: true,
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#F1EBFC'),
                  ),
                  children: [
                    for (final h in [
                      'Date',
                      'Transaction',
                      'Account',
                      'Amount (INR)',
                    ])
                      _cell(
                        pw.Text(
                          h,
                          textAlign: h == 'Amount (INR)'
                              ? pw.TextAlign.right
                              : pw.TextAlign.left,
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: _ink,
                          ),
                        ),
                      ),
                  ],
                ),
                for (var i = 0; i < transactions.length; i++)
                  _row(
                    transactions[i],
                    accountMap[transactions[i].accountId],
                    i,
                    date,
                    money,
                  ),
              ],
            ),
        ],
      ),
    );
    return (await files.create('pdf', await doc.save())).path;
  }

  pw.Widget _summary(String label, String value, PdfColor color) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#FAF8FD'),
        border: pw.Border.all(color: _line),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 9, color: _muted)),
          pw.SizedBox(height: 8),
          pw.FittedBox(
            fit: pw.BoxFit.scaleDown,
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    ),
  );
  pw.Widget _cell(pw.Widget child) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 11),
    child: child,
  );
  pw.TableRow _row(
    TransactionModel tx,
    Account? account,
    int index,
    DateFormat date,
    NumberFormat money,
  ) {
    final income = tx.type == 'income';
    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: index.isEven ? PdfColors.white : PdfColor.fromHex('#FAF9FC'),
        border: pw.Border(bottom: pw.BorderSide(color: _line, width: .4)),
      ),
      children: [
        _cell(
          pw.Text(
            date.format(tx.date),
            style: pw.TextStyle(fontSize: 9, color: _muted),
          ),
        ),
        _cell(
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                tx.merchant.trim().isEmpty ? tx.category : tx.merchant,
                style: pw.TextStyle(
                  fontSize: 10,
                  color: _ink,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '${tx.category} | ${income ? 'Income' : 'Expense'}',
                style: pw.TextStyle(fontSize: 9, color: _muted),
              ),
            ],
          ),
        ),
        _cell(
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                account?.name ?? 'Unknown account',
                style: pw.TextStyle(fontSize: 10, color: _ink),
              ),
              if (account != null && account.bankName != account.name) ...[
                pw.SizedBox(height: 4),
                pw.Text(
                  account.bankName,
                  style: pw.TextStyle(fontSize: 9, color: _muted),
                ),
              ],
            ],
          ),
        ),
        _cell(
          pw.Text(
            '${income ? '+' : '-'}${money.format(tx.amount)}',
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: income ? _green : _red,
            ),
          ),
        ),
      ],
    );
  }
}
