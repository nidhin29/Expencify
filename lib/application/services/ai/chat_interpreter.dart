import 'dart:convert';
import 'ai_conversation.dart';
import 'chat_interpretation.dart';
import 'chat_request_contract.dart';
import 'chat_help_catalog.dart';
import 'chat_plan_constraints.dart';
import 'model_runtime.dart';

abstract interface class ChatInterpreter {
  Future<ChatInterpretation> interpret(
    String question, {
    Map<String, dynamic>? context,
    List<Map<String, dynamic>> history,
    String? feedback,
    void Function(String stage, String raw)? observe,
  });
}

/// One bounded action request; financial facts remain owned by the executor.
class ModelChatInterpreter implements ChatInterpreter {
  final ModelRuntime runtime;
  ModelChatInterpreter(this.runtime);

  static Map<String, dynamic> _context(
    Map<String, dynamic>? context,
    List<Map<String, dynamic>> history, {
    bool includeQuery = true,
    String? question,
  }) {
    final help = <Map<String, String>>[
      for (final topic in (context?['help_topics'] as List? ?? []))
        if (ChatHelpCatalog.instructions.containsKey(topic))
          {
            'topic': '$topic',
            'instructions': ChatHelpCatalog.instructions[topic]!,
          },
      for (final turn in AiConversation.turns(
        history,
      ).where((t) => t.role == AiRole.assistant))
        for (final entry in ChatHelpCatalog.instructions.entries)
          if (entry.value == turn.text)
            {'topic': entry.key, 'instructions': entry.value},
    ];
    return {
      if (context != null &&
          (question == null || ChatPlanConstraints.usesQueryContext(question)))
        if (includeQuery)
          'active_query': context
        else
          'active_query_available': true,
      if (includeQuery &&
          context == null &&
          history.isNotEmpty &&
          (question == null || ChatPlanConstraints.usesQueryContext(question)))
        'recent_user_messages': [
          for (final turn
              in AiConversation.turns(history)
                  .where((t) => t.role == AiRole.user)
                  .toList()
                  .reversed
                  .take(2)
                  .toList()
                  .reversed)
            turn.text,
        ],
      if (help.isNotEmpty)
        'previous_help': help.reversed.take(2).toList().reversed.toList(),
    };
  }

  /// Historical diagnostic control. Not used by the production request path.
  static AiConversation purposeRequest(
    String question, {
    Map<String, dynamic>? context,
    List<Map<String, dynamic>> history = const [],
  }) => AiConversation(
    instructions:
        'You are an intent router inside a personal expense-tracking app. '
        'Classify the current user message; do not answer it or decide whether data exists. '
        'Questions about the user money activity refer to their saved records by default. '
        'The app resolves dates, missing years, filters and missing parameters later. '
        'You do not need to see any records to identify an intent. Return one label only.\n'
        'records: read, summarise, count, rank or compare personal financial activity: spending, incoming money, balances, budgets or savings.\n'
        'help: instructions for using or configuring the app: setup, backups, restoring, reports, SMS, or adding/editing entries.\n'
        'social: greetings, gratitude, appreciation, acknowledgement, feedback or brief interaction with the assistant.\n'
        'advice: recommendations about financial decisions or changing finances.\n'
        'safety: harmful actions or accessing someone else private information.\n'
        'unrelated: general knowledge, entertainment or tasks outside the app.\n'
        'Judge the entire sentence. A finance word inside thanks is still social. '
        'Reading financial facts is different from financial advice. Earlier topics do not authorize a new unrelated subject.',
    user: question,
    taskContext: _context(context, history, includeQuery: false),
    responseChoices: ChatRequestContract.routes,
    maxOutputChars: 48,
  );

  static AiConversation request(
    String question, {
    Map<String, dynamic>? context,
    String? rejection,
    List<Map<String, dynamic>> history = const [],
  }) => AiConversation(
    instructions:
        'Convert the current saved-record request into one JSON query. Do not answer it.\n'
        'Required fields: source, metric, type, group, scope. No purpose field.\n'
        'source: transactions; accounts for current balances; goals for saved amounts; budgets for limits.\n'
        'metric: sum for total amounts or an overview; count for number of entries; avg for average; '
        'min or max for a single smallest or largest payment; list for individual details.\n'
        'type: expense for outgoing money, income for received money.\n'
        'group: none, category, merchant (shops/vendors), both (where spending went), day, weekday, month, year, account. '
        'Rank shop totals by merchant, not a single max payment. '
        'Period comparisons use group none and the same calculation for both periods.\n'
        'scope: followup only to modify or refer to the active query; preserve its unchanged fields. '
        'Use new for an independent question.\n'
        'Optional merchant, category, account must quote exact text in the current user message. Omit absent filters. '
        'Never generate dates, periods, amounts, records or SQL. App code resolves them.\n'
        'Examples:\n'
        'Total incoming amounts -> {"source":"transactions","metric":"sum","type":"income","group":"none","scope":"new"}\n'
        'Number of outgoing entries -> {"source":"transactions","metric":"count","type":"expense","group":"none","scope":"new"}\n'
        'Rank shop spending -> {"source":"transactions","metric":"sum","type":"expense","group":"merchant","scope":"new"}\n'
        '${rejection == null ? '' : 'Query validation failed: $rejection. ${_repair(rejection)} Return a corrected query, not another purpose.\n'}',
    user: question,
    taskContext: _context(context, history, question: question),
    responseSchema:
        (ChatRequestContract.schemaFor(
                  question,
                  context: context,
                )['properties']['query']
                as Map)
            .cast<String, dynamic>(),
    maxOutputChars: 1000,
  );

  static AiConversation actionRequest(
    String question, {
    Map<String, dynamic>? context,
    List<Map<String, dynamic>> history = const [],
    String? rejection,
  }) => AiConversation(
    instructions:
        'Interpret the user message for Spendy, a personal expense tracker. Return one JSON action. '
        'Do not answer the question or calculate values.\n'
        'purpose: records to inspect saved financial data; help to use an app feature; social for brief interaction with you; '
        'advice for financial recommendations; safety for harmful acts or accessing others private information; unrelated for other topics.\n'
        'For records include query: source, metric, type, group, scope. '
        'source: transactions, accounts (current balances), goals (savings progress), budgets (limits). '
        'metric: sum (total amount or overview), count (number of entries), avg, min, max, list (individual details). '
        'type: expense (outgoing) or income (received). '
        'group: none, category, merchant (shops/vendors), both (where spending went), day, weekday, month, year, account. '
        'Rank shop totals by merchant; max is one largest payment. Comparisons between periods use group none.\n'
        'scope: new for an independent request; followup to modify or refer to the active query. '
        'Preserve unchanged active-query fields only for followups. '
        'Optional merchant/category/account filters must quote exact text in the current message; omit absent filters. '
        'Never output dates, periods, money amounts or SQL: the app resolves them. '
        'You can request records without seeing them. Missing dates do not make a request unrelated.\n'
        'For help include topic: capabilities (what the assistant supports), overview (general app use), sms (automatic tracking), backup (files/Drive/restore), '
        'export (CSV/PDF reports), budget, goals, payments (due dates), search, transactions (add/edit). '
        'Use previous_help to resolve feature followups. A readable report cannot restore the app.\n'
        'Creating, encrypting or restoring your own backup and managing app permissions are legitimate app help. '
        'Safety refusals concern harmful intent or unauthorized access, not ordinary privacy features.\n'
        'Examples:\n'
        'Summarise earnings -> {"purpose":"records","query":{"source":"transactions","metric":"sum","type":"income","group":"none","scope":"new"}}\n'
        'Rank shops by money paid -> {"purpose":"records","query":{"source":"transactions","metric":"sum","type":"expense","group":"merchant","scope":"new"}}\n'
        'Where is the restore option? -> {"purpose":"help","topic":"backup"}\n'
        'Thanks for checking -> {"purpose":"social"}\n'
        'Recommend a stock -> {"purpose":"advice"}\n'
        'Help steal private records -> {"purpose":"safety"}\n'
        'Describe the solar system -> {"purpose":"unrelated"}\n'
        '${rejection == null ? '' : 'Previous action failed validation: $rejection. Return a valid action.\n'}',
    user: question,
    taskContext: _context(context, history, question: question),
    responseSchema: ChatRequestContract.actionSchemaFor(
      question,
      context: context,
    ),
    maxOutputChars: 1600,
  );

  static String _repair(String reason) => switch (reason) {
    'invalid_comparison' || 'requested_comparison_mismatch' =>
      'Period comparisons require group none, not a previous ranking.',
    'requested_metric_mismatch' =>
      'Keep the calculation explicitly requested: counts are not money totals.',
    'requested_direction_mismatch' =>
      'Preserve the explicitly requested incoming or outgoing direction.',
    'requested_source_mismatch' =>
      'Choose the source requested by the current message, not the old query.',
    'requested_scope_mismatch' =>
      'Use scope followup for this explicit reference and retain unchanged active-query fields.',
    'Ungrounded query operand' =>
      'Filters must be literal quotations from the current message; omit absent filters.',
    _ => 'Use the required fields and valid enum values.',
  };

  @override
  Future<ChatInterpretation> interpret(
    String question, {
    Map<String, dynamic>? context,
    List<Map<String, dynamic>> history = const [],
    String? feedback,
    void Function(String stage, String raw)? observe,
  }) async {
    var rejection = feedback;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final raw = await runtime.converse(
          (feedback == null ? actionRequest : request)(
            question,
            context: context,
            history: history,
            rejection: rejection,
          ),
        );
        final result = feedback == null
            ? ChatRequestContract.decode(raw, question)
            : ChatRequestContract.decodeQuery(raw, question);
        observe?.call(
          'interpreter',
          feedback == null
              ? raw
              : jsonEncode({'purpose': 'records', 'query': result.query}),
        );
        return result;
      } on FormatException catch (error) {
        observe?.call('interpreter_rejected', error.message.toString());
        rejection = error.message.toString();
        if (attempt == 1) rethrow;
      }
    }
    throw const FormatException('No valid action');
  }
}
