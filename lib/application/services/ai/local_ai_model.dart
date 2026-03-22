import 'dart:io';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter/foundation.dart';

enum LocalAIModelType {
  qwenLite, // Qwen 2.5 0.5B
}

class LocalAIModelMetadata {
  final LocalAIModelType id;
  final String name;
  final String description;
  final String size;
  final int minSize; // In bytes
  final String fileName;
  final String url;
  final ModelType flutterGemmaModelType;
  final ModelFileType fileType;

  const LocalAIModelMetadata({
    required this.id,
    required this.name,
    required this.description,
    required this.size,
    required this.minSize,
    required this.fileName,
    required this.url,
    required this.flutterGemmaModelType,
    this.fileType = ModelFileType.binary,
  });

  static List<LocalAIModelMetadata> get all {
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    if (isDesktop) {
      return [
        const LocalAIModelMetadata(
          id: LocalAIModelType.qwenLite,
          name: 'Qwen 3 0.6B (Lite)',
          description: 'Faster and smaller, good for mid-range devices.',
          size: '586 MB',
          minSize: 500 * 1024 * 1024, // ~500 MB
          fileName: 'qwen3-0_6b-it-gpu-int4.task',
          url:
              'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/qwen3-0_6b-it-gpu-int4.task',
          flutterGemmaModelType: ModelType.qwen,
          fileType: ModelFileType.task,
        ),
      ];
    }

    // Default (Android/iOS/Web)
    return [
      const LocalAIModelMetadata(
        id: LocalAIModelType.qwenLite,
        name: 'Qwen 0.5B (Lite)',
        description: 'Faster and smaller, good for mid-range devices.',
        size: '547 MB',
        minSize: 500 * 1024 * 1024, // ~500 MB
        fileName: 'Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
        url:
            'https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/resolve/main/Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
        flutterGemmaModelType: ModelType.qwen,
        fileType: ModelFileType.task,
      ),
    ];
  }
}
