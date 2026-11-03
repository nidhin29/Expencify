import 'chat_evidence.dart';
import 'chat_interpretation.dart';
import 'chat_query_engine.dart';

class ChatExecution {
  final String answer;
  final ChatEvidence? evidence;
  final Map<String, dynamic>? plan;
  const ChatExecution(this.answer, this.evidence, this.plan);
}

abstract interface class ChatRecordExecutor {
  Future<ChatExecution> execute(
    ChatInterpretation interpretation,
    String question, {
    int? accountId,
    Map<String, dynamic>? context,
    List<Map<String, dynamic>> history,
  });
}

/// Only this stage connects an interpreted capability to the existing bounded
/// compiler/database. It cannot generate model responses or select social topics.
class ValidatedChatRecordExecutor implements ChatRecordExecutor {
  final ChatQueryEngine engine;
  ValidatedChatRecordExecutor(this.engine);

  @override
  Future<ChatExecution> execute(
    ChatInterpretation interpretation,
    String question, {
    int? accountId,
    Map<String, dynamic>? context,
    List<Map<String, dynamic>> history = const [],
  }) async {
    final operation = interpretation.operation;
    if (interpretation.purpose != ChatPurpose.records || operation == null) {
      throw const FormatException('A record operation is required');
    }
    ChatEvidence? evidence;
    Map<String, dynamic>? plan;
    final answer = await engine.answerOperation(
      operation,
      question,
      accountId: accountId,
      history: history,
      previousPlan: context,
      request: interpretation,
      onEvidence: (value) => evidence = value,
      onResolved: (value) => plan = value,
    );
    return ChatExecution(answer, evidence, plan);
  }
}
