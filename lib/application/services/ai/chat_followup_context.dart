import 'ai_conversation.dart';
import 'chat_plan_constraints.dart';
import 'chat_policy.dart';
import 'chat_reply_status.dart';
import 'chat_scope.dart';

/// Resolve missing referents before routing. These are clarification questions,
/// not answers about records and never permission for an unrelated new topic.
class ChatFollowupContext {
  static String? resolvedQuestion(
    String question,
    List<Map<String, dynamic>> history,
  ) {
    final features = _referencedFeatures(question, history);
    if (features == null || features.length != 1) return null;
    return ChatPolicy.normalizedQuestion(
      question,
    ).replaceFirst(RegExp(r'\b(?:it|that|this)\b.*$'), features.single);
  }

  static Map<String, dynamic>? status(String reply) {
    if (reply == ChatReplyStatus.scopeReply) {
      return const {'app_status': 'scope_rejection'};
    }
    if (reply.startsWith('I could not complete') ||
        reply.startsWith('I could not reliably interpret')) {
      return const {'app_status': 'generation_failure'};
    }
    return null;
  }

  static String? clarification(
    String question,
    List<Map<String, dynamic>> history,
  ) {
    final q = ChatPolicy.normalizedQuestion(question);
    final lastStatus = history
        .where((m) => m.containsKey('app_status'))
        .lastOrNull;
    if (RegExp(r'^(?:why|why not|why is that|what happened)$').hasMatch(q) &&
        lastStatus != null) {
      return lastStatus['app_status'] == 'scope_rejection'
          ? 'My scope check blocked the previous request. It may have been too restrictive if you meant your saved records or an app feature. Which part did you want to check?'
          : 'I could not reliably interpret or complete the previous request. Your records were not changed. Could you rephrase it?';
    }

    final turns = AiConversation.turns(history);
    if (turns.isEmpty) return null;
    final hasRecords = history.any(
      (m) =>
          m['isUser'] == true &&
          m['pending'] != true &&
          ChatPlanConstraints.recordRequest('${m['text']}'),
    );
    // Evaluation needs a user-selected benchmark. Treat it as an in-domain
    // clarification rather than an unrelated topic or a financial judgement.
    if (hasRecords &&
        RegExp(
          r'^(?:is|was|does|do) (?:it|that|this|my spending|my expenses|that amount) (?:seem |look )?(?:too (?:much|high|low)|high|low|normal|reasonable|excessive|a lot|okay|ok)$',
        ).hasMatch(q)) {
      return 'Which saved budget or earlier time period would you like to compare that spending with? An amount alone does not tell me whether it is too much.';
    }

    final features = _referencedFeatures(question, history);
    if (features == null || features.length == 1) return null;
    return features.isEmpty
        ? 'Which Spendy feature would you like to set up?'
        : 'Which feature do you mean: ${features.join(', ')}?';
  }

  static List<String>? _referencedFeatures(
    String question,
    List<Map<String, dynamic>> history,
  ) {
    final q = ChatPolicy.normalizedQuestion(question);
    final turns = AiConversation.turns(history);
    // A feature reference must actually refer back, and cannot introduce a new
    // subject. We only ask for clarification; no feature is enabled from chat.
    final reference = RegExp(
      r'^(?:how (?:to|do i|can i)|can you help me) (?:enable|activate|set up|use|edit|change|update|turn on|switch on|switch|turn|start) (?:it|that|this)(?: (?:feature|option|thing))?(?: on)?(?: (?:you|u) (?:mentioned|told|described|suggested)(?: me)?)?$',
    ).hasMatch(q);
    if (!reference) return null;
    for (var i = turns.length - 2; i >= 0; i -= 2) {
      final previous = turns[i].text;
      if (!ChatScope.appHelp(previous) ||
          ChatPlanConstraints.recordRequest(previous)) {
        continue;
      }
      final reply = turns[i + 1].text.toLowerCase();
      final features = <String>[
        if (RegExp(r'\bsms\b').hasMatch(reply)) 'bank SMS tracking',
        if (RegExp(r'\bbudget\b').hasMatch(reply)) 'budgets',
        if (RegExp(r'\bgoals?\b').hasMatch(reply)) 'savings goals',
        if (RegExp(r'\bpayments?|reminders?\b').hasMatch(reply))
          'payment reminders',
        if (RegExp(r'\bbackups?|drive\b').hasMatch(reply)) 'backups',
        if (RegExp(r'\bsearch\b').hasMatch(reply)) 'search',
        if (RegExp(r'\bvoice\b').hasMatch(reply)) 'voice entry',
        if (RegExp(r'\bscan|receipt\b').hasMatch(reply)) 'receipt scanning',
      ];
      return features;
    }
    return null;
  }
}
