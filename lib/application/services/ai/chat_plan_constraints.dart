import 'chat_facts.dart';
import 'chat_policy.dart';
import 'chat_scope_delta.dart';

/// Checks explicit request constraints; never creates a query or an answer.
/// Unknown wording remains the model's job rather than a phrase-answer table.
class ChatPlanConstraints {
  /// Only an actual continuation or an underspecified view needs prior query
  /// operands. Complete fresh requests must not inherit a previous calculation.
  static bool usesQueryContext(String question) {
    final grouping = group(question);
    return isFollowup(question) ||
        hasScopeReference(question) ||
        needsPriorScope(question) ||
        (grouping != null && grouping != 'none');
  }

  /// Strip only a syntactic refocusing clause, preserving the actual request
  /// verbatim (including decimal amounts and entity spelling).
  static String queryBody(String question) => question.replaceFirst(
    RegExp(
      r'^\s*(?:back|returning|going back) to [^,:\n]{1,80}[,:]\s*(?=(?:what|which|where|how|show|list|compare)\b)',
      caseSensitive: false,
    ),
    '',
  );

  /// Recognizes an explicit request to inspect records, never an answer or a
  /// query. A financial noun inside ordinary conversation is insufficient.
  static bool recordRequest(String question) {
    final q = ChatPolicy.normalizedQuestion(question);
    final financial = financialReference(q);
    return financial &&
        RegExp(
          r'\b(?:what|how much|how many|where|which|show|list|total|sum|count|compare|break|summari[sz]e|calculate|give|find)\b|^(?:spending|expenses?|income|balance|budgets?|savings?|transactions?|payments?)\b',
        ).hasMatch(q);
  }

  static bool financialReference(String question) =>
      source(question) != null ||
      type(question) != null ||
      RegExp(
        r'\b(money|cash|rupees?|amounts?|costs?|expenditure|outlays?|merchants?|categories|category)\b',
        caseSensitive: false,
      ).hasMatch(question);

  static bool isFollowup(String question) =>
      ChatScopeDelta.periodOnly(question) ||
      RegExp(
        r'^(?:(?:and|what about|how about|same|only|just|by|per|instead)\b|income$|expenses?$|spending$)',
        caseSensitive: false,
      ).hasMatch(ChatPolicy.normalizedQuestion(question)) ||
      // A connective retains the resolved financial scope only when this is
      // independently a financial request. "So explain volcanoes" gets no
      // permission from an earlier spending question.
      (RegExp(
            r'^\s*(?:so|then|okay|ok|well|alright)\b',
            caseSensitive: false,
          ).hasMatch(question) &&
          recordRequest(question));

  /// References to a prior scope are independent of the model's optional
  /// continuation flag. A deictic period must never quietly become all time.
  static bool needsPriorScope(String question) {
    final q = ChatPolicy.normalizedQuestion(question);
    return hasScopeReference(q) ||
        (source(q) == null && (group(q) != null || metric(q) != null)) ||
        (RegExp(r'\bcompare\b').hasMatch(q) &&
            !financialReference(q) &&
            RegExp(ChatPolicy.periodPattern).hasMatch(q));
  }

  static bool hasScopeReference(String question) {
    final q = ChatPolicy.normalizedQuestion(question);
    return RegExp(
          r'\b(?:first|second|third|fourth|last) (?:one|part|result|request)\b',
        ).hasMatch(q) ||
        RegExp(
          r'\b(?:that|those|same|previous|earlier|above) (?:months?|weeks?|years?|periods?|accounts?|merchants?|category|categories|payments?|transactions?|expenses?|records?)\b',
        ).hasMatch(q) ||
        RegExp(
          r'\b(?:that|this|those|these|the same) (?:amounts?|figures?|totals?|counts?|averages?|balances?|results?)\b',
        ).hasMatch(q) ||
        (RegExp(
              r'\b(?:does|did|is|was|were|are|about|of|for) (?:that|those|it|them)\b',
            ).hasMatch(q) &&
            (financialReference(q) || metric(q) != null || group(q) != null));
  }

  static String previousQuestion(
    String question,
    List<Map<String, dynamic>> history,
  ) {
    if (!isFollowup(question) && !needsPriorScope(question)) {
      return '';
    }
    final prior = history
        .where(
          (m) =>
              m['isUser'] == true &&
              m['text'] != question &&
              (recordRequest('${m['text']}') || group('${m['text']}') != null),
        )
        .toList();
    return prior.isEmpty ? '' : '${prior.last['text']}';
  }

  static bool missingPeriodContext(
    String question,
    List<Map<String, dynamic>> history,
  ) {
    final q = question.toLowerCase();
    return history.where((m) => m['isUser'] == true).isEmpty &&
        RegExp(r'\b(that|those|same)\b').hasMatch(q) &&
        RegExp(
          r'\b(before|previous|periods?|dates?|times?|months?|weeks?|years?)\b',
        ).hasMatch(q) &&
        !RegExp(
          '\\b${ChatPolicy.periodPattern}\\b|\\b(?:19|20)[0-9]{2}\\b',
        ).hasMatch(q);
  }

  static String? type(String question) {
    final q = question.toLowerCase();
    if (RegExp(
      r'\b(income|incoming|inflows?|earned|earn|salary)\b|\b(?:to me|i received|i receive|came in)\b',
    ).hasMatch(q)) {
      return 'income';
    }
    if (RegExp(
      r'\b(expenses?|spend|spent|spending|paid|pay|outgoings|outflows?)\b|\b(?:from me|went out|money[- ]out)\b',
    ).hasMatch(q)) {
      return 'expense';
    }
    return null;
  }

  static String? group(String question) {
    final q = question.toLowerCase().replaceAll('-', ' ');
    if (RegExp(r'\b(list|latest|recent)\b').hasMatch(q)) return null;
    final by = RegExp(
      r'\b(?:by|per) (category|categories|merchant|merchants|shop|shops|store|stores|date|day|weekday|month|year|account)\b',
    ).firstMatch(q);
    if (by != null) {
      return const {
            'categories': 'category',
            'merchants': 'merchant',
            'shop': 'merchant',
            'shops': 'merchant',
            'store': 'merchant',
            'stores': 'merchant',
            'date': 'day',
          }[by.group(1)] ??
          by.group(1);
    }
    if (q.contains('day of the week')) return 'weekday';
    if (RegExp(r'\b(which|top|biggest|most|highest)\b').hasMatch(q)) {
      if (RegExp(r'\b(?:merchants?|shops?|stores?|vendors?)\b').hasMatch(q)) {
        return 'merchant';
      }
      if (RegExp(r'\b(categor(?:y|ies))\b').hasMatch(q)) return 'category';
    }
    if (RegExp(
      r'\bmonthly (?:spending|expense|income|payment).*totals?\b',
    ).hasMatch(q)) {
      return 'month';
    }
    if (RegExp(r'\bwhere\b').hasMatch(q) &&
        RegExp(r'\b(spend|spent|spending|money)\b').hasMatch(q)) {
      return 'both';
    }
    // A period comparison uses the same ungrouped calculation on both sides;
    // an explicit "by ..." above remains a distinct, validated request.
    if (RegExp(r'\bcompare\b').hasMatch(q)) return 'none';
    return null;
  }

  static String? metric(String question) {
    final q = question.toLowerCase();
    if (RegExp(
          r'\bshow (?:me )?(?:my )?(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten)\b',
        ).hasMatch(q) &&
        RegExp(r'\b(payments?|transactions?)\b').hasMatch(q)) {
      return 'list';
    }
    if (RegExp(r'\b(count|number|how many)\b').hasMatch(q) &&
        RegExp(r'\b(total|sum|average|mean)\b').hasMatch(q)) {
      return null;
    }
    if (RegExp(r'\b(list|latest|recent)\b').hasMatch(q)) return 'list';
    if (RegExp(r'\b(how many|count|number of)\b').hasMatch(q)) return 'count';
    if (RegExp(r'\b(average|mean)\b').hasMatch(q)) return 'avg';
    if (RegExp(r'\b(categories|category|merchants?|accounts?)\b').hasMatch(q)) {
      return null;
    }
    if (RegExp(
      r'\b(largest|biggest|highest|maximum) (?:expense|payment|amount)\b',
    ).hasMatch(q)) {
      return 'max';
    }
    if (RegExp(
      r'\b(smallest|lowest|minimum) (?:expense|payment|amount)\b',
    ).hasMatch(q)) {
      return 'min';
    }
    if (RegExp(r'\b(total|sum|combined|how much)\b').hasMatch(q)) return 'sum';
    return null;
  }

  static String? source(String question) {
    final q = question.toLowerCase();
    if (RegExp(r'\b(?:account )?balances?\b').hasMatch(q)) return 'accounts';
    if (RegExp(r'\baccounts?\b').hasMatch(q) &&
        !RegExp(
          r'\b(spend|spending|spent|expenses?|payments?|transactions?|income|goals?|budgets?)\b',
        ).hasMatch(q)) {
      return 'accounts';
    }
    if (RegExp(
      r'\b(spend|spending|spent|expenses?|payments?|transactions?|income)\b',
    ).hasMatch(q)) {
      return RegExp(r'\b(goals?|budgets?)\b').hasMatch(q)
          ? null
          : 'transactions';
    }
    if (RegExp(r'\b(goals?|savings?|saved)\b').hasMatch(q)) return 'goals';
    if (RegExp(r'\bbudgets?\b').hasMatch(q)) return 'budgets';
    // An explicit money-flow direction identifies ledger events even when its
    // wording did not repeat one of the source nouns above.
    return type(question) != null ? 'transactions' : null;
  }

  /// Return only a single unambiguous period. Multi-period comparisons and
  /// explicit day ranges are validated by the compiler, not guessed here.
  static ChatWindow? period(String question, DateTime now) {
    final q = question.toLowerCase();
    if (RegExp(r'\b(since|before|after|last \d+)\b').hasMatch(q)) return null;
    if (RegExp(r'\b\d{4}-\d{2}-\d{2}\b').hasMatch(q) ||
        RegExp('\\b${ChatPolicy.monthNamePattern} \\d{1,2}\\b').hasMatch(q)) {
      return null;
    }
    final named = RegExp(
      '\\b${ChatPolicy.monthNamePattern}(?: (?:19|20)[0-9]{2})?\\b',
    ).allMatches(q).toList();
    final relative = RegExp(
      r'\b(today|yesterday|this month|last month|this week|last week|this year|last year|all time)\b',
    ).allMatches(q).toList();
    if (named.length + relative.length > 1) return null;
    if (named.isNotEmpty) {
      return ChatWindow.forQuery(named.single.group(0)!, now);
    }
    if (relative.isNotEmpty) {
      return ChatWindow.forQuery(relative.single.group(0)!, now);
    }
    final years = RegExp(
      r'\b(?:in|during|for|year) ((?:19|20)[0-9]{2})\b',
    ).allMatches(q).toList();
    if (years.length != 1) return null;
    final year = int.parse(years.single.group(1)!);
    return ChatWindow(DateTime(year), DateTime(year + 1), '$year');
  }
}
