import 'inference_queue.dart';
import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../infrastructure/database/database_helper.dart';
import '../ai/model_download.dart';
import 'search_math.dart';

/// Rebuildable vectors stay in the same SQLCipher database as source records.
/// Nothing is uploaded: only the public, pinned model is downloaded.
class SemanticSearchService extends ChangeNotifier with WidgetsBindingObserver {
  static final SemanticSearchService _instance = SemanticSearchService._();
  factory SemanticSearchService() => _instance;
  SemanticSearchService._() {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([
        'all-MiniLM-L6-v2 · Sentence Transformers',
      ], await rootBundle.loadString('assets/search/LICENSE'));
    });
  }
  static const modelId = 'minilm-l6-v2-int8-1110a243-mean384-v1';
  static const modelBytes = 23026053;
  static const modelHash =
      '4278337fd0ff3c68bfb6291042cad8ab363e1d9fbc43dcb499fe91c871902474';
  static const modelUrl =
      'https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/1110a243fdf4706b3f48f1d95db1a4f5529b4d41/onnx/model_qint8_arm64.onnx';
  bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  bool enabled = false, indexing = false, downloading = false;
  int indexed = 0, total = 0;
  double downloadProgress = 0;
  String? error;
  OrtSession? _session;
  WordPieceTokenizer? _tokenizer;
  bool _active = false, _registered = false;
  Timer? _timer, _debounce;
  final _inference = InferenceQueue();
  CancelToken? _downloadCancel;
  Future<void>? _activation;
  Future<File> _file() async => File(
    '${(await getApplicationSupportDirectory()).path}/search_minilm_int8.onnx',
  );
  Future<void> activate() => _activation ??= _activate();
  Future<void> _activate() async {
    if (!supported) return;
    enabled =
        (await SharedPreferences.getInstance()).getBool(
          'semantic_search_enabled',
        ) ??
        false;
    if (!_registered) {
      WidgetsBinding.instance.addObserver(this);
      _registered = true;
    }
    _active = true;
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) => schedule());
    notifyListeners();
    schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) {
      schedule();
    } else {
      unawaited(
        _inference
            .cleanup(() async {
              await _session?.close();
              _session = null;
            })
            .catchError((Object _) {}),
      );
    }
  }

  Future<void> enable() async {
    if (downloading || !supported) return;
    await activate();
    downloading = true;
    error = null;
    notifyListeners();
    _downloadCancel = CancelToken();
    try {
      final file = await _file();
      if (!await file.exists() ||
          await file.length() != modelBytes ||
          (await sha256.bind(file.openRead()).first).toString() != modelHash) {
        await downloadVerifiedFile(
          url: modelUrl,
          expectedSize: modelBytes,
          sha256Hash: modelHash,
          partial: File('${file.path}.part'),
          destination: file,
          onProgress: (v) {
            downloadProgress = v;
            notifyListeners();
          },
          cancelToken: _downloadCancel,
        );
      }
      await _inference.run(_prepare);
      if (_downloadCancel?.isCancelled == true) {
        throw StateError("Setup cancelled");
      }
      await (await SharedPreferences.getInstance()).setBool(
        'semantic_search_enabled',
        true,
      );
      enabled = true;
    } catch (_) {
      error = _downloadCancel?.isCancelled == true
          ? null
          : 'Could not set up search. Check your connection and try again.';
    } finally {
      downloading = false;
      _downloadCancel = null;
      notifyListeners();
      schedule();
    }
  }

  void retryIndexing() {
    error = null;
    notifyListeners();
    schedule();
  }

  void cancelDownload() => _downloadCancel?.cancel();
  Future<void> disable() async {
    _downloadCancel?.cancel();
    enabled = false;
    _debounce?.cancel();
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(
      'semantic_search_enabled',
      false,
    );
    await _inference
        .cleanup(() async {
          await _session?.close();
          _session = null;
        })
        .timeout(const Duration(seconds: 2), onTimeout: () {});
    await (await DatabaseHelper().database).delete('transaction_vectors');
    indexed = 0;
    error = null;
    notifyListeners();
  }

  Future<void> _prepare() async {
    if (_session != null) return;
    final file = await _file();
    if (!await file.exists() ||
        await file.length() != modelBytes ||
        (await sha256.bind(file.openRead()).first).toString() != modelHash) {
      throw const FormatException('Search model verification failed');
    }
    _tokenizer ??= WordPieceTokenizer(
      await rootBundle.loadString('assets/search/vocab.txt'),
    );
    _session = await OnnxRuntime().createSession(
      file.path,
      options: OrtSessionOptions(intraOpNumThreads: 2, interOpNumThreads: 1),
    );
  }

  Future<List<double>> _embed(String text) => _inference.run(() async {
    await _prepare();
    final ids = _tokenizer!.encode(text);
    final tensors = <String, OrtValue>{};
    Map<String, OrtValue>? outputs;
    try {
      tensors['input_ids'] = await OrtValue.fromList(Int64List.fromList(ids), [
        1,
        ids.length,
      ]);
      tensors['attention_mask'] = await OrtValue.fromList(
        Int64List.fromList(List.filled(ids.length, 1)),
        [1, ids.length],
      );
      if (_session!.inputNames.contains('token_type_ids')) {
        tensors['token_type_ids'] = await OrtValue.fromList(
          Int64List(ids.length),
          [1, ids.length],
        );
      }
      outputs = await _session!.run(tensors);
      final output = outputs['last_hidden_state'] ?? outputs.values.first;
      return meanPool(await output.asFlattenedList(), ids.length, 384);
    } finally {
      for (final tensor in tensors.values) {
        await tensor.dispose();
      }
      if (outputs != null) {
        for (final tensor in outputs.values) {
          await tensor.dispose();
        }
      }
    }
  });
  static String describe(Map<String, Object?> row) =>
      'Merchant: ${row['merchant'] ?? ''}. Category: ${row['category'] ?? ''}. Notes: ${row['note'] ?? ''}.';
  void schedule() {
    if (!enabled ||
        error != null ||
        !_active ||
        indexing ||
        downloading ||
        _debounce?.isActive == true) {
      return;
    }
    _debounce = Timer(const Duration(seconds: 2), () {
      unawaited(_index());
    });
  }

  Future<void> _index() async {
    if (!enabled || !_active || indexing) return;
    indexing = true;
    error = null;
    notifyListeners();
    try {
      final db = await DatabaseHelper().database;
      await db.delete(
        'transaction_vectors',
        where: 'model != ?',
        whereArgs: [modelId],
      );
      while (enabled && _active) {
        final pending = await db.rawQuery(
          'SELECT t.* FROM transactions t LEFT JOIN transaction_vectors v ON v.transaction_id = t.id WHERE v.transaction_id IS NULL ORDER BY t.id LIMIT 20',
        );
        total =
            (await db.rawQuery(
                  'SELECT COUNT(*) AS n FROM transactions',
                )).single['n']
                as int;
        indexed =
            (await db.rawQuery(
                  'SELECT COUNT(*) AS n FROM transaction_vectors',
                )).single['n']
                as int;
        notifyListeners();
        if (pending.isEmpty) break;
        for (final row in pending) {
          if (!enabled || !_active) break;
          final source = describe(row);
          final vector = await _embed(source);
          if (!enabled || !_active) break;
          final bytes = ByteData(384 * 4);
          for (var i = 0; i < 384; i++) {
            bytes.setFloat32(i * 4, vector[i], Endian.little);
          }
          await db.transaction((txn) async {
            final current = await txn.query(
              'transactions',
              where: 'id = ?',
              whereArgs: [row['id']],
            );
            if (current.isEmpty ||
                describe(current.single) != source ||
                !enabled) {
              return;
            }
            await txn.rawInsert(
              'INSERT OR REPLACE INTO transaction_vectors(transaction_id, model, source, vector) VALUES(?,?,?,?)',
              [row['id'], modelId, source, bytes.buffer.asUint8List()],
            );
          });
          indexed++;
          notifyListeners();
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      }
    } catch (_) {
      error = 'Could not finish preparing search. Try again.';
    } finally {
      indexing = false;
      notifyListeners();
    }
  }

  Future<List<Map<String, Object?>>> search(
    List<Map<String, Object?>> rows,
    String query,
  ) async {
    if (query.trim().isEmpty) return [];
    if (query.length > 600) query = query.substring(0, 600);
    if (!enabled || !supported) {
      return rows
          .where((r) => describe(r).toLowerCase().contains(query.toLowerCase()))
          .toList();
    }
    try {
      final queryVector = await _embed(query);
      final db = await DatabaseHelper().database;
      final vectors = await db.query(
        'transaction_vectors',
        where: 'model = ?',
        whereArgs: [modelId],
      );
      final ranked = await compute(_rankSearchResults, (
        rows,
        vectors,
        query,
        queryVector,
      ));
      final byId = {for (final row in rows) row['id'] as int: row};
      schedule();
      return ranked.take(50).map((id) => byId[id]!).toList();
    } catch (_) {
      error = 'Improved search is unavailable. Showing keyword matches.';
      notifyListeners();
      return rows
          .where((r) => describe(r).toLowerCase().contains(query.toLowerCase()))
          .toList();
    }
  }
}

List<int> _rankSearchResults(
  (List<Map<String, Object?>>, List<Map<String, Object?>>, String, List<double>)
  data,
) {
  final (rows, vectors, query, queryVector) = data;
  final byId = {for (final row in rows) row['id'] as int: row};
  final scored = <int, double>{};
  for (final stored in vectors) {
    final id = stored['transaction_id'] as int;
    if (!byId.containsKey(id) ||
        stored['source'] != SemanticSearchService.describe(byId[id]!)) {
      continue;
    }
    final bytes = ByteData.sublistView(stored['vector'] as Uint8List);
    if (bytes.lengthInBytes != 384 * 4) continue;
    final vector = List.generate(
      384,
      (i) => bytes.getFloat32(i * 4, Endian.little),
    );
    final score = cosine(queryVector, vector);
    if (score >= .25) scored[id] = score;
  }
  final semantic = scored.keys.toList()
    ..sort((a, b) => scored[b]!.compareTo(scored[a]!));
  final lexical = lexicalRanking(
    byId.map((id, row) => MapEntry(id, SemanticSearchService.describe(row))),
    query,
  );
  final ranked = reciprocalRankFusion(lexical, semantic.take(30).toList());
  return ranked;
}
