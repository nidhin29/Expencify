import 'chat_help_catalog.dart';
import 'chat_plan_constraints.dart';
import 'chat_scope.dart';
import 'chat_policy.dart';

class ChatBatchTask {
  final List<String> parts;
  final bool needsPeriod;
  String get question => parts
      .join(' ')
      .trim()
      .replaceFirst(
        RegExp(r'^(?:(?:and|also|plus|then)\s+)+', caseSensitive: false),
        '',
      );
  const ChatBatchTask(this.parts, {this.needsPeriod = false});
}

class ChatBatchLimit implements Exception {
  const ChatBatchLimit();
}

/// Literal compound syntax and temporal scope, independent of model inference.
class ChatBatchPlanner {
  static const maxTasks = 4;

  static bool _actionable(String text) =>
      ChatPlanConstraints.financialReference(text) ||
      ChatPlanConstraints.metric(text) != null ||
      ChatHelpCatalog.requestedTopic(text) != null ||
      ChatHelpCatalog.isCapabilityRequest(text) ||
      ChatScope.conversation(text, const []) != null ||
      RegExp(
        r'^(?:what|how|where|show|list|tell|give|explain|recommend|help)\b',
        caseSensitive: false,
      ).hasMatch(text);

  /// Literal syntax boundaries, never rewritten questions or generated values.
  /// Quoted names and continuations of an unquoted name keep their conjunction.
  static List<String> excerpts(String question) {
    final quotes = RegExp(r'"[^"\n]*"').allMatches(question).toList();
    final separators =
        RegExp(r'\b(?:and|also|plus|then)\b|[;\n]|,\s*', caseSensitive: false)
            .allMatches(question)
            .where(
              (m) => !quotes.any((q) => q.start <= m.start && m.end <= q.end),
            );
    final parts = <String>[];
    var start = 0;
    for (final separator in separators) {
      final next = question.substring(start, separator.start).trim();
      if (next.isNotEmpty) parts.add(next);
      start = separator.end;
    }
    final tail = question.substring(start).trim();
    if (tail.isNotEmpty) parts.add(tail);
    // Use original offsets to retain words such as "and" in merchant names.
    final result = <String>[];
    var search = 0;
    for (final part in parts) {
      final at = question.indexOf(part, search);
      if (result.isNotEmpty && !_actionable(part)) {
        final priorAt = question.lastIndexOf(result.last, at);
        result[result.length - 1] = question.substring(
          priorAt,
          at + part.length,
        );
      } else {
        result.add(part);
      }
      search = at + part.length;
    }
    return result;
  }

  static List<String> qualifiers(String question) {
    final quotes = RegExp(r'"[^"\n]*"').allMatches(question).toList();
    final pattern = RegExp(
      r'\b(?:\d{4}-\d{2}(?:-\d{2})?|(?:last|past|previous) \d{1,3} (?:days?|weeks?|months?|years?)|'
      '(?:in |during |for )?${ChatPolicy.monthNamePattern}'
      r'(?: \d{1,2}(?!\d))?(?: (?:19|20)[0-9]{2})?|'
      '${ChatPolicy.periodPattern})\\b',
      caseSensitive: false,
    );
    return pattern
        .allMatches(question)
        .where((m) => !quotes.any((q) => q.start <= m.start && m.end <= q.end))
        .map((m) => m[0]!)
        .toSet()
        .toList();
  }

  static int? referencedIndex(String question, int length) {
    final match = RegExp(
      r'\b(first|second|third|fourth|last) (?:one|part|result|request)\b',
      caseSensitive: false,
    ).firstMatch(question);
    if (match == null) return null;
    return match[1]!.toLowerCase() == 'last'
        ? length - 1
        : [
            'first',
            'second',
            'third',
            'fourth',
          ].indexOf(match[1]!.toLowerCase());
  }

  static bool isCandidate(String question) {
    // A conjunction inside a quoted entity is not another request.
    final text = question.replaceAll(RegExp(r'"[^"\n]*"'), 'quoted entity');
    final clauses = text
        .split(
          RegExp(
            r'\b(?:and|also|plus|then)\b|[;\n]|,\s*',
            caseSensitive: false,
          ),
        )
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (clauses.length < 2) return false;
    bool actionable(String s) =>
        ChatPlanConstraints.financialReference(s) ||
        ChatPlanConstraints.metric(s) != null ||
        ChatHelpCatalog.requestedTopic(s) != null ||
        ChatHelpCatalog.isCapabilityRequest(s) ||
        ChatScope.conversation(s, const []) != null ||
        RegExp(
          r'^(?:what|how|where|show|list|tell|give|explain|recommend|help)\b',
          caseSensitive: false,
        ).hasMatch(s);
    final requests = clauses.where(actionable).toList();
    if (requests.length < 2) return false;
    if (RegExp(
      r'\b(?:compare|versus|vs)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      final sources = requests
          .map(ChatPlanConstraints.source)
          .whereType<String>()
          .toSet();
      final types = requests
          .map(ChatPlanConstraints.type)
          .whereType<String>()
          .toSet();
      final metrics = requests
          .map(ChatPlanConstraints.metric)
          .whereType<String>()
          .toSet();
      final extraCommand = clauses
          .skip(1)
          .any(
            (s) => RegExp(
              r'^(?:what|how|where|show|list|tell|give|explain|recommend|help)\b',
              caseSensitive: false,
            ).hasMatch(s),
          );
      if (sources.length <= 1 &&
          types.length <= 1 &&
          metrics.length <= 1 &&
          !extraCommand) {
        return false;
      }
    }
    return true;
  }

  static List<ChatBatchTask> plan(String question) {
    final literal = excerpts(question);
    if (literal.length > maxTasks) throw const ChatBatchLimit();
    if (literal.length < 2) {
      throw const FormatException('No clear request boundaries');
    }
    final dates = qualifiers(question);
    final transactions = [
      for (var i = 0; i < literal.length; i++)
        if (ChatPlanConstraints.source(literal[i]) == 'transactions' &&
            ChatPlanConstraints.type(literal[i]) != null)
          i,
    ];
    final newClause = RegExp(
      r'^(?:what|how|where|which|show|list|tell|give|explain|can|could|would|do|does|is|are)\b',
      caseSensitive: false,
    );
    // A trailing modifier binds a coordinated noun phrase (income and expenses
    // in June). Separate finite questions have separate scope and need dates.
    final shared =
        dates.length == 1 &&
        transactions.length > 1 &&
        literal[transactions.last]
            .replaceAll(RegExp(r'[?.!]+$'), '')
            .trim()
            .endsWith(dates.single) &&
        transactions.skip(1).every((i) => !newClause.hasMatch(literal[i]));
    return [
      for (var i = 0; i < literal.length; i++)
        ChatBatchTask(
          List.unmodifiable([
            literal[i],
            if (shared &&
                transactions.contains(i) &&
                qualifiers(literal[i]).isEmpty)
              dates.single,
          ]),
          needsPeriod:
              !shared &&
              dates.isNotEmpty &&
              transactions.contains(i) &&
              qualifiers(literal[i]).isEmpty &&
              !ChatPlanConstraints.hasScopeReference(literal[i]),
        ),
    ];
  }
}
