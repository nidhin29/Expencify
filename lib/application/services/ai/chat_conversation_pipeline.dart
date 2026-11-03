import '../chat/chat_query_context_store.dart';
import 'ai_conversation.dart';
import 'chat_debug.dart';
import 'chat_help_catalog.dart';
import 'chat_interpretation.dart';
import 'chat_interpreter.dart';
import 'chat_narrator.dart';
import 'chat_policy.dart';
import 'chat_record_executor.dart';
import 'chat_reply_status.dart';
import 'chat_scope.dart';
import 'chat_small_talk.dart';
import 'model_runtime.dart';
import 'chat_evidence.dart';
import 'chat_query_engine.dart';
import 'chat_plan_constraints.dart';
import 'chat_batch_planner.dart';
import 'chat_scope_delta.dart';
import 'dart:convert';

/// Model selection/formatting live below the interpreter; SQL/amounts live in
/// the executor. This coordinator records handoffs, never changes model intent.
class ChatConversationPipeline {
  final ChatInterpreter interpreter;
  final ChatRecordExecutor executor;
  final ChatQueryContextStore contexts;
  final ModelRuntime runtime;
  ChatConversationPipeline({
    required this.interpreter,
    required this.executor,
    required this.contexts,
    required this.runtime,
  });

  bool _nonRecordReply(String question, String reply) =>
      ChatHelpCatalog.instructions.containsValue(reply) ||
      ChatPolicy.unsafeOrAdviceReply(question) != null ||
      ChatScope.conversation(question, const []) != null;

  Future<String> answer(
    String question, {
    int? accountId,
    required List<Map<String, dynamic>> history,
    required ChatDebug debug,
    void Function(ChatEvidence)? observeEvidence,
    void Function(Map<String, dynamic>)? observePlan,
    void Function(String)? observeDraft,
  }) async {
    if (!ChatBatchPlanner.isCandidate(question)) {
      return _answerSingle(
        question,
        accountId: accountId,
        history: history,
        debug: debug,
        observeEvidence: observeEvidence,
        observePlan: observePlan,
        observeDraft: observeDraft,
      );
    }
    List<ChatBatchTask> tasks;
    try {
      tasks = ChatBatchPlanner.plan(question);
      debug.log('batch_split', {'parts': tasks.length});
    } on ChatBatchLimit {
      return 'Please ask up to ${ChatBatchPlanner.maxTasks} requests at a time. No parts were processed.';
    } on FormatException {
      return 'Please ask these as separate questions so I can check every part accurately. No parts were processed.';
    }
    final stamp = history.where((m) => m['chat_generation'] is int).lastOrNull;
    int? generation = stamp?['chat_generation'] as int?;
    Map<String, dynamic>? prior;
    if (history.isNotEmpty) {
      generation ??= await contexts.generation();
      prior = await contexts.load(history, accountId, generation);
    }
    final childHistory = history
        .where((m) => !(m['isUser'] == true && m['text'] == question))
        .toList();
    final results = <String>[];
    final plans = <Map<String, dynamic>?>[];
    final evidence = <ChatEvidence>[];
    final helpTopics = <String>{};
    Map<String, dynamic>? lastPlan;
    for (var i = 0; i < tasks.length; i++) {
      final text = tasks[i].question;
      Map<String, dynamic>? plan;
      ChatEvidence? facts;
      String reply;
      try {
        final refusal = ChatPolicy.unsafeOrAdviceReply(text);
        final topic = ChatHelpCatalog.requestedTopic(text);
        if (refusal != null) {
          reply = refusal;
        } else if (tasks[i].needsPeriod) {
          reply = 'Which dates or period should I use for this part?';
        } else if (topic != null) {
          reply = ChatHelpCatalog.instructions[topic]!;
        } else if (!runtime.ready) {
          reply =
              'Offline AI stopped before this part could be checked. Please retry this part.';
        } else {
          final refers =
              ChatPlanConstraints.hasScopeReference(text) ||
              ChatScopeDelta.periodOnly(text) ||
              ChatPlanConstraints.needsPriorScope(text);
          var selected = refers ? (i == 0 ? prior : lastPlan) : null;
          final index = ChatBatchPlanner.referencedIndex(text, plans.length);
          if (refers && i > 0 && selected == null && index == null) {
            lastPlan = null;
            plans.add(null);
            results.add('Which earlier financial result do you mean?');
            continue;
          }
          if (index != null) {
            if (index < 0 || index >= plans.length || plans[index] == null) {
              lastPlan = null;
              plans.add(null);
              results.add('Which earlier financial result do you mean?');
              continue;
            }
            selected = {...plans[index]!, 'force_followup': true};
          }
          reply = await _answerSingle(
            text,
            accountId: accountId,
            history: childHistory,
            debug: debug,
            providedContext: selected,
            useProvidedContext: true,
            persistContext: false,
            narrate: false,
            observeEvidence: (v) => facts = v,
            observePlan: (v) => plan = v,
            observeDraft: observeDraft,
          );
        }
      } on FormatException {
        reply =
            'This part needs clarification. Please ask it separately with the dates and records you mean.';
      } catch (error) {
        debug.error('batch_part', error);
        reply = 'This part could not be completed. Please retry this part.';
      }
      results.add(reply);
      plans.add(plan);
      if (plan != null && facts != null) {
        lastPlan = plan;
      } else if (!_nonRecordReply(text, reply)) {
        lastPlan = null;
      }
      if (facts != null) evidence.add(facts!);
      for (final entry in ChatHelpCatalog.instructions.entries) {
        if (reply == entry.value) helpTopics.add(entry.key);
      }
      childHistory.addAll([
        {'isUser': true, 'text': text},
        {'isUser': false, 'text': reply},
      ]);
      debug.log('batch_part_complete', {
        'part': i + 1,
        'parts': tasks.length,
        'verifiedEvidence': facts != null,
      });
    }
    final combined = <String, dynamic>{
      'queries': [
        for (var i = 0; i < plans.length; i++)
          if (plans[i] != null) ...plans[i]!['queries'] as List,
      ],
      'batch': true,
      'batch_incomplete': [
        for (var i = 0; i < plans.length; i++)
          plans[i] == null && !_nonRecordReply(tasks[i].question, results[i]),
      ].any((v) => v),
      'batch_parts': [
        for (var i = 0; i < tasks.length; i++)
          {'question': tasks[i].question, 'plan': plans[i]},
      ],
      if (helpTopics.isNotEmpty) 'help_topics': helpTopics.toList(),
    };
    try {
      generation ??= await contexts.generation();
      await contexts.save(
        question,
        jsonEncode(combined).length <= 6000
            ? combined
            : {'queries': <dynamic>[], 'batch': true, 'ambiguous': true},
        accountId,
        generation,
      );
    } catch (error) {
      debug.error('batch_context', error);
    }
    observePlan?.call(combined);
    if (evidence.isNotEmpty) {
      observeEvidence?.call(
        ChatEvidence(
          facts: [for (final e in evidence) ...e.facts],
          exact: evidence.map((e) => e.exact).join('\n\n'),
          partial: evidence.any((e) => e.partial),
          comparison: evidence.any((e) => e.comparison),
        ),
      );
    }
    return [
      for (var i = 0; i < tasks.length; i++)
        '${i + 1}. ${tasks[i].question.replaceAll(RegExp(r'\s+'), ' ')}\n${results[i]}',
    ].join('\n\n');
  }

  Future<String> _answerSingle(
    String question, {
    int? accountId,
    required List<Map<String, dynamic>> history,
    required ChatDebug debug,
    void Function(ChatEvidence)? observeEvidence,
    void Function(Map<String, dynamic>)? observePlan,
    void Function(String)? observeDraft,
    Map<String, dynamic>? providedContext,
    bool useProvidedContext = false,
    bool persistContext = true,
    bool narrate = true,
  }) async {
    final stamp = history.where((m) => m['chat_generation'] is int).lastOrNull;
    int? generation = stamp?['chat_generation'] as int?;
    final hasQueryHistory =
        stamp != null ||
        history.any(
          (m) =>
              m['isUser'] == true &&
              ChatPlanConstraints.recordRequest('${m['text']}'),
        );
    var context = useProvidedContext
        ? providedContext
        : history.isEmpty || !hasQueryHistory
        ? null
        : await contexts.load(
            history,
            accountId,
            generation ??= await contexts.generation(),
          );
    if (context?['batch'] == true &&
        ChatPlanConstraints.usesQueryContext(question)) {
      final parts = context?['batch_parts'] as List? ?? [];
      final index = ChatBatchPlanner.referencedIndex(question, parts.length);
      if (index != null) {
        if (index < 0 ||
            index >= parts.length ||
            parts[index] is! Map ||
            parts[index]['plan'] is! Map) {
          return 'Which completed financial part of the previous answer do you mean?';
        }
        context = {
          ...Map<String, dynamic>.from(parts[index]['plan'] as Map),
          'force_followup': true,
        };
      } else {
        final candidates = (context?['queries'] as List? ?? [])
            .whereType<Map>()
            .where(
              (q) =>
                  (ChatPlanConstraints.source(question) == null ||
                      q['source'] == ChatPlanConstraints.source(question)) &&
                  (ChatPlanConstraints.type(question) == null ||
                      q['type'] == ChatPlanConstraints.type(question)),
            )
            .toList();
        if (candidates.length != 1 || context?['batch_incomplete'] == true) {
          return 'Which part of the previous answer should I use for this follow-up?';
        }
        context = {
          'queries': [Map<String, dynamic>.from(candidates.single)],
        };
      }
    }
    debug.log('stage_context', {'available': context != null});
    final watch = Stopwatch()..start();
    var interpretation = await interpreter.interpret(
      question,
      context: context,
      history: history,
      observe: debug.raw,
    );
    debug.log('stage_interpretation', {
      'code': interpretation.code,
      'purpose': interpretation.purpose.name,
      'elapsedMs': watch.elapsedMilliseconds,
    });
    switch (interpretation.purpose) {
      case ChatPurpose.advice:
        return ChatPolicy.adviceReply;
      case ChatPurpose.safety:
        return 'I can’t help access another person’s private information or assist with harmful actions.';
      case ChatPurpose.unrelated:
        return ChatScope.reply;
      case ChatPurpose.clarify:
        return switch (interpretation.reason ?? interpretation.code) {
          'period' || 'clarify_period' =>
            'Which dates or period would you like me to check?',
          'type' || 'clarify_type' => 'Spending or income?',
          'merchant' ||
          'clarify_merchant' => 'Which merchant would you like me to check?',
          'category' || 'clarify_category' =>
            'Which recorded category would you like me to check?',
          'benchmark' =>
            'Which saved budget or earlier period would you like to compare it with?',
          'feature' => 'Which Spendy feature do you mean?',
          _ => 'What would you like to check in your saved records?',
        };
      case ChatPurpose.social:
        if (!interpretation.structured &&
            ChatScope.conversation(question, history) == null) {
          return ChatScope.reply;
        }
        String? rejectedReason;
        final socialReply = await ChatSmallTalk.reply(
          runtime,
          question,
          history: history,
          debug: debug,
          interpretedSocial: interpretation.structured,
          onRejected: (reason) => rejectedReason = reason,
        );
        if (socialReply != null) return socialReply;
        if (rejectedReason == 'output_advice_policy' ||
            rejectedReason == 'output_safety_policy') {
          debug.log('app_reply', {'source': 'policy_safe_capabilities'});
          return ChatHelpCatalog.capabilities;
        }
        return ChatReplyStatus.socialFailure;
      case ChatPurpose.help:
        if (interpretation.structured) {
          return ChatHelpCatalog.instructions[interpretation.topic] ??
              'Which Spendy feature would you like help with?';
        }
        if (!ChatScope.appHelp(question)) return ChatScope.reply;
        final raw = await runtime.converse(
          AiConversation(
            instructions:
                'Choose one Spendy help topic. Reply only with one label: ${ChatHelpCatalog.instructions.keys.join(', ')}. No explanation.',
            user: question,
            responseChoices: ChatHelpCatalog.instructions.keys.toList(),
          ),
        );
        debug.raw('help_topic', raw);
        return ChatHelpCatalog.instructions[raw.trim().toLowerCase()] ??
            'Which Spendy feature would you like help with?';
      case ChatPurpose.records:
        watch.reset();
        for (
          var executionAttempt = 0;
          executionAttempt < 2;
          executionAttempt++
        ) {
          try {
            final result = await executor.execute(
              interpretation,
              question,
              accountId: accountId,
              context: context,
              history: history
                  .where((m) => m['isUser'] == true && m['pending'] != true)
                  .toList(),
            );
            debug.log('stage_validation', {
              'accepted': result.evidence != null,
              'operation': interpretation.code,
              'elapsedMs': watch.elapsedMilliseconds,
            });
            if (result.plan != null) {
              observePlan?.call(result.plan!);
              if (persistContext) {
                try {
                  await contexts.save(
                    question,
                    result.plan!,
                    accountId,
                    generation ??= await contexts.generation(),
                  );
                } catch (_) {
                  debug.log('stage_context', {'saved': false});
                }
              }
            }
            if (result.evidence != null) {
              observeEvidence?.call(result.evidence!);
            }
            if (!narrate) return result.evidence?.fallback ?? result.answer;
            final response = await ChatNarrator.answer(
              runtime,
              question,
              result.answer,
              evidence: result.evidence,
              history: history,
              onGenerated: observeDraft,
              onDecision: (decision) =>
                  debug.log('stage_narration', {'decision': decision}),
            );
            debug.log('stage_response', {
              'verifiedEvidence': result.evidence != null,
            });
            return response;
          } on FormatException catch (error) {
            final reason = ChatQueryEngine.rejectionCode(error);
            debug.log('stage_validation', {
              'accepted': false,
              'reason': reason,
              'operation': interpretation.code,
              'attempt': executionAttempt + 1,
            });
            if (executionAttempt == 1) rethrow;
            interpretation = await interpreter.interpret(
              question,
              context: context,
              history: history,
              observe: debug.raw,
              feedback: reason,
            );
            debug.log('stage_interpretation', {
              'code': interpretation.code,
              'purpose': interpretation.purpose.name,
              'repair': true,
            });
            if (interpretation.purpose != ChatPurpose.records) {
              return interpretation.purpose == ChatPurpose.advice
                  ? ChatPolicy.adviceReply
                  : 'Could you clarify what you would like to check in your saved records?';
            }
          }
        }
        throw const FormatException('No validated operation');
    }
  }
}
