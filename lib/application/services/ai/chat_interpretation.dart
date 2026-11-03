/// Domain contract shared by model interpretation and validated execution.
/// This catalog describes capabilities, never user phrases or financial answers.
enum ChatPurpose { records, social, help, advice, safety, unrelated, clarify }

class ChatOperation {
  final String source, metric, group, type;
  const ChatOperation(this.source, this.metric, this.group, this.type);
  Map<String, Object> toIntent({bool followup = false}) => {
    'source': source,
    'metric': metric,
    'group': group,
    'type': type,
    if (followup) 'followup': true,
  };
}

class ChatInterpretation {
  final ChatPurpose purpose;
  final String code;
  final ChatOperation? operation;
  final Map<String, dynamic>? query;
  final String? topic, reason;
  final bool structured;
  const ChatInterpretation(this.purpose, this.code, [this.operation])
    : query = null,
      topic = null,
      reason = null,
      structured = false;
  const ChatInterpretation.structured(
    this.purpose,
    this.code, {
    this.operation,
    this.query,
    this.topic,
    this.reason,
  }) : structured = true;

  static const operations = <String, ChatOperation>{
    'expense_total': ChatOperation('transactions', 'sum', 'none', 'expense'),
    'income_total': ChatOperation('transactions', 'sum', 'none', 'income'),
    'expense_count': ChatOperation('transactions', 'count', 'none', 'expense'),
    'income_count': ChatOperation('transactions', 'count', 'none', 'income'),
    'expense_average': ChatOperation('transactions', 'avg', 'none', 'expense'),
    'income_average': ChatOperation('transactions', 'avg', 'none', 'income'),
    'expense_largest': ChatOperation('transactions', 'max', 'none', 'expense'),
    'expense_smallest': ChatOperation('transactions', 'min', 'none', 'expense'),
    'income_largest': ChatOperation('transactions', 'max', 'none', 'income'),
    'income_smallest': ChatOperation('transactions', 'min', 'none', 'income'),
    'expense_list': ChatOperation('transactions', 'list', 'none', 'expense'),
    'income_list': ChatOperation('transactions', 'list', 'none', 'income'),
    'expense_category': ChatOperation(
      'transactions',
      'sum',
      'category',
      'expense',
    ),
    'expense_merchant': ChatOperation(
      'transactions',
      'sum',
      'merchant',
      'expense',
    ),
    'expense_breakdown': ChatOperation(
      'transactions',
      'sum',
      'both',
      'expense',
    ),
    'income_category': ChatOperation(
      'transactions',
      'sum',
      'category',
      'income',
    ),
    'income_merchant': ChatOperation(
      'transactions',
      'sum',
      'merchant',
      'income',
    ),
    'expense_day': ChatOperation('transactions', 'sum', 'day', 'expense'),
    'expense_weekday': ChatOperation(
      'transactions',
      'sum',
      'weekday',
      'expense',
    ),
    'expense_month': ChatOperation('transactions', 'sum', 'month', 'expense'),
    'expense_year': ChatOperation('transactions', 'sum', 'year', 'expense'),
    'expense_account': ChatOperation(
      'transactions',
      'sum',
      'account',
      'expense',
    ),
    'account_balance': ChatOperation('accounts', 'sum', 'none', 'expense'),
    'goal_savings': ChatOperation('goals', 'sum', 'none', 'expense'),
    'budget_limits': ChatOperation('budgets', 'sum', 'none', 'expense'),
  };

  static ChatInterpretation parse(String raw) {
    final code = raw.trim().toLowerCase();
    final op = operations[code];
    if (op != null) return ChatInterpretation(ChatPurpose.records, code, op);
    final purpose = switch (code) {
      'social' => ChatPurpose.social,
      'help' => ChatPurpose.help,
      'advice' => ChatPurpose.advice,
      'safety' => ChatPurpose.safety,
      'unrelated' => ChatPurpose.unrelated,
      'clarify' ||
      'clarify_period' ||
      'clarify_type' ||
      'clarify_merchant' ||
      'clarify_category' ||
      'clarify_records' => ChatPurpose.clarify,
      _ => throw const FormatException('Unknown interpretation code'),
    };
    return ChatInterpretation(purpose, code);
  }
}
