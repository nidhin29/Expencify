import '../../../infrastructure/database/database_helper.dart';
import 'chat_plan_constraints.dart';
import 'chat_policy.dart';
import 'chat_scope_delta.dart';

/// A conservative accelerator for completely covered read requests. It creates
/// an operation, never an answer. Unknown content, modifiers and arithmetic go
/// to interpretation instead; the normal compiler still validates every slot.
class ChatResolvedRead {
  static const _words = <String>{
    'please',
    'can',
    'could',
    'you',
    'tell',
    'give',
    'show',
    'calculate',
    'me',
    'i',
    'my',
    'the',
    'a',
    'an',
    'to',
    'at',
    'in',
    'on',
    'for',
    'during',
    'from',
    'did',
    'do',
    'have',
    'has',
    'was',
    'is',
    'are',
    'were',
    'what',
    'how',
    'much',
    'many',
    'total',
    'totals',
    'amount',
    'amounts',
    'paid',
    'pay',
    'spend',
    'spent',
    'spending',
    'expense',
    'expenses',
    'cost',
    'outgoings',
    'outflows',
    'income',
    'received',
    'earned',
    'average',
    'avg',
    'mean',
    'number',
    'count',
    'of',
    'transaction',
    'transactions',
    'payment',
    'payments',
    'recorded',
    'records',
    'entries',
    'went',
    'sent',
    'by',
    'per',
    'category',
    'categories',
    'merchant',
    'merchants',
    'account',
    'accounts',
    'balance',
    'balances',
    'across',
    'available',
    'overall',
    'current',
  };

  static Future<Map<String, dynamic>?> intent(
    DatabaseHelper helper,
    String question,
    Map<String, dynamic>? previous,
  ) async {
    if (ChatScopeDelta.periodOnly(question)) {
      final queries = previous?['queries'];
      if (queries is! List || queries.length != 1 || queries.single is! Map) {
        return null;
      }
      final q = queries.single as Map;
      return {
        'source': q['source'],
        'metric': q['metric'],
        'group': q['group'] ?? 'none',
        'type': q['type'] ?? 'expense',
        'followup': true,
      };
    }
    final source =
        ChatPlanConstraints.source(question) ??
        (ChatPlanConstraints.type(question) == null ? null : 'transactions');
    final metric = ChatPlanConstraints.metric(question);
    final type = ChatPlanConstraints.type(question);
    if (source != 'transactions' ||
        type == null ||
        !{'sum', 'avg', 'count'}.contains(metric)) {
      return null;
    }
    if (!ChatPlanConstraints.recordRequest(question)) return null;
    var remaining = ChatPolicy.normalizedQuestion(
      ChatPlanConstraints.queryBody(question),
    );
    final db = await helper.database;
    final entities = await db.rawQuery(
      'SELECT merchant AS name FROM transactions WHERE LENGTH(merchant)>1 AND INSTR(LOWER(?),LOWER(merchant))>0 '
      'UNION SELECT name FROM categories WHERE INSTR(LOWER(?),LOWER(name))>0 '
      'UNION SELECT name FROM accounts WHERE INSTR(LOWER(?),LOWER(name))>0 LIMIT 24',
      [question, question, question],
    );
    final names =
        entities
            .map((r) => '${r['name']}')
            .where((n) => n.length > 1)
            .toSet()
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    var matched = 0;
    for (final name in names) {
      final pattern = RegExp(
        '\\b${RegExp.escape(ChatPolicy.normalizedQuestion(name))}\\b',
      );
      if (!pattern.hasMatch(remaining)) continue;
      matched++;
      remaining = remaining.replaceAll(pattern, ' ');
    }
    if (matched > 1) return null;
    remaining = remaining.replaceAll(
      RegExp('\\b${ChatPolicy.periodPattern}\\b'),
      ' ',
    );
    if (remaining
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .any((s) => !_words.contains(s))) {
      return null;
    }
    return {
      'source': source,
      'metric': metric,
      'group': ChatPlanConstraints.group(question) ?? 'none',
      'type': type,
    };
  }
}
