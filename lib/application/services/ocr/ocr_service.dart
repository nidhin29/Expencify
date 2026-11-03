import '../security/receipt_store.dart';
import '../security/private_file_cleanup.dart';
import 'receipt_parser.dart';
import 'receipt_items.dart';
import 'dart:developer';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class ReceiptScanException implements Exception {
  const ReceiptScanException();
}

class OCRService {
  String? lastImagePath;
  List<ReceiptWord> _words = [];
  final TextRecognizer _textRecognizer = TextRecognizer();
  final ImagePicker _picker = ImagePicker();

  Future<String?> pickAndRecognizeText(
    ImageSource source, {
    Future<void> Function()? onProcessing,
  }) async {
    XFile? picked;
    lastImagePath = null;
    _words = [];
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image == null) return null;
      picked = image;
      await onProcessing?.call();
      lastImagePath = await ReceiptStore().importPhoto(image.path);

      final InputImage inputImage = InputImage.fromFilePath(image.path);
      final RecognizedText recognizedText = await _textRecognizer.processImage(
        inputImage,
      );

      String result = '';
      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          result += '${line.text}\n';
          for (final element in line.elements) {
            final box = element.boundingBox;
            _words.add(
              ReceiptWord(
                element.text,
                box.left,
                box.top,
                box.right,
                box.bottom,
              ),
            );
          }
        }
      }

      return result;
    } catch (e) {
      log('OCR could not complete.');
      throw const ReceiptScanException();
    } finally {
      if (picked != null) {
        await const PrivateFileCleanup().removePickerCopy(picked.path);
      }
    }
  }

  Map<String, dynamic> parseReceipt(String text) => {
    ...ReceiptParser.parse(text),
    'items': ReceiptItems.parse(_words),
  };

  void dispose() {
    try {
      _textRecognizer.close();
    } catch (e) {
      log('OCR Dispose Error: $e');
    }
  }
}
