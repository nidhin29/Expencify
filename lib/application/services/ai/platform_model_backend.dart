import 'ai_conversation.dart';
import 'lite_rt_lm_backend.dart';
import 'local_ai_model.dart';
import 'model_runtime.dart';

/// Model metadata selects an adapter; feature code never selects token formats.
class PlatformModelBackend implements AiModelBackend, ConversationBackend {
  final AiModelBackend liteRtLm, mediaPipe;
  AiModelBackend? _active;
  PlatformModelBackend({AiModelBackend? liteRtLm, AiModelBackend? mediaPipe})
    : liteRtLm = liteRtLm ?? LiteRtLmModelBackend(),
      mediaPipe = mediaPipe ?? MediaPipeModelBackend();
  @override
  Future<void> install(String path, LocalAIModelMetadata metadata) async {
    _active = metadata.runtime == LocalModelRuntime.liteRtLm
        ? liteRtLm
        : mediaPipe;
    await _active!.install(path, metadata);
  }

  @override
  Future<String> generate(String prompt) => _active!.generate(prompt);
  @override
  Future<String> converse(AiConversation request) =>
      (_active as ConversationBackend).converse(request);
  @override
  Future<void> stop() async {
    await _active?.stop();
  }
}
