import 'ai_conversation.dart';
import 'chat_policy.dart';
import 'chat_plan_constraints.dart';
import 'chat_reply_status.dart';
import 'chat_scope_delta.dart';

enum ConversationPurpose { courtesy, assistant, reference, boundary }

/// Positive permission for brief interaction with the assistant. Conversation
/// history can resolve an explicit reference, never authorize a new topic.
class ChatScope {
  static const reply = ChatReplyStatus.scopeReply;
  static const boundaryReply = ChatReplyStatus.boundaryReply;

  static ConversationPurpose? conversation(
    String question,
    List<Map<String, dynamic>> history,
  ) {
    final q = ChatPolicy.normalizedQuestion(
      question,
    ).replaceAll(RegExp(r'\bu\b'), 'you').replaceAll(RegExp(r'\by\b'), 'why');
    final asksWhy = RegExp(r'\b(why|should|shouldn|again)\b').hasMatch(q);
    if (asksWhy &&
        RegExp(
          r'\b(scope|role|unrelated|topic)\b|\bfinancial assistant\b',
        ).hasMatch(q) &&
        RegExp(r'\b(you|your|assistant|spendy)\b').hasMatch(q)) {
      return ConversationPurpose.boundary;
    }
    if (RegExp(
      r'^(how (?:(?:are|r|have) )?you(?: been)?(?: (?:doing|feeling))?(?: (?:today|lately))?|how is it going|how s it going|who are you|what (?:is|s) your (?:name|role)|are you (?:an? )?(?:financial |offline )?assistant)$',
    ).hasMatch(q)) {
      return ConversationPurpose.assistant;
    }
    if (RegExp(
      r'^(hi|hello|hey|good morning|good evening|ok|okay|sure|understood|got it|let me think|give me a moment)$',
    ).hasMatch(q)) {
      return ConversationPurpose.courtesy;
    }
    final isStatement = !RegExp(
      r'\b(tell|explain|describe|teach|write|what|where|when|why|how|can|could|would|should)\b',
    ).hasMatch(q);
    if (isStatement &&
        RegExp(
          r'\b(thanks|thank you|appreciate|grateful|helpful|nice talking)\b|^i (?:like|love|enjoy) you\b',
        ).hasMatch(q)) {
      return ConversationPurpose.courtesy;
    }
    if (RegExp(
      r'^(?:(?:actually|please|instead|now) )?(?:my name is|call me)\b',
    ).hasMatch(q)) {
      return ConversationPurpose.reference;
    }
    if ((AiConversation.turns(history).isNotEmpty ||
            AiConversation.memoryNotes(history).isNotEmpty) &&
        RegExp(
          r'\b(?:my|your) name\b|\bwhat name\b.*\byou\b.*\bme\b|\bcall me\b|\bwho\b.*\bthank\w*\b|\bwhat\b.*\b(?:i|you|we)\b.*\b(?:say|said|tell|told|mention|mentioned|ask|asked)\b|\bremember\b.*\b(?:me|my|our)\b|\b(?:our|this) (?:chat|conversation)\b|\b(?:where|what) were we\b|\bwhat (?:was|is) (?:my|our) (?:last|previous) (?:question|topic)\b',
        ).hasMatch(q)) {
      return ConversationPurpose.reference;
    }
    return null;
  }

  static bool appHelp(String question) => RegExp(
    r'\b(spendy|app|sms|backup|restore|export|import|settings|permissions?|transactions?|payments?|budgets?|goals?|categories|merchants?|search|receipts?|accounts?|notifications?|reminders?|subscriptions?|calculator|voice|scan|ocr|tracking|passphrase|encryption)\b',
    caseSensitive: false,
  ).hasMatch(question);

  static bool recordFollowup(
    String question,
    List<Map<String, dynamic>> history, {
    bool hasResolvedQuery = false,
  }) {
    if ((!ChatPlanConstraints.isFollowup(question) &&
            !ChatPlanConstraints.needsPriorScope(question)) ||
        (!hasResolvedQuery &&
            !history.any(
              (m) =>
                  m['isUser'] == true &&
                  m['pending'] != true &&
                  ChatPlanConstraints.recordRequest('${m['text']}'),
            ))) {
      return false;
    }
    if (ChatPlanConstraints.financialReference(question)) return true;
    final tail = ChatPolicy.normalizedQuestion(question).replaceFirst(
      RegExp(r'^(?:and|what about|how about|same|only|just|instead)\s+'),
      '',
    );
    return continuationShape(question) ||
        RegExp(
          '^(?:in |for |during )?${ChatPolicy.periodPattern}\$',
        ).hasMatch(tail) ||
        RegExp(
          r'^(?:over|under|above|below|at least|at most)\s+\d+(?:\.\d+)?$',
        ).hasMatch(tail);
  }

  static bool continuationShape(String question) {
    final q = ChatPolicy.normalizedQuestion(question);
    final tail = q.replaceFirst(
      RegExp(r'^(?:and|what about|how about|same|only|just|instead)\s+'),
      '',
    );
    return ChatScopeDelta.periodOnly(question) ||
        RegExp(
          '^(?:in |for |during )?${ChatPolicy.periodPattern}\$',
        ).hasMatch(tail) ||
        (RegExp(r'^compare\b').hasMatch(q) &&
            RegExp(ChatPolicy.periodPattern).hasMatch(q));
  }
}
