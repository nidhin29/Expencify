import 'ai_conversation.dart';
import 'voice_intent_contract.dart';
import 'voice_allocations.dart';
import 'chat_debug.dart';
import 'chat_followup_context.dart';
import 'chat_help_catalog.dart';
import 'chat_resolved_read.dart';
import 'chat_identity.dart';
import 'chat_scope_delta.dart';
import 'chat_scope.dart';
import 'chat_interpreter.dart';
import 'chat_record_executor.dart';
import 'chat_conversation_pipeline.dart';
import 'chat_batch_planner.dart';
import 'chat_evidence.dart';
import '../chat/chat_query_context_store.dart';
import 'chat_plan_constraints.dart';
import 'chat_query_engine.dart';
import 'dart:async';
import 'chat_facts.dart';
import 'model_runtime.dart';
import 'platform_model_backend.dart';
import 'chat_policy.dart';
import 'ai_guardrails.dart';
import '../performance/performance_probe.dart';
import 'model_download.dart';
import 'model_file_hash.dart';
import 'qwen_task_template.dart';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'local_ai_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AIActionType { add, update, delete, chat }

class AIAction {
  final AIActionType type;
  final double? amount;
  final String? category;
  final String? merchant;
  final String? originalText;
  final DateTime? date;
  final String? message;
  final List<AISplitItem>? items;

  AIAction({
    required this.type,
    this.amount,
    this.category,
    this.merchant,
    this.originalText,
    this.date,
    this.message,
    this.items,
  });

  factory AIAction.fromJson(
    Map<String, dynamic> json,
    String original, {
    String? validationSource,
  }) {
    AiGuardrails.validateIntent(json, validationSource ?? original);
    final itemsList = json['items'] as List?;
    final typeStr = json['action']?.toString().toUpperCase();
    AIActionType type = AIActionType.chat;
    if (typeStr == 'ADD') type = AIActionType.add;
    if (typeStr == 'UPDATE') type = AIActionType.update;
    if (typeStr == 'DELETE') type = AIActionType.delete;

    // Support both new (amount) and legacy (value) keys
    final amountValue = double.tryParse(
      (json['amount'] ?? json['value'])?.toString() ?? '',
    );
    // Support new (category/merchant) and legacy (target) keys
    final categoryValue = (json['category'] ?? json['target'])?.toString();
    final merchantValue = json['merchant']?.toString();

    DateTime? parsedDate = AiGuardrails.sourceDate(original);
    if (json['date'] != null) {
      final proposed = AiGuardrails.strictDate(json['date'] as String);
      if (parsedDate == null || proposed != parsedDate) {
        throw const FormatException('Date not grounded in source');
      }
    }

    // Parse items if present (for OCR itemization)
    final items = itemsList
        ?.map((i) => AISplitItem.fromJson(i as Map<String, dynamic>))
        .toList();

    return AIAction(
      type: type,
      amount: amountValue,
      category: categoryValue,
      merchant: merchantValue,
      date: parsedDate,
      originalText: original,
      message: json['message']?.toString(),
      items: items,
    );
  }
}

class AISplitItem {
  final double amount;
  final String category;
  final String? merchant;
  final String? label;

  AISplitItem({
    required this.amount,
    required this.category,
    this.merchant,
    this.label,
  });

  factory AISplitItem.fromJson(Map<String, dynamic> json) {
    return AISplitItem(
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      category: json['category']?.toString() ?? 'Other',
      merchant: json['merchant']?.toString(),
      label: json['label']?.toString(),
    );
  }
}

class AIService {
  static const _channel = MethodChannel('com.example.expencify/asset_delivery');
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal()
    : _runtime = ModelRuntime(PlatformModelBackend()),
      _facts = ChatFacts(),
      _observeEvidence = null,
      _observeDraft = null,
      _observeTrace = null,
      _observePlan = null,
      _interpreter = null;
  AIService.withDependencies({
    required ModelRuntime runtime,
    required ChatFacts facts,
    ChatInterpreter? interpreter,
    void Function(ChatEvidence)? observeEvidence,
    void Function(String)? observeDraft,
    void Function(Map<String, Object?>)? observeTrace,
    void Function(Map<String, dynamic>)? observePlan,
  }) : _runtime = runtime,
       _facts = facts,
       _observeEvidence = observeEvidence,
       _observeDraft = observeDraft,
       _observeTrace = observeTrace,
       _observePlan = observePlan,
       _interpreter = interpreter;
  final ChatInterpreter? _interpreter;
  final ModelRuntime _runtime;
  final ChatFacts _facts;
  final void Function(ChatEvidence)? _observeEvidence;
  final void Function(String)? _observeDraft;
  final void Function(Map<String, Object?>)? _observeTrace;
  final void Function(Map<String, dynamic>)? _observePlan;

  bool _initialized = false;
  bool get isInitialized => _initialized && _runtime.ready;

  LocalAIModelMetadata? _currentModel;
  LocalAIModelMetadata? get currentModel => _currentModel;

  Future<bool> supportsCurrentModel() async {
    if (!LocalAIModelMetadata.isSupported) return false;
    if (LocalAIModelMetadata.all.first.runtime == LocalModelRuntime.mediaPipe) {
      return true;
    }
    try {
      final capabilities = await const MethodChannel(
        'com.nidhi.expencify/litert_lm',
      ).invokeMapMethod<String, dynamic>('capabilities');
      return capabilities?['supported'] == true;
    } on MissingPluginException {
      return false;
    }
  }

  bool _isAiBusy = false;
  Future<void>? _initFuture;
  CancelToken? _downloadCancelToken;

  void pauseDownload() {
    _downloadCancelToken?.cancel('User paused');
    _downloadCancelToken = null;
  }

  Future<void> init([LocalAIModelType? type]) async {
    if (_initFuture != null) return _initFuture;

    _initFuture = PerformanceProbe.measure(
      'ai.initialize',
      () => _initInternal(type),
    );
    try {
      await _initFuture;
    } finally {
      _initFuture = null;
    }
  }

  Future<void> _initInternal([LocalAIModelType? type]) async {
    if (!LocalAIModelMetadata.isSupported) {
      throw UnsupportedError('Local AI is available on Android and iOS.');
    }
    // If already initialized with the same model, skip
    if (isInitialized && (_currentModel?.id == type || type == null)) return;
    if (_runtime.busy || _isAiBusy) {
      throw StateError(
        'AI is still finishing its previous request. Try again shortly, or restart the app if it remains busy.',
      );
    }
    _initialized = false;

    // Use default if nothing specified and no current model
    final targetType =
        type ?? _currentModel?.id ?? LocalAIModelMetadata.all.first.id;
    final metadata = LocalAIModelMetadata.all.firstWhere(
      (m) => m.id == targetType,
    );

    String? foundModelPath;

    // 1. Try to find in Play Asset Delivery (Android only) via MethodChannel
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final String? packPath = await _channel.invokeMethod(
          'getAssetPackPath',
          {'packName': 'model_pack'},
        );
        if (packPath != null) {
          final modelPathInPack = '$packPath/${metadata.fileName}';
          if (await File(modelPathInPack).exists()) {
            foundModelPath = modelPathInPack;
            debugPrint('AI: Found model in Play Asset Pack: $foundModelPath');
          }
        }
      } catch (e) {
        debugPrint('AI: Play Asset Delivery MethodChannel failed: $e');
      }
    }

    // 2. Fallback to Documents Directory (Manual download)
    if (foundModelPath == null) {
      final directory = await getApplicationDocumentsDirectory();
      final localPath = '${directory.path}/${metadata.fileName}';

      // Select the exact pinned artifact. Other downloads are not ours to delete.
      if (await File(localPath).exists()) {
        foundModelPath = localPath;
        debugPrint('AI: Found model in Documents Directory: $localPath');
      }
    }

    if (foundModelPath != null) {
      final file = File(foundModelPath);
      final bytes = await file.length();
      debugPrint('AI: Loading model from: $foundModelPath ($bytes bytes)');

      if (!await _validModel(file, metadata)) {
        debugPrint(
          'AI: Model failed size/checksum verification. Rejecting the invalid file.',
        );
        // Reject without destroying a user's file. Verified import/download
        // replaces the artifact only after its replacement has passed checks.
        _initialized = false;
        return;
      }

      try {
        await _runtime.initialize(foundModelPath, metadata);
        _currentModel = metadata;
        _initialized = true;
      } catch (_) {
        _initialized = false;
        // A verified file is not corrupt merely because the runtime failed.
        // Preserve it for a retry; only checksum/size validation rejects files.
        rethrow;
      }
    } else {
      _initialized = false;
      _currentModel = metadata;
      debugPrint('AI: Model not found locally. Download required.');
    }
  }

  Future<bool> modelExists(LocalAIModelType type) async {
    if (!LocalAIModelMetadata.isSupported) return false;
    final metadata = LocalAIModelMetadata.all.firstWhere((m) => m.id == type);

    // 1. Check Play Asset Delivery (Android)
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final String? packPath = await _channel.invokeMethod(
          'getAssetPackPath',
          {'packName': 'model_pack'},
        );
        if (packPath != null) {
          final fullPath = '$packPath/${metadata.fileName}';
          final file = File(fullPath);
          if (await file.exists()) {
            final size = await file.length();
            if (size == metadata.expectedSize &&
                await _validModel(file, metadata)) {
              return true;
            }
          }
        }
      } catch (e) {
        debugPrint('AI: modelExists PAD check failed: $e');
      }
    }

    // 2. Check Local Documents
    final directory = await getApplicationDocumentsDirectory();
    final localPath = '${directory.path}/${metadata.fileName}';
    final file = File(localPath);
    if (await file.exists()) {
      final size = await file.length();
      final isValid =
          size == metadata.expectedSize && await _validModel(file, metadata);
      debugPrint(
        'AI: Checked local path: $localPath | size: $size | valid: $isValid',
      );
      return isValid;
    }
    return false;
  }

  Future<void> downloadModel(
    LocalAIModelMetadata metadata,
    Function(double) onProgress,
  ) async {
    if (!LocalAIModelMetadata.isSupported) {
      throw UnsupportedError('Local AI is available on Android and iOS.');
    }
    if (_downloadCancelToken != null) {
      throw StateError('A model download is already running.');
    }
    final directory = await getApplicationDocumentsDirectory();
    final destination = File('${directory.path}/${metadata.fileName}');
    final token = CancelToken();
    _downloadCancelToken = token;
    try {
      await downloadVerifiedModel(
        metadata: metadata,
        partial: File('${destination.path}.tmp'),
        destination: destination,
        onProgress: onProgress,
        cancelToken: token,
      );
    } on DioException catch (e) {
      if (!CancelToken.isCancel(e)) rethrow;
      return;
    } finally {
      _downloadCancelToken = null;
    }
    await init(metadata.id);
  }

  final Map<String, String> _verifiedFiles = {};
  Future<void> importModelFile(String path) async {
    if (!LocalAIModelMetadata.isSupported) {
      throw UnsupportedError('Local AI is available on Android and iOS.');
    }
    if (_downloadCancelToken != null || _runtime.busy || _isAiBusy) {
      throw StateError('AI is busy. Try again shortly.');
    }
    final metadata = LocalAIModelMetadata.all.single;
    final directory = await getApplicationDocumentsDirectory();
    final destination = File('${directory.path}/${metadata.fileName}');
    await importVerifiedModel(
      source: File(path),
      destination: destination,
      metadata: metadata,
    );
    _verifiedFiles.remove(destination.path);
    await init(metadata.id);
  }

  Future<bool> _validModel(File file, LocalAIModelMetadata metadata) async {
    final stat = await file.stat();
    if (stat.size != metadata.expectedSize) return false;
    final signature =
        '${metadata.sha256Hash}:${stat.modified.microsecondsSinceEpoch}:${stat.size}';
    if (_verifiedFiles[file.path] == signature) return true;
    final digest = await ModelFileHash.sha256File(file.path);
    if (!QwenTaskTemplate.accepts(metadata.sha256Hash, digest)) return false;
    QwenTaskTemplate.rememberVerified(
      file.path,
      stat,
      metadata.sha256Hash,
      digest,
    );
    _verifiedFiles[file.path] = signature;
    return true;
  }

  static const conversationalSetupReply =
      'This question needs offline AI to interpret it. Set up offline AI, then try again. Basic spending totals still work without it.';

  Future<String?> _resolvedAnswer(
    String query,
    List<Map<String, dynamic>> history,
    int? accountId,
    ChatDebug debug,
  ) async {
    final temporalEdit = ChatScopeDelta.periodOnly(query);
    if (!temporalEdit &&
        !(ChatPlanConstraints.recordRequest(query) &&
            ChatPlanConstraints.type(query) != null &&
            {
              'sum',
              'avg',
              'count',
            }.contains(ChatPlanConstraints.metric(query)))) {
      return null;
    }
    final store = ChatQueryContextStore(_facts.helper);
    final stamp = history.where((m) => m['chat_generation'] is int).lastOrNull;
    final generation =
        stamp?['chat_generation'] as int? ?? await store.generation();
    final context = await store.load(history, accountId, generation);
    final intent = await ChatResolvedRead.intent(_facts.helper, query, context);
    if (intent == null) return null;
    Map<String, dynamic>? resolved;
    ChatEvidence? evidence;
    try {
      final answer =
          await ChatQueryEngine(
            helper: _facts.helper,
            clock: _facts.clock,
          ).answerModel(
            jsonEncode({'intent': intent}),
            query,
            accountId: accountId,
            history: history
                .where((m) => m['isUser'] == true && m['pending'] != true)
                .toList(),
            previousPlan: context,
            onResolved: (p) {
              resolved = p;
              _observePlan?.call(p);
            },
            onEvidence: (e) {
              evidence = e;
              _observeEvidence?.call(e);
            },
          );
      if (resolved != null) {
        try {
          await store.save(query, resolved!, accountId, generation);
        } catch (_) {
          /* Answer remains verified. */
        }
      }
      debug.log('answer_source', {'source': 'verified_read', 'modelCalls': 0});
      return evidence?.fallback ?? answer;
    } on FormatException {
      // Incomplete interpretation can still use the normal bounded model path.
      return null;
    }
  }

  Future<String> ask(
    String query, {
    int? accountId,
    List<Map<String, dynamic>>? history,
  }) async {
    final debug = ChatDebug(observe: _observeTrace);
    final transcript = AiConversation.usableHistory(history ?? const []);
    debug.log('request', {
      'questionChars': query.length,
      'historyMessages': history?.length ?? 0,
      'modelReady': _runtime.ready,
      'usableHistoryMessages': transcript.length,
    });
    if (query.trim().isEmpty || query.length > AiGuardrails.maxChatChars) {
      return 'Please ask a shorter question about your saved records.';
    }
    final multiple = ChatBatchPlanner.isCandidate(query);
    final refusal = ChatPolicy.unsafeOrAdviceReply(query);
    if (refusal != null && (!multiple || !_runtime.ready)) {
      debug.log('app_reply', {'source': 'input_safety_or_advice_policy'});
      return refusal;
    }
    final identity = ChatIdentity.answer(query, transcript);
    if (identity != null && !multiple) {
      debug.log('app_reply', {'source': 'explicit_user_preference'});
      return identity;
    }
    if (ChatHelpCatalog.isCapabilityRequest(query)) {
      debug.log('app_reply', {'source': 'capabilities_catalog'});
      return ChatHelpCatalog.capabilities;
    }
    // With a ready model there is one interpretation path. Legacy keyword
    // fallbacks below serve basic reads/help when AI is not available.
    if (_runtime.ready) {
      return _answerReady(query, transcript, accountId, debug);
    }
    if (multiple) return conversationalSetupReply;
    final clarification = ChatFollowupContext.clarification(
      query,
      history ?? const [],
    );
    if (clarification != null) {
      debug.log('app_reply', {'source': 'unresolved_conversation_reference'});
      return clarification;
    }
    final resolvedQuestion = ChatFollowupContext.resolvedQuestion(
      query,
      transcript,
    );
    if (resolvedQuestion != null) {
      query = resolvedQuestion;
      debug.log('context_resolved', {'source': 'single_app_feature'});
    }
    final help = ChatHelpCatalog.direct(
      query,
      hasHelpContext: transcript.any(
        (m) =>
            m['isUser'] == true &&
            m['pending'] != true &&
            ChatScope.appHelp('${m['text']}') &&
            !ChatPlanConstraints.recordRequest('${m['text']}'),
      ),
    );
    if (help != null) {
      debug.log('app_reply', {'source': 'app_help_catalog'});
      return help;
    }
    final policyReply = ChatPolicy.requestReply(query);
    final normalized = ChatPolicy.normalizedQuestion(query);
    final followup = ChatPlanConstraints.isFollowup(query);
    final conversationPurpose = ChatScope.conversation(query, transcript);
    if (conversationPurpose == ConversationPurpose.boundary) {
      debug.log('app_reply', {'source': 'scope_correction'});
      return ChatScope.boundaryReply;
    }
    if (policyReply != null && policyReply != ChatPolicy.scopeReply) {
      debug.log('app_reply', {'source': 'input_policy'});
      return policyReply;
    }
    try {
      final answer = await _resolvedAnswer(query, transcript, accountId, debug);
      if (answer != null) return answer;
    } catch (error) {
      debug.error('resolved_read', error);
      return 'I could not read those records. Please try again.';
    }
    final hasPriorQuestion = transcript.any(
      (m) => m['isUser'] == true && m['text'] != query,
    );
    final explicitPeriod = RegExp(
      r'\b' + ChatPolicy.periodPattern + r'\b',
    ).hasMatch(normalized);
    // Fast, exact operations continue to work without a downloaded model.
    if (!_runtime.ready &&
        policyReply == null &&
        !followup &&
        (!hasPriorQuestion || explicitPeriod)) {
      try {
        return await _facts.answer(query, accountId: accountId);
      } catch (_) {
        return 'I could not complete that request. Please try again.';
      }
    }
    if (_isAiBusy || _runtime.busy) {
      return 'AI is processing another request. Please try again shortly.';
    }
    if (!_runtime.ready) {
      try {
        await init();
      } catch (_) {
        return conversationalSetupReply;
      }
      if (!_runtime.ready) return conversationalSetupReply;
    }
    return _answerReady(query, transcript, accountId, debug);
  }

  Future<String> _answerReady(
    String query,
    List<Map<String, dynamic>> transcript,
    int? accountId,
    ChatDebug debug,
  ) async {
    if (_isAiBusy || _runtime.busy) {
      return 'AI is processing another request. Please try again shortly.';
    }
    _isAiBusy = true;
    try {
      return await ChatConversationPipeline(
        interpreter: _interpreter ?? ModelChatInterpreter(_runtime),
        executor: ValidatedChatRecordExecutor(
          ChatQueryEngine(helper: _facts.helper, clock: _facts.clock),
        ),
        contexts: ChatQueryContextStore(_facts.helper),
        runtime: _runtime,
      ).answer(
        query,
        accountId: accountId,
        history: transcript,
        debug: debug,
        observeEvidence: _observeEvidence,
        observeDraft: _observeDraft,
        observePlan: _observePlan,
      );
    } on FormatException catch (error) {
      debug.error('chat_pipeline', error);
      return 'I could not reliably interpret that request. Could you rephrase it?';
    } on TimeoutException catch (error) {
      debug.error('chat_pipeline', error);
      return 'I could not complete that request in time. Please try again.';
    } on StateError catch (error) {
      debug.error('chat_pipeline', error);
      if (error.message == 'AI template restart required') {
        return 'Please close and reopen Spendy to apply the AI update.';
      }
      return 'I could not complete that request. Please try again.';
    } catch (error) {
      debug.error('chat_pipeline', error);
      return 'I could not complete that request. Please try again.';
    } finally {
      _isAiBusy = false;
    }
  }

  Future<AIAction> parseIntent(String text) async {
    AIAction fallback() => AIAction(
      type: AIActionType.chat,
      message:
          'I could not verify those details. Please add the transaction manually.',
    );
    if (text.trim().isEmpty || text.length > AiGuardrails.maxIntentChars) {
      return fallback();
    }
    final policyReply = ChatPolicy.unsafeOrAdviceReply(text);
    if (policyReply != null) {
      return AIAction(type: AIActionType.chat, message: policyReply);
    }
    if (_isAiBusy || _runtime.busy) {
      return AIAction(
        type: AIActionType.chat,
        message:
            'AI is still finishing a request. Try again shortly. If it stays busy, restart the app.',
      );
    }
    _isAiBusy = true;
    var intentStage = 'readiness';
    try {
      if (!_runtime.ready) return fallback();
      intentStage = 'local_validation';
      final local = _tryResolveLocally(text);
      if (local != null) {
        return await _validateCategories(
          AIAction.fromJson({
            'action': local.type.name.toUpperCase(),
            'amount': local.amount,
            'category': local.category,
            'merchant': local.merchant,
          }, text),
        );
      }
      intentStage = 'categories';
      final rows = await (await _facts.helper.database).query('categories');
      final categories = rows
          .where((r) => r['type'] == 'expense')
          .map((r) => r['name'])
          .whereType<String>();
      intentStage = 'extraction';
      final response = await _runtime.converse(
        VoiceIntentContract.request(text, categories),
      );
      intentStage = 'source_validation';
      final action = AIAction.fromJson(
        VoiceIntentContract.decode(response, text),
        text,
        validationSource: VoiceAllocations.normalize(text),
      );
      return await _validateCategories(action);
    } on TimeoutException {
      return AIAction(
        type: AIActionType.chat,
        message:
            'That took too long. Try again shortly. If AI stays busy, restart the app.',
      );
    } on FormatException catch (e) {
      debugPrint(
        'AI intent rejected: stage=$intentStage reason=${VoiceIntentContract.rejectionReason(e)}',
      );
      if (VoiceAllocations.applies(text)) {
        return AIAction(
          type: AIActionType.chat,
          message: e.message == 'Split does not match total'
              ? 'The item amounts don’t add up to the total. Try again or enter the expense manually.'
              : 'I couldn’t verify every split item and its total. Try again or enter the expense manually.',
        );
      }
      return fallback();
    } catch (e) {
      debugPrint(
        'AI intent rejected: stage=$intentStage error=${e.runtimeType}',
      );
      return fallback();
    } finally {
      _isAiBusy = false;
    }
  }

  Future<AIAction> _validateCategories(AIAction action) async {
    if (action.type == AIActionType.chat) {
      return AIAction(
        type: AIActionType.chat,
        message:
            'Please open Chat for questions, or add a transaction manually.',
      );
    }
    final rows = await (await _facts.helper.database).query('categories');
    final matchingCategories = rows
        .where(
          (r) =>
              (r['name'] as String).toLowerCase() ==
              action.category?.toLowerCase(),
        )
        .toList();
    if (action.type == AIActionType.add &&
        matchingCategories.isNotEmpty &&
        matchingCategories.every((r) => r['type'] == 'income')) {
      return AIAction(
        type: AIActionType.chat,
        message:
            'Please add this income manually to check its type, account and amount.',
      );
    }
    final known = {
      for (final row in rows)
        (row['name'] as String).toLowerCase(): row['name'] as String,
    };
    String category(String? value) => known[value?.toLowerCase()] ?? 'Other';
    // Extraction lists even one expense. A single fully covering item is an
    // ordinary transaction in the UI, rather than a one-child split.
    final single =
        action.type == AIActionType.add &&
            action.items?.length == 1 &&
            action.amount != null &&
            (action.items!.single.amount * 100).round() ==
                (action.amount! * 100).round()
        ? action.items!.single
        : null;
    final merchant = action.merchant ?? single?.merchant;
    return AIAction(
      type: action.type,
      amount: action.amount,
      category: action.type == AIActionType.add
          ? category(single?.category ?? action.category)
          : action.category,
      merchant: merchant == null
          ? null
          : AiGuardrails.bounded(merchant.trim(), 120),
      originalText: action.originalText,
      date: action.date,
      message: action.message,
      items: single != null
          ? null
          : action.items
                ?.map(
                  (i) => AISplitItem(
                    amount: i.amount,
                    category: category(i.category),
                    merchant: i.merchant,
                    label: i.label,
                  ),
                )
                .toList(),
    );
  }

  AIAction? _tryResolveLocally(String text) {
    final lower = text.toLowerCase().trim();

    // 1. Edit Pattern: "edit food [from] 500 to 600"
    final editRegex = RegExp(
      r'(edit|update)\s+([a-zA-Z]+)\s+(?:from\s+)?(\d+)\s+to\s+(\d+)',
      caseSensitive: false,
    );
    final editMatch = editRegex.firstMatch(lower);
    if (editMatch != null) {
      final category = editMatch.group(2);
      final newAmount = double.tryParse(editMatch.group(4) ?? '');
      if (newAmount != null) {
        return AIAction(
          type: AIActionType.update,
          category: category,
          amount: newAmount,
          originalText: text,
        );
      }
    }

    // 2. Add Pattern: "food 500" or "paid 500 for grocery"
    // Handle very simple "[Category] [Amount]"
    final addRegex = RegExp(r'^([a-zA-Z]+)\s+(\d+)$', caseSensitive: false);
    final addMatch = addRegex.firstMatch(lower);
    if (addMatch != null) {
      final category = addMatch.group(1);
      final amount = double.tryParse(addMatch.group(2) ?? '');
      if (amount != null) {
        return AIAction(
          type: AIActionType.add,
          category: category,
          amount: amount,
          originalText: text,
        );
      }
    }

    return null;
  }
}
