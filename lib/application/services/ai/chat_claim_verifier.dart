import 'chat_evidence.dart';

/// A conservative typed check. Rejects unsupported associations instead of
/// treating a number's presence anywhere in context as proof of a claim.
class ChatClaimVerifier {
  static final _money = RegExp(r'([-−]?)₹\s*([-−]?)([\d,]+(?:\.\d+)?)');
  static double? money(String text) {
    final m = _money.firstMatch(text);
    if (m == null) return null;
    final value = double.tryParse(m[3]!.replaceAll(',', ''));
    return value == null
        ? null
        : (m[1]!.isNotEmpty || m[2]!.isNotEmpty ? -value : value);
  }

  static const _monthNames = [
    r'jan(?:uary)?',
    r'feb(?:ruary)?',
    r'mar(?:ch)?',
    r'apr(?:il)?',
    r'may',
    r'jun(?:e)?',
    r'jul(?:y)?',
    r'aug(?:ust)?',
    r'sep(?:tember)?',
    r'oct(?:ober)?',
    r'nov(?:ember)?',
    r'dec(?:ember)?',
  ];

  static bool valid(String text, ChatEvidence evidence) {
    if (evidence.facts.isEmpty) return false;
    // This ledger's typed money values are INR. A count must never become a
    // dollar amount merely because its numeric value also appears in evidence.
    if (RegExp(
      r'[$€£¥]|\b(?:USD|EUR|GBP|dollars?|euros?|pounds?)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return false;
    }
    final sentences = text
        .split(RegExp(r'[!?]|\.(?:\s|$)'))
        .where((s) => s.trim().isNotEmpty);
    for (final sentence in sentences) {
      final amounts = _money.allMatches(sentence).toList();
      if (amounts.isEmpty) {
        final counts = RegExp(r'\b\d+\b').allMatches(sentence);
        if (!counts.any(
          (n) => evidence.facts.any(
            (f) =>
                f.metric == 'count' &&
                f.display == n[0] &&
                _meaning(sentence, f),
          ),
        )) {
          return false;
        }
      }
      for (final amount in amounts) {
        final value = money(amount[0]!);
        final matching = evidence.facts.where(
          (f) => f.metric != 'count' && money(f.display) == value,
        );
        if (!matching.any(
          (f) =>
              _meaning(sentence, f) &&
              _label(sentence, amount.start, f, evidence.facts),
        )) {
          return false;
        }
      }
    }
    return true;
  }

  static bool _label(
    String sentence,
    int at,
    ChatFact fact,
    List<ChatFact> facts,
  ) {
    if (fact.label.isEmpty) return true;
    final before = sentence.substring(0, at).toLowerCase();
    ChatFact? closest;
    var last = -1;
    for (final candidate in facts.where((f) => f.label.isNotEmpty)) {
      final pos = before.lastIndexOf(candidate.label.toLowerCase());
      if (pos > last) {
        closest = candidate;
        last = pos;
      }
    }
    return closest != null
        ? closest.label == fact.label
        : sentence.toLowerCase().contains(fact.label.toLowerCase());
  }

  static List<String> unsupportedScopes(String text, Iterable<ChatFact> facts) {
    final unsupported = <String>[];
    for (final match in RegExp(
      r'\b(?:on|at|from|towards?)\s+([^,.;]+)',
      caseSensitive: false,
    ).allMatches(text)) {
      final scope = match[1]!
          .toLowerCase()
          .split(RegExp(r'\b(?:in|during|for|since|before|after)\b'))
          .first
          .trim();
      if (scope.isEmpty ||
          _monthNames.any((m) => RegExp('\\b$m\\b').hasMatch(scope))) {
        continue;
      }
      final known = facts.any(
        (fact) =>
            [fact.label, ...fact.filters.values]
                .where((s) => s.isNotEmpty)
                .any((s) => scope.contains(s.toLowerCase())) ||
            fact.scope == 'all accounts' && scope.contains('all accounts') ||
            fact.source == 'goals' &&
                fact.label.isEmpty &&
                fact.filters.isEmpty &&
                RegExp(
                  r'^(?:(?:my|your|our|the|all)\s+)?(?:savings\s+)?goals?$',
                ).hasMatch(scope),
      );
      if (!known) unsupported.add(scope);
    }
    return unsupported;
  }

  static bool _meaning(String sentence, ChatFact fact) {
    final text = sentence.toLowerCase();
    bool has(String pattern) => RegExp('\\b(?:$pattern)\\b').hasMatch(text);
    if (fact.source == 'transactions' &&
        has('spent|paid|received|earned') &&
        !has('you|your')) {
      return false;
    }
    if (unsupportedScopes(sentence, [fact]).isNotEmpty) return false;
    if (fact.filters.values.any((v) => !text.contains(v.toLowerCase()))) {
      return false;
    }
    if (fact.selectedAccount && has('all accounts|across accounts')) {
      return false;
    }
    if (!fact.selectedAccount &&
        fact.scope == 'all accounts' &&
        has('selected account')) {
      return false;
    }
    if (fact.scope != 'all accounts' && has('all accounts')) return false;
    if (fact.metric == 'avg' && !has('average|mean')) return false;
    if (fact.metric == 'count' &&
        (!has(
              'count|number|payments?|transactions?|entries|records?|credits?|debits?',
            ) ||
            _money.hasMatch(sentence) ||
            has('rupees?|INR|dollars?|amounts?|money'))) {
      return false;
    }
    if (fact.metric == 'min' && !has('minimum|smallest|lowest')) return false;
    if (fact.metric == 'max' && !has('maximum|largest|highest|biggest')) {
      return false;
    }
    if (fact.metric == 'sum' &&
        has(
          'average|mean|minimum|smallest|lowest|maximum|largest|highest|biggest',
        ) &&
        !fact.grouped) {
      return false;
    }
    if (fact.metric == 'sum' && fact.grouped) {
      if (has('maximum|largest|highest|biggest') && fact.rank != 'highest') {
        return false;
      }
      if (has('minimum|smallest|lowest') && fact.rank != 'lowest') return false;
      if (has('average|mean')) return false;
    }
    if (fact.source == 'accounts') {
      if (!has('balance|balances|accounts?') ||
          has(
            'spent|spending|expenses?|income|earned|received|savings|budgets?',
          )) {
        return false;
      }
    } else if (fact.source == 'goals') {
      if (!has('goals?|saved|savings') ||
          has('spent|expenses?|income|balance')) {
        return false;
      }
    } else if (fact.source == 'budgets') {
      if (!has('budgets?|limits?') || has('spent|expenses?|income|balance')) {
        return false;
      }
    } else if (fact.type == 'income') {
      if (!has('income|received|earned|incoming|inflows?|credits?') ||
          has('spent|spending|expenses?|outflows?')) {
        return false;
      }
    } else {
      if (!has(
            'spent|spend|spending|expenses?|paid|payments?|cost|outflows?|outgoings',
          ) ||
          has('income|received|earned|balance|savings')) {
        return false;
      }
    }
    final dateText = text
        .replaceAll(_money, '')
        .replaceAll(fact.label.toLowerCase(), '');
    final mentioned = <int>{};
    for (var i = 0; i < _monthNames.length; i++) {
      if (RegExp('\\b${_monthNames[i]}\\b').hasMatch(dateText)) {
        mentioned.add(i + 1);
      }
    }
    final years = RegExp(
      r'\b(?:19|20)\d{2}\b',
    ).allMatches(dateText).map((m) => int.parse(m[0]!));
    if (fact.from == null || fact.until == null || fact.from!.year == 1900) {
      return mentioned.isEmpty && years.isEmpty;
    }
    final end = fact.until!.subtract(const Duration(days: 1));
    if (years.any((y) => y < fact.from!.year || y > end.year)) return false;
    final allowed = <int>{};
    var cursor = DateTime(fact.from!.year, fact.from!.month);
    while (!cursor.isAfter(end) && allowed.length < 12) {
      allowed.add(cursor.month);
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    if (mentioned.isNotEmpty &&
        (mentioned.length != allowed.length ||
            !mentioned.containsAll(allowed))) {
      return false;
    }
    return true;
  }
}
