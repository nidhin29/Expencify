import 'package:intl/intl.dart';
import '../../../infrastructure/database/database_helper.dart';
import 'chat_policy.dart';

class ChatWindow {
  final DateTime from, until;
  final String label;
  const ChatWindow(this.from, this.until, this.label);
  factory ChatWindow.forQuery(String q, DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    if (q.contains('all time')) {
      return ChatWindow(
        DateTime(1900),
        DateTime(day.year, day.month, day.day + 1),
        'All time',
      );
    }
    final namedMonth = RegExp(
      r'\b(' + ChatPolicy.monthNamePattern + r')(?: ((?:19|20)[0-9]{2}))?\b',
    ).firstMatch(q);
    if (namedMonth != null) {
      const months = [
        'jan',
        'feb',
        'mar',
        'apr',
        'may',
        'jun',
        'jul',
        'aug',
        'sep',
        'oct',
        'nov',
        'dec',
      ];
      final month = months.indexOf(namedMonth.group(1)!.substring(0, 3)) + 1;
      final year = int.tryParse(namedMonth.group(2) ?? '') ?? now.year;
      final from = DateTime(year, month);
      return ChatWindow(
        from,
        DateTime(year, month + 1),
        DateFormat('MMMM yyyy').format(from),
      );
    }

    final monday = DateTime(day.year, day.month, day.day - day.weekday + 1);
    if (q.contains('yesterday')) {
      return ChatWindow(
        DateTime(day.year, day.month, day.day - 1),
        day,
        'Yesterday',
      );
    }
    if (q.contains('today')) {
      return ChatWindow(
        day,
        DateTime(day.year, day.month, day.day + 1),
        'Today',
      );
    }
    if (q.contains('last week')) {
      return ChatWindow(
        DateTime(monday.year, monday.month, monday.day - 7),
        monday,
        'Last week',
      );
    }
    if (q.contains('this week')) {
      return ChatWindow(
        monday,
        DateTime(monday.year, monday.month, monday.day + 7),
        'This week',
      );
    }
    if (q.contains('last month')) {
      return ChatWindow(
        DateTime(day.year, day.month - 1),
        DateTime(day.year, day.month),
        'Last month',
      );
    }
    if (q.contains('last year')) {
      return ChatWindow(
        DateTime(day.year - 1),
        DateTime(day.year),
        'Last year',
      );
    }
    if (q.contains('this year')) {
      return ChatWindow(
        DateTime(day.year),
        DateTime(day.year + 1),
        'This year',
      );
    }
    return ChatWindow(
      DateTime(day.year, day.month),
      DateTime(day.year, day.month + 1),
      'This month',
    );
  }
}

/// Financial statements are rendered from scoped facts, never free-form model
/// prose. An amount cannot be reassigned to another period/category by Qwen.
class ChatFacts {
  final DatabaseHelper helper;
  final DateTime Function() clock;
  ChatFacts({DatabaseHelper? helper, DateTime Function()? clock})
    : helper = helper ?? DatabaseHelper(),
      clock = clock ?? DateTime.now;
  static String _money(int paise) =>
      '₹${NumberFormat('#,##,##0.00', 'en_IN').format(paise / 100)}';
  static String _text(Object? raw) => String.fromCharCodes(
    '${raw ?? ''}'
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ')
        .replaceAll(RegExp(r'[\[\]<>*_`#\\]'), '')
        .runes
        .take(100),
  );
  Future<String> answer(String query, {int? accountId}) async {
    final refusal = ChatPolicy.requestReply(query);
    if (refusal != null) return refusal;
    final q = ChatPolicy.normalizedQuestion(query);
    if (q.startsWith('and ') || q.startsWith('what about ')) {
      return 'Please ask a full question with the period and category you want to check.';
    }
    final now = clock();
    final window = ChatWindow.forQuery(q, now);
    final hasPeriod = RegExp(
      r'\b' + ChatPolicy.periodPattern + r'\b',
    ).hasMatch(q);
    final category = RegExp(
      r'\b(?:on|for) (food|fuel|shopping|rent|travel|health|bills|grocery|groceries|transport|entertainment)\b',
    ).firstMatch(q)?.group(1);
    final db = await helper.database;
    return db.transaction((txn) async {
      final scope = accountId == null ? 'All accounts' : 'Selected account';
      if (q.contains('balance')) {
        if (hasPeriod && !q.contains('today')) {
          return 'Historical account balances are not available. Open Accounts to see current balances.';
        }
        final rows = await txn.rawQuery(
          'SELECT COALESCE(SUM(CAST(ROUND(balance * 100) AS INTEGER)),0) AS paise FROM accounts${accountId == null ? '' : ' WHERE id = ?'}',
          [if (accountId != null) accountId],
        );
        return 'Current balance: ${_money((rows.single['paise'] as num).toInt())}.\n$scope.';
      }
      if (q.contains('budget')) {
        // Budgets are editable plans; no historical plan snapshots are stored.
        if (hasPeriod &&
            (RegExp(r'last|yesterday|all time').hasMatch(q) ||
                RegExp(
                  r'\b' + ChatPolicy.monthNamePattern + r'\b',
                ).hasMatch(q))) {
          return 'Historical budget plans are not stored. Open Budget to see your current plans.';
        }
        final rows = await txn.query(
          'budgets',
          where: accountId == null ? null : 'account_id = ?',
          whereArgs: accountId == null ? null : [accountId],
        );
        final matching = rows
            .where(
              (r) =>
                  (category == null ||
                      '${r['category']}'.toLowerCase() == category) &&
                  (DateTime.tryParse('${r['start_date']}')?.isAfter(now) ==
                      false),
            )
            .toList();
        if (matching.isEmpty) {
          return 'No budget plans found for this selection.';
        }
        return 'Recorded budget plans ($scope):\n${matching.take(15).map((r) => '${_text(r['category'])}: ${_money(((r['amount'] as num) * 100).round())} (${_text(r['period'])})').join('\n')}${matching.length > 15 ? '\nShowing 15 of ${matching.length} plans.' : ''}';
      }
      if (RegExp(r'\b(save|saved|savings)\b').hasMatch(q)) {
        if (hasPeriod) {
          return 'Goal savings are stored as current totals, without dated contribution history. Open Goals to see recorded progress.';
        }
        final rows = await txn.query(
          'goals',
          where: accountId == null ? null : 'account_id = ?',
          whereArgs: accountId == null ? null : [accountId],
        );
        final paise = rows.fold<int>(
          0,
          (sum, r) =>
              sum +
              (((r['saved_amount'] as num?)?.toDouble() ?? 0) * 100).round(),
        );
        // Contributions are recorded savings, not money automatically moved from accounts.
        return 'Current recorded goal savings: ${_money(paise)}.\n$scope.';
      }
      final income = RegExp(
        r'\b(income|earn|earned|receive|received)\b',
      ).hasMatch(q);
      final recent =
          RegExp(r'\b(show|transactions|payments)\b').hasMatch(q) &&
          !RegExp(r'\b(summarize|summarise)\b').hasMatch(q);
      final where = <String>[
        't.id NOT IN (SELECT parent_id FROM transactions WHERE parent_id IS NOT NULL)',
      ];
      final args = <Object?>[];
      if (accountId != null) {
        where.add('t.account_id = ?');
        args.add(accountId);
      }
      if (category != null) {
        if (category == 'grocery' || category == 'groceries') {
          where.add('LOWER(t.category) IN (?, ?)');
          args.addAll(['grocery', 'groceries']);
        } else {
          where.add('LOWER(t.category) = ?');
          args.add(category);
        }
      }
      if (!recent || hasPeriod) {
        where.add('t.date >= ? AND t.date < ?');
        args.addAll([
          window.from.toIso8601String(),
          window.until.toIso8601String(),
        ]);
      }
      if (recent) {
        if (!q.contains('transactions') && !q.contains('payments')) {
          where.add('t.type = ?');
          args.add(income ? 'income' : 'expense');
        }
        final rows = await txn.rawQuery(
          'SELECT t.* FROM transactions t WHERE ${where.join(' AND ')} ORDER BY t.date DESC, t.id DESC LIMIT 10',
          args,
        );
        if (rows.isEmpty) return 'No transactions found for this selection.';
        return 'Latest ${rows.length} matching transactions${hasPeriod ? ' - ${window.label.toLowerCase()}' : ''} ($scope):\n${rows.map((r) => '${DateFormat('d MMM yyyy').format(DateTime.parse(r['date'] as String))}: ${r['type'] == 'income' ? '+' : '-'}${_money(((r['amount'] as num) * 100).round())} | ${_text(r['category'])} | ${_text(r['merchant'])}').join('\n')}\nThis list is not a complete spending total.';
      }
      if (q.contains('summari') && q.contains('transactions')) {
        final totals = await txn.rawQuery(
          'SELECT t.type, SUM(CAST(ROUND(t.amount * 100) AS INTEGER)) AS paise FROM transactions t WHERE ${where.join(' AND ')} GROUP BY t.type',
          args,
        );
        int total(String type) => totals
            .where((r) => r['type'] == type)
            .fold(0, (sum, r) => sum + (r['paise'] as num).toInt());
        final incoming = total('income'), outgoing = total('expense');
        return '${window.label} | $scope\nRecorded income: ${_money(incoming)}.\nRecorded expenses: ${_money(outgoing)}.\nNet cash flow: ${_money(incoming - outgoing)}.';
      }
      where.add('t.type = ?');
      args.add(income ? 'income' : 'expense');
      final rows = await txn.rawQuery(
        'SELECT LOWER(t.category) AS category, SUM(CAST(ROUND(t.amount * 100) AS INTEGER)) AS paise FROM transactions t WHERE ${where.join(' AND ')} GROUP BY LOWER(t.category) ORDER BY paise DESC, category ASC',
        args,
      );
      final total = rows.fold<int>(
        0,
        (sum, r) => sum + (r['paise'] as num).toInt(),
      );
      final dates =
          '${DateFormat('d MMM yyyy').format(window.from)} - ${DateFormat('d MMM yyyy').format(window.until.subtract(const Duration(days: 1)))}';
      final title = window.label == 'All time'
          ? 'All time | $scope'
          : '${window.label} | $dates | $scope';
      if (q.contains('most')) {
        if (rows.isEmpty) return '$title\nNo recorded expenses.';
        final top = (rows.first['paise'] as num).toInt();
        final tied = rows
            .where((r) => (r['paise'] as num).toInt() == top)
            .map((r) => _text(r['category']))
            .join(', ');
        return '$title\nHighest recorded spending: $tied, ${_money(top)}${rows.length > 1 && rows[1]['paise'] == rows.first['paise'] ? ' each (tie)' : ''}.';
      }
      final breakdown =
          category == null &&
          (q.contains('summari') ||
              q.contains('where') ||
              q.contains('understand'));
      return '$title\nRecorded ${income ? 'income' : 'expenses'}${category == null ? '' : ' for $category'}: ${_money(total)}.${breakdown && rows.isNotEmpty ? '\n${rows.take(10).map((r) => '${_text(r['category'])}: ${_money((r['paise'] as num).toInt())}').join('\n')}${rows.length > 10 ? '\nShowing the 10 largest categories; total includes all categories.' : ''}' : ''}';
    });
  }
}
