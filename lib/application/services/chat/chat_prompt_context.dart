import '../ai/chat_followup_context.dart';
import '../ai/chat_reply_status.dart';
import 'chat_history_store.dart';

/// One context assembly path for the UI and end-to-end model evaluations.
class ChatPromptContext {
  static List<Map<String, dynamic>> build({
    required List<ChatMessage> messages,
    required List<Map<String, dynamic>> memory,
    required String current,
    required int? generation,
    int? beforeIndex,
  }) {
    final questionIndex = beforeIndex == null
        ? messages.length - 1
        : beforeIndex - 1;
    final beforeId = questionIndex >= 0 ? messages[questionIndex].id : null;
    final history = <Map<String, dynamic>>[
      ...memory.where((m) => beforeId == null || (m['id'] as int) < beforeId),
    ];
    for (var i = 0; i + 1 < (beforeIndex ?? messages.length); i++) {
      final question = messages[i], answer = messages[i + 1];
      if (!question.isUser || answer.isUser) continue;
      history.removeWhere((m) => m.containsKey('app_status'));
      final status = ChatFollowupContext.status(answer.text);
      if (status != null) history.add(status);
      if (!answer.failed && !ChatReplyStatus.isStatus(answer.text)) {
        history.add(question.toHistory());
        history.add(answer.toHistory());
      }
    }
    history.add({
      'text': current,
      if (beforeId != null) 'id': beforeId,
      'isUser': true,
      'pending': true,
      'chat_generation': generation,
    });
    return history;
  }
}
