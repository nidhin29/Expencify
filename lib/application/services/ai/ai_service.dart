import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:expencify/infrastructure/database/database_helper.dart';
import 'package:intl/intl.dart';
import 'local_ai_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:expencify/infrastructure/repositories/sqlite_account_repository.dart';
import 'package:expencify/infrastructure/repositories/sqlite_transaction_repository.dart';
import 'package:expencify/infrastructure/repositories/sqlite_goal_repository.dart';
import 'package:expencify/infrastructure/repositories/sqlite_reminder_repository.dart';

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

  factory AIAction.fromJson(Map<String, dynamic> json, String original) {
    // 💎 Fallback: If model hallucinates metadata into the 'items' list,
    // promote missing keys upwards to the parent object.
    final itemsList = json['items'] as List?;
    if (itemsList != null) {
      for (var i in itemsList) {
        if (i is Map<String, dynamic>) {
          if (json['date'] == null && i['date'] != null) {
            json['date'] = i['date'];
          }
          if (json['merchant'] == null && i['merchant'] != null) {
            json['merchant'] = i['merchant'];
          }
          if ((json['amount'] ?? json['value']) == null &&
              i['amount'] != null) {
            json['amount'] = i['amount'];
          }
        }
      }
    }

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

    // Parse date if present
    DateTime? parsedDate;
    if (json['date'] != null) {
      parsedDate = DateTime.tryParse(json['date'].toString());
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

  AISplitItem({required this.amount, required this.category, this.merchant});

  factory AISplitItem.fromJson(Map<String, dynamic> json) {
    return AISplitItem(
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      category: json['category']?.toString() ?? 'Other',
      merchant: json['merchant']?.toString(),
    );
  }
}

class AIService {
  static const _channel = MethodChannel('com.example.expencify/asset_delivery');
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  LocalAIModelMetadata? _currentModel;
  LocalAIModelMetadata? get currentModel => _currentModel;

  InferenceModelSession? _activeSession;
  InferenceModel? _activeModel;
  bool _isAiBusy = false;
  Future<void>? _initFuture;

  Future<void> init([LocalAIModelType? type]) async {
    if (_initFuture != null) return _initFuture;

    _initFuture = _initInternal(type);
    try {
      await _initFuture;
    } finally {
      _initFuture = null;
    }
  }

  Future<void> _initInternal([LocalAIModelType? type]) async {
    // If already initialized with the same model, skip
    if (_initialized && (_currentModel?.id == type || type == null)) return;

    // Manual registration workaround for Desktop platforms
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      FlutterGemmaDesktop.registerWith();
    }

    await FlutterGemma.initialize();

    // Use default if nothing specified and no current model
    // Qwen 2.5 0.5B is now the default as requested
    final targetType = type ?? _currentModel?.id ?? LocalAIModelType.qwenLite;
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

      // 1b. Development Fallback: Check /sdcard/Download (PAD doesn't work in sideloaded builds)
      if (foundModelPath == null) {
        final devPath = '/sdcard/Download/${metadata.fileName}';
        if (await File(devPath).exists()) {
          debugPrint('AI: Detected model in Sideload/Download folder.');
          final directory = await getApplicationDocumentsDirectory();
          final localPath = '${directory.path}/${metadata.fileName}';

          if (!await File(localPath).exists()) {
            debugPrint(
              'AI: Requesting All Files Access (Manage External Storage) for migration...',
            );
            // On Android 11+ we need this for direct path access to /sdcard/Download
            if (await Permission.manageExternalStorage.isDenied) {
              await Permission.manageExternalStorage.request();
            }

            debugPrint('AI: Copying to internal storage (Source: $devPath)...');
            try {
              final sourceFile = File(devPath);
              final sourceSize = await sourceFile.length();
              debugPrint(
                'AI: Source file size: ${sourceSize / (1024 * 1024)} MB',
              );

              await sourceFile.copy(localPath);

              final targetFile = File(localPath);
              final targetSize = await targetFile.length();
              debugPrint(
                'AI: target migration complete. Target file size: ${targetSize / (1024 * 1024)} MB',
              );
            } catch (e) {
              debugPrint('AI: Copy failed: $e');
            }
          } else {
            final targetFile = File(localPath);
            final size = await targetFile.length();
            debugPrint(
              'AI: Existing model size in internal storage: ${size / (1024 * 1024)} MB',
            );
          }
          foundModelPath = localPath;
        }
      }
    }

    // 2. Fallback to Documents Directory (Manual download)
    if (foundModelPath == null) {
      final directory = await getApplicationDocumentsDirectory();
      final localPath = '${directory.path}/${metadata.fileName}';

      // CLEANUP: Detect and delete invalid/legacy model files to prevent crashes
      final wrongExtensions = ['.tflite', '.litertlm', '.bin'];
      for (var ext in wrongExtensions) {
        if (metadata.fileName.endsWith(ext)) continue;

        final invalidPath = localPath.replaceAll(
          metadata.fileName.substring(metadata.fileName.lastIndexOf('.')),
          ext,
        );
        if (await File(invalidPath).exists()) {
          debugPrint('AI: Deleting invalid legacy model file: $invalidPath');
          try {
            await File(invalidPath).delete();
          } catch (e) {
            debugPrint('AI Cleanup Error: $e');
          }
        }
      }

      if (await File(localPath).exists()) {
        foundModelPath = localPath;
        debugPrint('AI: Found model in Documents Directory: $localPath');
      }
    }

    if (foundModelPath != null) {
      final file = File(foundModelPath);
      final bytes = await file.length();
      debugPrint('AI: Loading model from: $foundModelPath ($bytes bytes)');

      if (bytes == 0) {
        debugPrint('AI Error: Model file is empty.');
        _initialized = false;
        return;
      }

      try {
        await FlutterGemma.installModel(
          modelType: metadata.flutterGemmaModelType,
          fileType: metadata.fileType,
        ).fromFile(foundModelPath).install();

        _currentModel = metadata;
        _initialized = true;
        debugPrint('AI: Model installation successful.');
      } catch (e) {
        debugPrint('AI Initialization Error: $e');
        _initialized = false;
      }
    } else {
      _initialized = false;
      _currentModel = metadata;
      debugPrint('AI: Model not found locally. Download required.');
    }
  }

  Future<bool> modelExists(LocalAIModelType type) async {
    final metadata = LocalAIModelMetadata.all.firstWhere((m) => m.id == type);
    debugPrint(
      'AI: Checking existence for ${metadata.fileName} (ID: ${type.name})',
    );

    // 1. Check Play Asset Delivery (Android)
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final String? packPath = await _channel.invokeMethod(
          'getAssetPackPath',
          {'packName': 'model_pack'},
        );
        debugPrint('AI: PAD Pack Path: $packPath');
        if (packPath != null) {
          final fullPath = '$packPath/${metadata.fileName}';
          if (await File(fullPath).exists()) {
            debugPrint('AI: Found in PAD: $fullPath');
            return true;
          }
        }
      } catch (e) {
        debugPrint('AI: modelExists PAD check failed: $e');
      }

      // 1b. Dev Fallback for modelExists
      final devPath = '/sdcard/Download/${metadata.fileName}';
      if (await File(devPath).exists()) {
        debugPrint(
          'AI: Found in Sideload/Download (Migration pending): $devPath',
        );
        return true;
      }
    }

    // 2. Check Local Documents
    final directory = await getApplicationDocumentsDirectory();
    final localPath = '${directory.path}/${metadata.fileName}';
    final exists = await File(localPath).exists();
    debugPrint('AI: Checked local path: $localPath | exists: $exists');
    return exists;
  }

  Future<void> downloadModel(
    LocalAIModelMetadata metadata,
    Function(double) onProgress,
  ) async {
    final directory = await getApplicationDocumentsDirectory();
    final modelPath = '${directory.path}/${metadata.fileName}';

    await Dio().download(
      metadata.url,
      modelPath,
      onReceiveProgress: (count, total) {
        if (total != -1) {
          onProgress(count / total);
        }
      },
    );
    await init(metadata.id);
  }

  Future<void> clearSession() async {
    await _activeSession?.close();
    _activeSession = null;
    _activeModel = null;
    debugPrint('AI: Session cleared.');
  }

  Future<String> ask(
    String query, {
    int? accountId,
    List<Map<String, dynamic>>? history,
  }) async {
    if (!_initialized || _currentModel == null) return 'AI not initialized.';

    try {
      // Fresh session per query: prevents KV-cache overflow in tiny 1024-token windows.
      // Re-using sessions causes system-prompt + history to consume ALL available tokens,
      // leaving no room for the AI to actually generate a response.
      await clearSession();

      final isCpuModel = _currentModel!.fileName.contains('cpu');
      if (isCpuModel && Platform.isAndroid) {
        _activeModel = await FlutterGemma.getActiveModel(
          maxTokens: 1024,
          preferredBackend: PreferredBackend.cpu,
        );
      } else {
        _activeModel = await FlutterGemma.getActiveModel(maxTokens: 1024);
      }
      _activeSession = await _activeModel!.createSession(
        temperature: 0.4,
        topK: 40,
      );

      // Compact financial snapshot
      final context = await _buildRAGContext(query, accountId: accountId);

      // Include only the very last AI response as a chat hint (saves tokens vs full history)
      String chatHint = '';
      if (history != null && history.isNotEmpty) {
        final lastAIMsg = history.lastWhere(
          (m) => m['isUser'] != true,
          orElse: () => {},
        );
        final lastText = lastAIMsg['text']?.toString() ?? '';
        if (lastText.isNotEmpty) {
          chatHint =
              'Prior answer: ${lastText.length > 120 ? lastText.substring(0, 120) : lastText}\n';
        }
      }

      final q = query.toLowerCase();
      bool isAdviceQuery =
          q.contains('reduce') ||
          q.contains('how to') ||
          q.contains('why') ||
          q.contains('explain') ||
          q.contains('guidance') ||
          q.contains('tip') ||
          q.contains('improve') ||
          q.contains('what mean') ||
          q.contains('advice');

      // Single lean prompt — maximises token budget available for the response
      final prompt = isAdviceQuery
          ? 'You are Expencify AI, a helpful Indian finance assistant. '
                'Provide helpful advice. Answer concisely. Do NOT use numbers unless present below.\n'
                '$chatHint'
                'Data: $context\n'
                'User: $query\n'
                'Answer:'
          : 'You are Expencify AI, a concise Indian finance assistant. '
                'Answer in 1-2 short sentences using ONLY the numbers below. Do NOT invent data.\n'
                '$chatHint'
                'Data: $context\n'
                'User: $query\n'
                'Answer:';

      debugPrint('AI: Processing query (fresh session).');
      await _activeSession!.addQueryChunk(Message(text: prompt, isUser: true));

      debugPrint('AI: Generating response...');
      String response = '';
      final stream = _activeSession!.getResponseAsync();

      bool shouldStop = false;
      await for (final token in stream) {
        if (shouldStop) continue; // drain remaining tokens without accumulating

        response += token;

        // Stop accumulating on char-sequence repetition (loop guard).
        // Use a flag instead of break/nested listen to avoid two errors:
        // 1. break → IllegalStateException (C++ engine still running on next clearSession)
        // 2. nested await for → "Bad state: Stream has already been listened to"
        if (response.length > 80) {
          final tail = response.substring(response.length - 40);
          final head = response.substring(0, response.length - 40);
          if (head.contains(tail)) {
            debugPrint(
              'AI: Char-loop detected. Draining remaining stream silently.',
            );

            // Graceful cleanup: trim back to the last period or newline
            int lastPeriod = response.lastIndexOf('.');
            int lastNewline = response.lastIndexOf('\n');
            int cutIndex = lastPeriod > lastNewline ? lastPeriod : lastNewline;

            if (cutIndex > response.length - 60) {
              // arbitrary buffer
              response = response.substring(0, cutIndex + 1);
            } else {
              response = head.trim(); // fallback
            }
            shouldStop = true;
          }
        }
      }

      // Final cleanup: unescape newlines outputted as literal text by small models
      response = response.replaceAll('\\n', '\n').trim();

      debugPrint('AI: Response successful.');
      return response;
    } catch (e) {
      debugPrint('AI Fatal Error: $e');
      await clearSession();
      return 'Error: $e';
    }
  }

  Future<AIAction> parseIntent(String text) async {
    if (_isAiBusy) {
      return AIAction(
        type: AIActionType.chat,
        message: 'AI is currently busy processing another request.',
      );
    }
    _isAiBusy = true;

    try {
      if (!_initialized || _currentModel == null) {
        final exists = await modelExists(LocalAIModelType.qwenLite);
        final message = exists
            ? 'AI is initializing, please try again in a moment.'
            : 'AI model not found. Please open the Chat screen to download it.';
        return AIAction(type: AIActionType.chat, message: message);
      }

      // Check for local resolver first (Regex)
      final localAction = _tryResolveLocally(text);
      if (localAction != null) {
        debugPrint('AI: Resolved locally via Regex.');
        return localAction;
      }

      final now = DateTime.now();
      final systemPrompt =
          '''
You are Expencify AI. Parse transaction/OCR text into JSON.
Current Date: ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}
Categories: [Food, Fuel, Shopping, Rent, Travel, Health, Salary, Bills, Grocery, Other].
Rules:
- "edit/update" means ACTION: UPDATE.
- Extract "merchant" if mentioned.
- Extract "date" as YYYY-MM-DD if mentioned (handle "yesterday", "2 days ago").
- Identify Indian context (e.g. Joseph Joseph = Fuel).
- For OCR, find "TOTAL". OUTPUT VALID JSON ONLY.
- If multiple items are listed, extract them into "items" list with "amount" and "category".
- EXAMPLES:
"edit food from 500 to 600" -> {"action": "UPDATE", "amount": 600, "category": "Food"}
"paid 500 at zomato yesterday" -> {"action": "ADD", "amount": 500, "category": "Food", "merchant": "Zomato", "date": "2026-02-23"}
"spent 1200 on fuel at shell" -> {"action": "ADD", "amount": 1200, "category": "Fuel", "merchant": "Shell"}
"200 on groceries" -> {"action": "ADD", "amount": 200, "category": "Grocery"}
"buy items 30 sugar 60 milk 40 salt" -> {"action": "ADD", "amount": 130, "items": [{"amount": 30, "category": "Sugar"}, {"amount": 60, "category": "Milk"}, {"amount": 40, "category": "Salt"}]}
"update 500 market items 30 salt 60 sugar" -> {"action": "UPDATE", "amount": 500, "merchant": "Market", "items": [{"amount": 30, "category": "Salt"}, {"amount": 60, "category": "Sugar"}]}

Input: "MART RECEIPT\nMilk: 50.0\nBread: 40.0\nTotal: 90.0"
Output: {"action": "ADD", "amount": 90, "merchant": "Mart", "items": [{"amount": 50, "category": "Grocery"}, {"amount": 40, "category": "Grocery"}]}

COMMAND: "''';

      if (_activeModel == null) {
        if (Platform.isAndroid) {
          // Force CPU backend for Intent Parsing to prevent Native TFLite GPU Delegate dimension/shader crashes
          _activeModel = await FlutterGemma.getActiveModel(
            maxTokens: 1024,
            preferredBackend: PreferredBackend.cpu,
          );
        } else {
          _activeModel = await FlutterGemma.getActiveModel(maxTokens: 1024);
        }
      }

      // Use a fresh session for intent parsing to avoid history interference
      final session = await _activeModel!.createSession(
        temperature: 0.0,
        topK: 1,
      );
      final fullQuery = '$systemPrompt$text"\nJSON:';

      debugPrint('AI Intent Parsing: $text');
      await session.addQueryChunk(Message(text: fullQuery, isUser: true));
      String response = await session.getResponse();
      await session
          .close(); // Prevent memory leaks from dangling LLM context bindings!

      if (response.trim().isEmpty) {
        debugPrint(
          'AI Returned Empty Intent. Retrying with temperature backoff (0.3)...',
        );
        final retrySession = await _activeModel!.createSession(
          temperature: 0.3, // Slightly higher to escape deterministic deadlocks
          topK: 20,
        );
        await retrySession.addQueryChunk(
          Message(text: fullQuery, isUser: true),
        );
        response = await retrySession.getResponse();
        await retrySession.close();
        debugPrint('AI Retry Intent Raw: $response');
      }
      debugPrint('AI Raw Intent: $response');

      // Clean response (remove markdown blocks if model adds them)
      String cleaned = response.trim();
      if (cleaned.contains('```json')) {
        cleaned = cleaned.split('```json')[1].split('```')[0].trim();
      } else if (cleaned.contains('```')) {
        cleaned = cleaned.split('```')[1].split('```')[0].trim();
      }

      // Safeguard against small LLM repetition loops ("Reached max sequence length")
      // by extracting ONLY the very first balanced JSON object.
      final startIndex = cleaned.indexOf('{');
      if (startIndex != -1) {
        int braceCount = 0;
        int endIndex = -1;
        for (int i = startIndex; i < cleaned.length; i++) {
          if (cleaned[i] == '{') {
            braceCount++;
          } else if (cleaned[i] == '}') {
            braceCount--;
          }

          if (braceCount == 0) {
            endIndex = i;
            break;
          }
        }
        if (endIndex != -1) {
          cleaned = cleaned.substring(startIndex, endIndex + 1);
        }
      }

      try {
        final Map<String, dynamic> json = jsonDecode(cleaned);
        return AIAction.fromJson(json, text);
      } catch (e) {
        // AI Response was truncated, attempt to repair partial JSON structure via Backtracking Stack.
        try {
          String repaired = cleaned.trim();
          Map<String, dynamic>? parsedJson;

          while (repaired.isNotEmpty) {
            try {
              String temp = repaired.trim();
              if (temp.endsWith(',')) temp = temp.substring(0, temp.length - 1);

              List<String> stack = [];
              bool inString = false;
              bool escapeNext = false;

              for (int i = 0; i < temp.length; i++) {
                String c = temp[i];
                if (escapeNext) {
                  escapeNext = false;
                  continue;
                }
                if (c == '\\') {
                  escapeNext = true;
                  continue;
                }
                if (c == '"') {
                  inString = !inString;
                  continue;
                }
                if (!inString) {
                  if (c == '{') {
                    stack.add('}');
                  } else if (c == '[') {
                    stack.add(']');
                  } else if (c == '}' &&
                      stack.isNotEmpty &&
                      stack.last == '}') {
                    stack.removeLast();
                  } else if (c == ']' &&
                      stack.isNotEmpty &&
                      stack.last == ']') {
                    stack.removeLast();
                  }
                }
              }

              StringBuffer sb = StringBuffer(temp);
              if (inString) sb.write('"');
              for (var closing in stack.reversed) {
                sb.write(closing);
              }

              parsedJson = jsonDecode(sb.toString());
              if (parsedJson != null) {
                break; // Found valid longest JSON truncation
              }
            } catch (_) {}
            repaired = repaired.substring(
              0,
              repaired.length - 1,
            ); // Trim last character and try again
          }

          if (parsedJson != null) {
            return AIAction.fromJson(parsedJson, text);
          }
        } catch (_) {}

        debugPrint('AI Intent Error: $e');
        await clearSession();
        return AIAction(
          type: AIActionType.chat,
          message: text,
        ); // Fallback to raw text
      }
    } catch (e) {
      debugPrint('AI Intent Outer Error: $e');
      await clearSession();
      return AIAction(type: AIActionType.chat, message: text);
    } finally {
      _isAiBusy = false;
    }
  }

  Future<String> _buildRAGContext(String query, {int? accountId}) async {
    final q = query.toLowerCase();
    final db = DatabaseHelper();
    final accRepo = SqliteAccountRepository(db);
    final txnRepo = SqliteTransactionRepository(db);
    final goalRepo = SqliteGoalRepository(db);
    final reminderRepo = SqliteReminderRepository(db);
    StringBuffer context = StringBuffer();

    // 1. ALWAYS ADD A SNAPSHOT (Total Balance & Month Totals)
    final totalBalance = await accRepo.getTotalBalance(accountId: accountId);
    final monthIncome = await txnRepo.getMonthTotal(
      'income',
      accountId: accountId,
    );
    final monthExpense = await txnRepo.getMonthTotal(
      'expense',
      accountId: accountId,
    );

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final todayExpense = await txnRepo.getRangeTotal(
      'expense',
      from: todayStart,
      to: todayEnd,
      accountId: accountId,
    );

    final daysElapsed = now.day > 0 ? now.day : 1;
    final dailyAverage = monthExpense / daysElapsed;
    final projectedExpense = dailyAverage * 30;

    context.writeln('--- FINANCIAL SNAPSHOT ---');
    context.writeln('Total Balance: ₹${totalBalance.toStringAsFixed(2)}');
    context.writeln('Today\'s Expenses: ₹${todayExpense.toStringAsFixed(2)}');
    context.writeln('This Month Income: ₹${monthIncome.toStringAsFixed(2)}');
    context.writeln('This Month Expenses: ₹${monthExpense.toStringAsFixed(2)}');
    context.writeln(
      'Average Daily Spent (This Month): ₹${dailyAverage.toStringAsFixed(2)}',
    );
    context.writeln(
      'Projected Monthly Spending: ₹${projectedExpense.toStringAsFixed(2)}',
    );
    context.writeln('--------------------------\n');

    // 2. Conditional Context based on keywords

    // Transactions & Spending
    if (q.contains('spend') ||
        q.contains('spent') ||
        q.contains('transaction') ||
        q.contains('cost') ||
        q.contains('buy') ||
        q.contains('bought')) {
      DateTime now = DateTime.now();
      DateTime weekAgo = now.subtract(const Duration(days: 7));
      final transactions = await txnRepo.getTransactions(
        from: weekAgo,
        limit: 10,
        accountId: accountId,
      );

      if (transactions.isNotEmpty) {
        context.writeln('Recent Activity (Last 7 Days):');
        for (var t in transactions) {
          context.writeln(
            '- ${DateFormat('MMM d').format(t.date)}: ₹${t.amount} (${t.type}) for ${t.category} @ ${t.merchant}',
          );
        }
      }
    }

    // Income specifically
    if (q.contains('income') ||
        q.contains('earn') ||
        q.contains('salary') ||
        q.contains('received')) {
      final income = await txnRepo.getTransactions(
        type: 'income',
        limit: 10,
        accountId: accountId,
      );
      if (income.isNotEmpty) {
        context.writeln('\nRecent Income Sources:');
        for (var i in income) {
          context.writeln(
            '- ${DateFormat('MMM d').format(i.date)}: ₹${i.amount} from ${i.category}',
          );
        }
      }
    }

    // Budgets
    if (q.contains('budget') || q.contains('limit') || q.contains('left')) {
      final budgets = await db.queryAll('budgets');
      if (budgets.isNotEmpty) {
        context.writeln('\nMonthly Budgets:');
        for (var b in budgets) {
          context.writeln(
            '- ${b['category']}: ₹${b['amount']} / ${b['period']}',
          );
        }
      }
    }

    // Accounts
    if (q.contains('account') ||
        q.contains('bank') ||
        q.contains('wallet') ||
        q.contains('where is my money')) {
      final accounts = await accRepo.getAll();
      context.writeln('\nAll Accounts:');
      for (var a in accounts) {
        context.writeln('- ${a.name} (${a.bankName}): ₹${a.balance}');
      }
    }

    // Goals
    if (q.contains('goal') ||
        q.contains('save') ||
        q.contains('saving') ||
        q.contains('target')) {
      final goals = await goalRepo.getAll();
      if (goals.isNotEmpty) {
        context.writeln('\nSavings Progress:');
        for (var g in goals) {
          final percent = (g.savedAmount / g.targetAmount * 100)
              .toStringAsFixed(1);
          context.writeln(
            '- ${g.name}: ₹${g.savedAmount} of ₹${g.targetAmount} ($percent%)',
          );
        }
      }
    }

    // Reminders
    if (q.contains('reminder') || q.contains('bill') || q.contains('due')) {
      final reminders = await reminderRepo.getAll();
      if (reminders.isNotEmpty) {
        context.writeln('\nUpcoming Bills/Reminders:');
        for (var r in reminders) {
          context.writeln(
            '- ${r.title}: ₹${r.amount} due on ${DateFormat('MMM d').format(r.dueDate)}',
          );
        }
      }
    }

    return context.toString();
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
