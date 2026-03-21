import 'dart:io';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter/foundation.dart';

enum LocalAIModelType {
  gemmaStandard, // Gemma 2B
  qwenLite, // Qwen 2.5 0.5B
  smolUltraLite, // SmolLM 135M
}

class LocalAIModelMetadata {
  final LocalAIModelType id;
  final String name;
  final String description;
  final String size;
  final String fileName;
  final String url;
  final ModelType flutterGemmaModelType;
  final ModelFileType fileType;

  const LocalAIModelMetadata({
    required this.id,
    required this.name,
    required this.description,
    required this.size,
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
          id: LocalAIModelType.gemmaStandard,
          name: 'Gemma 3 1B (Standard)',
          description: 'Best reasoning and accuracy for financial analysis.',
          size: '500 MB',
          fileName: 'gemma-3-1b-it-gpu-int4.task',
          url:
              'https://huggingface.co/google/gemma-3-1b-it/resolve/main/gemma-3-1b-it-gpu-int4.task',
          flutterGemmaModelType: ModelType.gemmaIt,
          fileType: ModelFileType.task,
        ),
        const LocalAIModelMetadata(
          id: LocalAIModelType.qwenLite,
          name: 'Qwen 3 0.6B (Lite)',
          description: 'Faster and smaller, good for mid-range devices.',
          size: '586 MB',
          fileName: 'qwen3-0_6b-it-gpu-int4.task',
          url:
              'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/qwen3-0_6b-it-gpu-int4.task',
          flutterGemmaModelType: ModelType.qwen,
          fileType: ModelFileType.task,
        ),
        const LocalAIModelMetadata(
          id: LocalAIModelType.smolUltraLite,
          name: 'SmolLM 135M (Ultra-Lite)',
          description: 'Smallest and fastest, ideal for basic tasks.',
          size: '135 MB',
          fileName: 'SmolLM-135M-Instruct-gpu-int4.task',
          url:
              'https://huggingface.co/litert-community/SmolLM-135M-Instruct/resolve/main/SmolLM-135M-Instruct-gpu-int4.task',
          flutterGemmaModelType: ModelType.general,
          fileType: ModelFileType.task,
        ),
      ];
    }

    // Default (Android/iOS/Web)
    return [
      const LocalAIModelMetadata(
        id: LocalAIModelType.gemmaStandard,
        name: 'Gemma 2B (Standard)',
        description: 'Best reasoning and accuracy for financial analysis.',
        size: '1.5 GB',
        fileName: 'gemma-2b-it-cpu-int4.bin',
        url:
            'https://huggingface.co/google/gemma-2b-it-tflite/resolve/main/gemma-2b-it-cpu-int4.bin',
        flutterGemmaModelType: ModelType.gemmaIt,
      ),
      const LocalAIModelMetadata(
        id: LocalAIModelType.qwenLite,
        name: 'Qwen 0.5B (Lite)',
        description: 'Faster and smaller, good for mid-range devices.',
        size: '547 MB',
        fileName: 'Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
        url:
            'https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/resolve/main/Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
        flutterGemmaModelType: ModelType.qwen,
        fileType: ModelFileType.task,
      ),
      const LocalAIModelMetadata(
        id: LocalAIModelType.smolUltraLite,
        name: 'SmolLM 135M (Ultra-Lite)',
        description: 'Smallest and fastest, ideal for basic tasks.',
        size: '143 MB',
        fileName: 'SmolLM-135M-Instruct-gpu-int4.task',
        url:
            'https://huggingface.co/litert-community/SmolLM-135M-Instruct/resolve/main/SmolLM-135M-Instruct-gpu-int4.task',
        flutterGemmaModelType: ModelType.general,
        fileType: ModelFileType.task,
      ),
    ];
  }
}
