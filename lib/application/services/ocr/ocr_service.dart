import 'dart:developer';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class OCRService {
  final TextRecognizer _textRecognizer = TextRecognizer();
  final ImagePicker _picker = ImagePicker();

  Future<String?> pickAndRecognizeText(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image == null) return null;

      final InputImage inputImage = InputImage.fromFilePath(image.path);
      final RecognizedText recognizedText = await _textRecognizer.processImage(
        inputImage,
      );

      String result = '';
      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          result += '${line.text}\n';
        }
      }

      return result;
    } catch (e) {
      log('OCR Error: $e');
      return null;
    }
  }

  // Simple parser to find amount and dates from OCR text
  Map<String, dynamic> parseReceipt(String text) {
    try {
      // Basic regex for currency patterns like "$10.00" or "Total: 50.00"
      RegExp amountRegExp = RegExp(r'\d+\.\d{2}');
      Iterable<RegExpMatch> matches = amountRegExp.allMatches(text);

      double? maxAmount;
      if (matches.isNotEmpty) {
        // Often the largest amount on a receipt is the total
        List<double> amounts = matches
            .map((m) => double.tryParse(m.group(0)!) ?? 0.0)
            .toList();
        if (amounts.isNotEmpty) {
          maxAmount = amounts.reduce((a, b) => a > b ? a : b);
        }
      }

      return {'amount': maxAmount, 'text': text};
    } catch (e) {
      log('OCR Parse Error: $e');
      return {'amount': null, 'text': text};
    }
  }

  void dispose() {
    try {
      _textRecognizer.close();
    } catch (e) {
      log('OCR Dispose Error: $e');
    }
  }
}
