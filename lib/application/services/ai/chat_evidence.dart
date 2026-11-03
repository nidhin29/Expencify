import 'package:intl/intl.dart';

/// App-owned results. An assistant message is never a source of these facts.
class ChatFact {
  final String source, metric, type, label, display, group, scope;
  final String? rank;
  final Map<String, String> filters;
  final num value;
  final DateTime? from, until;
  final bool selectedAccount, grouped;
  const ChatFact({
    required this.source,
    required this.metric,
    required this.type,
    required this.label,
    required this.display,
    required this.value,
    this.from,
    this.until,
    this.selectedAccount = false,
    this.grouped = false,
    this.group = 'none',
    this.scope = 'all accounts',
    this.rank,
    this.filters = const {},
  });

  String get period {
    if (from == null || until == null) return 'current records';
    final end = until!.subtract(const Duration(days: 1));
    if (from!.year == 1900) return 'all time';
    if (from!.day == 1 && until == DateTime(from!.year, from!.month + 1)) {
      return DateFormat('MMMM yyyy').format(from!);
    }
    if (from!.month == 1 &&
        from!.day == 1 &&
        until == DateTime(from!.year + 1)) {
      return '${from!.year}';
    }
    if (from == end) return DateFormat.yMMMd().format(from!);
    return '${DateFormat.yMMMd().format(from!)} – ${DateFormat.yMMMd().format(end)}';
  }

  Map<String, dynamic> toJson() => {
    'source': source,
    'metric': metric,
    if (source == 'transactions') 'type': type,
    'period': period,
    if (from != null) 'from': DateFormat('yyyy-MM-dd').format(from!),
    if (until != null)
      'to': DateFormat(
        'yyyy-MM-dd',
      ).format(until!.subtract(const Duration(days: 1))),
    'account_scope': selectedAccount ? 'selected account' : scope,
    if (label.isNotEmpty) 'label': label,
    'value': display,
    'unit': metric == 'count' ? 'count' : 'INR',
    if (filters.isNotEmpty) 'filters': filters,
  };

  String get sentence {
    final when = source == 'transactions' ? ' for $period' : '';
    final filterText = [
      if (filters['merchant'] != null)
        '${type == 'income' ? 'from' : 'at'} ${filters['merchant']}',
      if (filters['category'] != null) 'on ${filters['category']}',
      if (filters['account'] != null)
        'in accounts matching ${filters['account']}',
    ].join(', ');
    final where = filterText.isEmpty ? '' : ' $filterText';
    if (grouped || metric == 'list') return '$label: $display';
    if (metric == 'count') {
      return 'You have $display ${source == 'transactions' ? '$type payments' : source}$where$when.';
    }
    final measure =
        const {
          'sum': 'total',
          'avg': 'average',
          'min': 'lowest',
          'max': 'highest',
        }[metric] ??
        '';
    if (source == 'accounts') {
      return 'Your $measure tracked account balance is $display$where.';
    }
    if (source == 'goals') {
      return 'Your $measure recorded goal savings are $display.';
    }
    if (source == 'budgets') {
      return 'Your $measure recorded budget limit is $display.';
    }
    final description = switch (metric) {
      'avg' => 'Your average $type payment was',
      'min' => 'Your smallest $type payment was',
      'max' => 'Your largest $type payment was',
      _ => type == 'income' ? 'You received' : 'You spent',
    };
    return '$description $display$where$when.';
  }
}

class ChatEvidence {
  final List<ChatFact> facts;
  final String exact;
  final bool partial, comparison;
  const ChatEvidence({
    required this.facts,
    required this.exact,
    this.partial = false,
    this.comparison = false,
  });
  Map<String, dynamic> toJson() => {
    'verified': true,
    'facts': facts.take(8).map((f) => f.toJson()).toList(),
    'partial_rows': partial || facts.length > 8,
    'rule':
        'These are calculated results, not a complete transaction history. Do not recalculate them.',
  };
  String get fallback {
    if (facts.isEmpty) {
      return exact.contains('No matching records.')
          ? 'I couldn’t find any matching records.\n${exact.split('\n').first}'
          : exact;
    }
    if (comparison) return exact;
    if (partial || facts.any((f) => f.grouped || f.metric == 'list')) {
      return exact;
    }
    final text = facts.map((f) => f.sentence).join('\n');
    return '$text\n\n${exact.split('\n').first}';
  }
}
