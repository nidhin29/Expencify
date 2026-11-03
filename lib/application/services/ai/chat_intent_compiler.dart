import 'package:intl/intl.dart';
import '../../../infrastructure/database/database_helper.dart';
import 'ai_guardrails.dart';
import 'chat_facts.dart';
import 'chat_policy.dart';
import 'chat_plan_constraints.dart';
import 'chat_scope_delta.dart';
import 'chat_interpretation.dart';

/// The model chooses four enums. Dates, names and amounts come from the request
/// and local catalog, never model-generated records or numeric values.
class ChatIntentCompiler {
  final DatabaseHelper helper;
  final DateTime now;
  ChatIntentCompiler(this.helper, this.now);

  Future<Map<String, dynamic>> compile(
    Map intent,
    String question,
    List<Map<String, dynamic>> history, {
    Map<String, dynamic>? previousPlan,
    ChatOperation? interpretation,
    Map<String, dynamic>? semanticRequest,
  }) async {
    question = ChatPlanConstraints.queryBody(question);
    if (RegExp(
      r'\b(not|excluding|exclude|except|without)\b',
      caseSensitive: false,
    ).hasMatch(question)) {
      return {'status': 'clarify', 'reason': 'records'};
    }
    if (intent.keys.any(
      (k) => !{
        'source',
        'metric',
        'group',
        'type',
        'followup',
        'category',
        'merchant',
        // Redundant operand hints are tolerated but never used. Dates and
        // limits are resolved exclusively from user text and app-owned scope.
        'from', 'to', 'day', 'limit',
      }.contains(k),
    )) {
      throw const FormatException('Unknown intent field');
    }
    if (intent['followup'] != null && intent['followup'] is! bool) {
      throw const FormatException('Invalid continuation flag');
    }
    final continuing = semanticRequest != null
        ? semanticRequest['scope'] == 'followup'
        : ChatPlanConstraints.isFollowup(question) ||
              intent['followup'] == true ||
              ChatPlanConstraints.needsPriorScope(question);
    if (semanticRequest != null &&
        !continuing &&
        ChatPlanConstraints.hasScopeReference(question)) {
      if (previousPlan == null &&
          ChatPlanConstraints.previousQuestion(question, history).isEmpty) {
        return {'status': 'clarify', 'reason': 'period'};
      }
      throw const FormatException('Requested scope was dropped');
    }
    final priorQueries = previousPlan?['queries'];
    final prior = continuing ? _sharedScope(priorQueries) : <String, dynamic>{};
    if (ChatPlanConstraints.hasScopeReference(question) &&
        prior.isEmpty &&
        ChatPlanConstraints.previousQuestion(question, history).isEmpty) {
      return {'status': 'clarify', 'reason': 'period'};
    }
    if (continuing &&
        priorQueries is List &&
        priorQueries.length > 1 &&
        prior.isEmpty) {
      return {'status': 'clarify', 'reason': 'records'};
    }
    // Resolved state replaces raw previous wording so a three-turn follow-up
    // retains filters while a changed month does not revive an older date.
    final previous = prior.isEmpty && (semanticRequest == null || continuing)
        ? ChatPlanConstraints.previousQuestion(question, history)
        : '';
    if (intent['followup'] == true && prior.isEmpty && previous.isEmpty) {
      return {'status': 'clarify', 'reason': 'question'};
    }
    // Reject an unrelated model-selected operation before opening the ledger.
    // The complete permission check below also handles literal catalog filters.
    if (semanticRequest == null &&
        !ChatPlanConstraints.financialReference(question) &&
        ChatPlanConstraints.metric(question) == null &&
        ChatPlanConstraints.group(question) == null &&
        !ChatPlanConstraints.hasScopeReference(question) &&
        !ChatScopeDelta.periodOnly(question)) {
      return {'status': 'clarify', 'reason': 'records'};
    }
    final source =
        interpretation?.source ??
        ChatPlanConstraints.source(question) ??
        ChatPlanConstraints.source(previous) ??
        prior['source'] ??
        intent['source'];
    final refusal = ChatPolicy.unsafeOrAdviceReply(question);
    if (refusal != null) {
      return {
        'status': refusal == ChatPolicy.adviceReply ? 'advice' : 'unsupported',
      };
    }
    if (ChatPlanConstraints.missingPeriodContext(question, history)) {
      return {'status': 'clarify', 'reason': 'period'};
    }
    if (source == 'unsupported') return {'status': 'unsupported'};
    if (source == 'clarify') return {'status': 'clarify', 'reason': 'question'};
    final explicitType =
        ChatPlanConstraints.type(question) ??
        ChatPlanConstraints.type(previous) ??
        prior['type'] as String?;
    if (interpretation != null &&
        source == 'transactions' &&
        explicitType != null &&
        interpretation.type != explicitType) {
      throw const FormatException('Requested direction was dropped');
    }
    if (source == 'transactions' &&
        interpretation == null &&
        explicitType == null &&
        intent['type'] == 'income') {
      return {'status': 'clarify', 'reason': 'type'};
    }
    final newGrouping =
        ChatPlanConstraints.group(question) != null &&
        !ChatPlanConstraints.isFollowup(question) &&
        !ChatPlanConstraints.hasScopeReference(question);
    final metric =
            interpretation?.metric ??
            ChatPlanConstraints.metric(question) ??
            (newGrouping ? 'sum' : null) ??
            intent['metric'] ??
            ChatPlanConstraints.metric(previous) ??
            prior['metric'] ??
            'sum',
        type = source == 'transactions'
            ? interpretation?.type ??
                  explicitType ??
                  intent['type'] ??
                  'expense'
            : 'expense';
    final requestedGroup =
        ChatPlanConstraints.group(question) ??
        ChatPlanConstraints.group(previous) ??
        prior['group'] as String?;
    var group =
        interpretation?.group ?? requestedGroup ?? intent['group'] ?? 'none';
    final wantsGroups = RegExp(
      r'\b(by|per|breakdown|break down|which|where|categories|merchants|distribution)\b',
      caseSensitive: false,
    ).hasMatch(question);
    if (interpretation == null && requestedGroup == null && !wantsGroups) {
      group = 'none';
    }
    if (interpretation == null &&
        requestedGroup == null &&
        RegExp(r'\bcompare\b', caseSensitive: false).hasMatch(question) &&
        !wantsGroups) {
      group = 'none';
    }
    if (!{'transactions', 'accounts', 'goals', 'budgets'}.contains(source) ||
        !{'sum', 'count', 'avg', 'min', 'max', 'list'}.contains(metric) ||
        !{
          'none',
          'category',
          'merchant',
          'both',
          'day',
          'weekday',
          'month',
          'year',
          'account',
        }.contains(group) ||
        !{'expense', 'income'}.contains(type)) {
      throw const FormatException('Invalid intent enum');
    }
    var windows = _windows(question);
    final allTime = RegExp(
      r'\ball[ -]time\b',
      caseSensitive: false,
    ).hasMatch(question);
    if (!allTime &&
        windows.isEmpty &&
        prior['source'] == source &&
        prior['from'] is String &&
        prior['to'] is String) {
      final end = AiGuardrails.strictDate(prior['to'] as String);
      windows = [
        ChatWindow(
          AiGuardrails.strictDate(prior['from'] as String),
          DateTime(end.year, end.month, end.day + 1),
          '',
        ),
      ];
    }
    if (!allTime && windows.isEmpty && previous.isNotEmpty) {
      windows = _windows(previous);
    }
    if (source == 'transactions' &&
        !allTime &&
        windows.isEmpty &&
        ['from', 'to', 'day'].any((key) => intent[key] != null)) {
      return {'status': 'clarify', 'reason': 'period'};
    }
    if (windows.isEmpty &&
        RegExp(
          r'\b(quarter|fortnight|weekend|monday|tuesday|wednesday|thursday|friday|saturday|sunday|ago|since|before|after)\b',
          caseSensitive: false,
        ).hasMatch(question)) {
      return {'status': 'clarify', 'reason': 'period'};
    }
    if (source != 'transactions' && windows.isNotEmpty) {
      return {'status': 'unsupported'};
    }
    final filters = await _names(question, source as String);
    for (final key in ['merchant', 'category', 'account']) {
      final requested = semanticRequest?[key];
      if (requested == null) continue;
      if (requested is! String ||
          !(filters[key] ?? <String>[]).any(
            (name) => name.toLowerCase() == requested.toLowerCase(),
          )) {
        return {
          'status': 'clarify',
          'reason': key == 'account' ? 'records' : key,
        };
      }
    }
    if (filters['category'] != null) {
      final known = await (await helper.database).rawQuery(
        'SELECT name FROM categories UNION SELECT DISTINCT category AS name FROM transactions',
      );
      if (filters['category']!.any(
        (name) => !known.any(
          (r) => '${r['name']}'.toLowerCase() == name.toLowerCase(),
        ),
      )) {
        return {'status': 'clarify', 'reason': 'category'};
      }
    }
    // The model's default intent alone does not authorize a ledger query.
    // Require a financial reference, a literal local entity, or resolved context.
    if (semanticRequest == null &&
        !ChatPlanConstraints.financialReference(question) &&
        filters.isEmpty &&
        prior.isEmpty &&
        previous.isEmpty) {
      return {'status': 'clarify', 'reason': 'records'};
    }
    if (intent['merchant'] != null &&
        (intent['merchant'] is! String ||
            !(filters['merchant'] ?? <String>[]).any(
              (m) => m.toLowerCase() == '${intent['merchant']}'.toLowerCase(),
            ))) {
      return {'status': 'clarify', 'reason': 'merchant'};
    }
    if (intent['category'] != null &&
        (filters['merchant'] == null || filters['category'] != null)) {
      final category = intent['category'];
      if (category is! String ||
          category.length > 100 ||
          !{'transactions', 'budgets'}.contains(source)) {
        throw const FormatException('Invalid category selection');
      }
      final known = await (await helper.database).rawQuery(
        'SELECT name FROM categories WHERE LOWER(name)=LOWER(?) LIMIT 1',
        [category],
      );
      if (known.isEmpty) {
        throw const FormatException('Unknown category selection');
      }
      filters.putIfAbsent('category', () => ['${known.single['name']}']);
    }
    final oldFilters = previous.isEmpty
        ? <String, List<String>>{}
        : await _names(previous, source);
    for (final entry in oldFilters.entries) {
      filters.putIfAbsent(entry.key, () => entry.value);
    }
    if (prior['source'] == source) {
      for (final key in ['merchant', 'category', 'account']) {
        if (prior[key] is String) {
          filters.putIfAbsent(key, () => [prior[key] as String]);
        }
      }
    }
    if (source != 'transactions') filters.remove('merchant');
    if (!{'transactions', 'budgets'}.contains(source)) {
      filters.remove('category');
    }
    final text = question.toLowerCase();
    var limit =
        prior['limit'] as int? ??
        ({'day', 'weekday', 'month', 'year'}.contains(group) ? 10 : 5);
    final count = RegExp(
      r'\b(?:top|latest|recent|first|last|show|list|which|my)\s+(?:my\s+)?(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten)\b',
    ).firstMatch(text);
    if (count != null) {
      limit = AiGuardrails.numbers(count.group(1)!).single.toInt().clamp(1, 10);
    }
    final base = <String, dynamic>{'source': source, 'metric': metric};
    if (prior['source'] == source) {
      for (final key in [
        'amount_lt',
        'amount_gt',
        'limit',
        'order',
        'sort',
        'period',
      ]) {
        if (prior.containsKey(key)) base[key] = prior[key];
      }
    }
    if (source == 'transactions') base['type'] = type;
    if (allTime || windows.isNotEmpty) base.remove('period');
    if (group != 'none' && group != 'both') base['group'] = group;
    if (group != 'none' || metric == 'list') base['limit'] = limit;
    if (metric == 'list') {
      base['order'] =
          RegExp(
            r'\b(largest|biggest|smallest|highest|lowest)\b',
          ).hasMatch(text)
          ? 'amount'
          : prior['order'] ?? 'date';
    }
    if (RegExp(r'\b(earliest|oldest|lowest|least|smallest)\b').hasMatch(text) &&
        (group != 'none' || metric == 'list')) {
      base['sort'] = 'asc';
    }
    final evidence = '$previous $question';
    for (final (pattern, key) in [
      (r'\b(?:under|below|less than)\s+(?:rs\.?\s*|₹\s*)?', 'amount_lt'),
      (
        r'\b(?:over|above|greater than|more than)\s+(?:rs\.?\s*|₹\s*)?',
        'amount_gt',
      ),
    ]) {
      final matches = RegExp(
        pattern,
        caseSensitive: false,
      ).allMatches(evidence).toList();
      if (matches.isNotEmpty) {
        final tail = evidence
            .substring(matches.last.end)
            .split(RegExp(r'\b(in|during|for|on)\b'))
            .first;
        final numbers = AiGuardrails.numbers(tail);
        if (numbers.isNotEmpty) base[key] = numbers.first;
      }
    }
    for (final entry in filters.entries) {
      if (entry.value.length == 1) base[entry.key] = entry.value.single;
    }
    List<Map<String, dynamic>> queries;
    final multiple = filters.entries.where((e) => e.value.length > 1).toList();
    if (multiple.isNotEmpty) {
      if (multiple.length > 1 || windows.length > 1) {
        return {'status': 'clarify', 'reason': 'question'};
      }
      queries = multiple.single.value
          .map((name) => {...base, multiple.single.key: name})
          .toList();
    } else {
      queries = windows.isEmpty
          ? [base]
          : windows
                .map(
                  (w) => {
                    ...base,
                    'from': _date(w.from),
                    'to': _date(w.until.subtract(const Duration(days: 1))),
                  },
                )
                .toList();
    }
    if (multiple.isNotEmpty && windows.isNotEmpty) {
      for (final query in queries) {
        query.addAll({
          'from': _date(windows.single.from),
          'to': _date(windows.single.until.subtract(const Duration(days: 1))),
        });
      }
    }
    if (group == 'both') {
      if (queries.length != 1) {
        return {'status': 'clarify', 'reason': 'category'};
      }
      queries = [
        {...queries.single, 'group': 'category'},
        {...queries.single, 'group': 'merchant'},
      ];
    }
    return {
      'queries': queries,
      if (queries.length == 2 &&
          group != 'both' &&
          (windows.length == 2 || multiple.isNotEmpty))
        'compare': true,
    };
  }

  String _date(DateTime value) => DateFormat('yyyy-MM-dd').format(value);

  /// A breakdown can contain both category and merchant queries. A follow-up
  /// may inherit their shared scope, never arbitrarily choose one of two
  /// different periods/accounts. Do not carry one group's labels to the other.
  static Map<String, dynamic> _sharedScope(Object? queries) {
    if (queries is! List || queries.isEmpty || queries.any((q) => q is! Map)) {
      return {};
    }
    final shared = Map<String, dynamic>.from(queries.first as Map);
    final keys = queries.cast<Map>().expand((q) => q.keys).toSet()
      ..remove('group');
    if (queries
        .skip(1)
        .cast<Map>()
        .any(
          (q) => keys.any(
            (key) =>
                q.containsKey(key) != shared.containsKey(key) ||
                q[key] != shared[key],
          ),
        )) {
      return {};
    }
    for (final q in queries.skip(1).cast<Map>()) {
      shared.removeWhere(
        (key, value) => !q.containsKey(key) || q[key] != value,
      );
    }
    // Different sources or date ranges require clarification, not an all-time
    // replacement of the comparison the user was looking at.
    if (queries.length > 1 &&
        !['source', 'from', 'to'].every(shared.containsKey)) {
      return {};
    }
    return shared;
  }

  List<ChatWindow> _windows(String question) {
    var text = question.toLowerCase();
    final comparison = text.indexOf('compare ');
    if (comparison >= 0) text = text.substring(comparison + 8);
    final windows = <ChatWindow>[];
    final iso = RegExp(r'\b\d{4}-\d{2}-\d{2}\b').allMatches(text);
    for (final match in iso) {
      final date = AiGuardrails.strictDate(match.group(0)!);
      windows.add(
        ChatWindow(date, DateTime(date.year, date.month, date.day + 1), ''),
      );
    }
    if (windows.isEmpty) {
      for (final match in RegExp(
        r'\b((?:19|20)[0-9]{2})-(0[1-9]|1[0-2])\b(?!-\d)',
      ).allMatches(text)) {
        final year = int.parse(match.group(1)!),
            month = int.parse(match.group(2)!);
        windows.add(
          ChatWindow(DateTime(year, month), DateTime(year, month + 1), ''),
        );
      }
    }
    if (windows.isEmpty) {
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
      final named = RegExp(
        '\\b(${ChatPolicy.monthNamePattern})(?: (\\d{1,2})(?=\\s|\\b))?(?: ((?:19|20)[0-9]{2}))?\\b',
      ).allMatches(text);
      for (final match in named) {
        final month = months.indexOf(match.group(1)!.substring(0, 3)) + 1;
        final year = int.tryParse(match.group(3) ?? '') ?? now.year;
        final day = int.tryParse(match.group(2) ?? '');
        final from = day == null
            ? DateTime(year, month)
            : AiGuardrails.strictDate(
                '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
              );
        windows.add(
          ChatWindow(
            from,
            day == null
                ? DateTime(year, month + 1)
                : DateTime(year, month, day + 1),
            '',
          ),
        );
      }
    }
    if (windows.isEmpty) {
      if (RegExp(r'\btomorrow\b').hasMatch(text)) {
        windows.add(
          ChatWindow(
            DateTime(now.year, now.month, now.day + 1),
            DateTime(now.year, now.month, now.day + 2),
            '',
          ),
        );
      }
      final rolling = RegExp(
        r'\blast (\d{1,3}) (days?|weeks?|months?|years?)\b',
      ).firstMatch(text);
      if (rolling != null) {
        final n = int.parse(rolling.group(1)!);
        if (n < 1) throw const FormatException('Invalid dates');
        final unit = rolling.group(2)!;
        final from = unit.startsWith('day')
            ? DateTime(now.year, now.month, now.day - n + 1)
            : unit.startsWith('week')
            ? DateTime(now.year, now.month, now.day - 7 * n + 1)
            : unit.startsWith('month')
            ? DateTime(now.year, now.month - n, now.day)
            : DateTime(now.year - n, now.month, now.day);
        windows.add(
          ChatWindow(from, DateTime(now.year, now.month, now.day + 1), ''),
        );
      }
    }
    if (windows.isEmpty) {
      for (final match in RegExp(
        r'\b(today|yesterday|this month|last month|this week|last week|this year|last year|all time)\b',
      ).allMatches(text)) {
        windows.add(ChatWindow.forQuery(match.group(0)!, now));
      }
    }
    if (windows.isEmpty) {
      for (final match in RegExp(
        r'\b(?:in|during|for|year|and|then|compare) ((?:19|20)[0-9]{2})\b',
      ).allMatches(text)) {
        final year = int.parse(match.group(1)!);
        windows.add(ChatWindow(DateTime(year), DateTime(year + 1), ''));
      }
    }
    final unique = <String, ChatWindow>{
      for (final w in windows) '${w.from}:${w.until}': w,
    }.values.toList();
    if (unique.length == 2 &&
        RegExp(r'\b(from|between|through|until)\b').hasMatch(text) &&
        comparison < 0) {
      return [ChatWindow(unique.first.from, unique.last.until, '')];
    }
    if (unique.length == 1) {
      if (RegExp(r'\bsince\b').hasMatch(text)) {
        return [
          ChatWindow(
            unique.single.from,
            DateTime(now.year, now.month, now.day + 1),
            '',
          ),
        ];
      }
      if (RegExp(r'\bbefore\b').hasMatch(text)) {
        return [ChatWindow(DateTime(1900), unique.single.from, '')];
      }
      if (RegExp(r'\bafter\b').hasMatch(text)) {
        return [
          ChatWindow(
            unique.single.until,
            DateTime(now.year, now.month, now.day + 1),
            '',
          ),
        ];
      }
    }
    return unique;
  }

  Future<Map<String, List<String>>> _names(
    String question,
    String source,
  ) async {
    final db = await helper.database;
    // Axis words describe a view, not a merchant/category with the same name.
    final lookupQuestion = question.replaceAll(
      RegExp(
        r'\b(?:by|per)[ -]+(?:categor(?:y|ies)|merchants?|shops?|stores?|dates?|days?|weekdays?|months?|years?|accounts?)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    final text = lookupQuestion.toLowerCase();
    bool contains(String name) =>
        name.trim().length > 1 &&
        RegExp('\\b${RegExp.escape(name.toLowerCase())}\\b').hasMatch(text);
    final found = <String, List<String>>{};
    final merchants = await db.rawQuery(
      'SELECT DISTINCT merchant FROM transactions WHERE LENGTH(merchant)>1 AND INSTR(LOWER(?),LOWER(merchant))>0 LIMIT 10',
      [lookupQuestion],
    );
    final merchantNames = merchants
        .map((r) => '${r['merchant']}')
        .where(contains)
        .toList();
    if (merchantNames.isNotEmpty) found['merchant'] = merchantNames;
    final categories = await db.query('categories', columns: ['name']);
    merchantNames.removeWhere(
      (m) =>
          categories.any(
            (c) => '${c['name']}'.toLowerCase() == m.toLowerCase(),
          ) &&
          !RegExp(
            '\\b(?:to|at|merchant) ${RegExp.escape(m.toLowerCase())}\\b',
          ).hasMatch(text),
    );
    if (merchantNames.isEmpty) found.remove('merchant');
    final names = categories
        .map((r) => '${r['name']}')
        .where(
          (n) =>
              contains(n) &&
              !merchantNames.any(
                (m) => m.toLowerCase().contains(n.toLowerCase()),
              ),
        )
        .toList();
    if (names.isNotEmpty) found['category'] = names;
    final accounts = await db.query('accounts', columns: ['name', 'bank_name']);
    final aliases = <String>{};
    for (final row in accounts) {
      for (final value in [
        '${row['name'] ?? ''}',
        '${row['bank_name'] ?? ''}',
      ]) {
        final alias = value
            .replaceAll(
              RegExp(r'\b(my|bank|account)\b', caseSensitive: false),
              '',
            )
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (contains(alias) &&
            (alias.toLowerCase() != 'cash' ||
                RegExp(
                  r'\b(?:from|in|my) cash\b|\bcash (?:wallet|account)\b',
                ).hasMatch(text))) {
          aliases.add(alias);
        }
      }
    }
    if (aliases.isNotEmpty) found['account'] = aliases.toList();
    String? literal(String pattern) {
      final match = RegExp(
        pattern,
        caseSensitive: false,
      ).firstMatch(lookupQuestion);
      final name = match?.group(1)?.trim().replaceAll(RegExp(r'[?!.]+$'), '');
      if (name == null ||
          name.isEmpty ||
          name.length > 100 ||
          RegExp(r'^(?:19|20)\d{2}$').hasMatch(name) ||
          _windows(name).isNotEmpty) {
        return null;
      }
      return name;
    }

    if (source == 'accounts') {
      final name = literal(
        r'\b(?:at|from|account named|bank named)\s+(.+?)(?=\s+(?:in|during|for|on)\b|[?!.;,]|$)',
      );
      if (name != null) found['account'] = [name];
    }
    if (source == 'transactions' && !found.containsKey('account')) {
      final name = literal(
        r'\b(?:to|at|merchant named|merchant called)\s+(.+?)(?=\s+(?:in|during|for|on)\b|[?!.;,]|$)',
      );
      if (name != null) found['merchant'] = [name];
    }
    if (source == 'transactions') {
      final name = literal(
        r'\bfrom\s+(?:my\s+)?(.+?)(?=\s+(?:in|during|for|on)\b|[?!.;,]|$)',
      );
      if (name != null &&
          !RegExp(
            r'^(me|us|them|you|myself)\b',
            caseSensitive: false,
          ).hasMatch(name)) {
        found[ChatPlanConstraints.type(question) == 'income'
            ? 'merchant'
            : 'account'] = [
          name.replaceAll(
            RegExp(r'\s+account(?: only)?$', caseSensitive: false),
            '',
          ),
        ];
      }
    }
    if (!found.containsKey('merchant') &&
        !found.containsKey('account') &&
        {'transactions', 'budgets'}.contains(source)) {
      final name = literal(
        ChatPlanConstraints.group(question) == null
            ? r'\b(?:on|for|category named|category called)\s+(.+?)(?=\s+(?:in|during|for|on)\b|[?!.;,]|$)'
            : r'\b(?:on|category named|category called)\s+(.+?)(?=\s+(?:in|during|for|on)\b|[?!.;,]|$)',
      );
      if (name != null &&
          !RegExp(
            r'^(all|each|every)\b',
            caseSensitive: false,
          ).hasMatch(name)) {
        found['category'] = [name];
      }
    }
    return found;
  }
}
