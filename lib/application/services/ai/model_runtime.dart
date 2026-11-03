import 'dart:async';
import 'dart:io';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'ai_guardrails.dart';
import 'local_ai_model.dart';
import 'qwen_task_template.dart';
import 'ai_conversation.dart';
import 'package:path_provider/path_provider.dart';

abstract interface class AiModelBackend {
  Future<void> install(String path, LocalAIModelMetadata metadata);
  Future<String> generate(String prompt);
  Future<void> stop();
}

class MediaPipeModelBackend implements AiModelBackend, ConversationBackend {
  final Future<InferenceModel> Function()? _createModelOverride;
  AiPromptFormat _format;
  int _contextTokens = 1024;
  MediaPipeModelBackend({
    Future<InferenceModel> Function()? createModel,
    AiPromptFormat format = AiPromptFormat.qwen,
  }) : _createModelOverride = createModel,
       _format = format {
    _envelopeReady = createModel != null;
  }
  Future<InferenceModel> _createModel() =>
      _createModelOverride?.call() ??
      FlutterGemma.getActiveModel(
        maxTokens: _contextTokens,
        preferredBackend: Platform.isAndroid ? PreferredBackend.cpu : null,
      );
  InferenceModel? _model;
  InferenceModelSession? _session;
  bool _cancelled = false;
  bool _envelopeReady = false;
  @override
  Future<void> install(String path, LocalAIModelMetadata metadata) async {
    _envelopeReady = false;
    await FlutterGemma.initialize();
    await _model?.close();
    _model = null;
    final runtimePath = metadata.sha256Hash == QwenTaskTemplate.originalHash
        ? await QwenTaskTemplate.prepare(
            path,
            (await getApplicationSupportDirectory()).path,
          )
        : path;
    await FlutterGemma.installModel(
      modelType: metadata.flutterGemmaModelType,
      fileType: metadata.fileType,
    ).fromFile(runtimePath).install();
    _format = AiPromptFormat.qwen;
    _contextTokens = metadata.contextTokens;
    _envelopeReady = true;
  }

  @override
  Future<String> generate(String prompt) => converse(
    AiConversation(instructions: AiConversation.baseInstructions, user: prompt),
  );

  @override
  Future<String> converse(AiConversation request) async {
    if (!_envelopeReady) throw StateError('AI template restart required');
    _cancelled = false;
    _model ??= await _createModel();
    if (_cancelled) {
      throw StateError('Inference cancelled before session creation');
    }
    final session = await _model!.createSession(
      temperature: request.response ? .3 : 0,
      topK: request.response ? 20 : 1,
    );
    _session = session;
    try {
      if (_cancelled) throw StateError('Inference cancelled before input');
      // Leave room for generation in the model's actual token window.
      var bounded = request;
      final inputLimit = _contextTokens == 1024 ? 768 : _contextTokens - 512;
      while (await session.sizeInTokens(bounded.renderFor(_format)) >
          inputLimit) {
        if (bounded.history.isEmpty && bounded.notes.isEmpty) {
          throw const FormatException(
            'Current request exceeds inference token budget',
          );
        }
        bounded = bounded.history.isNotEmpty
            ? bounded.dropOldestPair()
            : bounded.dropOldestNote();
      }
      if (_cancelled) throw StateError('Inference cancelled before input');
      await session.addQueryChunk(
        Message(text: bounded.nativePayloadFor(_format), isUser: true),
      );
      if (_cancelled) throw StateError('Inference cancelled before generation');
      var result = '';
      var overflow = false;
      final outputLimit =
          (request.maxOutputChars ??
                  (request.task ? 512 : AiGuardrails.maxResponseChars))
              .clamp(32, AiGuardrails.maxResponseChars);
      await for (final token in session.getResponseAsync()) {
        if (!overflow && result.length + token.length > outputLimit) {
          overflow = true;
          // Stop runaway structured tasks early, but keep draining until native
          // completion. Never release/close a still-generating session.
          try {
            await session.stopGeneration();
          } catch (_) {
            // Unsupported cancellation remains protected by the outer timeout
            // and quarantine; natural completion must still be awaited.
          }
        } else if (!overflow) {
          result += token;
        }
      }
      if (overflow) {
        throw const FormatException('Model response exceeded limit');
      }
      return result.trim();
    } finally {
      // Only close after generation finishes, including after cancellation.
      await session.close();
      _session = null;
    }
  }

  @override
  Future<void> stop() async {
    _cancelled = true;
    await _session?.stopGeneration();
  }
}

/// A timeout ends the caller's wait, but never releases the native engine lock
/// until the original operation and its cleanup actually finish.
class ModelRuntime {
  final AiModelBackend backend;
  final Duration initializationTimeout, requestTimeout;
  bool busy = false, ready = false;
  ModelRuntime(
    this.backend, {
    this.initializationTimeout = const Duration(seconds: 150),
    this.requestTimeout = const Duration(seconds: 45),
  });
  Future<T> _run<T>(
    Future<T> Function(bool Function()) action,
    Duration timeout,
  ) async {
    if (busy) throw StateError('Model is still finishing its previous request');
    busy = true;
    var expired = false;
    var operationDone = false, cancellationDone = true;
    void releaseIfSafe() {
      if (operationDone && cancellationDone) busy = false;
    }

    final operation = Future<T>.sync(() => action(() => expired));
    // Handle late completion/errors without resurrecting readiness or starting
    // another native request while the old generation is still running.
    unawaited(
      operation.then<void>(
        (_) {
          operationDone = true;
          releaseIfSafe();
        },
        onError: (Object _, StackTrace __) {
          operationDone = true;
          releaseIfSafe();
        },
      ),
    );
    try {
      return await operation.timeout(timeout);
    } on TimeoutException {
      expired = true;
      ready = false;
      // The backend may time out after its future settles. Hold quarantine
      // while its cancellation acknowledgement is still pending in that case.
      busy = true;
      cancellationDone = false;
      unawaited(
        Future<void>.sync(backend.stop).then<void>(
          (_) {
            cancellationDone = true;
            releaseIfSafe();
          },
          onError: (Object _, StackTrace __) {
            cancellationDone = true;
            releaseIfSafe();
          },
        ),
      );
      rethrow;
    }
  }

  Future<void> initialize(String path, LocalAIModelMetadata metadata) async {
    if (busy) throw StateError('Model is still finishing its previous request');
    ready = false;
    await _run((expired) async {
      await backend.install(path, metadata);
      if (expired()) throw StateError('Initialization expired');
      final response = await backend.generate('Reply with only OK.');
      if (!RegExp(r'\bOK\b', caseSensitive: false).hasMatch(response) ||
          response.length > 128) {
        throw StateError('Model inference check failed');
      }
    }, initializationTimeout);
    ready = true;
  }

  Future<String> generate(String prompt) async {
    if (!ready) throw StateError('Model is not ready');
    if (busy) throw StateError('Model is still finishing its previous request');
    try {
      return await _run((_) => backend.generate(prompt), requestTimeout);
    } on FormatException {
      rethrow;
    } catch (_) {
      ready = false;
      rethrow;
    }
  }

  Future<String> converse(AiConversation request) async {
    if (!ready) throw StateError('Model is not ready');
    if (busy) throw StateError('Model is still finishing its previous request');
    try {
      return await _run(
        (_) => backend is ConversationBackend
            ? (backend as ConversationBackend).converse(request)
            : backend.generate(request.diagnosticPrompt),
        requestTimeout,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      ready = false;
      rethrow;
    }
  }
}
