import 'dart:io';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter/foundation.dart';

enum LocalAIModelType {
  qwenLite, // Legacy iOS runtime.
  qwen3Small,
}

enum LocalModelRuntime { mediaPipe, liteRtLm }

class LocalAIModelMetadata {
  final LocalAIModelType id;
  final String name;
  final String description;
  final String size;
  final int minSize; // In bytes
  final int expectedSize;
  final String sha256Hash;
  final String fileName;
  final String url;
  final ModelType flutterGemmaModelType;
  final ModelFileType fileType;
  final int contextTokens;
  final LocalModelRuntime runtime;

  const LocalAIModelMetadata({
    required this.id,
    required this.name,
    required this.description,
    required this.size,
    required this.minSize,
    required this.expectedSize,
    required this.sha256Hash,
    required this.fileName,
    required this.url,
    required this.flutterGemmaModelType,
    this.fileType = ModelFileType.binary,
    this.contextTokens = 1024,
    this.runtime = LocalModelRuntime.mediaPipe,
  });

  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // The native LiteRT-LM adapter is Android-only. Keep iOS's existing model
  // until its native adapter is implemented rather than advertise an unusable file.
  static List<LocalAIModelMetadata> get all => [
    Platform.isIOS ? legacyQwen : qwen3,
  ];

  static const qwen3 = LocalAIModelMetadata(
    id: LocalAIModelType.qwen3Small,
    name: 'Qwen3 0.6B',
    description: 'Offline text model from LiteRT Community, quantized to INT4.',
    size: '343 MB',
    minSize: 343490560,
    expectedSize: 343490560,
    sha256Hash:
        'bf1aba9ce8d963124407353c6aa4cbf72eba78db21ae133de983eac672ce83e0',
    fileName: 'Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm',
    url:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/2670e142a0d16a1b685be6604e5b4f2b31a826d7/Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm',
    flutterGemmaModelType: ModelType.qwen,
    fileType: ModelFileType.task,
    contextTokens: 2048,
    runtime: LocalModelRuntime.liteRtLm,
  );

  static const legacyQwen = LocalAIModelMetadata(
    id: LocalAIModelType.qwenLite,
    name: 'Qwen 2.5 0.5B',
    description: 'Offline text model from LiteRT Community, quantized to INT8.',
    size: '547 MB',
    minSize: 546660344,
    expectedSize: 546660344,
    sha256Hash:
        'e608953f169aeb1bd7b9155fec2559825e08453fc209b84eda3a781ed0452fd2',
    fileName: 'Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
    url:
        'https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/resolve/063da0a7c3baec2dbfb79b95947a434d2634b260/Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
    flutterGemmaModelType: ModelType.qwen,
    fileType: ModelFileType.task,
    contextTokens: 1024,
  );
}
